import Foundation
import AppKit
import Combine
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
    #expect(decoded.agentInstructions == MarkReviewDocument.currentAgentInstructions)
    #expect(decoded.id == original.id)
    #expect(decoded.title == original.title)
    #expect(decoded.sourcePath == original.sourcePath)
    #expect(decoded.originalMarkdown == original.originalMarkdown)
    #expect(decoded.annotations.map(\.sequence) == original.annotations.map(\.sequence))
    #expect(decoded.annotations.map(\.comment) == original.annotations.map(\.comment))
}

@Test("review documents carry explicit muted-agent instructions")
func reviewDocumentsCarryMutedAgentInstructions() throws {
    let document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "Text",
        annotations: [ReviewAnnotation(
            sequence: 1,
            kind: .text,
            selectedText: "Text",
            contextBefore: "",
            contextAfter: "",
            blockText: "Text",
            section: "",
            comment: "Ignore this for now.",
            status: .muted
        )]
    )
    let data = try JSONEncoder.markReview.encode(document)
    let decoded = try JSONDecoder.markReview.decode(MarkReviewDocument.self, from: data)

    #expect(decoded.formatVersion == MarkReviewDocument.currentFormatVersion)
    #expect(decoded.agentInstructions == MarkReviewDocument.currentAgentInstructions)
    #expect(decoded.annotations.first?.status == .muted)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("Act only on annotations whose status is open"))
    #expect(json.contains("\"status\" : \"muted\""))
}

@Test("future review formats are rejected instead of overwritten")
func futureReviewFormatsAreRejected() throws {
    let data = try JSONEncoder.markReview.encode(MarkReviewDocument(originalMarkdown: "Text"))
    guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    payload["formatVersion"] = MarkReviewDocument.currentFormatVersion + 1
    let futureData = try JSONSerialization.data(withJSONObject: payload)

    var rejected = false
    do {
        _ = try JSONDecoder.markReview.decode(MarkReviewDocument.self, from: futureData)
    } catch {
        rejected = true
    }
    #expect(rejected)
}

