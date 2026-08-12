import Foundation

struct ReviewSourceLocation {
    let lineStart: Int
    let lineEnd: Int
    let offset: Int
}

enum ReviewSourceLocator {
    static func locate(_ text: String, in markdown: String) -> ReviewSourceLocation? {
        let lines = markdown.components(separatedBy: .newlines)
        let rawTarget = normalize(text)
        guard !rawTarget.isEmpty else { return nil }

        if let location = locate(
            target: rawTarget,
            lines: lines,
            transform: { $0 }
        ) {
            return location
        }

        let displayTarget = normalize(stripMarkdownSyntax(text))
        guard !displayTarget.isEmpty else { return nil }
        return locate(
            target: displayTarget,
            lines: lines,
            transform: stripMarkdownSyntax
        )
    }

    private static func locate(
        target: String,
        lines: [String],
        transform: (String) -> String
    ) -> ReviewSourceLocation? {
        var flattened = ""
        var lineMap: [Int] = []

        for (index, line) in lines.enumerated() {
            let normalizedLine = normalize(transform(line))
            guard !normalizedLine.isEmpty else { continue }
            if !flattened.isEmpty {
                flattened.append(" ")
                lineMap.append(index + 1)
            }
            flattened.append(contentsOf: normalizedLine)
            lineMap.append(contentsOf: repeatElement(index + 1, count: normalizedLine.count))
        }

        guard let match = flattened.range(of: target) else {
            return nil
        }
        let startOffset = flattened.distance(from: flattened.startIndex, to: match.lowerBound)
        let endOffset = flattened.distance(from: flattened.startIndex, to: match.upperBound)
        guard startOffset < lineMap.count else { return nil }
        let endIndex = min(max(endOffset - 1, startOffset), lineMap.count - 1)
        return ReviewSourceLocation(
            lineStart: lineMap[startOffset],
            lineEnd: lineMap[endIndex],
            offset: startOffset
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func stripMarkdownSyntax(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\x60{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|~~"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}(?:[-+*]|\d+\.)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}>\s?"#, with: "", options: .regularExpression)
    }
}

public enum AnnotationKind: String, Codable, CaseIterable {
    case text
    case block
}

public enum AnnotationStatus: String, Codable, CaseIterable {
    case open
    case resolved
}

public struct ReviewAnnotation: Identifiable, Codable, Equatable {
    public let id: UUID
    public var sequence: Int
    public var kind: AnnotationKind
    public var selectedText: String
    public var contextBefore: String
    public var contextAfter: String
    public var blockText: String
    public var section: String
    public var comment: String
    public var status: AnnotationStatus
    public var sourceLineStart: Int?
    public var sourceLineEnd: Int?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sequence: Int,
        kind: AnnotationKind,
        selectedText: String,
        contextBefore: String,
        contextAfter: String,
        blockText: String,
        section: String,
        comment: String,
        status: AnnotationStatus = .open,
        sourceLineStart: Int? = nil,
        sourceLineEnd: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.selectedText = selectedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.blockText = blockText
        self.section = section
        self.comment = comment
        self.status = status
        self.sourceLineStart = sourceLineStart
        self.sourceLineEnd = sourceLineEnd
        self.createdAt = createdAt
    }
}

public struct MarkReviewDocument: Codable, Equatable {
    public static let currentFormatVersion = 1

    public var id: UUID
    public var formatVersion: Int
    public var title: String
    public var sourcePath: String?
    public var originalMarkdown: String
    public var annotations: [ReviewAnnotation]

    public init(
        id: UUID = UUID(),
        title: String = "Untitled review",
        sourcePath: String? = nil,
        originalMarkdown: String = "",
        annotations: [ReviewAnnotation] = []
    ) {
        self.id = id
        self.formatVersion = Self.currentFormatVersion
        self.title = title
        self.sourcePath = sourcePath
        self.originalMarkdown = originalMarkdown
        self.annotations = annotations
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case formatVersion
        case title
        case sourcePath
        case originalMarkdown
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? Self.currentFormatVersion
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled review"
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        originalMarkdown = try container.decodeIfPresent(String.self, forKey: .originalMarkdown) ?? ""
        annotations = try container.decodeIfPresent([ReviewAnnotation].self, forKey: .annotations) ?? []
    }

    public var nextSequence: Int {
        (annotations.map(\.sequence).max() ?? 0) + 1
    }

    public mutating func add(_ annotation: ReviewAnnotation) {
        annotations.append(annotation)
        annotations.sort { $0.sequence < $1.sequence }
    }

    public mutating func toggleStatus(for id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].status = annotations[index].status == .open ? .resolved : .open
    }

    public mutating func updateComment(for id: UUID, comment: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].comment = comment
    }

