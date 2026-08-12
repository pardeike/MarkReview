import AppKit
import Foundation

struct SavedWindowFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ frame: NSRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.size.width
        height = frame.size.height
    }

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

struct SavedReviewWindow: Codable, Equatable {
    let path: String
    let frame: SavedWindowFrame
}

struct MarkReviewSession: Codable, Equatable {
    let windows: [SavedReviewWindow]
}

enum MarkReviewWindowNaming {
    static func autosaveName(fileURL: URL?, documentID: UUID) -> String {
        guard let fileURL else { return "MarkReview.document.\(documentID.uuidString)" }
        let pathData = Data(fileURL.standardizedFileURL.path.utf8)
        return "MarkReview.file.\(pathData.base64EncodedString())"
    }
}

final class SessionRestoration {
    static let shared = SessionRestoration()

    private var didRestore = false
    private var isTerminating = false
    private var isSuppressingLaunchWindows = false
    private var windowCloseObserver: NSObjectProtocol?
    private var launchWindowObservers: [NSObjectProtocol] = []

    private init() {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isTerminating else { return }
                self.saveCurrentSession()
            }
        }

        for notificationName in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
        ] {
            launchWindowObservers.append(
                NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    self?.suppressLaunchWindowIfNeeded(window)
                }
            )
        }
    }

    deinit {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        launchWindowObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func beginLaunchSuppression() {
        isSuppressingLaunchWindows = true
        NSApp.windows.forEach(suppressLaunchWindowIfNeeded)
    }

    func restoreLastSession() {
        guard !didRestore else { return }
        didRestore = true
        beginLaunchSuppression()

        DispatchQueue.main.async { [weak self] in
            self?.restoreWhenDocumentSceneIsReady(attempt: 0)
        }
    }

    func saveCurrentSession() {
        let windows = NSApp.windows.compactMap { window -> SavedReviewWindow? in
            guard window.isVisible, let controller = window.windowController else { return nil }
            guard let document = controller.document else { return nil }
            guard let fileURL = document.fileURL ?? nil else { return nil }
            guard fileURL.isFileURL else { return nil }
            return SavedReviewWindow(path: fileURL.standardizedFileURL.path, frame: SavedWindowFrame(window.frame))
        }

        var uniqueWindows: [String: SavedReviewWindow] = [:]
        windows.forEach { uniqueWindows[$0.path] = $0 }
        save(MarkReviewSession(windows: uniqueWindows.values.sorted { $0.path < $1.path }))
    }

    func prepareForTermination() {
        isTerminating = true
        saveCurrentSession()
    }

    private func open(url: URL, frame: NSRect) {
        if let existing = NSDocumentController.shared.documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            apply(frame: frame, to: existing)
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, _ in
            guard let self, let document else { return }
            self.apply(frame: frame, to: document)
        }
    }

    private func restoreWhenDocumentSceneIsReady(attempt: Int) {
        if NSApp.windows.isEmpty, attempt < 8 {
            DispatchQueue.main.async { [weak self] in
                self?.restoreWhenDocumentSceneIsReady(attempt: attempt + 1)
            }
            return
        }

        let session = load()
        closeUntitledWindows()
        isSuppressingLaunchWindows = false
        guard let session, !session.windows.isEmpty else { return }

        for savedWindow in session.windows {
            let url = URL(fileURLWithPath: savedWindow.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            open(url: url, frame: savedWindow.frame.nsRect)
        }
    }

    private func apply(frame: NSRect, to document: NSDocument) {
        DispatchQueue.main.async {
            document.windowControllers.forEach { controller in
                guard let window = controller.window else { return }
                window.setFrame(frame, display: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func closeUntitledWindows() {
        NSApp.windows
            .filter { isLaunchPlaceholder($0) }
            .forEach {
                $0.orderOut(nil)
                $0.close()
            }
    }

    private func suppressLaunchWindowIfNeeded(_ window: NSWindow) {
        guard isSuppressingLaunchWindows, isLaunchPlaceholder(window) else { return }
        window.orderOut(nil)
    }

    private func isLaunchPlaceholder(_ window: NSWindow) -> Bool {
        if window.title == "Untitled" {
            return true
        }
        guard let document = window.windowController?.document else { return window.title == "Untitled" }
        return document.fileURL == nil
    }

    private var sessionURL: URL? {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return applicationSupport.appendingPathComponent("MarkReview", isDirectory: true).appendingPathComponent("session.json")
    }

    private func load() -> MarkReviewSession? {
        guard let sessionURL,
              let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(MarkReviewSession.self, from: data)
    }

    private func save(_ session: MarkReviewSession) {
        guard let sessionURL else { return }
        let directory = sessionURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }
}
