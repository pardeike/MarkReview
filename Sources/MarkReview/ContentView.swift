import AppKit
import SwiftUI

private extension Color {
    static let reviewBlue = Color(red: 0, green: 122.0 / 255.0, blue: 1)
}

private struct CommentFrame: Equatable {
    let id: UUID
    let minY: CGFloat
}

private struct CommentFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CommentFrame] = []

    static func reduce(value: inout [CommentFrame], nextValue: () -> [CommentFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private enum SidebarScrollAnchor: Equatable {
    case center
    case bottom
}

private struct SidebarScrollRequest: Equatable {
    let id: UUID
    let anchor: SidebarScrollAnchor
}

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

        let textView = NSTextView()
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

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }

        guard isFocused, let window = scrollView.window else { return }
        if window.firstResponder !== textView {
            DispatchQueue.main.async {
                window.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReviewTextEditor

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
    @Binding var document: MarkReviewDocument
    @State private var draftRegion: SelectedRegion?
    @State private var draftID: UUID?
    @State private var draftComment = ""
    @State private var selectedAnnotationID: UUID?
    @State private var sidebarScrollRequest: SidebarScrollRequest?
    @State private var pendingBottomScrollID: UUID?
    @State private var sidebarWidth: CGFloat = 350
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var focusedComment: CommentFocus?
    @State private var nextPreviewFocusToken = 0
    @State private var previewFocusRequest: PreviewFocusRequest?
    @State private var lastSidebarFollowID: UUID?

    private let renderer = MarkdownRenderer()

    private enum CommentFocus: Hashable {
        case draft
        case annotation(UUID)
    }

    var body: some View {
        Group {
            if document.originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    PreviewWebView(
                        html: renderer.render(document.originalMarkdown),
                        annotations: previewAnnotations,
                        onRegion: handleRegion,
                        onFocusAnnotation: selectAnnotation,
                        onVisibleAnnotation: handlePreviewVisibility,
                        selectedAnnotationID: selectedAnnotationID,
                        focusRequest: previewFocusRequest
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(minWidth: 980, minHeight: 680)
        .navigationTitle(document.title)
        .focusedSceneValue(\.markReviewActions, MarkReviewActions(
            importMarkdown: importMarkdown,
            exportAgentJSON: exportAgentJSON,
            renumberAnnotations: renumberAnnotations,
            canExportAgentJSON: !document.originalMarkdown.isEmpty
        ))
        .background(WindowFrameObserver(identifier: document.id.uuidString))
        .onReceive(NotificationCenter.default.publisher(for: .markReviewDocumentImport)) { _ in
            importMarkdown()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markReviewDocumentExport)) { _ in
            exportAgentJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markReviewDocumentRenumber)) { _ in
            renumberAnnotations()
        }
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
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach($document.annotations) { $annotation in
                                annotationCard($annotation)
                            }
                            if let draftRegion, let draftID {
                                draftCard(region: draftRegion, id: draftID)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .coordinateSpace(name: "review-sidebar-scroll")
                    .onPreferenceChange(CommentFramePreferenceKey.self) { frames in
                        syncFromSidebarScroll(frames)
                    }
                    .onChange(of: sidebarScrollRequest) { _, request in
                        guard let request else { return }
                        sidebarScrollRequest = nil
                        let targetID = request.id == draftID
                            ? "draft-\(request.id.uuidString)"
                            : "annotation-\(request.id.uuidString)"
                        let anchor: UnitPoint = request.anchor == .bottom ? .bottom : .center
                        let scroll = {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(targetID, anchor: anchor)
                            }
                        }
                        DispatchQueue.main.async {
                            scroll()
                            if request.anchor == .bottom {
                                DispatchQueue.main.async {
                                    scroll()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        if pendingBottomScrollID == request.id {
                                            lastSidebarFollowID = request.id
                                            pendingBottomScrollID = nil
                                        }
                                    }
                                }
                            }
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
                onFocus: {
                    selectedAnnotationID = id
                    requestPreviewFocus(id)
                }
            )
        }
        .padding(11)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.reviewBlue.opacity(0.32), lineWidth: 1))
        .contentShape(Rectangle())
        .id("draft-\(id.uuidString)")
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: CommentFramePreferenceKey.self,
                value: [CommentFrame(id: id, minY: geometry.frame(in: .named("review-sidebar-scroll")).minY)]
            )
        })
        .onTapGesture { selectDraft(id: id) }
    }

    private func annotationCard(_ annotation: Binding<ReviewAnnotation>) -> some View {
        let value = annotation.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                numberBadge(value.sequence, selected: selectedAnnotationID == value.id)
                Text("“\(value.selectedText)”")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)
                Spacer(minLength: 0)
            }
            commentEditor(
                text: Binding(
                    get: { annotation.wrappedValue.comment },
                    set: { document.updateComment(for: value.id, comment: $0) }
                ),
                placeholder: "Type your remark…",
                focus: .annotation(value.id),
                onFocus: {
                    selectedAnnotationID = value.id
                    requestPreviewFocus(value.id)
                }
            )
            HStack(spacing: 6) {
                Spacer()
                pillButton(value.status == .open ? "Resolve" : "Reopen") {
                    document.toggleStatus(for: value.id)
                }
                pillButton("Delete") {
                    document.remove(id: value.id)
                    if selectedAnnotationID == value.id {
                        selectedAnnotationID = nil
                        focusedComment = nil
                    }
                }
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedAnnotationID == value.id ? Color.reviewBlue.opacity(0.42) : Color.secondary.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
        .id("annotation-\(value.id.uuidString)")
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: CommentFramePreferenceKey.self,
                value: [CommentFrame(id: value.id, minY: geometry.frame(in: .named("review-sidebar-scroll")).minY)]
            )
        })
        .onTapGesture { selectAnnotation(value.id) }
    }

    private func numberBadge(_ number: Int, selected: Bool) -> some View {
        Text(String(number))
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(selected ? Color.reviewBlue : Color.reviewBlue.opacity(0.45), in: Circle())
            .overlay {
                if selected {
                    Circle()
                        .stroke(Color.reviewBlue.opacity(0.35), lineWidth: 3)
                        .padding(-3)
                }
            }
    }

    private func commentEditor(
        text: Binding<String>,
        placeholder: String,
        focus: CommentFocus,
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
            ReviewTextEditor(text: text, isFocused: editorFocus)
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
            Text("Open or import a Markdown file, annotate passages, and export a numbered JSON review for your agent.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text("Use File > Open or File > Import Markdown… to begin.")
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
        document.add(annotation)
        return id
    }

    private func handleRegion(_ region: SelectedRegion) {
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

    private func overlappingAnnotationID(for region: SelectedRegion) -> UUID? {
        let newSelection = normalizeForOverlap(region.selectedText)
        guard !newSelection.isEmpty else { return nil }
        let newBlock = normalizeForOverlap(region.blockText)

        let matches = document.annotations.filter { annotation in
            let existingSelection = normalizeForOverlap(annotation.selectedText)
            guard !existingSelection.isEmpty else { return false }

            if newSelection.contains(existingSelection) || existingSelection.contains(newSelection) {
                return true
            }

            let existingBlock = normalizeForOverlap(annotation.blockText)
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
            _ = promoteDraft()
        }
    }

    private func selectDraft(id: UUID) {
        selectedAnnotationID = id
        requestPreviewFocus(id)
        scrollDraftToBottom(id)
        focusDraft()
    }

    private func requestPreviewFocus(_ id: UUID, selectsAnnotation: Bool = true) {
        nextPreviewFocusToken += 1
        lastSidebarFollowID = id
        previewFocusRequest = PreviewFocusRequest(
            annotationID: id,
            token: nextPreviewFocusToken,
            selectsAnnotation: selectsAnnotation
        )
    }

    private func scrollDraftToBottom(_ id: UUID) {
        pendingBottomScrollID = id
        sidebarScrollRequest = SidebarScrollRequest(id: id, anchor: .bottom)
    }

    private func selectAnnotation(_ id: UUID) {
        pendingBottomScrollID = nil
        selectedAnnotationID = id
        requestPreviewFocus(id)
        focusedComment = .annotation(id)
    }

    private func renumberAnnotations() {
        document.renumberTopDown()
        if let selectedAnnotationID {
            sidebarScrollRequest = SidebarScrollRequest(id: selectedAnnotationID, anchor: .center)
        }
    }

    private func handlePreviewVisibility(_ id: UUID) {
        guard pendingBottomScrollID == nil else { return }
        guard previewAnnotations.contains(where: { $0.id == id }) else { return }
        selectedAnnotationID = id
    }

    private func syncFromSidebarScroll(_ frames: [CommentFrame]) {
        guard pendingBottomScrollID == nil else { return }
        guard !frames.isEmpty else { return }
        let target = frames.min { lhs, rhs in
            abs(lhs.minY - 8) < abs(rhs.minY - 8)
        }
        guard let id = target?.id, lastSidebarFollowID != id else { return }
        requestPreviewFocus(id, selectsAnnotation: false)
    }

    private func focusDraft() {
        DispatchQueue.main.async {
            focusedComment = .draft
        }
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
        } catch {
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
        } catch {
        }
    }
}