    public mutating func updateRegion(
        for id: UUID,
        kind: AnnotationKind,
        selectedText: String,
        contextBefore: String,
        contextAfter: String,
        blockText: String,
        section: String,
        sourceLineStart: Int?,
        sourceLineEnd: Int?
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].kind = kind
        annotations[index].selectedText = selectedText
        annotations[index].contextBefore = contextBefore
        annotations[index].contextAfter = contextAfter
        annotations[index].blockText = blockText
        annotations[index].section = section
        annotations[index].sourceLineStart = sourceLineStart
        annotations[index].sourceLineEnd = sourceLineEnd
    }

    public mutating func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    public mutating func renumberTopDown() {
        var reordered = annotations
        reordered.sort { lhs, rhs in
            let lhsPosition = Self.topDownPosition(for: lhs, in: originalMarkdown)
            let rhsPosition = Self.topDownPosition(for: rhs, in: originalMarkdown)
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return lhs.sequence < rhs.sequence
        }
        for index in reordered.indices {
            reordered[index].sequence = index + 1
        }
        annotations = reordered
    }

    private static func topDownPosition(for annotation: ReviewAnnotation, in markdown: String) -> (Int, Int) {
        let location = [annotation.selectedText, annotation.blockText]
            .compactMap { ReviewSourceLocator.locate($0, in: markdown) }
            .first
        let line = location?.lineStart ?? annotation.sourceLineStart ?? Int.max
        let offset = location?.offset ?? Int.max
        return (line, offset)
    }
}

public struct SelectedRegion: Equatable {
    public var kind: AnnotationKind
    public var selectedText: String
    public var contextBefore: String
    public var contextAfter: String
    public var blockText: String
    public var section: String

    public init(
        kind: AnnotationKind,
        selectedText: String,
        contextBefore: String,
        contextAfter: String,
        blockText: String,
        section: String
    ) {
        self.kind = kind
        self.selectedText = selectedText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.blockText = blockText
        self.section = section
    }
}

public struct AgentExport: Codable {
    public let format: String
    public let version: Int
    public let source: AgentExportSource
    public let annotations: [AgentExportAnnotation]

    public init(document: MarkReviewDocument) {
        self.format = "markreview-agent-export"
        self.version = 1
        self.source = AgentExportSource(
            title: document.title,
            path: document.sourcePath,
            markdown: document.originalMarkdown
        )
        self.annotations = document.annotations
            .filter { !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sequence < $1.sequence }
            .map(AgentExportAnnotation.init)
    }
}

public struct AgentExportSource: Codable {
    public let title: String
    public let path: String?
    public let markdown: String
}

public struct AgentExportAnnotation: Codable {
    public let number: Int
    public let id: String
    public let status: String
    public let kind: String
    public let section: String
    public let selectedText: String
    public let blockText: String
    public let context: AgentContext
    public let comment: String
    public let sourceLines: AgentSourceLines?
    public let createdAt: String

    public init(annotation: ReviewAnnotation) {
        number = annotation.sequence
        id = annotation.id.uuidString
        status = annotation.status.rawValue
        kind = annotation.kind.rawValue
        section = annotation.section
        selectedText = annotation.selectedText
        blockText = annotation.blockText
        context = AgentContext(
            before: annotation.contextBefore,
            after: annotation.contextAfter
        )
        comment = annotation.comment
        if annotation.sourceLineStart != nil || annotation.sourceLineEnd != nil {
            sourceLines = AgentSourceLines(
                start: annotation.sourceLineStart,
                end: annotation.sourceLineEnd
            )
        } else {
            sourceLines = nil
        }
        createdAt = ISO8601DateFormatter.markReview.string(from: annotation.createdAt)
    }
}

public struct AgentContext: Codable {
    public let before: String
    public let after: String
}

public struct AgentSourceLines: Codable {
    public let start: Int?
    public let end: Int?
}

extension ISO8601DateFormatter {
    static let markReview: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
