import Foundation
import Markdown

struct MarkdownRenderer {
    static func makeContentNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func render(_ markdown: String, contentNonce: String = Self.makeContentNonce()) -> String {
        let document = Document(parsing: markdown)
        let body = HTMLFormatter.format(document)
        let accent = SystemAccentPalette.current
        return HTMLPage.template
            .replacingOccurrences(of: "__MARKREVIEW_CONTENT_NONCE__", with: contentNonce)
            .replacingOccurrences(of: "__REVIEW_ACCENT_MUTED__", with: accent.cssRGBA(alpha: 0.45))
            .replacingOccurrences(of: "__REVIEW_ACCENT_OUTLINE__", with: accent.cssRGBA(alpha: 0.82))
            .replacingOccurrences(of: "__REVIEW_ACCENT_SELECTED__", with: accent.cssRGBA())
            .replacingOccurrences(of: "__REVIEW_ACCENT_RING__", with: accent.cssRGBA(alpha: 0.24))
            .replacingOccurrences(of: "__MARKDOWN_BODY__", with: body)
    }

    func sourceLineHints(for region: SelectedRegion, in markdown: String) -> (Int?, Int?) {
        let candidates = [region.blockText, region.selectedText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let location = candidates.compactMap({ ReviewSourceLocator.locate($0, in: markdown) }).first else {
            return (nil, nil)
        }
        return (location.lineStart, location.lineEnd)
    }
}

private enum HTMLPage {
    static let template = #"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; script-src 'nonce-__MARKREVIEW_CONTENT_NONCE__'; style-src 'nonce-__MARKREVIEW_CONTENT_NONCE__'; base-uri 'none'; form-action 'none'">
      <style nonce="__MARKREVIEW_CONTENT_NONCE__">
        :root { --markdown-font-scale: 1; color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 38px 54px 72px; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: calc(16px * var(--markdown-font-scale)); line-height: 1.58; color: #202124; background: #fff; }
        @media (prefers-color-scheme: dark) { body { color: #f1f3f4; background: #202124; } a { color: #8ab4f8; } code { background: #303134; color: #f8fafc; } pre, pre code { background: #111827; color: #f8fafc; } blockquote { border-color: #777; color: #c5c7c9; } }
        #document { max-width: 900px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.5em 0 .55em; letter-spacing: -.015em; }
        h1 { font-size: 2em; } h2 { font-size: 1.55em; } h3 { font-size: 1.25em; }
        p, ul, ol, blockquote, pre, table { margin: .8em 0; }
        ul, ol { padding-left: 1.6em; } li { margin: .25em 0; }
        blockquote { border-left: 4px solid #c9cdd2; padding-left: 1em; color: #5f6368; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; color: #1f2937; background: #eef2f7; padding: .12em .3em; border-radius: 4px; }
        pre { max-width: 100%; padding: 14px 16px; overflow-x: auto; border-radius: 8px; background: #eef2f7; color: #1f2937; }
        pre > code { display: block; width: max-content; min-width: 100%; }
        pre code { background: transparent; color: #1f2937; padding: 0; }
        table { display: block; width: 100%; max-width: 100%; overflow-x: auto; border-collapse: collapse; } th, td { padding: 7px 10px; border: 1px solid #c9cdd2; text-align: left; }
        a, :not(pre) > code { overflow-wrap: anywhere; }
        img { max-width: 100%; } hr { border: 0; border-top: 1px solid #c9cdd2; margin: 2em 0; }
        input[type="checkbox"] { width: 14px; height: 14px; margin: 0 .5em 0 0; vertical-align: -2px; accent-color: __REVIEW_ACCENT_SELECTED__; }
        li:has(> input[type="checkbox"]) { list-style: none; }
        li > input[type="checkbox"] + p { display: inline; }
        .review-annotated-block { position: relative; }
        #review-outline-layer { position: fixed; top: 0; left: 0; display: block; width: 100vw; height: 100vh; z-index: 2; overflow: visible; pointer-events: none; }
        #review-marker-layer { position: fixed; top: 0; left: 0; display: block; width: 100vw; height: 100vh; z-index: 3; overflow: visible; pointer-events: none; }
        .review-outline { fill: none; stroke: __REVIEW_ACCENT_OUTLINE__; stroke-width: 2px; stroke-linejoin: miter; stroke-linecap: butt; }
        .review-outline.review-muted { stroke: #94a3b8; opacity: .55; }
        .review-outline.review-selected { stroke: __REVIEW_ACCENT_SELECTED__; }
        .review-outline.review-muted.review-selected { stroke: __REVIEW_ACCENT_SELECTED__; opacity: 1; }
        .review-marker { position: absolute; left: 0; top: 0; z-index: 3; display: inline-flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: 0; border-radius: 50%; padding: 0; color: #fff; background: __REVIEW_ACCENT_MUTED__; box-shadow: 0 1px 3px rgba(0,0,0,.14); cursor: pointer; font: 700 12px -apple-system, BlinkMacSystemFont, sans-serif; pointer-events: auto; transform: translateX(var(--stack-offset, 0px)); transition: transform .12s ease, box-shadow .12s ease; }
        .review-marker.review-selected { z-index: 10; background: __REVIEW_ACCENT_SELECTED__; box-shadow: 0 0 0 3px __REVIEW_ACCENT_RING__, 0 1px 3px rgba(0,0,0,.18); }
        .review-marker:hover { z-index: 100; transform: translateX(var(--stack-offset, 0px)) scale(1.12); box-shadow: 0 2px 6px rgba(0,0,0,.28); }
        .review-marker.review-selected:hover { box-shadow: 0 0 0 3px __REVIEW_ACCENT_RING__, 0 2px 6px rgba(0,0,0,.28); }
        .review-marker.review-muted { background: #94a3b8; }
        #hint { position: fixed; right: 18px; bottom: 14px; opacity: .55; font-size: calc(12px * var(--markdown-font-scale)); pointer-events: none; }
        @media (prefers-reduced-motion: reduce) { .review-marker { transition: none; } }
      </style>
    </head>
    <body>
      <main id="document">__MARKDOWN_BODY__</main>
      <div id="hint">Select text · ⌥-click a block for a block comment</div>
      <script nonce="__MARKREVIEW_CONTENT_NONCE__">
        const review = () => window.webkit?.messageHandlers?.review;
        const root = document.getElementById('document');
        const reviewRanges = new Map();
        const reviewStatuses = new Map();

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

        function contextForSelection(block, selectionRange) {
          const beforeRange = document.createRange();
          beforeRange.selectNodeContents(block);
          beforeRange.setEnd(selectionRange.startContainer, selectionRange.startOffset);

          const afterRange = document.createRange();
          afterRange.selectNodeContents(block);
          afterRange.setStart(selectionRange.endContainer, selectionRange.endOffset);

          return {
            before: beforeRange.toString().slice(-120),
            after: afterRange.toString().slice(0, 120)
          };
        }

        function send(region) {
          review()?.postMessage({ type: 'region', ...region });
        }

        function emitSelection(event) {
          const element = event.target.closest?.('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th');
          if (!element || !root.contains(element)) return;
          const selection = window.getSelection();
          const text = selection?.toString().replace(/\s+/g, ' ').trim() || '';

          if (event.altKey) {
            const block = blockFor(element);
            const blockText = readableText(block);
            if (!blockText) return;
            selection.removeAllRanges();
            send({ kind: 'block', selectedText: blockText, blockText, section: sectionFor(block), ...contextFor(block, blockText) });
            return;
          }

          if (!text || !selection.rangeCount) return;
          const selectionRange = selection.getRangeAt(0).cloneRange();
          const startElement = selectionRange.startContainer.nodeType === Node.ELEMENT_NODE
            ? selectionRange.startContainer
            : selectionRange.startContainer.parentElement;
          const endElement = selectionRange.endContainer.nodeType === Node.ELEMENT_NODE
            ? selectionRange.endContainer
            : selectionRange.endContainer.parentElement;
          if (!startElement || !endElement || !root.contains(startElement) || !root.contains(endElement)) return;
          const block = blockFor(startElement);
          const blockText = readableText(block);
          const contextScope = block.contains(endElement) ? block : root;
          const region = {
            kind: 'text',
            selectedText: text,
            blockText,
            section: sectionFor(block),
            ...contextForSelection(contextScope, selectionRange)
          };
          selection.removeAllRanges();
          send(region);
        }

        document.addEventListener('mouseup', emitSelection);

        function clearHighlights() {
          reviewRanges.clear();
          reviewStatuses.clear();
          document.querySelectorAll('.review-highlight').forEach(mark => {
            const parent = mark.parentNode;
            while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
            mark.remove();
          });
          document.querySelectorAll('.review-marker').forEach(marker => marker.remove());
          document.querySelectorAll('.review-annotated-block').forEach(block => block.classList.remove('review-annotated-block'));
          document.getElementById('review-marker-layer')?.remove();
          document.getElementById('review-outline-layer')?.remove();
          window.getSelection()?.removeAllRanges();
        }

        function normalizeForSearch(value) {
          return (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
        }

        function findTextRange(text, item) {
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

          const candidates = [];
          let index = normalized.indexOf(target);
          while (index >= 0) {
            const first = positions[index];
            const last = positions[index + target.length - 1];
            if (first && last) {
              const candidateBlock = blockFor(first.start.node.parentElement);
              const candidateBefore = normalized.slice(
                Math.max(0, index - normalizeForSearch(item?.contextBefore).length),
                index
              );
              const candidateAfter = normalized.slice(
                index + target.length,
                index + target.length + normalizeForSearch(item?.contextAfter).length
              );
              const expectedBefore = normalizeForSearch(item?.contextBefore);
              const expectedAfter = normalizeForSearch(item?.contextAfter);
              const expectedBlock = normalizeForSearch(item?.blockText);
              const actualBlock = normalizeForSearch(readableText(candidateBlock));
              let score = 0;
              if (expectedBlock && actualBlock === expectedBlock) score += 100;
              if (expectedBefore && candidateBefore.endsWith(expectedBefore)) score += 50;
              if (expectedAfter && candidateAfter.startsWith(expectedAfter)) score += 50;
              candidates.push({ index, first, last, score });
            }
            index = normalized.indexOf(target, index + Math.max(target.length, 1));
          }

          candidates.sort((left, right) => right.score - left.score || left.index - right.index);
          const candidate = candidates[0];
          if (!candidate) return;
          const range = document.createRange();
          range.setStart(candidate.first.start.node, candidate.first.start.offset);
          range.setEnd(candidate.last.end.node, candidate.last.end.offset);
          return range;
        }

        function addMarker(block, item, lineRect) {
          const marker = document.createElement('button');
          const isMuted = item.status === 'muted';
          marker.className = 'review-marker' + (isMuted ? ' review-muted' : '');
          marker.dataset.annotationId = item.id;
          marker.dataset.reviewMarker = 'true';
          marker.textContent = item.sequence;
          marker.setAttribute('aria-label', 'Review ' + item.sequence + (isMuted ? ', muted and ignored by agents' : ''));
          const markerLayer = document.getElementById('review-marker-layer');
          if (!markerLayer) return;
          const rowTop = lineRect.top + (lineRect.height - 24) / 2;
          const sameRowMarkers = Array.from(markerLayer.querySelectorAll('.review-marker'))
            .filter(existing => Math.abs(parseFloat(existing.dataset.rowTop || 'NaN') - rowTop) < 8);
          marker.dataset.rowTop = String(rowTop);
          marker.style.setProperty('--stack-offset', Math.min(sameRowMarkers.length * 5, 16) + 'px');
          marker.addEventListener('pointerdown', event => {
            event.preventDefault();
            event.stopPropagation();
            review()?.postMessage({ type: 'focusAnnotation', id: item.id });
          });
          markerLayer.appendChild(marker);
          positionMarker(marker, lineRect);
        }

        function positionMarker(marker, lineRect = reviewRanges.get(marker.dataset.annotationId)?.getClientRects()[0]) {
          if (!lineRect) return;
          const documentRect = root.getBoundingClientRect();
          marker.style.left = (documentRect.left - 38) + 'px';
          marker.style.top = (lineRect.top + (lineRect.height - 24) / 2) + 'px';
        }

        function positionMarkers() {
          document.querySelectorAll('.review-marker').forEach(marker => {
            positionMarker(marker);
          });
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
          reviewRanges.forEach((range, annotationID) => {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.classList.add('review-outline');
            if (reviewStatuses.get(annotationID) === 'muted') path.classList.add('review-muted');
            path.dataset.annotationId = annotationID;
            path.setAttribute('d', outlinePath(Array.from(range.getClientRects())));
            layer.appendChild(path);
          });
          positionMarkers();
          window.setSelectedAnnotation(window.selectedReviewAnnotationID || null);
        }

        function highlight(item) {
          const range = findTextRange(item.selectedText, item);
          if (!range) return;
          const block = blockFor(range.startContainer.parentElement);
          const firstLine = range.getClientRects()[0] || range.getBoundingClientRect();
          reviewRanges.set(item.id, range.cloneRange());
          reviewStatuses.set(item.id, item.status);
          addMarker(block, item, firstLine);
        }

        window.setAnnotations = (annotations, selectedID) => {
          clearHighlights();
          const markerLayer = document.createElement('div');
          markerLayer.id = 'review-marker-layer';
          document.body.appendChild(markerLayer);
          (annotations || []).forEach(item => highlight(item));
          const layer = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          layer.id = 'review-outline-layer';
          document.body.appendChild(layer);
          redrawOutlines();
          window.setSelectedAnnotation(selectedID || null);
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
          const range = reviewRanges.get(id);
          const anchor = range?.startContainer?.parentElement;
          const target = anchor?.closest('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th') || marker;
          if (!target) return;
          const rect = target.getBoundingClientRect();
          const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
          window.scrollBy({ top: rect.top - window.innerHeight * 0.25, behavior: reduceMotion ? 'auto' : 'smooth' });
        };

        window.setMarkdownFontScale = scale => {
          const normalized = Math.min(2, Math.max(0.75, Number(scale) || 1));
          document.documentElement.style.setProperty('--markdown-font-scale', normalized);
          window.requestAnimationFrame(redrawOutlines);
        };

        window.addEventListener('scroll', () => {
          redrawOutlines();
        }, { passive: true });
        window.addEventListener('resize', redrawOutlines);
      </script>
    </body>
    </html>
    """#
}
