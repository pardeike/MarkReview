import Foundation
import Testing
@testable import MarkReview

@Test("review document round-trips with annotations")
func documentRoundTrip() throws {
    let annotation = ReviewAnnotation(
        sequence: 1,
        kind: .text,
        selectedText: "important sentence",
        contextBefore: "before ",
        contextAfter: " after",
        blockText: "before important sentence after",
        section: "Section one",
        comment: "Please turn this into a task."
    )
    let original = MarkReviewDocument(
        title: "Review",
        sourcePath: "/tmp/source.md",
        originalMarkdown: "# Section one\n\nimportant sentence",
        annotations: [annotation]
    )
    let data = try JSONEncoder.markReview.encode(original)
    let decoded = try JSONDecoder.markReview.decode(MarkReviewDocument.self, from: data)
    #expect(decoded.formatVersion == original.formatVersion)
    #expect(decoded.id == original.id)
    #expect(decoded.title == original.title)
    #expect(decoded.sourcePath == original.sourcePath)
    #expect(decoded.originalMarkdown == original.originalMarkdown)
    #expect(decoded.annotations.map(\.sequence) == original.annotations.map(\.sequence))
    #expect(decoded.annotations.map(\.comment) == original.annotations.map(\.comment))
}

@Test("agent export preserves sequence and context")
func agentExport() throws {
    let document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "# Heading\n\nText",
        annotations: [ReviewAnnotation(
            sequence: 3,
            kind: .block,
            selectedText: "Text",
            contextBefore: "",
            contextAfter: "",
            blockText: "Text",
            section: "Heading",
            comment: "Make this actionable."
        )]
    )
    let export = AgentExport(document: document)
    #expect(export.annotations.first?.number == 3)
    #expect(export.annotations.first?.comment == "Make this actionable.")
    #expect(export.source.markdown == "# Heading\n\nText")
}

@Test("agent export omits an unfinished inline comment")
func agentExportOmitsEmptyComments() {
    let document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "Text",
        annotations: [
            ReviewAnnotation(sequence: 1, kind: .text, selectedText: "Text", contextBefore: "", contextAfter: "", blockText: "Text", section: "", comment: "   "),
            ReviewAnnotation(sequence: 2, kind: .text, selectedText: "Text", contextBefore: "", contextAfter: "", blockText: "Text", section: "", comment: "Keep this one.")
        ]
    )

    let export = AgentExport(document: document)
    #expect(export.annotations.map(\.number) == [2])
}

@Test("renumbering follows Markdown order")
func renumberTopDown() {
    let first = ReviewAnnotation(
        sequence: 2,
        kind: .text,
        selectedText: "First passage",
        contextBefore: "",
        contextAfter: "",
        blockText: "First passage",
        section: "First",
        comment: "First comment.",
        sourceLineStart: 3,
        sourceLineEnd: 3
    )
    let second = ReviewAnnotation(
        sequence: 1,
        kind: .text,
        selectedText: "Second passage",
        contextBefore: "",
        contextAfter: "",
        blockText: "Second passage",
        section: "Second",
        comment: "Second comment.",
        sourceLineStart: 7,
        sourceLineEnd: 7
    )
    var document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "# First\n\nFirst passage\n\n# Second\n\nSecond passage",
        annotations: [second, first]
    )

    document.renumberTopDown()

    #expect(document.annotations.map(\.selectedText) == ["First passage", "Second passage"])
    #expect(document.annotations.map(\.sequence) == [1, 2])
}

@Test("deleting an annotation closes the sequence gap without reordering")
func deletingAnnotationClosesSequenceGapWithoutReordering() {
    let firstID = UUID()
    let deletedID = UUID()
    let lastID = UUID()
    var document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "First\n\nSecond\n\nThird",
        annotations: [
            ReviewAnnotation(id: firstID, sequence: 1, kind: .text, selectedText: "First", contextBefore: "", contextAfter: "", blockText: "First", section: "", comment: "First"),
            ReviewAnnotation(id: deletedID, sequence: 2, kind: .text, selectedText: "Second", contextBefore: "", contextAfter: "", blockText: "Second", section: "", comment: "Second"),
            ReviewAnnotation(id: lastID, sequence: 3, kind: .text, selectedText: "Third", contextBefore: "", contextAfter: "", blockText: "Third", section: "", comment: "Third")
        ]
    )

    document.remove(id: deletedID)

    #expect(document.annotations.map(\.id) == [firstID, lastID])
    #expect(document.annotations.map(\.sequence) == [1, 2])
    #expect(document.annotations.map(\.selectedText) == ["First", "Third"])
}

