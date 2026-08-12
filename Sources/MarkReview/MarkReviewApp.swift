import SwiftUI
import AppKit

struct MarkReviewActions {
    let saveDocument: () -> Void
    let closeWindow: () -> Void
    let renumberAnnotations: () -> Void
    let toggleSidebar: () -> Void
    let isSidebarVisible: Bool
    let zoomInPreview: () -> Void
    let zoomOutPreview: () -> Void
    let resetPreviewZoom: () -> Void
    let canZoomInPreview: Bool
    let canZoomOutPreview: Bool
    let isPreviewAtActualSize: Bool
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

        CommandMenu("Review") {
            Button("Renumber Comments") {
                actions?.renumberAnnotations()
            }
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(actions?.isSidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Actual Size") {
                actions?.resetPreviewZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(actions == nil || actions?.isPreviewAtActualSize == true)

            Button("Zoom In") {
                actions?.zoomInPreview()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(actions == nil || actions?.canZoomInPreview == false)

            Button("Zoom Out") {
                actions?.zoomOutPreview()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(actions == nil || actions?.canZoomOutPreview == false)
        }
    }
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
