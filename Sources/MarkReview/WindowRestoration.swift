import AppKit
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

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

    func save(_ document: NSDocument) {
        objc_setAssociatedObject(
            document,
            &documentSaveDelegateKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        MarkReviewSavePolicy.save(
            document,
            delegate: self,
            didSave: #selector(documentDidSave(_:didSave:contextInfo:))
        )
    }

    @objc func documentDidSave(
        _ document: NSDocument,
        didSave didSaveSuccessfully: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if didSaveSuccessfully {
            MarkReviewDocumentChangeState.shared.clear(documentID)
            document.updateChangeCount(.changeCleared)
        }
        objc_setAssociatedObject(document, &documentSaveDelegateKey, nil, .OBJC_ASSOCIATION_ASSIGN)
    }
}

@MainActor
enum MarkReviewSavePolicy {
    static func requiresReviewDestination(_ fileURL: URL?) -> Bool {
        fileURL?.pathExtension.caseInsensitiveCompare("md") == .orderedSame
    }

    static func prepareReviewDestination(for document: NSDocument) {
        document.fileType = UTType.markReview.identifier
    }

    static func save(_ document: NSDocument, delegate: AnyObject, didSave selector: Selector) {
        if requiresReviewDestination(document.fileURL) {
            prepareReviewDestination(for: document)
            document.runModalSavePanel(
                for: .saveAsOperation,
                delegate: delegate,
                didSave: selector,
                contextInfo: nil
            )
        } else {
            document.save(
                withDelegate: delegate,
                didSave: selector,
                contextInfo: nil
            )
        }
    }
}

@MainActor
final class ReviewWindowCloseGuard: NSObject, NSWindowDelegate {
    let documentID: UUID
    var prepareForSave: (() -> Void)?
    private weak var forwardingDelegate: (any NSWindowDelegate)?
    private weak var pendingWindow: NSWindow?
    private var isSaving = false
    private var isPresentingCloseAlert = false

    init(
        documentID: UUID,
        prepareForSave: (() -> Void)? = nil,
        forwardingDelegate: (any NSWindowDelegate)? = nil
    ) {
        self.documentID = documentID
        self.prepareForSave = prepareForSave
        self.forwardingDelegate = forwardingDelegate
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardingDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: selector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard MarkReviewDocumentChangeState.shared.isDirty(documentID) else {
            return forwardingDelegate?.windowShouldClose?(sender) ?? true
        }
        guard !isPresentingCloseAlert else { return false }
        isPresentingCloseAlert = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes to this document?"
        alert.informativeText = "Your changes will be lost if you close the document without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard let self, let sender else { return }
            self.isPresentingCloseAlert = false
            switch response {
            case .alertFirstButtonReturn:
                guard let document = sender.windowController?.document as? NSDocument else {
                    MarkReviewDocumentChangeState.shared.clear(self.documentID)
                    sender.close()
                    return
                }
                self.save(document, closing: sender)
            case .alertSecondButtonReturn:
                sender.windowController?.document?.updateChangeCount(.changeCleared)
                MarkReviewDocumentChangeState.shared.clear(self.documentID)
                sender.close()
            default:
                break
            }
        }
        return false
    }

    func save(_ document: NSDocument, closing window: NSWindow? = nil) {
        guard !isSaving else { return }
        isSaving = true
        prepareForSave?()
        if let window {
            pendingWindow = window
        }
        MarkReviewSavePolicy.save(
            document,
            delegate: self,
            didSave: #selector(documentDidSave(_:didSave:contextInfo:))
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
        document.updateChangeCount(.changeCleared)
        pendingWindow?.close()
        pendingWindow = nil
    }
}

private var reviewWindowCloseGuardKey: UInt8 = 0
private var documentSaveDelegateKey: UInt8 = 0
private var reviewWindowActionsKey: UInt8 = 0

@MainActor
private final class MarkReviewWindowActionBox: NSObject {
    var actions: MarkReviewActions

    init(actions: MarkReviewActions) {
        self.actions = actions
    }
}

@MainActor
enum MarkReviewWindowActions {
    static func resolve(_ focusedActions: MarkReviewActions?) -> MarkReviewActions? {
        if let focusedActions {
            return focusedActions
        }

        let windows = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.orderedWindows.map(Optional.some)
        for window in windows {
            if let actions = actions(for: window) {
                return actions
            }
        }
        return nil
    }

    static func actions(for window: NSWindow?) -> MarkReviewActions? {
        guard let window else { return nil }
        return (objc_getAssociatedObject(window, &reviewWindowActionsKey) as? MarkReviewWindowActionBox)?.actions
    }

    static func install(_ actions: MarkReviewActions, on window: NSWindow) {
        if let box = objc_getAssociatedObject(window, &reviewWindowActionsKey) as? MarkReviewWindowActionBox {
            box.actions = actions
        } else {
            objc_setAssociatedObject(
                window,
                &reviewWindowActionsKey,
                MarkReviewWindowActionBox(actions: actions),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

struct WindowFrameObserver: NSViewRepresentable {
    let identifier: String
    let prepareForSave: () -> Void
    let actions: MarkReviewActions

    init(
        identifier: String,
        prepareForSave: @escaping () -> Void = {},
        actions: MarkReviewActions
    ) {
        self.identifier = identifier
        self.prepareForSave = prepareForSave
        self.actions = actions
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, prepareForSave: prepareForSave, actions: actions)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: view, prepareForSave: prepareForSave, actions: actions)
        }
    }

    private func configureWindow(
        for view: NSView,
        prepareForSave: @escaping () -> Void,
        actions: MarkReviewActions
    ) {
        guard let window = view.window else { return }
        MarkReviewWindowActions.install(actions, on: window)
        if let documentID = UUID(uuidString: identifier) {
            let existingGuard = objc_getAssociatedObject(window, &reviewWindowCloseGuardKey) as? ReviewWindowCloseGuard
            if existingGuard?.documentID != documentID {
                let closeGuard = ReviewWindowCloseGuard(
                    documentID: documentID,
                    prepareForSave: prepareForSave,
                    forwardingDelegate: window.delegate
                )
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
