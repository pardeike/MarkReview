import SwiftUI

struct CommentEditor: View {
    let region: SelectedRegion
    let sequence: Int
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var comment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(region.kind == .block ? "Comment on block" : "Comment on selection")
                    .font(.headline)
                Spacer()
                Text("#\(sequence)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(region.section.isEmpty ? "Document" : region.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("“\(region.selectedText.trimmingCharacters(in: .whitespacesAndNewlines))”")
                    .font(.body)
                    .lineLimit(5)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Your comment")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $comment)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add comment") {
                    let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 470)
    }
}
