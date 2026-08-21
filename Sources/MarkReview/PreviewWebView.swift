import Foundation
import AppKit
import SwiftUI
import WebKit

struct PreviewFocusRequest: Equatable {
    let annotationID: UUID
    let token: Int
}

struct PreviewActivationRequest: Equatable {
    let token: Int
}

enum PreviewFindDirection: Equatable {
    case next
    case previous
}

struct PreviewFindNavigationRequest: Equatable {
    let offset: Int
}

struct PreviewFindResult: Equatable {
    let query: String
    let matchCount: Int
    let activeMatchIndex: Int?

    static let empty = PreviewFindResult(query: "", matchCount: 0, activeMatchIndex: nil)
}

enum PreviewFindCommand: Equatable {
    case show
    case next
    case previous
}

enum PreviewFindInput {
    static func keyCommand(
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> PreviewFindCommand? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return nil }

        switch charactersIgnoringModifiers?.lowercased() {
        case "f" where !flags.contains(.shift):
            return .show
        case "g" where flags.contains(.shift):
            return .previous
        case "g":
            return .next
        default:
            return nil
        }
    }
}

enum PreviewZoomCommand: Equatable {
    case adjust(CGFloat)
    case reset
}

enum PreviewFontScaleChangePhase: Equatable {
    case changing
    case settled
}

enum PreviewZoomInput {
    static let fontScaleStep: CGFloat = 0.1
    static let preciseScrollPointsPerStep: CGFloat = 12

    static func keyCommand(
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> PreviewZoomCommand? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return nil }

        switch charactersIgnoringModifiers {
        case "+", "=":
            return .adjust(1)
        case "-":
            return .adjust(-1)
        case "0":
            return .reset
        default:
            return nil
        }
    }

    static func usesScrollZoom(modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) || flags.contains(.command)
    }

    static func preciseScrollSteps(for delta: CGFloat) -> CGFloat {
        delta / preciseScrollPointsPerStep
    }

    static func adjustedFontScale(_ currentScale: CGFloat, steps: CGFloat) -> CGFloat {
        let scale = currentScale + steps * fontScaleStep
        return min(
            max(scale, CGFloat(MarkReviewDocument.minimumPreviewFontScale)),
            CGFloat(MarkReviewDocument.maximumPreviewFontScale)
        )
    }
}

enum PreviewNavigationPolicy {
    static func opensExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    static func allowsInPreview(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.scheme?.lowercased() == "about"
    }
}

private final class ZoomableWebView: WKWebView {
    var onZoom: ((CGFloat) -> Void)?
    var onResetZoom: (() -> Void)?
    var onShowFind: (() -> Void)?
    var onFindNext: (() -> Void)?
    var onFindPrevious: (() -> Void)?
    var onCloseFind: (() -> Void)?
    var isFindBarVisible = false
    private var magnificationRemainder: CGFloat = 0

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch PreviewFindInput.keyCommand(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) {
        case .show:
            onShowFind?()
            return true
        case .next:
            onFindNext?()
            return true
        case .previous:
            onFindPrevious?()
            return true
        case nil:
            break
        }

