import Foundation
import Markdown

/// Keeps Markdown-authored values from changing MarkReview's private preview document.
/// `HTMLFormatter` still owns the structural HTML so upstream Markdown behavior is preserved.
enum SafeHTMLFormatter {
    static func format(_ markup: Markup) -> String {
        var rewriter = HTMLEscapingMarkupRewriter()
        guard let escapedMarkup = rewriter.visit(markup) else { return "" }
        return HTMLFormatter.format(escapedMarkup)
    }
}

private struct HTMLEscapingMarkupRewriter: MarkupRewriter {
    mutating func visitText(_ text: Text) -> Markup? {
        var text = text
        text.string = text.string.escapedForHTML
        return text
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        var codeBlock = codeBlock
        codeBlock.code = codeBlock.code.escapedForHTML
        codeBlock.language = codeBlock.language?.escapedForHTML
        return codeBlock
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        var inlineCode = inlineCode
        inlineCode.code = inlineCode.code.escapedForHTML
        return inlineCode
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
        // Raw HTML is review content, not preview chrome. Show it instead of executing it.
        CodeBlock(language: "html", html.rawHTML.escapedForHTML)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
        var inlineHTML = inlineHTML
        inlineHTML.rawHTML = inlineHTML.rawHTML.escapedForHTML
        return inlineHTML
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        var link = link
        link.destination = link.destination?.escapedForHTML
        link.title = link.title?.escapedForHTML
        return defaultVisit(link)
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        var image = image
        image.source = image.source?.escapedForHTML
        image.title = image.title?.escapedForHTML
        return defaultVisit(image)
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> Markup? {
        var attributes = attributes
        attributes.attributes = attributes.attributes.escapedForHTML
        return defaultVisit(attributes)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> Markup? {
        var symbolLink = symbolLink
        symbolLink.destination = symbolLink.destination?.escapedForHTML
        return symbolLink
    }
}

private extension String {
    var escapedForHTML: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
