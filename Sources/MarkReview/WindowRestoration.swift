import AppKit
import SwiftUI

struct WindowFrameObserver: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        let autosaveName = MarkReviewWindowNaming.autosaveName(
            fileURL: window.windowController?.document?.fileURL,
            documentID: UUID(uuidString: identifier) ?? UUID()
        )
        guard window.frameAutosaveName != autosaveName else { return }

        window.setFrameAutosaveName(autosaveName)
        window.isRestorable = true
        _ = window.setFrameUsingName(autosaveName)
    }
}
