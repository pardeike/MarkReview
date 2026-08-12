import Foundation
import AppKit
import SwiftUI
import WebKit

struct PreviewFocusRequest: Equatable {
    let annotationID: UUID
    let token: Int
}

private final class ZoomableWebView: WKWebView {
    var onAltScroll: ((CGFloat) -> Void)?
    private var preciseScrollRemainder: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.option) else {
            preciseScrollRemainder = 0
            super.scrollWheel(with: event)
            return
        }

        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        preciseScrollRemainder += event.scrollingDeltaY
        let steps = Int(preciseScrollRemainder / threshold)
        guard steps != 0 else { return }
        preciseScrollRemainder -= CGFloat(steps) * threshold
        onAltScroll?(CGFloat(steps))
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
    let onZoomScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegion: onRegion,
            onFocusAnnotation: onFocusAnnotation,
            onZoomScroll: onZoomScroll
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "review")
        let webView = ZoomableWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.onAltScroll = { steps in
            context.coordinator.onZoomScroll(steps)
        }
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.onFocusAnnotation = onFocusAnnotation
        context.coordinator.onZoomScroll = onZoomScroll
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
        var onZoomScroll: (CGFloat) -> Void
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
            onZoomScroll: @escaping (CGFloat) -> Void
        ) {
            self.onRegion = onRegion
            self.onFocusAnnotation = onFocusAnnotation
            self.onZoomScroll = onZoomScroll
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