@Test("renumbering recovers positions from rendered Markdown syntax")
func renumberTopDownRecoversRenderedMarkdownPositions() {
    let earlier = ReviewAnnotation(
        sequence: 3,
        kind: .text,
        selectedText: "output actionable",
        contextBefore: "",
        contextAfter: "",
        blockText: "output actionable",
        section: "",
        comment: "Earlier comment."
    )
    let inlineCode = ReviewAnnotation(
        sequence: 2,
        kind: .text,
        selectedText: "Duplicating these values in .steam-mods.json creates another burden.",
        contextBefore: "",
        contextAfter: "",
        blockText: "Duplicating these values in .steam-mods.json creates another burden.",
        section: "",
        comment: "Inline code comment."
    )
    let formattedHeading = ReviewAnnotation(
        sequence: 1,
        kind: .text,
        selectedText: "6. Turn instructions into a concise exception file",
        contextBefore: "",
        contextAfter: "",
        blockText: "6. Turn instructions into a concise exception file",
        section: "",
        comment: "Heading comment."
    )
    var document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: """
        # Review

        output actionable

        Duplicating these values in \u{60}.steam-mods.json\u{60} creates another burden.

        ### 6. **Turn instructions into a concise exception file**
        """,
        annotations: [formattedHeading, inlineCode, earlier]
    )

    document.renumberTopDown()

    #expect(document.annotations.map(\.selectedText) == [
        "output actionable",
        "Duplicating these values in .steam-mods.json creates another burden.",
        "6. Turn instructions into a concise exception file"
    ])
    #expect(document.annotations.map(\.sequence) == [1, 2, 3])
}

@Test("source line hints ignore Markdown syntax around a selection")
func sourceLineHintsIgnoreMarkdownSyntax() {
    let renderer = MarkdownRenderer()
    let region = SelectedRegion(
        kind: .text,
        selectedText: "config.json",
        contextBefore: "",
        contextAfter: "",
        blockText: "Use \u{60}config.json\u{60} for the review.",
        section: ""
    )

    #expect(renderer.sourceLineHints(
        for: region,
        in: "# Review\n\nUse \u{60}config.json\u{60} for the review."
    ) == (3, 3))
}

@Test("preview review colors come from the macOS accent color")
func previewUsesSystemAccentColor() {
    let rendered = MarkdownRenderer().render("# Review")
    let accent = SystemAccentPalette.current

    #expect(rendered.contains(accent.cssRGBA(alpha: 0.45)))
    #expect(rendered.contains(accent.cssRGBA(alpha: 0.82)))
    #expect(rendered.contains(accent.cssRGBA()))
    #expect(!rendered.contains("#60a5fa"))
    #expect(!rendered.contains("rgba(0, 122, 255"))
}

@Test("region updates preserve the existing annotation identity")
func regionUpdatePreservesAnnotationIdentity() {
    let id = UUID()
    let annotation = ReviewAnnotation(
        id: id,
        sequence: 1,
        kind: .text,
        selectedText: "small part",
        contextBefore: "before ",
        contextAfter: " after",
        blockText: "before small part after",
        section: "Section",
        comment: "Keep my remark.",
        status: .resolved
    )
    var document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "before small part after",
        annotations: [annotation]
    )

    document.updateRegion(
        for: id,
        kind: .text,
        selectedText: "before small part after",
        contextBefore: "",
        contextAfter: "",
        blockText: "before small part after",
        section: "Section",
        sourceLineStart: 1,
        sourceLineEnd: 1
    )

    #expect(document.annotations.first?.id == id)
    #expect(document.annotations.first?.sequence == 1)
    #expect(document.annotations.first?.comment == "Keep my remark.")
    #expect(document.annotations.first?.status == .resolved)
    #expect(document.annotations.first?.selectedText == "before small part after")
}
