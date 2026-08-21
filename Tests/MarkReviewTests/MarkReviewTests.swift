import Foundation
import AppKit
import Combine
import Testing
import UniformTypeIdentifiers
@testable import MarkReview

@Test("recent documents wait until app launch completes before querying AppKit")
@MainActor
func recentDocumentsDeferInitialLoad() {
    let store = RecentDocumentsStore()

    #expect(store.urls.isEmpty)
}

@Test("Escape deselects comments and removes only blank ones")
func escapeUsesCommentContentToChooseItsAction() {
    #expect(ReviewCommentEscapeAction.action(for: "Keep this comment") == .deselect)
    #expect(ReviewCommentEscapeAction.action(for: "") == .remove)
    #expect(ReviewCommentEscapeAction.action(for: " \n\t ") == .remove)
}

@Test("review editors handle Escape without consuming ordinary text commands")
@MainActor
func reviewEditorsHandleEscapeAsACommentExit() {
    var escapeCount = 0
    let editor = ReviewTextEditor(
        text: .constant("Comment"),
        isFocused: .constant(true),
        focusToken: 1,
        accessibilityLabel: "Review comment",
        onEscape: { escapeCount += 1 }
    )
    let coordinator = editor.makeCoordinator()
    let textView = NSTextView()

    #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    #expect(escapeCount == 1)
    #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    #expect(escapeCount == 1)
}

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
        previewFontScale: 1.5,
        previewScrollPosition: 0.42,
        selectedAnnotationID: annotation.id,
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
    #expect(decoded.previewFontScale == original.previewFontScale)
    #expect(decoded.previewScrollPosition == original.previewScrollPosition)
    #expect(decoded.selectedAnnotationID == annotation.id)
    #expect(decoded.annotations.map(\.sequence) == original.annotations.map(\.sequence))
    #expect(decoded.annotations.map(\.comment) == original.annotations.map(\.comment))
}

@Test("older review documents open with default preview state")
func olderReviewDocumentsUseDefaultPreviewState() throws {
    let current = MarkReviewDocument(
        originalMarkdown: "Text",
        previewFontScale: 1.5,
        previewScrollPosition: 0.42
    )
    let data = try JSONEncoder.markReview.encode(current)
    guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    payload.removeValue(forKey: "previewFontScale")
    payload.removeValue(forKey: "previewScrollPosition")
    payload.removeValue(forKey: "selectedAnnotationID")
    let olderData = try JSONSerialization.data(withJSONObject: payload)

    let decoded = try JSONDecoder.markReview.decode(MarkReviewDocument.self, from: olderData)

    #expect(decoded.formatVersion == MarkReviewDocument.currentFormatVersion)
    #expect(decoded.previewFontScale == MarkReviewDocument.defaultPreviewFontScale)
    #expect(decoded.previewScrollPosition == MarkReviewDocument.defaultPreviewScrollPosition)
    #expect(decoded.selectedAnnotationID == nil)
}

