import SwiftUI
import AppKit

struct MarkReviewActions {
    let saveDocument: () -> Void
    let closeWindow: () -> Void
    let exportAgentJSON: () -> Void
    let renumberAnnotations: () -> Void
    let toggleSidebar: () -> Void
    let isSidebarVisible: Bool
    let zoomInPreview: () -> Void
    let zoomOutPreview: () -> Void
    let resetPreviewZoom: () -> Void
    let canZoomInPreview: Bool
    let canZoomOutPreview: Bool
    let isPreviewAtActualSize: Bool
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
        CommandGroup(replacing: .saveItem) {
            Button("Close Window") {
                actions?.closeWindow()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(actions == nil)

            Divider()

            Button("Save") {
                actions?.saveDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(actions == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Export Agent JSON…") {
                if let actions {
                    actions.exportAgentJSON()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentExport, object: nil)
                }
            }
            .disabled(actions?.canExportAgentJSON == false)
        }

        CommandMenu("Tools") {
            Button("Renumber Comments") {
                if let actions {
                    actions.renumberAnnotations()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentRenumber, object: nil)
                }
            }
        }

        CommandGroup(replacing: .sidebar) {
            Button(actions?.isSidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                if let actions {
                    actions.toggleSidebar()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentToggleSidebar, object: nil)
                }
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
        }

        CommandGroup(after: .sidebar) {
            Button("Actual Size") {
                if let actions {
                    actions.resetPreviewZoom()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentResetPreviewZoom, object: nil)
                }
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(actions?.isPreviewAtActualSize == true)

            Button("Zoom In") {
                if let actions {
                    actions.zoomInPreview()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentZoomIn, object: nil)
                }
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(actions?.canZoomInPreview == false)

            Button("Zoom Out") {
                if let actions {
                    actions.zoomOutPreview()
                } else {
                    NotificationCenter.default.post(name: .markReviewDocumentZoomOut, object: nil)
                }
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(actions?.canZoomOutPreview == false)
        }
    }
}

extension Notification.Name {
    static let markReviewDocumentExport = Notification.Name("MarkReviewDocumentExport")
    static let markReviewDocumentRenumber = Notification.Name("MarkReviewDocumentRenumber")
    static let markReviewDocumentToggleSidebar = Notification.Name("MarkReviewDocumentToggleSidebar")
    static let markReviewDocumentZoomIn = Notification.Name("MarkReviewDocumentZoomIn")
    static let markReviewDocumentZoomOut = Notification.Name("MarkReviewDocumentZoomOut")
    static let markReviewDocumentResetPreviewZoom = Notification.Name("MarkReviewDocumentResetPreviewZoom")
}

final class MarkReviewAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        SessionRestoration.shared.beginLaunchSuppression()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionRestoration.shared.restoreLastSession()
        NSApp.activate(ignoringOtherApps: true)
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
        DocumentGroup(newDocument: { MarkReviewDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands { MarkReviewCommands() }
    }
}
