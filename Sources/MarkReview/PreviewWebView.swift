import Foundation
import SwiftUI
import WebKit

struct PreviewWebView: NSViewRepresentable {
    let html: String
    let annotations: [ReviewAnnotation]
    let onRegion: (SelectedRegion) -> Void
    let onFocusAnnotation: (UUID) -> Void
    let onVisibleAnnotation: (UUID) -> Void
    let selectedAnnotationID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegion: onRegion,
            onFocusAnnotation: onFocusAnnotation,
            onVisibleAnnotation: onVisibleAnnotation
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "review")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.onFocusAnnotation = onFocusAnnotation
        context.coordinator.onVisibleAnnotation = onVisibleAnnotation
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.pendingAnnotations = annotations
        context.coordinator.pendingSelectedAnnotationID = selectedAnnotationID
        context.coordinator.applyAnnotationsWhenReady()
        context.coordinator.focusSelectedAnnotationWhenReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "review")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onRegion: (SelectedRegion) -> Void
        var onFocusAnnotation: (UUID) -> Void
        var onVisibleAnnotation: (UUID) -> Void
        weak var webView: WKWebView?
        var lastHTML = ""
        var pendingAnnotations: [ReviewAnnotation] = []
        var pendingSelectedAnnotationID: UUID?
        var isReady = false

        init(
            onRegion: @escaping (SelectedRegion) -> Void,
            onFocusAnnotation: @escaping (UUID) -> Void,
            onVisibleAnnotation: @escaping (UUID) -> Void
        ) {
            self.onRegion = onRegion
            self.onFocusAnnotation = onFocusAnnotation
            self.onVisibleAnnotation = onVisibleAnnotation
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "focusAnnotation", let value = body["id"] as? String, let id = UUID(uuidString: value) {
                DispatchQueue.main.async { self.onFocusAnnotation(id) }
                return
            }
            if type == "visibleAnnotation", let value = body["id"] as? String, let id = UUID(uuidString: value) {
                DispatchQueue.main.async { self.onVisibleAnnotation(id) }
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
        }

        func applyAnnotationsWhenReady() {
            guard isReady, let webView else { return }
            guard let data = try? JSONEncoder.markReview.encode(pendingAnnotations),
                  let json = String(data: data, encoding: .utf8) else { return }
            let selectedID = pendingSelectedAnnotationID.map { "\"\($0.uuidString)\"" } ?? "null"
            webView.evaluateJavaScript("window.setAnnotations(\(json), \(selectedID));")
        }

        func focusSelectedAnnotationWhenReady() {
            guard isReady, let webView else { return }
            let value = pendingSelectedAnnotationID.map { "\"\($0.uuidString)\"" } ?? "null"
            webView.evaluateJavaScript("window.focusAnnotation(\(value));")
        }
    }
}