@Test("persisted preview state is constrained to supported values")
func persistedPreviewStateUsesSupportedValues() {
    let annotation = ReviewAnnotation(
        sequence: 1,
        kind: .text,
        selectedText: "Text",
        contextBefore: "",
        contextAfter: "",
        blockText: "Text",
        section: "",
        comment: "Comment"
    )
    let document = MarkReviewDocument(
        originalMarkdown: "Text",
        previewFontScale: 4,
        previewScrollPosition: -1,
        selectedAnnotationID: UUID(),
        annotations: [annotation]
    )

    #expect(document.previewFontScale == MarkReviewDocument.maximumPreviewFontScale)
    #expect(document.previewScrollPosition == 0)
    #expect(document.selectedAnnotationID == nil)
    #expect(MarkReviewDocument.minimumPreviewFontScale == 0.5)
    #expect(MarkReviewDocument.maximumPreviewFontScale == 3.0)
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

@Test("Markdown sources always require a review destination")
@MainActor
func markdownSourcesRequireReviewDestination() {
    #expect(MarkReviewSavePolicy.requiresReviewDestination(URL(fileURLWithPath: "/tmp/Review.md")))
    #expect(MarkReviewSavePolicy.requiresReviewDestination(URL(fileURLWithPath: "/tmp/Review.MD")))
    #expect(!MarkReviewSavePolicy.requiresReviewDestination(URL(fileURLWithPath: "/tmp/Review.markreview")))
    #expect(!MarkReviewSavePolicy.requiresReviewDestination(nil))
}

@Test("saving a Markdown source switches the native writable type")
@MainActor
func markdownSavePolicySelectsReviewType() {
    let document = NSDocument()
    document.fileURL = URL(fileURLWithPath: "/tmp/Review.md")
    document.fileType = UTType.markReviewMarkdown.identifier

    #expect(MarkReviewSavePolicy.requiresReviewDestination(document.fileURL))
    MarkReviewSavePolicy.prepareReviewDestination(for: document)
    #expect(document.fileType == UTType.markReview.identifier)
    #expect(document.fileURL?.pathExtension == "md")
}

@Test("the serializer refuses Markdown destinations")
func serializerRefusesMarkdownDestinations() throws {
    let document = MarkReviewDocument(title: "Review", originalMarkdown: "# Source")

    #expect(throws: MarkReviewDocumentWriteError.self) {
        _ = try document.snapshot(contentType: .markReviewMarkdown)
    }
    let snapshot = try document.snapshot(contentType: .markReview)
    #expect(snapshot.originalMarkdown == "# Source")
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
        selectedAnnotationID: deletedID,
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
    #expect(document.selectedAnnotationID == nil)
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
    #expect(rendered.contains("#review-outline-layer { position: absolute"))
    #expect(rendered.contains("left: rect.left + window.scrollX"))
    #expect(rendered.contains("top: rect.top + window.scrollY"))
    #expect(rendered.contains("Array.from(range.getClientRects(), rectInDocument)"))
}

@Test("preview keeps native ordered-list markers outside review markers")
func previewKeepsNativeOrderedListMarkersOutsideReviewMarkers() {
    let rendered = MarkdownRenderer().render("1. **First item**\n2. Second item")

    #expect(rendered.contains("#review-marker-layer"))
    #expect(rendered.contains("block.classList.add('review-annotated-block')") == false)
}

@Test("preview preserves ordered task numbers while hiding unordered task bullets")
func previewPreservesOrderedTaskNumbers() {
    let rendered = MarkdownRenderer().render("- [ ] Unordered task\n\n1. [x] Ordered task")

    #expect(rendered.contains("<ul>"))
    #expect(rendered.contains("<ol>"))
    #expect(rendered.contains("ul > li:has(> input[type=\"checkbox\"]) { list-style: none; }"))
    #expect(rendered.contains("\n        li:has(> input[type=\"checkbox\"]) { list-style: none; }") == false)
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
    #expect(rendered.contains("#document { max-width: 56.25em;"))
    #expect(rendered.contains("max-width: 900px") == false)
    #expect(rendered.contains("input[type=\"checkbox\"] { font-size: inherit; width: .875em; height: .875em;"))
    #expect(rendered.contains("vertical-align: -.125em;"))
    #expect(rendered.contains("window.setMarkdownFontScale = scale"))
    #expect(rendered.contains("3.0,"))
    #expect(rendered.contains("Math.max(0.5, Number(scale) || 1)"))
    #expect(rendered.contains("__MARKREVIEW_MIN_FONT_SCALE__") == false)
    #expect(rendered.contains("__MARKREVIEW_MAX_FONT_SCALE__") == false)
    #expect(rendered == renderer.render("# Review", contentNonce: nonce))
    #expect(rendered != renderer.render("# Review", contentNonce: "different-preview-window"))
}

@Test("preview restores its saved scroll position independently of selection")
func previewReportsAndRestoresScrollPosition() {
    let rendered = MarkdownRenderer().render("# Review\n\nText")
    let compact = rendered.filter { !$0.isWhitespace }

    #expect(rendered.contains("window.setPreviewScrollPosition = position"))
    #expect(compact.contains("window.restorePreviewViewport=position=>{window.setPreviewScrollPosition(position);window.requestAnimationFrame"))
    #expect(rendered.contains("window.requestAnimationFrame(() => window.requestAnimationFrame"))
    #expect(rendered.contains("window.setPreviewScrollPosition(position)"))
    #expect(rendered.contains("!window.focusAnnotation(selectedID, 'auto')") == false)
    #expect(rendered.contains("document.documentElement.scrollHeight - window.innerHeight"))
    #expect(rendered.contains("type: 'previewScrollPosition'"))
    #expect(rendered.contains("userInitiated: !isRestoringPreviewViewport"))
    #expect(rendered.contains("isRestoringPreviewViewport = false"))
}

