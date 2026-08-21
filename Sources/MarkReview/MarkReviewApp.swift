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

@MainActor
final class RecentDocumentsStore: ObservableObject {
    @Published private(set) var urls: [URL]
    private var observers: [NSObjectProtocol] = []

    init() {
        urls = []
        for notificationName in [
            NSApplication.didFinishLaunchingNotification,
            NSWindow.didBecomeKeyNotification
        ] {
            observers.append(NotificationCenter.default.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.reload()
                }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func open(_ url: URL) {
        let controller = NSDocumentController.shared
        controller.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
            if let error {
                controller.presentError(error)
            } else {
                controller.noteNewRecentDocumentURL(url)
            }
            self?.reload()
        }
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        reload()
    }

    private func reload() {
        let currentURLs = NSDocumentController.shared.recentDocumentURLs
        guard currentURLs != urls else { return }
        urls = currentURLs
    }
}

struct MarkReviewCommands: Commands {
    @FocusedValue(\.markReviewActions) private var actions
    @ObservedObject var recentDocuments: RecentDocumentsStore

    private var target: MarkReviewActions? {
        MarkReviewWindowActions.resolve(actions)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                NSDocumentController.shared.newDocument(nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Open…") {
                NSDocumentController.shared.openDocument(nil)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu("Open Recent") {
                if recentDocuments.urls.isEmpty {
                    Button("No Recent Documents") {}
                        .disabled(true)
                } else {
                    ForEach(recentDocuments.urls, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            recentDocuments.open(url)
                        }
                        .help(url.path)
                    }
                }

                Divider()

                Button("Clear Menu") {
                    recentDocuments.clear()
                }
                .disabled(recentDocuments.urls.isEmpty)
            }
        }

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
        let commandLineFiles = Self.fileURLs(fromCommandLineArguments: CommandLine.arguments)
        if commandLineFiles.isEmpty {
            SessionRestoration.shared.restoreLastSession()
        } else {
            SessionRestoration.shared.openCommandLineFiles(commandLineFiles)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Lets a direct launch (e.g. `swift run MarkReview <path>`) open a file without depending
    // on a saved session or a Finder/Launch Services open event.
    private static func fileURLs(fromCommandLineArguments arguments: [String]) -> [URL] {
        arguments.dropFirst().compactMap { argument in
            guard !argument.hasPrefix("-") else { return nil }
            let url = URL(fileURLWithPath: argument)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
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
    @StateObject private var recentDocuments = RecentDocumentsStore()

    var body: some Scene {
        DocumentGroup(newDocument: { MarkReviewDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands { MarkReviewCommands(recentDocuments: recentDocuments) }
    }
}
