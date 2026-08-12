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
        @media (prefers-color-scheme: dark) { body { color: #f1f3f4; background: #202124; } a { color: #8ab4f8; } code { background: #303134; color: #f8fafc; } pre, pre code { background: #111827; color: #f8fafc; } blockquote { border-color: #777; color: #c5c7c9; } }
        #document { max-width: 900px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.5em 0 .55em; letter-spacing: -.015em; }
        h1 { font-size: 2em; } h2 { font-size: 1.55em; } h3 { font-size: 1.25em; }
        p, ul, ol, blockquote, pre, table { margin: .8em 0; }
        ul, ol { padding-left: 1.6em; } li { margin: .25em 0; }
        blockquote { border-left: 4px solid #c9cdd2; padding-left: 1em; color: #5f6368; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; color: #1f2937; background: #eef2f7; padding: .12em .3em; border-radius: 4px; }
        pre { padding: 14px 16px; overflow-x: auto; border-radius: 8px; background: #eef2f7; color: #1f2937; }
        pre code { background: transparent; color: #1f2937; padding: 0; }
        table { border-collapse: collapse; width: 100%; } th, td { padding: 7px 10px; border: 1px solid #c9cdd2; text-align: left; }
        img { max-width: 100%; } hr { border: 0; border-top: 1px solid #c9cdd2; margin: 2em 0; }
        .review-annotated-block { position: relative; }
        .review-highlight { color: inherit; background: transparent; border: 0; padding: 0; }
        #review-outline-layer { position: fixed; top: 0; left: 0; display: block; width: 100vw; height: 100vh; z-index: 2; overflow: visible; pointer-events: none; }
        .review-outline { fill: none; stroke: rgba(147, 197, 253, .95); stroke-width: 2px; stroke-linejoin: miter; stroke-linecap: butt; }
        .review-outline.review-selected { stroke: #60a5fa; }
        .review-marker { position: absolute; left: -38px; top: 0; z-index: 3; display: inline-flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: 0; border-radius: 50%; padding: 0; color: #fff; background: rgba(0, 122, 255, .45); box-shadow: 0 1px 3px rgba(0,0,0,.14); cursor: pointer; font: 700 12px -apple-system, BlinkMacSystemFont, sans-serif; }
        .review-marker.review-resolved { background: #94a3b8; }
        .review-marker.review-selected { background: #007aff; box-shadow: 0 0 0 3px rgba(0, 122, 255, .24), 0 1px 3px rgba(0,0,0,.18); }
        #hint { position: fixed; right: 18px; bottom: 14px; opacity: .55; font-size: 12px; pointer-events: none; }
      </style>
    </head>
    <body>
      <main id="document">__MARKDOWN_BODY__</main>
      <div id="hint">Select text · ⌥-click a block for a block comment</div>
      <script>
        const review = () => window.webkit?.messageHandlers?.review;
        const root = document.getElementById('document');

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

        function readableText(block) {
          const clone = block.cloneNode(true);
          clone.querySelectorAll('.review-marker').forEach(marker => marker.remove());
          return (clone.innerText || clone.textContent || '').replace(/\s+/g, ' ').trim();
        }

        function contextFor(block, text) {
          const content = readableText(block);
          const index = content.toLowerCase().indexOf(text.toLowerCase());
          if (index < 0) return { before: content.slice(0, 120), after: '' };
          return { before: content.slice(Math.max(0, index - 120), index), after: content.slice(index + text.length, index + text.length + 120) };
        }

        function send(region) {
          review()?.postMessage({ type: 'region', ...region });
        }

        document.addEventListener('mouseup', event => {
          const element = event.target.closest?.('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th');
          if (!element || !root.contains(element)) return;
          const selection = window.getSelection();
          const text = selection?.toString().replace(/\s+/g, ' ').trim() || '';
          const block = blockFor(element);
          const blockText = readableText(block);
          const section = sectionFor(block);

          if (event.altKey && blockText) {
            send({ kind: 'block', selectedText: blockText, blockText, section, ...contextFor(block, blockText) });
            return;
          }

          if (!text || !selection.rangeCount) return;
          send({ kind: 'text', selectedText: text, blockText, section, ...contextFor(block, text) });
        });

        function clearHighlights() {
          document.querySelectorAll('.review-highlight').forEach(mark => {
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            mark.remove();
          });
          document.querySelectorAll('.review-marker').forEach(marker => marker.remove());
          document.querySelectorAll('.review-annotated-block').forEach(block => block.classList.remove('review-annotated-block'));
          document.getElementById('review-outline-layer')?.remove();
        }

        function findTextRange(text) {
          const target = (text || '').replace(/\s+/g, ' ').trim().toLowerCase();
          if (!target) return;

          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          const characters = [];
          while (walker.nextNode()) {
            const node = walker.currentNode;
            if (node.parentElement?.closest('.review-marker')) continue;
            const value = node.nodeValue || '';
            for (let offset = 0; offset < value.length; offset += 1) {
              characters.push({ node, offset, value: value[offset] });
            }
          }

          let normalized = '';
          const positions = [];
          let previousWasWhitespace = false;
          characters.forEach(character => {
            if (/\s/.test(character.value)) {
              if (!normalized || previousWasWhitespace) return;
              normalized += ' ';
              positions.push({
                start: character,
                end: { node: character.node, offset: character.offset + 1 }
              });
              previousWasWhitespace = true;
              return;
            }

            normalized += character.value.toLowerCase();
            positions.push({
              start: character,
              end: { node: character.node, offset: character.offset + 1 }
            });
            previousWasWhitespace = false;
          });

          const index = normalized.indexOf(target);
          if (index < 0) return;
          const first = positions[index];
          const last = positions[index + target.length - 1];
          if (!first || !last) return;
          const range = document.createRange();
          range.setStart(first.start.node, first.start.offset);
          range.setEnd(last.end.node, last.end.offset);
          return range;
        }

        function addMarker(block, item, lineRect) {
          block.classList.add('review-annotated-block');
          const marker = document.createElement('button');
          marker.className = 'review-marker' + (item.status === 'resolved' ? ' review-resolved' : '');
          marker.dataset.annotationId = item.id;
          marker.dataset.reviewMarker = 'true';
          marker.textContent = item.sequence;
          marker.setAttribute('aria-label', 'Review ' + item.sequence);
          const blockRect = block.getBoundingClientRect();
          let top = lineRect.top - blockRect.top + (lineRect.height - 24) / 2;
          const occupiedTops = Array.from(block.querySelectorAll('.review-marker')).map(existing => parseFloat(existing.style.top) || 0);
          while (occupiedTops.some(existing => Math.abs(existing - top) < 22)) top += 29;
          marker.style.top = Math.max(0, top) + 'px';
          marker.addEventListener('pointerdown', event => {
            event.preventDefault();
            event.stopPropagation();
            review()?.postMessage({ type: 'focusAnnotation', id: item.id });
          });
          block.appendChild(marker);
        }

        function outlinePath(rectangles) {
          const paddingX = 3;
          const paddingY = 2;
          const valid = rectangles
            .filter(rect => rect.width > 0 && rect.height > 0)
            .sort((left, right) => left.top - right.top || left.left - right.left);
          if (!valid.length) return '';

          const lines = [];
          valid.forEach(rect => {
            const line = lines[lines.length - 1];
            const sameLine = line && rect.top <= line.bottom + 1 && rect.bottom >= line.top - 1;
            if (sameLine) {
              line.left = Math.min(line.left, rect.left);
              line.top = Math.min(line.top, rect.top);
              line.right = Math.max(line.right, rect.right);
              line.bottom = Math.max(line.bottom, rect.bottom);
            } else {
              lines.push({ left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom });
            }
          });

          const padded = lines.map(line => ({
            left: line.left - paddingX,
            top: line.top - paddingY,
            right: line.right + paddingX,
            bottom: line.bottom + paddingY
          }));
          let path = 'M ' + padded[0].left + ' ' + padded[0].top + ' H ' + padded[0].right + ' V ' + padded[0].bottom;
          for (let index = 1; index < padded.length; index += 1) {
            path += ' H ' + padded[index].right + ' V ' + padded[index].bottom;
          }
          const last = padded[padded.length - 1];
          path += ' H ' + last.left + ' V ' + last.top;
          for (let index = padded.length - 2; index >= 0; index -= 1) {
            path += ' H ' + padded[index].left + ' V ' + padded[index].top;
          }
          return path + ' Z';
        }

        function redrawOutlines() {
          const layer = document.getElementById('review-outline-layer');
          if (!layer) return;
          layer.setAttribute('viewBox', '0 0 ' + window.innerWidth + ' ' + window.innerHeight);
          layer.setAttribute('width', window.innerWidth);
          layer.setAttribute('height', window.innerHeight);
          layer.setAttribute('preserveAspectRatio', 'none');
          layer.replaceChildren();
          document.querySelectorAll('.review-highlight[data-annotation-id]').forEach(mark => {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.classList.add('review-outline');
            path.dataset.annotationId = mark.dataset.annotationId;
            path.setAttribute('d', outlinePath(Array.from(mark.getClientRects())));
            layer.appendChild(path);
          });
          window.setSelectedAnnotation(window.selectedReviewAnnotationID || null);
        }

        function highlight(item) {
          const range = findTextRange(item.selectedText);
          if (!range) return;
          const block = blockFor(range.startContainer.parentElement);
          const mark = document.createElement('mark');
          mark.className = 'review-highlight'; mark.dataset.annotationId = item.id;
          const firstLine = range.getClientRects()[0] || range.getBoundingClientRect();
          try {
            mark.appendChild(range.extractContents());
            range.insertNode(mark);
          } catch (_) { return; }
          addMarker(block, item, firstLine);
        }

        window.setAnnotations = (annotations, selectedID) => {
          clearHighlights();
          (annotations || []).forEach(item => highlight(item));
          const layer = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          layer.id = 'review-outline-layer';
          document.body.appendChild(layer);
          redrawOutlines();
          window.setSelectedAnnotation(selectedID || null);
          notifyVisibleAnnotation();
        };
        window.selectedReviewAnnotationID = null;
        window.setSelectedAnnotation = id => {
          window.selectedReviewAnnotationID = id || null;
          document.querySelectorAll('.review-selected').forEach(element => element.classList.remove('review-selected'));
          if (!id) return;
          document.querySelectorAll(`[data-annotation-id="${id}"]`).forEach(element => element.classList.add('review-selected'));
        };
        window.focusAnnotation = id => {
          window.setSelectedAnnotation(id);
          const marker = document.querySelector(`.review-marker[data-annotation-id="${id}"]`);
          const target = marker?.closest('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th') || marker;
          if (!target) return;
          const rect = target.getBoundingClientRect();
          window.scrollBy({ top: rect.top - window.innerHeight * 0.25, behavior: 'smooth' });
        };

        let visibleAnnotationTimer = null;
        let lastVisibleAnnotationID = null;
        function notifyVisibleAnnotation() {
          const markers = Array.from(document.querySelectorAll('.review-marker[data-annotation-id]'));
          if (!markers.length) return;
          const targetY = window.innerHeight * 0.25;
          let nearest = null;
          let nearestDistance = Number.POSITIVE_INFINITY;
          markers.forEach(marker => {
            const block = marker.closest('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th') || marker;
            const rect = block.getBoundingClientRect();
            if (rect.bottom < 0 || rect.top > window.innerHeight) return;
            const distance = Math.abs(rect.top - targetY);
            if (distance < nearestDistance) {
              nearest = marker.dataset.annotationId;
              nearestDistance = distance;
            }
          });
          if (!nearest || nearest === lastVisibleAnnotationID) return;
          lastVisibleAnnotationID = nearest;
          review()?.postMessage({ type: 'visibleAnnotation', id: nearest });
        }

        window.addEventListener('scroll', () => {
          redrawOutlines();
          window.clearTimeout(visibleAnnotationTimer);
          visibleAnnotationTimer = window.setTimeout(notifyVisibleAnnotation, 45);
        }, { passive: true });
        window.addEventListener('resize', redrawOutlines);
      </script>
    </body>
    </html>
    """#
}
