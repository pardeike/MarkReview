import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markReview = UTType(exportedAs: "com.markreview.document", conformingTo: .json)
    static let markReviewMarkdown = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}

extension MarkReviewDocument {
    public static var readableContentTypes: [UTType] {
        [.markReview, .markReviewMarkdown]
    }

    public static var writableContentTypes: [UTType] {
        [.markReview]
    }

    public convenience init(configuration: FileDocumentReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        if configuration.contentType.conforms(to: .markReview) {
            let decoded = try JSONDecoder.markReview.decode(MarkReviewDocument.self, from: data)
            self.init()
            replace(with: decoded)
        } else if configuration.contentType.conforms(to: .markReviewMarkdown),
                  let markdown = String(data: data, encoding: .utf8) {
            let filename = configuration.file.preferredFilename ?? configuration.file.filename
            let title = filename.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            } ?? "Untitled review"
            self.init(title: title, sourcePath: filename, originalMarkdown: markdown)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    public func snapshot(contentType: UTType) throws -> MarkReviewDocument {
        copy()
    }

    public func fileWrapper(snapshot: MarkReviewDocument, configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder.markReview.encode(snapshot)
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