@Test("preview keeps the centered text position near the center across layout reflow")
func previewPreservesCenteredTextAcrossLayoutReflow() {
    let rendered = MarkdownRenderer().render("# Review\n\nText")
    let compact = rendered.filter { !$0.isWhitespace }

    #expect(rendered.contains("function captureViewportCenterAnchor()"))
    #expect(rendered.contains("const centerY = window.innerHeight * 0.5"))
    #expect(rendered.contains("const adjustment = rect.top - anchor.viewportY"))
    #expect(rendered.contains("window.scrollBy({ top: adjustment, behavior: 'auto' })"))
    #expect(compact.contains("functionpreserveViewportCenterDuringResize(){if(isRestoringPreviewViewport)return;"))
    #expect(rendered.contains("window.addEventListener('resize', preserveViewportCenterDuringResize)"))
    #expect(rendered.contains("userInitiated: !isRestoringPreviewViewport && !isPreservingReflowViewport"))
    #expect(compact.contains("rebuildAnnotationGeometry();viewportAnchor=captureViewportCenterAnchor();"))
    #expect(rendered.contains("if (!isRestoringPreviewViewport) beginViewportReflow(true)"))
    #expect(rendered.contains("document.documentElement.style.setProperty('--markdown-font-scale', normalized)"))
    #expect(rendered.contains("scheduleViewportReflowAdjustment()"))
    #expect(rendered.contains("function scheduleViewportAnchorCapture()"))
    #expect(rendered.contains("const generation = ++reflowGeneration"))
    #expect(rendered.components(separatedBy: "if (generation !== reflowGeneration) return").count == 3)
}

@Test("wide Markdown content scrolls locally instead of widening the document")
func wideMarkdownContentDoesNotWidenDocument() {
    let rendered = MarkdownRenderer().render("| Very wide value |\n|---|\n| value |\n\n```text\nvalue\n```")

    #expect(rendered.contains("pre { max-width: 100%;"))
    #expect(rendered.contains("table { display: block; width: 100%; max-width: 100%; overflow-x: auto;"))
    #expect(rendered.contains("a, :not(pre) > code { overflow-wrap: anywhere; }"))
}

@Test("preview escapes HTML-like code in fenced blocks and tables")
func previewEscapesHTMLLikeCode() {
    let rendered = MarkdownRenderer().render(
        """
        ```html
        <script>
        ```

        | Example |
        | --- |
        | `<section>` |
        """
    )

    #expect(rendered.contains("<pre><code class=\"language-html\">&lt;script&gt;"))
    #expect(rendered.contains("<td><code>&lt;section&gt;</code></td>"))
    #expect(rendered.contains("<script>") == false)
}

@Test("preview displays raw HTML as inert source")
func previewDisplaysRawHTMLAsInertSource() {
    let rendered = MarkdownRenderer().render("<script>document.body.remove()</script>")

    #expect(rendered.contains("<pre><code class=\"language-html\">&lt;script&gt;document.body.remove()&lt;/script&gt;"))
    #expect(rendered.contains("<script>document.body.remove()</script>") == false)
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

@Test("preview find inputs use standard document search shortcuts")
func previewFindInputs() {
    #expect(PreviewFindInput.keyCommand(
        charactersIgnoringModifiers: "f",
        modifiers: [.command]
    ) == .show)
    #expect(PreviewFindInput.keyCommand(
        charactersIgnoringModifiers: "g",
        modifiers: [.command]
    ) == .next)
    #expect(PreviewFindInput.keyCommand(
        charactersIgnoringModifiers: "g",
        modifiers: [.command, .shift]
    ) == .previous)
    #expect(PreviewFindInput.keyCommand(
        charactersIgnoringModifiers: "f",
        modifiers: [.command, .option]
    ) == nil)
    #expect(PreviewFindInput.keyCommand(
        charactersIgnoringModifiers: "f",
        modifiers: []
    ) == nil)
}

