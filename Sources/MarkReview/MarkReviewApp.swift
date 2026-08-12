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

    private var target: MarkReviewActions? {
        MarkReviewWindowActions.resolve(actions)
    }

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close Window") {
                MarkReviewWindowActions.resolve(actions)?.closeWindow()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(target == nil)

            Divider()

            Button("Save") {
                MarkReviewWindowActions.resolve(actions)?.saveDocument()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(target == nil)
        }

        CommandMenu("Review") {
            Button("Renumber Comments") {
                MarkReviewWindowActions.resolve(actions)?.renumberAnnotations()
            }
            .disabled(target == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(target?.isSidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                MarkReviewWindowActions.resolve(actions)?.toggleSidebar()
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(target == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Actual Size") {
                MarkReviewWindowActions.resolve(actions)?.resetPreviewZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(target == nil || target?.isPreviewAtActualSize == true)

            Button("Zoom In") {
                MarkReviewWindowActions.resolve(actions)?.zoomInPreview()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(target == nil || target?.canZoomInPreview == false)

            Button("Zoom Out") {
                MarkReviewWindowActions.resolve(actions)?.zoomOutPreview()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(target == nil || target?.canZoomOutPreview == false)
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
