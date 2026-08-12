import Foundation

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

    public mutating func remove(id: UUID) {
        annotations.removeAll { $0.id == id }
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
