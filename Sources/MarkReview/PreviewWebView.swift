import Foundation
import AppKit
import SwiftUI
import WebKit

struct PreviewFocusRequest: Equatable {
    let annotationID: UUID
    let token: Int
}

enum PreviewZoomCommand: Equatable {
    case adjust(CGFloat)
    case reset
}

enum PreviewZoomInput {
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
    private var preciseScrollRemainder: CGFloat = 0
    private var magnificationRemainder: CGFloat = 0

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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

    override func scrollWheel(with event: NSEvent) {
        guard PreviewZoomInput.usesScrollZoom(modifiers: event.modifierFlags) else {
            preciseScrollRemainder = 0
            super.scrollWheel(with: event)
            return
        }

        if !event.hasPreciseScrollingDeltas {
            preciseScrollRemainder = 0
            guard event.scrollingDeltaY != 0 else { return }
            let steps: CGFloat = event.scrollingDeltaY > 0 ? 1 : -1
            onZoom?(steps)
            return
        }

        let threshold: CGFloat = 24
        preciseScrollRemainder += event.scrollingDeltaY
        let quantizedSteps = Int(preciseScrollRemainder / threshold)
        guard quantizedSteps != 0 else { return }
        preciseScrollRemainder -= CGFloat(quantizedSteps) * threshold
        onZoom?(quantizedSteps > 0 ? 1 : -1)
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
    let annotations: [ReviewAnnotation]
    let onRegion: (SelectedRegion) -> Void
    let onFocusAnnotation: (UUID) -> Void
    let selectedAnnotationID: UUID?
    let focusRequest: PreviewFocusRequest?
    let onZoom: (CGFloat) -> Void
    let onResetZoom: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegion: onRegion,
            onFocusAnnotation: onFocusAnnotation,
            onZoom: onZoom,
            onResetZoom: onResetZoom
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
        webView.onZoom = { steps in
            context.coordinator.onZoom(steps)
        }
        webView.onResetZoom = {
            context.coordinator.onResetZoom()
        }
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.onFocusAnnotation = onFocusAnnotation
        context.coordinator.onZoom = onZoom
        context.coordinator.onResetZoom = onResetZoom
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.isReady = false
            context.coordinator.appliedFontScale = nil
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.pendingFontScale = fontScale
        context.coordinator.pendingAnnotations = annotations
        context.coordinator.pendingSelectedAnnotationID = selectedAnnotationID
        context.coordinator.pendingFocusRequest = focusRequest
        context.coordinator.applyAnnotationsWhenReady()
        context.coordinator.focusRequestedAnnotationWhenReady()
        context.coordinator.applyFontScaleWhenReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "review")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onRegion: (SelectedRegion) -> Void
        var onFocusAnnotation: (UUID) -> Void
        var onZoom: (CGFloat) -> Void
        var onResetZoom: () -> Void
        weak var webView: WKWebView?
        var lastHTML = ""
        var pendingFontScale: CGFloat = 1
        var pendingAnnotations: [ReviewAnnotation] = []
        var pendingSelectedAnnotationID: UUID?
        var pendingFocusRequest: PreviewFocusRequest?
        var appliedFocusRequestToken: Int?
        var appliedFontScale: CGFloat?
        var isReady = false

        init(
            onRegion: @escaping (SelectedRegion) -> Void,
            onFocusAnnotation: @escaping (UUID) -> Void,
            onZoom: @escaping (CGFloat) -> Void,
            onResetZoom: @escaping () -> Void
        ) {
            self.onRegion = onRegion
            self.onFocusAnnotation = onFocusAnnotation
            self.onZoom = onZoom
            self.onResetZoom = onResetZoom
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "focusAnnotation", let value = body["id"] as? String, let id = UUID(uuidString: value) {
                DispatchQueue.main.async { self.onFocusAnnotation(id) }
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
            applyAnnotationsWhenReady()
            focusRequestedAnnotationWhenReady()
            applyFontScaleWhenReady()
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
            guard let data = try? JSONEncoder.markReview.encode(pendingAnnotations),
                  let json = String(data: data, encoding: .utf8) else { return }
            let selectedID = pendingSelectedAnnotationID.map { "\"\($0.uuidString)\"" } ?? "null"
            webView.evaluateJavaScript("window.setAnnotations(\(json), \(selectedID));")
        }

        func focusRequestedAnnotationWhenReady() {
            guard isReady, let webView else { return }
            guard let request = pendingFocusRequest,
                  appliedFocusRequestToken != request.token else { return }
            appliedFocusRequestToken = request.token
            let value = "\"\(request.annotationID.uuidString)\""
            webView.evaluateJavaScript("window.focusAnnotation(\(value));")
        }

        func applyFontScaleWhenReady() {
            guard isReady, let webView, appliedFontScale != pendingFontScale else { return }
            appliedFontScale = pendingFontScale
            webView.evaluateJavaScript("window.setMarkdownFontScale(\(pendingFontScale));")
        }
    }
}
