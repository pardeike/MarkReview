import SwiftUI

@main
struct MarkReviewApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkReviewDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Text("Import Markdown from the review window")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
