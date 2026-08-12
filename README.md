# MarkReview

MarkReview is a small, free macOS document-review app for Markdown files.

It is designed for the workflow where a human reads a document, selects a
passage, writes a comment, and then gives the resulting structured review to
an AI agent. The app deliberately keeps the scope narrow:

- Markdown is rendered in a native macOS window using Apple's `swift-markdown`
  Swift package and a local WebKit preview.
- Select rendered text and choose **Comment selection**, or hold Option and
  click a paragraph/list item/heading to comment on the whole block.
- Comments appear in a right-hand review panel and can be resolved or deleted.
- The review is saved as one `.markreview` document containing the original
  Markdown and annotations. The source `.md` file is never modified.
- **Export Agent JSON** writes numbered annotations with the exact selected
  text, section, surrounding context, source-line hints, and status.

## Build and run

Requirements: macOS 14 or later, Xcode 27 or a compatible Swift toolchain.

```sh
./scripts/build-app.sh
open MarkReview.app
```

You can also run the executable during development:

```sh
swift run MarkReview
```

## Workflow

1. Open MarkReview and choose **Import Markdown**.
2. Select a sentence or paragraph in the rendered document.
3. Click **Comment selection** and write an actionable note.
4. Save the review as `Document.markreview`.
5. Choose **Export Agent JSON** and give the exported JSON to the agent.

The `.markreview` file is JSON rather than a binary container, so it remains
inspectable, diffable, and easy to back up in iCloud. It is a separate copy of
the Markdown plus review state; no hidden database is required.

## Deliberate limitations in this first version

- This is a review surface, not a Markdown editor. The imported Markdown is
  intentionally read-only inside the review document.
- Text annotations are anchored by quoted text and surrounding context. If the
  source is later changed, the agent can still locate the intended passage by
  quote, section, and context, but MarkReview does not yet re-anchor visually.
- Option-click creates a block annotation. There is no freehand drawing layer;
  “circle an area” is represented as a selected block so the exported data is
  useful to an agent rather than dependent on screen coordinates.
- Images and advanced Markdown extensions are left to the renderer's normal
  behavior; the review anchor is textual.