@Test("Markdown is readable but only reviews are writable")
func documentContentTypesKeepMarkdownImportOnly() {
    #expect(MarkReviewDocument.readableContentTypes.contains(.markReviewMarkdown))
    #expect(MarkReviewDocument.readableContentTypes.contains(.markReview))
    #expect(MarkReviewDocument.writableContentTypes == [.markReview])
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
    let document = MarkReviewDocument(
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
    let document = MarkReviewDocument(
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
    let document = MarkReviewDocument(
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

@Test("source line hints use the containing block to disambiguate short selections")
func sourceLineHintsUseContainingBlock() {
    let renderer = MarkdownRenderer()
    let region = SelectedRegion(
        kind: .text,
        selectedText: "t",
        contextBefore: "Release by",
        contextAfter: "es are built once.",
        blockText: "Release bytes are built once.",
        section: "Later"
    )

    #expect(renderer.sourceLineHints(
        for: region,
        in: "# First\n\nThe first t is here.\n\n# Later\n\nRelease bytes are built once."
    ) == (7, 7))
}

@Test("preview positions review markers from the document rail")
func previewPositionsMarkersFromDocumentRail() {
    let rendered = MarkdownRenderer().render("1. First item")

    #expect(rendered.contains("id = 'review-marker-layer'"))
    #expect(rendered.contains("documentRect.left - 38"))
    #expect(rendered.contains("markerLayer.appendChild(marker)"))
    #expect(rendered.contains("positionMarkers()"))
}

@Test("preview keeps native ordered-list markers outside review markers")
func previewKeepsNativeOrderedListMarkersOutsideReviewMarkers() {
    let rendered = MarkdownRenderer().render("1. **First item**\n2. Second item")

    #expect(rendered.contains("#review-marker-layer"))
    #expect(rendered.contains("block.classList.add('review-annotated-block')") == false)
}

@Test("preview captures and restores the selected occurrence using context")
func previewCapturesAndRestoresSelectedOccurrenceUsingContext() {
    let rendered = MarkdownRenderer().render("One letter: a. Another letter: a.")

    #expect(rendered.contains("const contextScope = block.contains(endElement) ? block : root"))
    #expect(rendered.contains("contextForSelection(contextScope, selectionRange)"))
    #expect(rendered.contains("function findTextRange(text, item)"))
    #expect(rendered.contains("expectedBefore && candidateBefore.endsWith(expectedBefore)"))
    #expect(rendered.contains("expectedAfter && candidateAfter.startsWith(expectedAfter)"))
}

@Test("preview supports runtime font scaling without replacing the document")
func previewSupportsRuntimeFontScaling() {
    let nonce = "stable-preview-window"
    let renderer = MarkdownRenderer()
    let rendered = renderer.render("# Review", contentNonce: nonce)

    #expect(rendered.contains("--markdown-font-scale: 1"))
    #expect(rendered.contains("font-size: calc(16px * var(--markdown-font-scale))"))
    #expect(rendered.contains("window.setMarkdownFontScale = scale"))
    #expect(rendered == renderer.render("# Review", contentNonce: nonce))
    #expect(rendered != renderer.render("# Review", contentNonce: "different-preview-window"))
}

@Test("wide Markdown content scrolls locally instead of widening the document")
func wideMarkdownContentDoesNotWidenDocument() {
    let rendered = MarkdownRenderer().render("| Very wide value |\n|---|\n| value |\n\n```text\nvalue\n```")

    #expect(rendered.contains("pre { max-width: 100%;"))
    #expect(rendered.contains("table { display: block; width: 100%; max-width: 100%; overflow-x: auto;"))
    #expect(rendered.contains("a, :not(pre) > code { overflow-wrap: anywhere; }"))
}

@Test("Markdown-only windows can be narrower than review windows")
func markdownOnlyWindowsHaveAdaptiveMinimumWidth() {
    #expect(ContentView.minimumPreviewOnlyWidth == 520)
    #expect(ContentView.minimumPreviewOnlyWidth < ContentView.minimumReviewWidth)
}

@Test("preview zoom inputs work while WebKit owns keyboard focus")
func previewZoomInputs() {
    #expect(PreviewZoomInput.keyCommand(
        charactersIgnoringModifiers: "-",
        modifiers: [.command]
    ) == .adjust(-1))
    #expect(PreviewZoomInput.keyCommand(
        charactersIgnoringModifiers: "=",
        modifiers: [.command, .shift]
    ) == .adjust(1))
    #expect(PreviewZoomInput.keyCommand(
        charactersIgnoringModifiers: "0",
        modifiers: [.command]
    ) == .reset)
    #expect(PreviewZoomInput.keyCommand(
        charactersIgnoringModifiers: "-",
        modifiers: []
    ) == nil)
    #expect(PreviewZoomInput.usesScrollZoom(modifiers: [.option]))
    #expect(PreviewZoomInput.usesScrollZoom(modifiers: [.command]))
    #expect(!PreviewZoomInput.usesScrollZoom(modifiers: []))
}

