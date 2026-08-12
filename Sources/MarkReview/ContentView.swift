import AppKit
import SwiftUI

private extension Color {
    static var reviewAccent: Color {
        Color(nsColor: SystemAccentPalette.current.nsColor)
    }
}

private enum SidebarScrollAnchor: Equatable {
    case top
    case center
    case bottom
}

private struct SidebarScrollRequest: Equatable {
    let id: UUID
    let anchor: SidebarScrollAnchor
}

private let sidebarBottomAnchor = "sidebar-bottom-anchor"

private struct SidebarResizeHandle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            Divider()
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

private struct ReviewTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusToken: Int
    let accessibilityLabel: String

    private final class FocusableTextView: NSTextView {
        var shouldBecomeFirstResponder = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFirstResponderIfNeeded()
        }

        func requestFirstResponderIfNeeded() {
            guard shouldBecomeFirstResponder, let window else { return }
            guard window.firstResponder !== self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.shouldBecomeFirstResponder, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = FocusableTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? FocusableTextView else { return }
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text {
            textView.string = text
        }

        textView.shouldBecomeFirstResponder = isFocused
        if isFocused {
            if context.coordinator.lastFocusToken != focusToken {
                context.coordinator.lastFocusToken = focusToken
            }
            textView.requestFirstResponderIfNeeded()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReviewTextEditor
        var lastFocusToken: Int?

        init(_ parent: ReviewTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
}

struct ContentView: View {
    static let minimumPreviewOnlyWidth: CGFloat = 520
    static let minimumReviewWidth: CGFloat = 800

    private static let minimumPreviewFontScale = 0.75
    private static let maximumPreviewFontScale = 2.0
    private static let previewFontScaleStep = 0.1
    private static let defaultPreviewFontScale = 1.0

    @ObservedObject var document: MarkReviewDocument
    private let fileURL: URL?
    @State private var documentRevision = 0
    @State private var draftRegion: SelectedRegion?
    @State private var draftID: UUID?
    @State private var draftComment = ""
    @State private var selectedAnnotationID: UUID?
    @State private var sidebarScrollRequest: SidebarScrollRequest?
    @State private var pendingBottomScrollID: UUID?
    @State private var sidebarWidth: CGFloat = 350
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var focusedComment: CommentFocus?
    @State private var commentFocusToken = 0
    @State private var nextPreviewFocusToken = 0
    @State private var previewFocusRequest: PreviewFocusRequest?
    @State private var isSidebarVisible: Bool
    @State private var previewFontScale = ContentView.defaultPreviewFontScale
    @State private var previewContentNonce: String

    private let renderer = MarkdownRenderer()

    private enum CommentFocus: Hashable {
        case draft
        case annotation(UUID)
    }

    init(document: MarkReviewDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        let hasMarkdown = !document.originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldShowForDocumentType = !Self.isMarkdownOnly(fileURL) || !document.annotations.isEmpty
        _isSidebarVisible = State(initialValue: hasMarkdown && shouldShowForDocumentType)
        _previewContentNonce = State(initialValue: MarkdownRenderer.makeContentNonce())
    }

    private static func isMarkdownOnly(_ fileURL: URL?) -> Bool {
        fileURL?.pathExtension.caseInsensitiveCompare("md") == .orderedSame
    }

    var body: some View {
        let _ = documentRevision
        let windowActions = MarkReviewActions(
            saveDocument: saveDocument,
            closeWindow: closeWindow,
            renumberAnnotations: renumberAnnotations,
            toggleSidebar: toggleSidebar,
            isSidebarVisible: isSidebarVisible,
            zoomInPreview: zoomInPreview,
            zoomOutPreview: zoomOutPreview,
            resetPreviewZoom: resetPreviewZoom,
            canZoomInPreview: canZoomInPreview,
            canZoomOutPreview: canZoomOutPreview,
            isPreviewAtActualSize: isPreviewAtActualSize
        )
        Group {
            if document.originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    PreviewWebView(
                        html: renderer.render(
                            document.originalMarkdown,
                            contentNonce: previewContentNonce
                        ),
                        fontScale: previewFontScale,
                        annotations: previewAnnotations,
                        onRegion: handleRegion,
                        onFocusAnnotation: selectAnnotationFromPreview,
                        selectedAnnotationID: selectedAnnotationID,
                        focusRequest: previewFocusRequest,
                        onZoom: adjustPreviewFontScale,
                        onResetZoom: resetPreviewZoom
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isSidebarVisible {
                        SidebarResizeHandle()
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let startWidth = sidebarDragStartWidth ?? sidebarWidth
                                        sidebarDragStartWidth = startWidth
                                        sidebarWidth = min(max(startWidth - value.translation.width, 280), 560)
                                    }
                                    .onEnded { _ in
                                        sidebarDragStartWidth = nil
                                    }
                            )
                        sidebar
                            .frame(width: sidebarWidth)
                    }
                }
            }
        }
        .frame(
            minWidth: isSidebarVisible ? Self.minimumReviewWidth : Self.minimumPreviewOnlyWidth,
            minHeight: 680
        )
        .tint(Color(nsColor: NSColor.controlAccentColor))
        .navigationTitle(document.title)
        .focusedSceneValue(\.markReviewActions, windowActions)
        .background(WindowFrameObserver(
            identifier: document.id.uuidString,
            prepareForSave: prepareDraftForSave,
            actions: windowActions
        ))
        .onChange(of: focusedComment) { _, focus in
            switch focus {
            case .draft:
                selectedAnnotationID = draftID
            case .annotation(let id):
                selectedAnnotationID = id
            case nil:
                break
            }
        }
    }

    private var previewAnnotations: [ReviewAnnotation] {
        guard let draftRegion, let draftID else { return document.annotations }
        let draft = ReviewAnnotation(
            id: draftID,
            sequence: document.nextSequence,
            kind: draftRegion.kind,
            selectedText: draftRegion.selectedText,
            contextBefore: draftRegion.contextBefore,
            contextAfter: draftRegion.contextAfter,
            blockText: draftRegion.blockText,
            section: draftRegion.section,
            comment: draftComment
        )
        return document.annotations + [draft]
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review comments")
                .font(.headline)
                .padding(14)

            if document.annotations.isEmpty && draftRegion == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No comments yet")
                        .font(.headline)
                    Text("Select text in the document or Option-click a block.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(document.annotations) { annotation in
                                annotationCard(annotation)
                            }
                            if let draftRegion, let draftID {
                                draftCard(region: draftRegion, id: draftID)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(sidebarBottomAnchor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: sidebarScrollRequest) { _, request in
                        guard let request else { return }
                        scrollSidebar(request, using: proxy)
                    }
                    .onAppear {
                        // A new markdown document inserts this whole reader when the
                        // first selection opens the sidebar. In that case the request
                        // can exist before this change handler is installed.
                        if let request = sidebarScrollRequest {
                            scrollSidebar(request, using: proxy)
                        }
                    }
                }
            }
        }
        .background(.bar)
    }

    private func draftCard(region: SelectedRegion, id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                numberBadge(document.nextSequence, selected: true)
                Text("“\(region.selectedText)”")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)
                Spacer()
            }
            commentEditor(
                text: Binding(get: { draftComment }, set: updateDraftComment),
                placeholder: "Type your remark…",
                focus: .draft,
                focusToken: commentFocusToken,
                accessibilityLabel: "New review comment",
                onFocus: {
                    selectedAnnotationID = id
                    requestPreviewFocus(id)
                }
            )
        }
        .padding(11)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.reviewAccent.opacity(0.32), lineWidth: 1))
        .contentShape(Rectangle())
        .id("draft-\(id.uuidString)")
        .onTapGesture { selectDraft(id: id) }
    }

    private func annotationCard(_ value: ReviewAnnotation) -> some View {
        let isMuted = value.status == .muted
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                numberBadge(value.sequence, selected: selectedAnnotationID == value.id, muted: isMuted)
                Text("“\(value.selectedText)”")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)
                Spacer(minLength: 0)
            }
            commentEditor(
                text: Binding(
                    get: { document.annotations.first(where: { $0.id == value.id })?.comment ?? value.comment },
                    set: { updateComment(for: value.id, comment: $0) }
                ),
                placeholder: "Type your remark…",
                focus: .annotation(value.id),
                focusToken: commentFocusToken,
                accessibilityLabel: "Review comment \(value.sequence)",
                onFocus: {
                    selectedAnnotationID = value.id
                    requestPreviewFocus(value.id)
                }
            )
            HStack(spacing: 6) {
                Spacer()
                pillButton(isMuted ? "Unmute" : "Mute") {
                    toggleStatus(for: value.id)
                }
                pillButton("Delete") {
                    removeAnnotation(id: value.id)
                    if selectedAnnotationID == value.id {
                        selectedAnnotationID = nil
                        focusedComment = nil
                    }
                }
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(isMuted ? 0.035 : 0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedAnnotationID == value.id ? Color.reviewAccent.opacity(0.42) : Color.secondary.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
        .id("annotation-\(value.id.uuidString)")
        .onTapGesture { selectAnnotation(value.id) }
    }

    private func numberBadge(_ number: Int, selected: Bool, muted: Bool = false) -> some View {
        Text(String(number))
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(muted ? Color.secondary : (selected ? Color.reviewAccent : Color.reviewAccent.opacity(0.45)), in: Circle())
            .overlay {
                if selected {
                    Circle()
                        .stroke(Color.reviewAccent.opacity(0.35), lineWidth: 3)
                        .padding(-3)
                }
            }
            .accessibilityHidden(true)
    }

    private func commentEditor(
        text: Binding<String>,
        placeholder: String,
        focus: CommentFocus,
        focusToken: Int,
        accessibilityLabel: String,
        onFocus: @escaping () -> Void
    ) -> some View {
        let editorFocus = Binding<Bool>(
            get: { focusedComment == focus },
            set: { isFocused in
                if isFocused {
                    onFocus()
                    focusedComment = focus
                } else if focusedComment == focus {
                    focusedComment = nil
                }
            }
        )

        return ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
            ReviewTextEditor(
                text: text,
                isFocused: editorFocus,
                focusToken: focusToken,
                accessibilityLabel: accessibilityLabel
            )
                .padding(8)
                .frame(minHeight: 66, maxHeight: 120)
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.09), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("Start a Markdown review")
                .font(.title2.weight(.semibold))
            Text("Open a Markdown file, annotate passages, and save the review to give directly to your agent.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text("Use File > Open to begin.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addAnnotation(region: SelectedRegion, comment: String, id: UUID = UUID()) -> UUID {
        let lines = renderer.sourceLineHints(for: region, in: document.originalMarkdown)
        let annotation = ReviewAnnotation(
            id: id,
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
        mutateDocument { document in
            document.add(annotation)
        }
        return id
    }

    private func handleRegion(_ region: SelectedRegion) {
        isSidebarVisible = true

        if let overlappingID = overlappingAnnotationID(for: region) {
            if draftRegion != nil, !draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = promoteDraft()
            }
            draftRegion = nil
            draftID = nil
            draftComment = ""
            updateAnnotationRegion(overlappingID, with: region)
            selectedAnnotationID = overlappingID
            focusedComment = .annotation(overlappingID)
            return
        }

        if draftRegion != nil {
            if draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.draftRegion = region
                selectedAnnotationID = draftID
                if let draftID {
                    scrollDraftToBottom(draftID)
                }
                focusDraft()
                return
            }
            _ = promoteDraft()
        }
        let id = UUID()
        draftID = id
        draftRegion = region
        draftComment = ""
        selectedAnnotationID = id
        scrollDraftToBottom(id)
        focusDraft()
    }

    private func updateAnnotationRegion(_ id: UUID, with region: SelectedRegion) {
        let lines = renderer.sourceLineHints(for: region, in: document.originalMarkdown)
        mutateDocument { document in
            document.updateRegion(
                for: id,
                kind: region.kind,
                selectedText: region.selectedText,
                contextBefore: region.contextBefore,
                contextAfter: region.contextAfter,
                blockText: region.blockText,
                section: region.section,
                sourceLineStart: lines.0,
                sourceLineEnd: lines.1
            )
        }
    }

    private func overlappingAnnotationID(for region: SelectedRegion) -> UUID? {
        let newSelection = normalizeForOverlap(region.selectedText)
        guard !newSelection.isEmpty else { return nil }
        let newBlock = normalizeForOverlap(region.blockText)

        let matches = document.annotations.filter { annotation in
            let existingSelection = normalizeForOverlap(annotation.selectedText)
            guard !existingSelection.isEmpty else { return false }

            let existingBlock = normalizeForOverlap(annotation.blockText)
            let hasComparableBlocks = !newBlock.isEmpty && !existingBlock.isEmpty
            guard !hasComparableBlocks || existingBlock == newBlock else { return false }

            if newSelection.contains(existingSelection) || existingSelection.contains(newSelection) {
                return true
            }

            guard !newBlock.isEmpty, existingBlock == newBlock else { return false }
            let block = newBlock as NSString
            let existingRange = block.range(of: existingSelection)
            let newRange = block.range(of: newSelection)
            guard existingRange.location != NSNotFound, newRange.location != NSNotFound else { return false }
            return NSIntersectionRange(existingRange, newRange).length > 0
        }

        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    private func normalizeForOverlap(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func promoteDraft() -> UUID? {
        guard let draftRegion, let draftID,
              !draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id = addAnnotation(region: draftRegion, comment: draftComment, id: draftID)
        self.draftRegion = nil
        self.draftID = nil
        self.draftComment = ""
        selectedAnnotationID = id
        focusedComment = .annotation(id)
        requestPreviewFocus(id)
        pendingBottomScrollID = id
        sidebarScrollRequest = SidebarScrollRequest(id: id, anchor: .bottom)
        return id
    }

    private func updateDraftComment(_ value: String) {
        draftComment = value
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            markDocumentEdited()
        }
    }

    private func selectDraft(id: UUID) {
        selectedAnnotationID = id
        requestPreviewFocus(id)
        scrollDraftToBottom(id)
        focusDraft()
    }

    private func requestPreviewFocus(_ id: UUID) {
        nextPreviewFocusToken += 1
        previewFocusRequest = PreviewFocusRequest(annotationID: id, token: nextPreviewFocusToken)
    }

    private func scrollDraftToBottom(_ id: UUID) {
        pendingBottomScrollID = id
        sidebarScrollRequest = SidebarScrollRequest(id: id, anchor: .bottom)
    }

    private func scrollSidebar(_ request: SidebarScrollRequest, using proxy: ScrollViewProxy) {
        let targetID = request.anchor == .bottom
            ? sidebarBottomAnchor
            : (request.id == draftID
                ? "draft-\(request.id.uuidString)"
                : "annotation-\(request.id.uuidString)")
        let anchor: UnitPoint
        switch request.anchor {
        case .top:
            anchor = .top
        case .center:
            anchor = .center
        case .bottom:
            anchor = .bottom
        }

        let scroll = {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        }

        // Keep the request alive until the inserted card and its bottom anchor have
        // participated in layout. This is important when this reader was just
        // inserted by the first selection in a markdown-only document.
        DispatchQueue.main.async {
            scroll()
            DispatchQueue.main.async {
                scroll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard sidebarScrollRequest == request else { return }
                    sidebarScrollRequest = nil
                    if pendingBottomScrollID == request.id {
                        pendingBottomScrollID = nil
                    }
                }
            }
        }
    }

    private func selectAnnotation(_ id: UUID) {
        if draftCommentHasContent {
            _ = promoteDraft()
        }
        pendingBottomScrollID = nil
        selectedAnnotationID = id
        requestPreviewFocus(id)
        focusedComment = .annotation(id)
    }

    private func selectAnnotationFromPreview(_ id: UUID) {
        selectAnnotation(id)
        sidebarScrollRequest = SidebarScrollRequest(id: id, anchor: .top)
    }

    private func renumberAnnotations() {
        mutateDocument { document in
            document.renumberTopDown()
        }
        if let selectedAnnotationID {
            sidebarScrollRequest = SidebarScrollRequest(id: selectedAnnotationID, anchor: .center)
        }
    }

    private func focusDraft() {
        commentFocusToken &+= 1
        DispatchQueue.main.async {
            focusedComment = .draft
        }
    }

    private var draftCommentHasContent: Bool {
        !draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepareDraftForSave() {
        guard draftCommentHasContent else { return }
        _ = promoteDraft()
    }

    private func saveDocument() {
        prepareDraftForSave()
        guard let nativeDocument = activeNativeDocument() else { return }
        let window = nativeDocument.windowControllers.first { $0.window?.isKeyWindow == true }?.window
        if let closeGuard = window?.delegate as? ReviewWindowCloseGuard {
            closeGuard.save(nativeDocument)
        } else {
            DocumentSaveDelegate(documentID: document.id).save(nativeDocument)
        }
    }

    private func closeWindow() {
        let window = activeNativeDocument()?.windowControllers.first { $0.window?.isKeyWindow == true }?.window
            ?? NSApp.keyWindow
        window?.performClose(nil)
    }

    private func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    private var canZoomInPreview: Bool {
        previewFontScale < Self.maximumPreviewFontScale - 0.001
    }

    private var canZoomOutPreview: Bool {
        previewFontScale > Self.minimumPreviewFontScale + 0.001
    }

    private var isPreviewAtActualSize: Bool {
        abs(previewFontScale - Self.defaultPreviewFontScale) < 0.001
    }

    private func zoomInPreview() {
        adjustPreviewFontScale(1)
    }

    private func zoomOutPreview() {
        adjustPreviewFontScale(-1)
    }

    private func resetPreviewZoom() {
        previewFontScale = Self.defaultPreviewFontScale
    }

    private func adjustPreviewFontScale(_ steps: CGFloat) {
        let nextScale = previewFontScale + (steps * Self.previewFontScaleStep)
        previewFontScale = min(
            max(nextScale, Self.minimumPreviewFontScale),
            Self.maximumPreviewFontScale
        )
    }

    private func updateComment(for id: UUID, comment: String) {
        mutateDocument { document in
            document.updateComment(for: id, comment: comment)
        }
    }

    private func toggleStatus(for id: UUID) {
        mutateDocument { document in
            document.toggleStatus(for: id)
        }
    }

    private func removeAnnotation(id: UUID) {
        mutateDocument { document in
            document.remove(id: id)
        }
    }

    private func mutateDocument(_ mutation: (MarkReviewDocument) -> Void) {
        let previousDocument = document.copy()
        mutation(document)
        guard document != previousDocument else { return }
        markDocumentEdited()
    }

    private func markDocumentEdited() {
        let changeState = MarkReviewDocumentChangeState.shared
        let wasDirty = changeState.isDirty(document.id)
        changeState.markDirty(document.id)
        if !wasDirty {
            activeNativeDocument()?.updateChangeCount(.changeDone)
        }
        documentRevision &+= 1
    }

    private func activeNativeDocument() -> NSDocument? {
        NSDocumentController.shared.documents.first { document in
            document.windowControllers.contains { $0.window?.isKeyWindow == true }
        } ?? NSDocumentController.shared.currentDocument
    }
}
