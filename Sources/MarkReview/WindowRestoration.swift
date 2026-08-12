import AppKit
import ObjectiveC
import SwiftUI

@MainActor
final class MarkReviewDocumentChangeState {
    static let shared = MarkReviewDocumentChangeState()

    private var dirtyDocumentIDs: Set<UUID> = []

    func markDirty(_ documentID: UUID) {
        dirtyDocumentIDs.insert(documentID)
    }

    func clear(_ documentID: UUID) {
        dirtyDocumentIDs.remove(documentID)
    }

    func isDirty(_ documentID: UUID) -> Bool {
        dirtyDocumentIDs.contains(documentID)
    }
}

@MainActor
final class DocumentSaveDelegate: NSObject {
    let documentID: UUID

    init(documentID: UUID) {
        self.documentID = documentID
    }

    @objc func documentDidSave(
        _ document: NSDocument,
        didSave didSaveSuccessfully: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if didSaveSuccessfully {
            MarkReviewDocumentChangeState.shared.clear(documentID)
        }
    }
}

@MainActor
final class ReviewWindowCloseGuard: NSObject, NSWindowDelegate {
    let documentID: UUID
    var prepareForSave: (() -> Void)?
    private weak var pendingWindow: NSWindow?
    private var isSaving = false

    init(documentID: UUID, prepareForSave: (() -> Void)? = nil) {
        self.documentID = documentID
        self.prepareForSave = prepareForSave
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard MarkReviewDocumentChangeState.shared.isDirty(documentID) else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes to this document?"
        alert.informativeText = "Your changes will be lost if you close the document without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let document = sender.windowController?.document else {
                MarkReviewDocumentChangeState.shared.clear(documentID)
                return true
            }
            pendingWindow = sender
            // Starting an NSDocument save directly from windowShouldClose can
            // re-enter AppKit's synchronous close/save activity and beachball.
            // Let the close decision return first, then start the async save.
            DispatchQueue.main.async { [weak self, weak sender, weak document] in
                guard let self, let sender, let document = document as? NSDocument,
                      sender.windowController?.document === document else { return }
                self.save(document, closing: sender)
            }
            return false
        case .alertSecondButtonReturn:
            sender.windowController?.document?.updateChangeCount(.changeCleared)
            MarkReviewDocumentChangeState.shared.clear(documentID)
            return true
        default:
            return false
        }
    }

    func save(_ document: NSDocument, closing window: NSWindow? = nil) {
        guard !isSaving else { return }
        isSaving = true
        prepareForSave?()
        if let window {
            pendingWindow = window
        }
        document.save(
            withDelegate: self,
            didSave: #selector(documentDidSave(_:didSave:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func documentDidSave(
        _ document: NSDocument,
        didSave didSaveSuccessfully: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        isSaving = false
        guard didSaveSuccessfully else {
            pendingWindow = nil
            return
        }
        MarkReviewDocumentChangeState.shared.clear(documentID)
        pendingWindow?.close()
        pendingWindow = nil
    }
}

private var reviewWindowCloseGuardKey: UInt8 = 0

struct WindowFrameObserver: NSViewRepresentable {
    let identifier: String
    let prepareForSave: () -> Void

    init(identifier: String, prepareForSave: @escaping () -> Void = {}) {
        self.identifier = identifier
        self.prepareForSave = prepareForSave
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, prepareForSave: prepareForSave)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: view, prepareForSave: prepareForSave)
        }
    }

    private func configureWindow(for view: NSView, prepareForSave: @escaping () -> Void) {
        guard let window = view.window else { return }
        if let documentID = UUID(uuidString: identifier) {
            let existingGuard = objc_getAssociatedObject(window, &reviewWindowCloseGuardKey) as? ReviewWindowCloseGuard
            if existingGuard?.documentID != documentID {
                let closeGuard = ReviewWindowCloseGuard(documentID: documentID, prepareForSave: prepareForSave)
                objc_setAssociatedObject(window, &reviewWindowCloseGuardKey, closeGuard, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                window.delegate = closeGuard
            } else {
                existingGuard?.prepareForSave = prepareForSave
            }
        }
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