@Test("preview stacks same-row review markers for hover inspection")
func previewStacksSameRowReviewMarkersForHoverInspection() {
    let rendered = MarkdownRenderer().render("First repeated text")

    #expect(rendered.contains("--stack-offset"))
    #expect(rendered.contains("sameRowMarkers"))
    #expect(rendered.contains(".review-marker:hover"))
    #expect(rendered.contains(".review-marker.review-selected:hover"))
    #expect(rendered.contains("z-index: 100"))
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

@Test("preview confines executable content to MarkReview's nonce")
func previewUsesRestrictiveContentSecurityPolicy() {
    let rendered = MarkdownRenderer().render("<script>alert('untrusted')</script>")

    #expect(rendered.contains("default-src 'none'"))
    #expect(rendered.contains("script-src 'nonce-"))
    #expect(rendered.contains("style-src 'nonce-"))
    #expect(rendered.contains("form-action 'none'"))
    #expect(!rendered.contains("__MARKREVIEW_CONTENT_NONCE__"))
    #expect(!rendered.contains("'unsafe-inline'"))
}

@Test("preview opens only ordinary web links outside its isolated document")
func previewNavigationIsRestricted() {
    #expect(PreviewNavigationPolicy.opensExternally(URL(string: "https://example.com")!))
    #expect(PreviewNavigationPolicy.opensExternally(URL(string: "mailto:review@example.com")!))
    #expect(!PreviewNavigationPolicy.opensExternally(URL(string: "file:///tmp/source")!))
    #expect(!PreviewNavigationPolicy.opensExternally(URL(string: "javascript:alert(1)")!))
    #expect(PreviewNavigationPolicy.allowsInPreview(URL(string: "about:blank")!))
    #expect(!PreviewNavigationPolicy.allowsInPreview(URL(string: "https://example.com")!))
}

@Test("muted annotations are explicitly non-actionable in the preview")
func previewMarksMutedAnnotationsAsIgnored() {
    let rendered = MarkdownRenderer().render("Text")

    #expect(rendered.contains("item.status === 'muted'"))
    #expect(rendered.contains("muted and ignored by agents"))
    #expect(rendered.contains(".review-outline.review-muted"))
}

@Test("document change state tracks edits until explicitly cleared")
@MainActor
func documentChangeStateTracksEditsUntilExplicitlyCleared() {
    let id = UUID()
    let state = MarkReviewDocumentChangeState.shared

    #expect(!state.isDirty(id))
    state.markDirty(id)
    #expect(state.isDirty(id))
    state.clear(id)
    #expect(!state.isDirty(id))
}

@Test("reference document snapshots are detached from later edits")
func referenceDocumentSnapshotsAreDetachedFromLaterEdits() throws {
    let id = UUID()
    let document = MarkReviewDocument(
        id: id,
        title: "Review",
        originalMarkdown: "Text",
        annotations: [ReviewAnnotation(
            id: UUID(),
            sequence: 1,
            kind: .text,
            selectedText: "Text",
            contextBefore: "",
            contextAfter: "",
            blockText: "Text",
            section: "",
            comment: "Before"
        )]
    )

    let snapshot = try document.snapshot(contentType: .markReview)
    document.updateComment(for: document.annotations[0].id, comment: "After")

    #expect(snapshot.id == id)
    #expect(snapshot.annotations[0].comment == "Before")
    #expect(document.annotations[0].comment == "After")
}

@Test("reference document edits do not publish automatic save events")
func referenceDocumentEditsDoNotPublishAutomaticSaveEvents() {
    let document = MarkReviewDocument(
        title: "Review",
        originalMarkdown: "Text",
        annotations: [ReviewAnnotation(
            sequence: 1,
            kind: .text,
            selectedText: "Text",
            contextBefore: "",
            contextAfter: "",
            blockText: "Text",
            section: "",
            comment: "Before"
        )]
    )
    var emissionCount = 0
    let observation = document.objectWillChange.sink { _ in emissionCount += 1 }

    document.updateComment(for: document.annotations[0].id, comment: "After")

    observation.cancel()
    #expect(emissionCount == 0)
}

@Test("successful saves clear the app-owned dirty state")
@MainActor
func successfulSavesClearAppOwnedDirtyState() {
    let id = UUID()
    let state = MarkReviewDocumentChangeState.shared
    let delegate = DocumentSaveDelegate(documentID: id)

    state.markDirty(id)
    delegate.documentDidSave(NSDocument(), didSave: true, contextInfo: nil)

    #expect(!state.isDirty(id))
}

@Test("failed saves keep the app-owned dirty state")
@MainActor
func failedSavesKeepAppOwnedDirtyState() {
    let id = UUID()
    let state = MarkReviewDocumentChangeState.shared
    let delegate = DocumentSaveDelegate(documentID: id)

    state.markDirty(id)
    delegate.documentDidSave(NSDocument(), didSave: false, contextInfo: nil)

    #expect(state.isDirty(id))
    state.clear(id)
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
        status: .muted
    )
    let document = MarkReviewDocument(
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
    #expect(document.annotations.first?.status == .muted)
    #expect(document.annotations.first?.selectedText == "before small part after")
}
