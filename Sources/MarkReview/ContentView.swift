import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: MarkReviewDocument
    @State private var selectedRegion: SelectedRegion?
    @State private var showCommentEditor = false
    @State private var statusMessage = ""

    private let renderer = MarkdownRenderer()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if document.originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    PreviewWebView(
                        html: renderer.render(document.originalMarkdown),
                        annotations: document.annotations,
                        onRegion: { region in
                            selectedRegion = region
                            showCommentEditor = true
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    sidebar
                        .frame(width: 330)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .sheet(isPresented: $showCommentEditor) {
            if let selectedRegion {
                CommentEditor(
                    region: selectedRegion,
                    sequence: document.nextSequence,
                    onSave: { comment in
                        addAnnotation(region: selectedRegion, comment: comment)
                        showCommentEditor = false
                        self.selectedRegion = nil
                    },
                    onCancel: {
                        showCommentEditor = false
                        self.selectedRegion = nil
                    }
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(document.title)
                .font(.headline)
                .lineLimit(1)
            if !document.annotations.isEmpty {
                Text("\(document.annotations.filter { $0.status == .open }.count) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Import Markdown…", action: importMarkdown)
            Button("Export Agent JSON…", action: exportAgentJSON)
                .disabled(document.originalMarkdown.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Review comments")
                    .font(.headline)
                Spacer()
                Text("\(document.annotations.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            if document.annotations.isEmpty {
                ContentUnavailableView("No comments yet", systemImage: "text.bubble", description: Text("Select text in the document or Option-click a block."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(document.annotations) { annotation in
                            annotationCard(annotation)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(.bar)
    }

    private func annotationCard(_ annotation: ReviewAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(annotation.sequence)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(annotation.status == .open ? .blue : .secondary)
                Text(annotation.kind == .block ? "block" : "selection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(annotation.status == .open ? "Resolve" : "Reopen") {
                    document.toggleStatus(for: annotation.id)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if !annotation.section.isEmpty {
                Text(annotation.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(annotation.comment)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("“\(annotation.selectedText)”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            HStack {
                Spacer()
                Button("Delete") { document.remove(id: annotation.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(11)
        .background(annotation.status == .open ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("Start a Markdown review")
                .font(.title2.weight(.semibold))
            Text("Import a Markdown file, annotate passages, and export a numbered JSON review for your agent.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Import Markdown…", action: importMarkdown)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addAnnotation(region: SelectedRegion, comment: String) {
        let lines = renderer.sourceLineHints(for: region, in: document.originalMarkdown)
        let annotation = ReviewAnnotation(
            sequence: document.nextSequence,
            kind: region.kind,
            selectedText: region.selectedText,
            contextBefore: region.contextBefore,
            contextAfter: region.contextAfter,
            blockText: region.blockText,
            section: region.section,
            comment: comment,
            sourceLineStart: lines.0,
            sourceLineEnd: lines.1
        )
        document.add(annotation)
    }

    private func importMarkdown() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            document = MarkReviewDocument(
                title: url.deletingPathExtension().lastPathComponent,
                sourcePath: url.path,
                originalMarkdown: markdown
            )
            statusMessage = "Imported"
        } catch {
            statusMessage = "Could not read file"
        }
    }

    private func exportAgentJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(document.title)-review.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.markReview.encode(AgentExport(document: document))
            try data.write(to: url, options: .atomic)
            statusMessage = "Exported"
        } catch {
            statusMessage = "Could not export JSON"
        }
    }
}
