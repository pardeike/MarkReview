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
        // SessionRestoration owns document reopening and frame restoration.
        // Disable AppKit's independent window restoration so a manually closed
        // document cannot come back through a second restoration path.
        window.isRestorable = false
        window.restorationClass = nil
        _ = window.setFrameUsingName(autosaveName)
    }
}
