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