        switch PreviewZoomInput.keyCommand(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) {
        case .adjust(let steps):
            onZoom?(steps)
            return true
        case .reset:
            onResetZoom?()
            return true
        case nil:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, isFindBarVisible {
            onCloseFind?()
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard PreviewZoomInput.usesScrollZoom(modifiers: event.modifierFlags) else {
            super.scrollWheel(with: event)
            return
        }

        if !event.hasPreciseScrollingDeltas {
            guard event.scrollingDeltaY != 0 else { return }
            let steps: CGFloat = event.scrollingDeltaY > 0 ? 1 : -1
            onZoom?(steps)
            return
        }

        let steps = PreviewZoomInput.preciseScrollSteps(for: event.scrollingDeltaY)
        guard steps != 0 else { return }
        onZoom?(steps)
    }

    override func magnify(with event: NSEvent) {
        magnificationRemainder += event.magnification
        let threshold: CGFloat = 0.08
        let steps = Int(magnificationRemainder / threshold)
        guard steps != 0 else { return }
        magnificationRemainder -= CGFloat(steps) * threshold
        onZoom?(CGFloat(steps))
    }
}

struct PreviewWebView: NSViewRepresentable {
    let html: String
    let fontScale: CGFloat
    let scrollPosition: Double
    let annotations: [ReviewAnnotation]
    let findQuery: String
    let findNavigationRequest: PreviewFindNavigationRequest?
    let previewActivationRequest: PreviewActivationRequest?
    let isFindBarVisible: Bool
    let onRegion: (SelectedRegion) -> Void
    let onFocusAnnotation: (UUID) -> Void
    let onScrollPositionChange: (Double, Bool) -> Void
    let selectedAnnotationID: UUID?
    let focusRequest: PreviewFocusRequest?
    let onFontScaleChange: (CGFloat, PreviewFontScaleChangePhase) -> Void
    let onShowFind: () -> Void
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onCloseFind: () -> Void
    let onFindResult: (PreviewFindResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegion: onRegion,
            onFocusAnnotation: onFocusAnnotation,
            onScrollPositionChange: onScrollPositionChange,
            onFontScaleChange: onFontScaleChange,
            onShowFind: onShowFind,
            onFindNext: onFindNext,
            onFindPrevious: onFindPrevious,
            onCloseFind: onCloseFind,
            onFindResult: onFindResult
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "review")
        let webView = ZoomableWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.onZoom = { [weak coordinator = context.coordinator] steps in
            coordinator?.adjustFontScaleImmediately(by: steps)
        }
        webView.onResetZoom = { [weak coordinator = context.coordinator] in
            coordinator?.resetFontScaleImmediately()
        }
        webView.onShowFind = { [weak coordinator = context.coordinator] in
            coordinator?.onShowFind()
        }
        webView.onFindNext = { [weak coordinator = context.coordinator] in
            coordinator?.onFindNext()
        }
        webView.onFindPrevious = { [weak coordinator = context.coordinator] in
            coordinator?.onFindPrevious()
        }
        webView.onCloseFind = { [weak coordinator = context.coordinator] in
            coordinator?.onCloseFind()
        }
        webView.isFindBarVisible = isFindBarVisible
        let coordinator = context.coordinator
        coordinator.webView = webView
        coordinator.updatePendingViewState(
            fontScale: fontScale,
            scrollPosition: scrollPosition,
            annotations: annotations,
            selectedAnnotationID: selectedAnnotationID,
            focusRequest: focusRequest,
            findQuery: findQuery,
            findNavigationRequest: findNavigationRequest,
            previewActivationRequest: previewActivationRequest
        )
        if coordinator.prepareHTMLLoad(html) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.onFocusAnnotation = onFocusAnnotation
        context.coordinator.onScrollPositionChange = onScrollPositionChange
        context.coordinator.onFontScaleChange = onFontScaleChange
        context.coordinator.onShowFind = onShowFind
        context.coordinator.onFindNext = onFindNext
        context.coordinator.onFindPrevious = onFindPrevious
        context.coordinator.onCloseFind = onCloseFind
        context.coordinator.onFindResult = onFindResult
        (webView as? ZoomableWebView)?.isFindBarVisible = isFindBarVisible
        context.coordinator.updatePendingViewState(
            fontScale: fontScale,
            scrollPosition: scrollPosition,
            annotations: annotations,
            selectedAnnotationID: selectedAnnotationID,
            focusRequest: focusRequest,
            findQuery: findQuery,
            findNavigationRequest: findNavigationRequest,
            previewActivationRequest: previewActivationRequest
        )
        if context.coordinator.prepareHTMLLoad(html) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.applyFontScaleWhenReady()
        context.coordinator.applyAnnotationsWhenReady()
        context.coordinator.restoreInitialViewportWhenReady()
        context.coordinator.focusRequestedAnnotationWhenReady()
        context.coordinator.applyContentFindWhenReady()
        context.coordinator.navigateContentFindWhenReady()
        context.coordinator.activatePreviewWhenReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelFontScaleSettlement()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "review")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onRegion: (SelectedRegion) -> Void
        var onFocusAnnotation: (UUID) -> Void
        var onScrollPositionChange: (Double, Bool) -> Void
        var onFontScaleChange: (CGFloat, PreviewFontScaleChangePhase) -> Void
        var onShowFind: () -> Void
        var onFindNext: () -> Void
        var onFindPrevious: () -> Void
        var onCloseFind: () -> Void
        var onFindResult: (PreviewFindResult) -> Void
        weak var webView: WKWebView?
        var lastHTML = ""
        var pendingFontScale: CGFloat = 1
        var pendingScrollPosition: Double = 0
        var pendingAnnotations: [ReviewAnnotation] = []
        var pendingSelectedAnnotationID: UUID?
        var pendingFocusRequest: PreviewFocusRequest?
        var appliedAnnotations: [ReviewAnnotation]?
        var appliedSelectedAnnotationID: UUID?
        var appliedFocusRequestToken: Int?
        var pendingFindQuery = ""
        var pendingFindNavigationRequest: PreviewFindNavigationRequest?
        var pendingPreviewActivationRequest: PreviewActivationRequest?
        var appliedFindQuery: String?
        var appliedFindNavigationOffset = 0
        var reloadedFindNavigationOffset: Int?
        var appliedPreviewActivationToken: Int?
        var appliedFontScale: CGFloat?
        var stagedFontScale: CGFloat?
        var fontScaleSettlement: DispatchWorkItem?
        var didRestoreInitialViewport = false
        var isReady = false

