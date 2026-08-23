import Foundation
import Markdown

struct MarkdownRenderer {
    static func makeContentNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func render(
        _ markdown: String,
        contentNonce: String = Self.makeContentNonce(),
        reviewColor: AppColorPalette = ReviewColorPreset.orange.palette
    ) -> String {
        let document = Document(parsing: markdown)
        let body = SafeHTMLFormatter.format(document)
        let findColor = AppColorPalette.systemAccent
        return HTMLPage.template
            .replacingOccurrences(of: "__MARKREVIEW_CONTENT_NONCE__", with: contentNonce)
            .replacingOccurrences(of: "__REVIEW_ACCENT_MUTED__", with: reviewColor.cssRGBA(alpha: 0.45))
            .replacingOccurrences(of: "__REVIEW_ACCENT_OUTLINE__", with: reviewColor.cssRGBA(alpha: 0.82))
            .replacingOccurrences(of: "__REVIEW_ACCENT_SELECTED__", with: reviewColor.cssRGBA())
            .replacingOccurrences(of: "__REVIEW_ACCENT_RING__", with: reviewColor.cssRGBA(alpha: 0.24))
            .replacingOccurrences(of: "__REVIEW_ACCENT_TEXT__", with: reviewColor.contrastingCSSTextColor)
            .replacingOccurrences(of: "__SYSTEM_ACCENT_SELECTED__", with: findColor.cssRGBA())
            .replacingOccurrences(of: "__FIND_ACCENT_MUTED__", with: findColor.cssRGBA(alpha: 0.22))
            .replacingOccurrences(of: "__FIND_ACCENT_OUTLINE__", with: findColor.cssRGBA(alpha: 0.52))
            .replacingOccurrences(of: "__FIND_ACCENT_CURRENT__", with: findColor.cssRGBA(alpha: 0.42))
            .replacingOccurrences(of: "__FIND_ACCENT_RING__", with: findColor.cssRGBA(alpha: 0.82))
            .replacingOccurrences(of: "__FIND_ACCENT_SELECTED__", with: findColor.cssRGBA())
            .replacingOccurrences(
                of: "__MARKREVIEW_MIN_FONT_SCALE__",
                with: String(MarkReviewDocument.minimumPreviewFontScale)
            )
            .replacingOccurrences(
                of: "__MARKREVIEW_MAX_FONT_SCALE__",
                with: String(MarkReviewDocument.maximumPreviewFontScale)
            )
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
        body { position: relative; margin: 0; padding: 38px 54px 72px; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: calc(16px * var(--markdown-font-scale)); line-height: 1.58; color: #202124; background: #fff; }
        #document { max-width: 56.25em; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin: 1.5em 0 .55em; letter-spacing: -.015em; }
        h1 { font-size: 2em; } h2 { font-size: 1.55em; } h3 { font-size: 1.25em; }
        p, ul, ol, blockquote, pre, table { margin: .8em 0; }
        ul, ol { padding-left: 1.6em; } li { margin: .25em 0; }
        blockquote { border-left: 4px solid #c9cdd2; padding-left: 1em; color: #5f6368; }
        code { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: .9em; font-weight: 400; color: #3c4043; background: #eef0f2; padding: .12em .3em; border-radius: 4px; }
        pre { max-width: 100%; padding: 14px 16px; overflow-x: auto; border-radius: 8px; background: #f4f5f6; color: #3c4043; line-height: 1.52; }
        pre > code { display: block; width: max-content; min-width: 100%; }
        pre code { background: transparent; color: inherit; padding: 0; }
        table { display: block; width: 100%; max-width: 100%; overflow-x: auto; border-collapse: collapse; } th, td { padding: 7px 10px; border: 1px solid #c9cdd2; text-align: left; }
        a, :not(pre) > code { overflow-wrap: anywhere; }
        img { max-width: 100%; } hr { border: 0; border-top: 1px solid #c9cdd2; margin: 2em 0; }
        input[type="checkbox"] { font-size: inherit; width: .875em; height: .875em; margin: 0 .5em 0 0; vertical-align: -.125em; accent-color: __SYSTEM_ACCENT_SELECTED__; }
        ul > li:has(> input[type="checkbox"]) { list-style: none; }
        li > input[type="checkbox"] + p { display: inline; }
        @media (prefers-color-scheme: dark) { body { color: #f1f3f4; background: #202124; } a { color: #8ab4f8; } code { background: #303134; color: #d3d6da; } pre { background: #292a2c; color: #d3d6da; } pre code { background: transparent; color: inherit; } blockquote { border-color: #777; color: #c5c7c9; } }
        #content-find-layer { position: absolute; top: 0; left: 0; display: block; width: 100%; height: 100%; z-index: 1; overflow: visible; pointer-events: none; }
        .content-find-highlight { position: absolute; border-radius: 3px; background: __FIND_ACCENT_MUTED__; box-shadow: inset 0 0 0 1px __FIND_ACCENT_OUTLINE__; }
        .content-find-highlight.content-find-current { background: __FIND_ACCENT_CURRENT__; box-shadow: 0 0 0 2px __FIND_ACCENT_RING__, inset 0 0 0 1px rgba(255, 255, 255, .28); }
        #content-find-marker-layer { position: absolute; top: 0; left: 0; display: block; width: 100%; height: 100%; z-index: 4; overflow: visible; pointer-events: none; }
        .content-find-marker { position: absolute; display: inline-flex; align-items: center; justify-content: center; width: 24px; height: 24px; color: __FIND_ACCENT_SELECTED__; opacity: .62; font: 900 22px/24px -apple-system, BlinkMacSystemFont, sans-serif; }
        .content-find-marker.content-find-current { opacity: 1; }
        .review-annotated-block { position: relative; }
        #review-outline-layer { position: absolute; top: 0; left: 0; display: block; z-index: 2; overflow: visible; pointer-events: none; }
        #review-marker-layer { position: absolute; top: 0; left: 0; display: block; width: 100%; height: 100%; z-index: 3; overflow: visible; pointer-events: none; }
        .review-outline { fill: none; stroke: __REVIEW_ACCENT_OUTLINE__; stroke-width: 2px; stroke-linejoin: miter; stroke-linecap: butt; }
        .review-outline.review-muted { stroke: #94a3b8; opacity: .55; }
        .review-outline.review-selected { stroke: __REVIEW_ACCENT_SELECTED__; }
        .review-outline.review-muted.review-selected { stroke: __REVIEW_ACCENT_SELECTED__; opacity: 1; }
        .review-marker { position: absolute; left: 0; top: 0; z-index: 3; display: inline-flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: 0; border-radius: 50%; padding: 0; color: __REVIEW_ACCENT_TEXT__; background: __REVIEW_ACCENT_MUTED__; box-shadow: 0 1px 3px rgba(0,0,0,.14); cursor: pointer; font: 700 12px -apple-system, BlinkMacSystemFont, sans-serif; pointer-events: auto; transform: translateX(calc(var(--stack-offset, 0px) + var(--find-offset, 0px))); transition: transform .12s ease, box-shadow .12s ease; }
        .review-marker.review-selected { z-index: 10; background: __REVIEW_ACCENT_SELECTED__; box-shadow: 0 0 0 3px __REVIEW_ACCENT_RING__, 0 1px 3px rgba(0,0,0,.18); }
        .review-marker:hover { z-index: 100; transform: translateX(calc(var(--stack-offset, 0px) + var(--find-offset, 0px))) scale(1.12); box-shadow: 0 2px 6px rgba(0,0,0,.28); }
        .review-marker.review-selected:hover { box-shadow: 0 0 0 3px __REVIEW_ACCENT_RING__, 0 2px 6px rgba(0,0,0,.28); }
        .review-marker.review-muted { color: #fff; background: #94a3b8; }
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
        const contentFindRanges = [];
        let currentContentFindQuery = '';
        let currentContentFindIndex = -1;

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

        function searchableTextIndex() {
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
          return { normalized, positions };
        }

        function findTextRange(text, item) {
          const target = (text || '').replace(/\s+/g, ' ').trim().toLowerCase();
          if (!target) return;
          const { normalized, positions } = searchableTextIndex();

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

        function rectInDocument(rect) {
          return {
            left: rect.left + window.scrollX,
            top: rect.top + window.scrollY,
            right: rect.right + window.scrollX,
            bottom: rect.bottom + window.scrollY,
            width: rect.width,
            height: rect.height
          };
        }

        function rangesForContentFind(query) {
          const target = normalizeForSearch(query);
          if (!target) return [];
          const { normalized, positions } = searchableTextIndex();
          const ranges = [];
          let index = normalized.indexOf(target);
          while (index >= 0) {
            const first = positions[index];
            const last = positions[index + target.length - 1];
            if (first && last) {
              const range = document.createRange();
              range.setStart(first.start.node, first.start.offset);
              range.setEnd(last.end.node, last.end.offset);
              ranges.push(range);
            }
            index = normalized.indexOf(target, index + Math.max(target.length, 1));
          }
          return ranges;
        }

        function contentFindResult() {
          return {
            query: currentContentFindQuery,
            count: contentFindRanges.length,
            activeIndex: currentContentFindIndex
          };
        }

        function contentFindRangeRect(range) {
          if (!range) return null;
          const rect = range.getClientRects()[0] || range.getBoundingClientRect();
          return rect && Number.isFinite(rect.top) ? rect : null;
        }

        function initialContentFindIndex() {
          if (!contentFindRanges.length) return -1;
          const visibleIndex = contentFindRanges.findIndex(range => {
            const rect = contentFindRangeRect(range);
            return rect && rect.bottom >= 12 && rect.top <= window.innerHeight - 12;
          });
          if (visibleIndex >= 0) return visibleIndex;
          const followingIndex = contentFindRanges.findIndex(range => {
            const rect = contentFindRangeRect(range);
            return rect && rect.bottom >= 12;
          });
          return followingIndex >= 0 ? followingIndex : 0;
        }

        function redrawContentFindHighlights() {
          document.getElementById('content-find-layer')?.remove();
          document.getElementById('content-find-marker-layer')?.remove();
          reconcileContentFindMarkerCollisions();
          if (!contentFindRanges.length) return;

          const layer = document.createElement('div');
          layer.id = 'content-find-layer';
          const markerLayer = document.createElement('div');
          markerLayer.id = 'content-find-marker-layer';
          const width = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth);
          const height = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
          layer.style.width = width + 'px';
          layer.style.height = height + 'px';
          markerLayer.style.width = width + 'px';
          markerLayer.style.height = height + 'px';
          const rows = [];

          contentFindRanges.forEach((range, matchIndex) => {
            Array.from(range.getClientRects()).forEach(rect => {
              if (rect.width <= 0 || rect.height <= 0) return;
              const documentRect = rectInDocument(rect);
              const rowTop = documentRect.top + (documentRect.height - 24) / 2;
              let row = rows.find(candidate => Math.abs(candidate.top - rowTop) < 8);
              if (!row) {
                row = { top: rowTop, matchIndices: [] };
                rows.push(row);
              }
              if (!row.matchIndices.includes(matchIndex)) row.matchIndices.push(matchIndex);

              const highlight = document.createElement('div');
              highlight.className = 'content-find-highlight';
              if (matchIndex === currentContentFindIndex) {
                highlight.classList.add('content-find-current');
              }
              highlight.dataset.matchIndex = String(matchIndex);
              highlight.style.left = (documentRect.left - 1) + 'px';
              highlight.style.top = (documentRect.top - 1) + 'px';
              highlight.style.width = (documentRect.width + 2) + 'px';
              highlight.style.height = (documentRect.height + 2) + 'px';
              layer.appendChild(highlight);
            });
          });

          rows.forEach(row => {
            const marker = document.createElement('div');
            marker.className = 'content-find-marker';
            if (row.matchIndices.includes(currentContentFindIndex)) {
              marker.classList.add('content-find-current');
            }
            marker.dataset.matchIndices = row.matchIndices.join(' ');
            marker.dataset.rowTop = String(row.top);
            marker.textContent = '!';
            marker.setAttribute('aria-hidden', 'true');
            marker.style.top = row.top + 'px';
            markerLayer.appendChild(marker);
          });

          document.body.appendChild(layer);
          document.body.appendChild(markerLayer);
          reconcileContentFindMarkerCollisions();
        }

        function reconcileContentFindMarkerCollisions() {
          const documentRect = rectInDocument(root.getBoundingClientRect());
          const reviewMarkers = Array.from(document.querySelectorAll('.review-marker'));
          reviewMarkers.forEach(marker => marker.style.removeProperty('--find-offset'));
          document.querySelectorAll('.content-find-marker').forEach(findMarker => {
            const rowTop = parseFloat(findMarker.dataset.rowTop || 'NaN');
            const sameRowReviewMarkers = reviewMarkers.filter(marker =>
              Math.abs(parseFloat(marker.dataset.rowTop || 'NaN') - rowTop) < 8
            );
            findMarker.style.left = (documentRect.left - (sameRowReviewMarkers.length ? 52 : 38)) + 'px';
            sameRowReviewMarkers.forEach(marker => {
              marker.style.setProperty('--find-offset', '10px');
            });
          });
        }

        function updateContentFindActiveState(previousIndex) {
          if (previousIndex >= 0) {
            document.querySelectorAll(
              `.content-find-highlight[data-match-index="${previousIndex}"], .content-find-marker[data-match-indices~="${previousIndex}"]`
            ).forEach(element => element.classList.remove('content-find-current'));
          }
          if (currentContentFindIndex >= 0) {
            document.querySelectorAll(
              `.content-find-highlight[data-match-index="${currentContentFindIndex}"], .content-find-marker[data-match-indices~="${currentContentFindIndex}"]`
            ).forEach(element => element.classList.add('content-find-current'));
          }
        }

        function revealCurrentContentFindMatch() {
          const rect = contentFindRangeRect(contentFindRanges[currentContentFindIndex]);
          if (!rect) return;
          const inset = 20;
          if (rect.top >= inset && rect.bottom <= window.innerHeight - inset) return;
          const adjustment = rect.top + rect.height * 0.5 - window.innerHeight * 0.5;
          window.scrollBy({ top: adjustment, behavior: 'auto' });
        }

        window.setContentFindQuery = query => {
          currentContentFindQuery = String(query || '');
          contentFindRanges.splice(
            0,
            contentFindRanges.length,
            ...rangesForContentFind(currentContentFindQuery)
          );
          currentContentFindIndex = initialContentFindIndex();
          redrawContentFindHighlights();
          revealCurrentContentFindMatch();
          return contentFindResult();
        };

        window.navigateContentFindBy = delta => {
          const count = contentFindRanges.length;
          if (!count) return contentFindResult();
          const step = Math.trunc(Number(delta) || 0);
          if (!step) return contentFindResult();
          const previousIndex = currentContentFindIndex;
          const origin = currentContentFindIndex < 0
            ? (step > 0 ? -1 : 0)
            : currentContentFindIndex;
          currentContentFindIndex = ((origin + step) % count + count) % count;
          updateContentFindActiveState(previousIndex);
          revealCurrentContentFindMatch();
          return contentFindResult();
        };

        window.navigateContentFind = direction =>
          window.navigateContentFindBy(direction === 'previous' ? -1 : 1);

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
          const documentLineRect = rectInDocument(lineRect);
          const rowTop = documentLineRect.top + (documentLineRect.height - 24) / 2;
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
          const documentRect = rectInDocument(root.getBoundingClientRect());
          const documentLineRect = rectInDocument(lineRect);
          const rowTop = documentLineRect.top + (documentLineRect.height - 24) / 2;
          marker.dataset.rowTop = String(rowTop);
          marker.style.left = (documentRect.left - 38) + 'px';
          marker.style.top = rowTop + 'px';
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
          const width = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth);
          const height = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
          layer.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
          layer.setAttribute('width', width);
          layer.setAttribute('height', height);
          layer.style.width = width + 'px';
          layer.style.height = height + 'px';
          layer.setAttribute('preserveAspectRatio', 'none');
          layer.replaceChildren();
          reviewRanges.forEach((range, annotationID) => {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.classList.add('review-outline');
            if (reviewStatuses.get(annotationID) === 'muted') path.classList.add('review-muted');
            path.dataset.annotationId = annotationID;
            path.setAttribute('d', outlinePath(Array.from(range.getClientRects(), rectInDocument)));
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

        let currentReviewAnnotations = [];
        window.selectedReviewAnnotationID = null;

        function rebuildAnnotationGeometry() {
          clearHighlights();
          const markerLayer = document.createElement('div');
          markerLayer.id = 'review-marker-layer';
          document.body.appendChild(markerLayer);
          currentReviewAnnotations.forEach(item => highlight(item));
          const layer = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          layer.id = 'review-outline-layer';
          document.body.appendChild(layer);
          redrawOutlines();
          reconcileContentFindMarkerCollisions();
        }

        window.setAnnotations = (annotations, selectedID) => {
          currentReviewAnnotations.splice(0, currentReviewAnnotations.length, ...(annotations || []));
          window.selectedReviewAnnotationID = selectedID || null;
          rebuildAnnotationGeometry();
        };
        window.setSelectedAnnotation = id => {
          window.selectedReviewAnnotationID = id || null;
          document.querySelectorAll('.review-selected').forEach(element => element.classList.remove('review-selected'));
          if (!id) return;
          document.querySelectorAll(`[data-annotation-id="${id}"]`).forEach(element => element.classList.add('review-selected'));
        };
        window.focusAnnotation = (id, behavior) => {
          window.setSelectedAnnotation(id);
          const marker = document.querySelector(`.review-marker[data-annotation-id="${id}"]`);
          const range = reviewRanges.get(id);
          const anchor = range?.startContainer?.parentElement;
          const target = anchor?.closest('p,li,pre,blockquote,h1,h2,h3,h4,h5,h6,td,th') || marker;
          if (!target) return false;
          const rect = target.getBoundingClientRect();
          const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
          const scrollBehavior = behavior || (reduceMotion ? 'auto' : 'smooth');
          window.scrollBy({ top: rect.top - window.innerHeight * 0.25, behavior: scrollBehavior });
          return true;
        };

        window.setMarkdownFontScale = scale => {
          const normalized = Math.min(
            __MARKREVIEW_MAX_FONT_SCALE__,
            Math.max(__MARKREVIEW_MIN_FONT_SCALE__, Number(scale) || 1)
          );
          if (!isRestoringPreviewViewport) beginViewportReflow(true);
          document.documentElement.style.setProperty('--markdown-font-scale', normalized);
          if (isRestoringPreviewViewport) {
            window.requestAnimationFrame(() => {
              redrawOutlines();
              redrawContentFindHighlights();
            });
          } else {
            scheduleViewportReflowAdjustment();
          }
        };

        let scrollReportFrame = null;
        let viewportAnchorFrame = null;
        let isRestoringPreviewViewport = true;
        let isPreservingReflowViewport = false;
        let viewportAnchor = null;
        let reflowViewportAnchor = null;
        let reflowAdjustmentFrame = null;
        let reflowEndTimer = null;
        let reflowGeneration = 0;

        function caretRangeAtPoint(x, y) {
          const position = document.caretPositionFromPoint?.(x, y);
          if (position?.offsetNode) {
            const range = document.createRange();
            range.setStart(position.offsetNode, position.offset);
            range.collapse(true);
            return range;
          }
          return document.caretRangeFromPoint?.(x, y) || null;
        }

        function textRangeNearViewportCenter() {
          const centerY = window.innerHeight * 0.5;
          const rootRect = root.getBoundingClientRect();
          const centerX = Math.min(
            Math.max(window.innerWidth * 0.5, rootRect.left + 1),
            rootRect.right - 1
          );
          const verticalOffsets = [0, -8, 8, -24, 24, -48, 48, -96, 96, -160, 160];
          for (const offset of verticalOffsets) {
            const range = caretRangeAtPoint(centerX, centerY + offset);
            const node = range?.startContainer;
            if (node?.nodeType === Node.TEXT_NODE && root.contains(node) && node.textContent?.trim()) {
              return range.cloneRange();
            }
          }
          return null;
        }

        function firstRangeRect(range) {
          if (!range) return null;
          const rect = range.getClientRects()[0] || range.getBoundingClientRect();
          return Number.isFinite(rect?.top) ? rect : null;
        }

        function captureViewportCenterAnchor() {
          const range = textRangeNearViewportCenter();
          const rect = firstRangeRect(range);
          return range && rect ? { range, viewportY: rect.top } : null;
        }

        function preserveViewportAnchor(anchor) {
          const rect = firstRangeRect(anchor?.range);
          if (!rect) return;
          const adjustment = rect.top - anchor.viewportY;
          if (Math.abs(adjustment) < 0.5) return;
          window.scrollBy({ top: adjustment, behavior: 'auto' });
        }

        function rememberCurrentViewportAnchor() {
          if (isRestoringPreviewViewport || isPreservingReflowViewport) return;
          viewportAnchor = captureViewportCenterAnchor();
        }

        function scheduleViewportAnchorCapture() {
          if (viewportAnchorFrame !== null) return;
          viewportAnchorFrame = window.requestAnimationFrame(() => {
            viewportAnchorFrame = null;
            rememberCurrentViewportAnchor();
          });
        }

        function beginViewportReflow(captureFreshAnchor = false) {
          if (!isPreservingReflowViewport) {
            reflowViewportAnchor = (captureFreshAnchor ? captureViewportCenterAnchor() : viewportAnchor)
              || captureViewportCenterAnchor();
            isPreservingReflowViewport = true;
          }
        }

        function scheduleViewportReflowAdjustment() {
          const generation = ++reflowGeneration;
          if (reflowAdjustmentFrame === null) {
            reflowAdjustmentFrame = window.requestAnimationFrame(() => {
              reflowAdjustmentFrame = null;
              preserveViewportAnchor(reflowViewportAnchor);
              redrawOutlines();
              redrawContentFindHighlights();
            });
          }

          if (reflowEndTimer !== null) window.clearTimeout(reflowEndTimer);
          reflowEndTimer = window.setTimeout(() => {
            reflowEndTimer = null;
            window.requestAnimationFrame(() => {
              if (generation !== reflowGeneration) return;
              preserveViewportAnchor(reflowViewportAnchor);
              redrawOutlines();
              redrawContentFindHighlights();
              window.requestAnimationFrame(() => {
                if (generation !== reflowGeneration) return;
                isPreservingReflowViewport = false;
                reflowViewportAnchor = null;
                rebuildAnnotationGeometry();
                viewportAnchor = captureViewportCenterAnchor();
                reportScrollPosition();
              });
            });
          }, 120);
        }

        function preserveViewportCenterDuringResize() {
          if (isRestoringPreviewViewport) return;
          beginViewportReflow();
          scheduleViewportReflowAdjustment();
        }

        function reportScrollPosition() {
          if (scrollReportFrame !== null) return;
          scrollReportFrame = window.requestAnimationFrame(() => {
            scrollReportFrame = null;
            const maximum = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
            const position = maximum > 0 ? window.scrollY / maximum : 0;
            review()?.postMessage({
              type: 'previewScrollPosition',
              position: Math.min(1, Math.max(0, position)),
              userInitiated: !isRestoringPreviewViewport && !isPreservingReflowViewport
            });
          });
        }

        window.setPreviewScrollPosition = position => {
          const normalized = Math.min(1, Math.max(0, Number(position) || 0));
          const maximum = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
          window.scrollTo({ top: maximum * normalized, behavior: 'auto' });
          window.requestAnimationFrame(redrawOutlines);
        };

        window.restorePreviewViewport = position => {
          window.setPreviewScrollPosition(position);
          window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
            window.setPreviewScrollPosition(position);
            window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
              isRestoringPreviewViewport = false;
              viewportAnchor = captureViewportCenterAnchor();
            }));
          }));
        };

        window.addEventListener('scroll', () => {
          reportScrollPosition();
          scheduleViewportAnchorCapture();
        }, { passive: true });
        window.addEventListener('resize', preserveViewportCenterDuringResize);
      </script>
    </body>
    </html>
    """#
}
