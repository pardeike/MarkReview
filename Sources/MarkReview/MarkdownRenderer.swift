import Foundation
import Markdown

struct MarkdownRenderer {
    func render(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        let body = HTMLFormatter.format(document)
        return HTMLPage.template.replacingOccurrences(of: "__MARKDOWN_BODY__", with: body)
    }

    func sourceLineHints(for region: SelectedRegion, in markdown: String) -> (Int?, Int?) {
        let candidates = [region.selectedText, region.blockText]
            .map(Self.normalize)
            .filter { !$0.isEmpty }

        guard let candidate = candidates.first(where: { markdown.normalizedForReview.contains($0) }) else {
            return (nil, nil)
        }

        let normalizedMarkdown = markdown.normalizedForReview
        guard let match = normalizedMarkdown.range(of: candidate) else {
            return (nil, nil)
        }
        let startOffset = normalizedMarkdown.distance(from: normalizedMarkdown.startIndex, to: match.lowerBound)
        let endOffset = normalizedMarkdown.distance(from: normalizedMarkdown.startIndex, to: match.upperBound)
        let normalizedLines = markdown.components(separatedBy: .newlines)
        var normalizedOffset = 0
        var start: Int?
        var end: Int?

        for (index, line) in normalizedLines.enumerated() {
            let lineLength = Self.normalize(line).count
            let lineEnd = normalizedOffset + lineLength
            if start == nil && startOffset <= lineEnd {
                start = index + 1
            }
            if start != nil && endOffset <= lineEnd {
                end = index + 1
                break
            }
            normalizedOffset = lineEnd + 1
        }

        return (start, end ?? start)
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var normalizedForReview: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum HTMLPage {
    static let template = #"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 38px 54px 72px; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: 16px; line-height: 1.58; color: #202124; background: #fff; }
        @media (prefers-color-scheme: dark) { body { color: #f1f3f4; background: #202124; } a { color: #8ab4f8; } code { background: #303134; } pre { background: #303134; } blockquote { border-color: #777; color: #c5c7c9; } }
        #document { max-width: 900px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.5em 0 .55em; letter-spacing: -.015em; }
        h1 { font-size: 2em; } h2 { font-size: 1.55em; } h3 { font-size: 1.25em; }
        p, ul, ol, blockquote, pre, table { margin: .8em 0; }
        ul, ol { padding-left: 1.6em; } li { margin: .25em 0; }
        blockquote { border-left: 4px solid #c9cdd2; padding-left: 1em; color: #5f6368; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; background: #f1f3f4; padding: .12em .3em; border-radius: 4px; }
        pre { padding: 14px 16px; overflow-x: auto; border-radius: 8px; background: #f1f3f4; }
        pre code { background: transparent; padding: 0; }
        table { border-collapse: collapse; width: 100%; } th, td { padding: 7px 10px; border: 1px solid #c9cdd2; text-align: left; }
        img { max-width: 100%; } hr { border: 0; border-top: 1px solid #c9cdd2; margin: 2em 0; }
        .review-highlight { background: rgba(255, 206, 64, .42); border-bottom: 2px solid #d99b00; border-radius: 2px; }
        .review-block-hover { outline: 2px solid rgba(91, 141, 239, .22); outline-offset: 3px; }
        #selection-button { display: none; position: fixed; z-index: 10; border: 0; border-radius: 7px; padding: 7px 11px; color: white; background: #2563eb; box-shadow: 0 4px 16px rgba(0,0,0,.22); cursor: pointer; font: 600 13px -apple-system, BlinkMacSystemFont, sans-serif; }
        #hint { position: fixed; right: 18px; bottom: 14px; opacity: .55; font-size: 12px; pointer-events: none; }
      </style>
    </head>
    <body>
      <main id="document">__MARKDOWN_BODY__</main>
      <button id="selection-button">Comment selection</button>
      <div id="hint">Select text · ⌥-click a block for a block comment</div>
      <script>
        const review = () => window.webkit?.messageHandlers?.review;
        const root = document.getElementById('document');
        const button = document.getElementById('selection-button');
        let pending = null;

        function sectionFor(element) {
          const headings = [];
          let cursor = element;
          while (cursor && cursor !== root) {
            let sibling = cursor.previousElementSibling;
            while (sibling) {
              if (/^H[1-6]$/.test(sibling.tagName)) {
                headings.unshift(sibling.innerText.trim());
                break;
              }
              sibling = sibling.previousElementSibling;
            }
            cursor = cursor.parentElement;
          }
          const nearest = element.closest('h1,h2,h3,h4,h5,h6');
          if (nearest && !headings.includes(nearest.innerText.trim())) headings.push(nearest.innerText.trim());
          return headings.join(' > ');
        }

        function blockFor(element) {
          return element.closest('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th') || element;
        }

        function contextFor(block, text) {
          const content = (block.innerText || '').replace(/\s+/g, ' ').trim();
          const index = content.toLowerCase().indexOf(text.toLowerCase());
          if (index < 0) return { before: content.slice(0, 120), after: '' };
          return { before: content.slice(Math.max(0, index - 120), index), after: content.slice(index + text.length, index + text.length + 120) };
        }

        function send(region) {
          pending = region;
          button.style.display = 'none';
          review()?.postMessage({ type: 'region', ...region });
        }

        document.addEventListener('mouseup', event => {
          const element = event.target.closest?.('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th');
          if (!element || !root.contains(element)) return;
          const selection = window.getSelection();
          const text = selection?.toString().replace(/\s+/g, ' ').trim() || '';
          const block = blockFor(element);
          const blockText = (block.innerText || '').replace(/\s+/g, ' ').trim();
          const section = sectionFor(block);

          if (event.altKey && blockText) {
            send({ kind: 'block', selectedText: blockText, blockText, section, ...contextFor(block, blockText) });
            return;
          }

          if (!text || !selection.rangeCount) return;
          const rect = selection.getRangeAt(0).getBoundingClientRect();
          pending = { kind: 'text', selectedText: text, blockText, section, ...contextFor(block, text) };
          button.style.left = Math.max(12, Math.min(window.innerWidth - 150, rect.left + rect.width / 2 - 55)) + 'px';
          button.style.top = Math.max(12, rect.top - 42) + 'px';
          button.style.display = 'block';
        });

        button.addEventListener('mousedown', event => { event.preventDefault(); if (pending) send(pending); });
        document.addEventListener('mousedown', event => { if (event.target !== button) button.style.display = 'none'; });

        function clearHighlights() {
          document.querySelectorAll('.review-highlight').forEach(mark => mark.replaceWith(document.createTextNode(mark.textContent)));
        }

        function highlight(text, id) {
          if (!text) return;
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          while (walker.nextNode()) {
            const node = walker.currentNode;
            const value = node.nodeValue || '';
            const index = value.toLowerCase().indexOf(text.toLowerCase());
            if (index >= 0) {
              const range = document.createRange();
              range.setStart(node, index); range.setEnd(node, index + text.length);
              const mark = document.createElement('mark');
              mark.className = 'review-highlight'; mark.dataset.annotationId = id;
              try { range.surroundContents(mark); } catch (_) { return; }
              return;
            }
          }
        }

        window.setAnnotations = annotations => {
          clearHighlights();
          (annotations || []).filter(item => item.status === 'open').forEach(item => highlight(item.selectedText, item.id));
        };
        window.focusAnnotation = id => {
          const mark = document.querySelector(`[data-annotation-id="${id}"]`);
          mark?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        };
      </script>
    </body>
    </html>
    """#
}