        init(
            onRegion: @escaping (SelectedRegion) -> Void,
            onFocusAnnotation: @escaping (UUID) -> Void,
            onScrollPositionChange: @escaping (Double, Bool) -> Void,
            onFontScaleChange: @escaping (CGFloat, PreviewFontScaleChangePhase) -> Void,
            onShowFind: @escaping () -> Void = {},
            onFindNext: @escaping () -> Void = {},
            onFindPrevious: @escaping () -> Void = {},
            onCloseFind: @escaping () -> Void = {},
            onFindResult: @escaping (PreviewFindResult) -> Void = { _ in }
        ) {
            self.onRegion = onRegion
            self.onFocusAnnotation = onFocusAnnotation
            self.onScrollPositionChange = onScrollPositionChange
            self.onFontScaleChange = onFontScaleChange
            self.onShowFind = onShowFind
            self.onFindNext = onFindNext
            self.onFindPrevious = onFindPrevious
            self.onCloseFind = onCloseFind
            self.onFindResult = onFindResult
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "focusAnnotation", let value = body["id"] as? String, let id = UUID(uuidString: value) {
                DispatchQueue.main.async { self.onFocusAnnotation(id) }
                return
            }
            if type == "previewScrollPosition", let value = body["position"] as? NSNumber {
                let userInitiated = body["userInitiated"] as? Bool ?? true
                DispatchQueue.main.async {
                    self.onScrollPositionChange(value.doubleValue, userInitiated)
                }
                return
            }
            guard type == "region" else { return }
            let kind = AnnotationKind(rawValue: body["kind"] as? String ?? "text") ?? .text
            let region = SelectedRegion(
                kind: kind,
                selectedText: body["selectedText"] as? String ?? "",
                contextBefore: body["before"] as? String ?? "",
                contextAfter: body["after"] as? String ?? "",
                blockText: body["blockText"] as? String ?? "",
                section: body["section"] as? String ?? ""
            )
            DispatchQueue.main.async { self.onRegion(region) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyFontScaleWhenReady()
            applyAnnotationsWhenReady()
            restoreInitialViewportWhenReady()
            focusRequestedAnnotationWhenReady()
            applyContentFindWhenReady()
            navigateContentFindWhenReady()
            activatePreviewWhenReady()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .linkActivated,
               let url,
               PreviewNavigationPolicy.opensExternally(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(PreviewNavigationPolicy.allowsInPreview(url) ? .allow : .cancel)
        }

        func applyAnnotationsWhenReady() {
            guard isReady, let webView else { return }
            switch pendingAnnotationUpdate {
            case .none:
                return
            case .selection(let selectedAnnotationID):
                appliedSelectedAnnotationID = selectedAnnotationID
                let selectedID = selectedAnnotationID.map { "\"\($0.uuidString)\"" } ?? "null"
                webView.evaluateJavaScript("window.setSelectedAnnotation(\(selectedID));")
            case .all:
                guard let data = try? JSONEncoder.markReview.encode(pendingAnnotations),
                      let json = String(data: data, encoding: .utf8) else { return }
                appliedAnnotations = pendingAnnotations
                appliedSelectedAnnotationID = pendingSelectedAnnotationID
                let selectedID = pendingSelectedAnnotationID.map { "\"\($0.uuidString)\"" } ?? "null"
                webView.evaluateJavaScript("window.setAnnotations(\(json), \(selectedID));")
            }
        }

        enum AnnotationUpdate: Equatable {
            case none
            case selection(UUID?)
            case all
        }

        var pendingAnnotationUpdate: AnnotationUpdate {
            guard appliedAnnotations == pendingAnnotations else { return .all }
            guard appliedSelectedAnnotationID != pendingSelectedAnnotationID else { return .none }
            return .selection(pendingSelectedAnnotationID)
        }

        func focusRequestedAnnotationWhenReady() {
            guard isReady, let webView else { return }
            guard let request = pendingFocusRequest,
                  appliedFocusRequestToken != request.token else { return }
            appliedFocusRequestToken = request.token
            let value = "\"\(request.annotationID.uuidString)\""
            webView.evaluateJavaScript("window.focusAnnotation(\(value));")
        }

        func applyContentFindWhenReady() {
            guard isReady, let webView, appliedFindQuery != pendingFindQuery else { return }
            guard let query = Self.javascriptString(pendingFindQuery) else { return }
            appliedFindQuery = pendingFindQuery
            appliedFindNavigationOffset = reloadedFindNavigationOffset ?? 0
            reloadedFindNavigationOffset = nil
            evaluateContentFind("window.setContentFindQuery(\(query));", in: webView)
        }

        func navigateContentFindWhenReady() {
            guard isReady, let webView, appliedFindQuery == pendingFindQuery else { return }
            guard let delta = pendingFindNavigationDelta else { return }
            appliedFindNavigationOffset += delta
            evaluateContentFind("window.navigateContentFindBy(\(delta));", in: webView)
        }

        var pendingFindNavigationDelta: Int? {
            guard let request = pendingFindNavigationRequest else { return nil }
            let delta = request.offset - appliedFindNavigationOffset
            return delta == 0 ? nil : delta
        }

        func activatePreviewWhenReady() {
            guard isReady, let webView else { return }
            guard let request = pendingPreviewActivationRequest,
                  appliedPreviewActivationToken != request.token else { return }
            appliedPreviewActivationToken = request.token
            DispatchQueue.main.async { [weak webView] in
                guard let webView, let window = webView.window else { return }
                window.makeFirstResponder(webView)
            }
        }

        private func evaluateContentFind(_ script: String, in webView: WKWebView) {
            webView.evaluateJavaScript(script) { [weak self] value, error in
                guard error == nil, let result = Self.parseFindResult(value) else { return }
                DispatchQueue.main.async {
                    self?.onFindResult(result)
                }
            }
        }

        static func parseFindResult(_ value: Any?) -> PreviewFindResult? {
            guard let payload = value as? [String: Any],
                  let query = payload["query"] as? String,
                  let countValue = payload["count"] as? NSNumber else { return nil }
            let matchCount = max(0, countValue.intValue)
            let candidateIndex = (payload["activeIndex"] as? NSNumber)?.intValue ?? -1
            let activeMatchIndex = (0..<matchCount).contains(candidateIndex) ? candidateIndex : nil
            return PreviewFindResult(
                query: query,
                matchCount: matchCount,
                activeMatchIndex: activeMatchIndex
            )
        }

        private static func javascriptString(_ value: String) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func updatePendingViewState(
            fontScale: CGFloat,
            scrollPosition: Double,
            annotations: [ReviewAnnotation],
            selectedAnnotationID: UUID?,
            focusRequest: PreviewFocusRequest?,
            findQuery: String,
            findNavigationRequest: PreviewFindNavigationRequest?,
            previewActivationRequest: PreviewActivationRequest?
        ) {
            updatePendingFontScale(fontScale)
            pendingScrollPosition = scrollPosition
            pendingAnnotations = annotations
            pendingSelectedAnnotationID = selectedAnnotationID
            pendingFocusRequest = focusRequest
            pendingFindQuery = findQuery
            pendingFindNavigationRequest = findNavigationRequest
            pendingPreviewActivationRequest = previewActivationRequest
        }

        func prepareHTMLLoad(_ html: String) -> Bool {
            guard lastHTML != html else { return false }
            reloadedFindNavigationOffset = appliedFindQuery == pendingFindQuery
                ? pendingFindNavigationRequest?.offset ?? appliedFindNavigationOffset
                : nil
            lastHTML = html
            webView?.alphaValue = 0
            isReady = false
            appliedFontScale = nil
            appliedAnnotations = nil
            appliedSelectedAnnotationID = nil
            appliedFindQuery = nil
            didRestoreInitialViewport = false
            appliedFocusRequestToken = nil
            return true
        }

        func updatePendingFontScale(_ fontScale: CGFloat) {
            pendingFontScale = fontScale
            if let stagedFontScale,
               abs(stagedFontScale - fontScale) < 0.000_001 {
                self.stagedFontScale = nil
            }
        }

        func adjustFontScaleImmediately(by steps: CGFloat) {
            let currentScale = stagedFontScale ?? appliedFontScale ?? pendingFontScale
            stageFontScale(PreviewZoomInput.adjustedFontScale(currentScale, steps: steps))
        }

        func resetFontScaleImmediately() {
            stageFontScale(CGFloat(MarkReviewDocument.defaultPreviewFontScale))
        }

        private func stageFontScale(_ fontScale: CGFloat) {
            let currentScale = stagedFontScale ?? appliedFontScale ?? pendingFontScale
            guard abs(currentScale - fontScale) > 0.000_001 else { return }

            stagedFontScale = fontScale
            if isReady, let webView {
                appliedFontScale = fontScale
                webView.evaluateJavaScript("window.setMarkdownFontScale(\(fontScale));")
            } else {
                appliedFontScale = nil
            }
            onFontScaleChange(fontScale, .changing)

            fontScaleSettlement?.cancel()
            let settlement = DispatchWorkItem { [weak self] in
                guard let self, let stagedFontScale = self.stagedFontScale else { return }
                self.fontScaleSettlement = nil
                self.onFontScaleChange(stagedFontScale, .settled)
            }
            fontScaleSettlement = settlement
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: settlement)
        }

        func cancelFontScaleSettlement() {
            fontScaleSettlement?.cancel()
            fontScaleSettlement = nil
        }

        func applyFontScaleWhenReady() {
            let fontScale = stagedFontScale ?? pendingFontScale
            guard isReady, let webView, appliedFontScale != fontScale else { return }
            appliedFontScale = fontScale
            webView.evaluateJavaScript("window.setMarkdownFontScale(\(fontScale));")
        }

        func restoreInitialViewportWhenReady() {
            guard isReady, let webView, !didRestoreInitialViewport else { return }
            didRestoreInitialViewport = true
            webView.evaluateJavaScript("window.restorePreviewViewport(\(pendingScrollPosition));") { [weak webView] _, _ in
                webView?.alphaValue = 1
            }
        }
    }
}
