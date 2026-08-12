import Foundation
import SwiftUI
import WebKit

struct PreviewWebView: NSViewRepresentable {
    let html: String
    let annotations: [ReviewAnnotation]
    let onRegion: (SelectedRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegion: onRegion)
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
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.pendingAnnotations = annotations
        context.coordinator.applyAnnotationsWhenReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "review")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onRegion: (SelectedRegion) -> Void
        weak var webView: WKWebView?
        var lastHTML = ""
        var pendingAnnotations: [ReviewAnnotation] = []
        var isReady = false

        init(onRegion: @escaping (SelectedRegion) -> Void) {
            self.onRegion = onRegion
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], body["type"] as? String == "region" else { return }
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
            guard let data = try? JSONEncoder().encode(pendingAnnotations),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.setAnnotations(\(json));")
        }
    }
}
