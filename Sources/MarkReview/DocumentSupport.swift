import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markReview = UTType(exportedAs: "com.markreview.document", conformingTo: .json)
}

extension MarkReviewDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [.markReview, .plainText, .text]
    }

    public static var writableContentTypes: [UTType] {
        [.markReview, .plainText, .text]
    }

    public init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        if let decoded = try? JSONDecoder.markReview.decode(MarkReviewDocument.self, from: data) {
            self = decoded
        } else if let markdown = String(data: data, encoding: .utf8) {
            let filename = configuration.file.preferredFilename ?? configuration.file.filename
            let title = filename.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            } ?? "Untitled review"
            self = MarkReviewDocument(title: title, sourcePath: filename, originalMarkdown: markdown)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType.conforms(to: .plainText) {
            return FileWrapper(regularFileWithContents: Data(originalMarkdown.utf8))
        }
        let data = try JSONEncoder.markReview.encode(self)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension JSONEncoder {
    static let markReview: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.markReview.string(from: date))
        }
        return encoder
    }()
}

extension JSONDecoder {
    static let markReview: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.markReview.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid MarkReview date")
            }
            return date
        }
        return decoder
    }()
}
