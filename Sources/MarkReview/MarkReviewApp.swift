import SwiftUI
import AppKit

struct MarkReviewActions {
    let importMarkdown: () -> Void
    let exportAgentJSON: () -> Void
    let renumberAnnotations: () -> Void
    let canExportAgentJSON: Bool
}

private struct MarkReviewActionsKey: FocusedValueKey {
    typealias Value = MarkReviewActions
}

extension FocusedValues {
    var markReviewActions: MarkReviewActions? {
        get { self[MarkReviewActionsKey.self] }
        set { self[MarkReviewActionsKey.self] = newValue }
    }
}

struct MarkReviewCommands: Commands {
    @FocusedValue(\.markReviewActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Markdown…") {
                if let actions {
                    actions.importMarkdown()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentImport, object: nil)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Export Agent JSON…") {
                if let actions {
                    actions.exportAgentJSON()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentExport, object: nil)
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(actions?.canExportAgentJSON == false)

            Button("Renumber Comments") {
                if let actions {
                    actions.renumberAnnotations()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentRenumber, object: nil)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}

extension Notification.Name {
    static let markReviewDocumentImport = Notification.Name("MarkReviewDocumentImport")
    static let markReviewDocumentExport = Notification.Name("MarkReviewDocumentExport")
    static let markReviewDocumentRenumber = Notification.Name("MarkReviewDocumentRenumber")
}

final class MarkReviewAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        SessionRestoration.shared.restoreLastSession()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionRestoration.shared.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

@main
struct MarkReviewApp: App {
    @NSApplicationDelegateAdaptor(MarkReviewAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkReviewDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands { MarkReviewCommands() }
    }
}