@Test("preview find results validate the active occurrence")
func previewFindResultsValidateActiveOccurrence() {
    let result = PreviewWebView.Coordinator.parseFindResult([
        "query": "method",
        "count": 4,
        "activeIndex": 2
    ])
    let missingActiveResult = PreviewWebView.Coordinator.parseFindResult([
        "query": "method",
        "count": 4,
        "activeIndex": 7
    ])

    #expect(result == PreviewFindResult(query: "method", matchCount: 4, activeMatchIndex: 2))
    #expect(missingActiveResult == PreviewFindResult(query: "method", matchCount: 4, activeMatchIndex: nil))
    #expect(PreviewWebView.Coordinator.parseFindResult(["query": "method"]) == nil)
}

@Test("preview finds rendered content without rewriting the Markdown DOM")
func previewFindsRenderedContentWithoutRewritingDOM() {
    let rendered = MarkdownRenderer().render("Method one. Method two.")

    #expect(rendered.contains("function searchableTextIndex()"))
    #expect(rendered.contains("function rangesForContentFind(query)"))
    #expect(rendered.contains("window.setContentFindQuery = query"))
    #expect(rendered.contains("window.navigateContentFind = direction"))
    #expect(rendered.contains("window.navigateContentFindBy = delta"))
    #expect(rendered.contains("id = 'content-find-layer'"))
    #expect(rendered.contains("id = 'content-find-marker-layer'"))
    #expect(rendered.contains("marker.textContent = '!'"))
    #expect(rendered.contains("row.matchIndices.includes(currentContentFindIndex)"))
    #expect(rendered.contains("sameRowReviewMarkers"))
    #expect(rendered.contains("--find-offset"))
    #expect(rendered.contains("marker.style.setProperty('--find-offset', '10px')"))
    #expect(rendered.contains("function reconcileContentFindMarkerCollisions()"))
    #expect(rendered.contains("content-find-current"))
    #expect(rendered.contains("redrawContentFindHighlights()"))
    #expect(rendered.contains("function updateContentFindActiveState(previousIndex)"))
    #expect(rendered.contains("updateContentFindActiveState(previousIndex);"))
    #expect(rendered.contains("document.createElement('mark')") == false)
}

@Test("rapid find navigation keeps every coalesced step")
func rapidFindNavigationKeepsEveryStep() {
    let coordinator = PreviewWebView.Coordinator(
        onRegion: { _ in },
        onFocusAnnotation: { _ in },
        onScrollPositionChange: { _, _ in },
        onFontScaleChange: { _, _ in }
    )
    coordinator.appliedFindNavigationOffset = 2
    coordinator.pendingFindNavigationRequest = PreviewFindNavigationRequest(offset: 7)

    #expect(coordinator.pendingFindNavigationDelta == 5)

    coordinator.appliedFindNavigationOffset = 7
    coordinator.pendingFindNavigationRequest = PreviewFindNavigationRequest(offset: 3)

    #expect(coordinator.pendingFindNavigationDelta == -4)
}

@Test("precise scroll zoom follows every gesture update proportionally")
func preciseScrollZoomIsContinuous() {
    #expect(PreviewZoomInput.preciseScrollSteps(for: 0.25) > 0)
    #expect(PreviewZoomInput.preciseScrollSteps(for: 12) == 1)
    #expect(PreviewZoomInput.preciseScrollSteps(for: -6) == -0.5)
    #expect(PreviewZoomInput.adjustedFontScale(1, steps: 0.5) == 1.05)
    #expect(PreviewZoomInput.adjustedFontScale(3, steps: 1) == 3)
    #expect(PreviewZoomInput.adjustedFontScale(0.5, steps: -1) == 0.5)
}

@Test("WebKit zoom applies and records a font change before settling SwiftUI state")
func webKitZoomAppliesImmediately() {
    var changes: [(scale: CGFloat, phase: PreviewFontScaleChangePhase)] = []
    let coordinator = PreviewWebView.Coordinator(
        onRegion: { _ in },
        onFocusAnnotation: { _ in },
        onScrollPositionChange: { _, _ in },
        onFontScaleChange: { scale, phase in
            changes.append((scale, phase))
        }
    )
    coordinator.updatePendingFontScale(1)

    coordinator.adjustFontScaleImmediately(by: 0.5)
    coordinator.cancelFontScaleSettlement()

    #expect(changes.count == 1)
    #expect(changes.first?.scale == 1.05)
    #expect(changes.first?.phase == .changing)
    #expect(coordinator.appliedFontScale == nil)
    #expect(coordinator.stagedFontScale == 1.05)
}

@Test("preview queues only one navigation per HTML revision")
func previewLoadsEachHTMLRevisionOnce() {
    let coordinator = PreviewWebView.Coordinator(
        onRegion: { _ in },
        onFocusAnnotation: { _ in },
        onScrollPositionChange: { _, _ in },
        onFontScaleChange: { _, _ in }
    )

    #expect(coordinator.prepareHTMLLoad("first"))
    coordinator.isReady = true
    coordinator.appliedFontScale = 1
    coordinator.didRestoreInitialViewport = true
    coordinator.appliedFocusRequestToken = 1

    #expect(!coordinator.prepareHTMLLoad("first"))
    #expect(coordinator.isReady)
    #expect(coordinator.didRestoreInitialViewport)

    #expect(coordinator.prepareHTMLLoad("second"))
    #expect(!coordinator.isReady)
    #expect(coordinator.appliedFontScale == nil)
    #expect(!coordinator.didRestoreInitialViewport)
    #expect(coordinator.appliedFocusRequestToken == nil)
}

@Test("unchanged annotations do not rebuild their geometry during zoom")
func unchangedAnnotationsDoNotRebuildDuringZoom() {
    let annotation = ReviewAnnotation(
        sequence: 1,
        kind: .text,
        selectedText: "Text",
        contextBefore: "",
        contextAfter: "",
        blockText: "Text",
        section: "",
        comment: "Review"
    )
    let coordinator = PreviewWebView.Coordinator(
        onRegion: { _ in },
        onFocusAnnotation: { _ in },
        onScrollPositionChange: { _, _ in },
        onFontScaleChange: { _, _ in }
    )
    coordinator.pendingAnnotations = [annotation]
    coordinator.pendingSelectedAnnotationID = annotation.id

    #expect(coordinator.pendingAnnotationUpdate == .all)

    coordinator.appliedAnnotations = [annotation]
    coordinator.appliedSelectedAnnotationID = annotation.id
    #expect(coordinator.pendingAnnotationUpdate == .none)

    coordinator.pendingSelectedAnnotationID = nil
    #expect(coordinator.pendingAnnotationUpdate == .selection(nil))
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

@Test("preview keeps configured review color separate from the macOS tint color")
func previewSeparatesReviewAndFindColors() {
    let reviewColor = ReviewColorPreset.purple.palette
    let findColor = AppColorPalette.systemAccent
    let rendered = MarkdownRenderer().render("# Review", reviewColor: reviewColor)

    #expect(rendered.contains(reviewColor.cssRGBA(alpha: 0.45)))
    #expect(rendered.contains(reviewColor.cssRGBA(alpha: 0.82)))
    #expect(rendered.contains(reviewColor.cssRGBA()))
    #expect(rendered.contains("background: \(findColor.cssRGBA(alpha: 0.22))"))
    #expect(rendered.contains("box-shadow: 0 0 0 2px \(findColor.cssRGBA(alpha: 0.82))"))
    #expect(rendered.contains("accent-color: \(findColor.cssRGBA())"))
    #expect(!rendered.contains("__REVIEW_ACCENT_"))
    #expect(!rendered.contains("__FIND_ACCENT_"))
}

@Test("review color preference defaults to orange and persists custom colors")
@MainActor
func reviewColorPreferencePersists() throws {
    let suiteName = "MarkReviewTests.reviewColor.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initialStore = ReviewColorStore(defaults: defaults)
    #expect(initialStore.palette == ReviewColorPreset.orange.palette)

    let customColor = AppColorPalette(red: 0.12, green: 0.34, blue: 0.56)
    initialStore.set(customColor)

    #expect(initialStore.palette == customColor)
    #expect(ReviewColorStore(defaults: defaults).palette == customColor)
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
    let annotationID = UUID()
    let document = MarkReviewDocument(
        id: id,
        title: "Review",
        originalMarkdown: "Text",
        previewFontScale: 1.4,
        previewScrollPosition: 0.35,
        selectedAnnotationID: annotationID,
        annotations: [ReviewAnnotation(
            id: annotationID,
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
    document.previewFontScale = 1.8
    document.previewScrollPosition = 0.8
    document.selectedAnnotationID = nil

    #expect(snapshot.id == id)
    #expect(snapshot.previewFontScale == 1.4)
    #expect(snapshot.previewScrollPosition == 0.35)
    #expect(snapshot.selectedAnnotationID == annotationID)
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
