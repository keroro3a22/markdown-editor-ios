# MarkdownEditor Architecture

## Overview

MarkdownEditor is a Swift package providing a rich markdown editor for iOS, built on a hard fork of Meta's Lexical framework (`jcfontecha/lexical-ios`, pinned by exact revision). Lexical's editor state is the single source of truth; the package adds markdown import/export, editing behavior, streaming AI editing, undo/redo, and theming on top of it.

## Layers

```
MarkdownEditorView (UIKit)                SwiftUIMarkdownEditor / MarkdownEditor
  └── UIScrollView                          └── wraps MarkdownEditorView
        └── MarkdownEditorContentView
              ├── LexicalView (Lexical engine: nodes, selection, rendering)
              ├── MarkdownLexicalBridge (internal service)
              ├── MarkdownImporter (markdown → Lexical nodes)
              ├── ZeroWidthSpaceFixPlugin (list editing)
              ├── MarkdownCommandBar (keyboard accessory, iOS 26 glass)
              └── snapshot-based undo/redo (EditorState stacks)
```

### MarkdownLexicalBridge

A thin internal service owning the operations the view exposes:

- `currentBlockType()` / `currentFormatting()` — selection-scoped reads (no document serialization).
- `applyFormatting(_:)` — toggles inline formatting, enforcing the three business rules: no inline formatting in code blocks, no multi-block formatting, and code is incompatible with bold/italic/strikethrough (within a request and against the selection). Rejections surface as `.unsupportedFeature` delegate errors with the document unchanged.
- `setBlockType(_:)` — smart toggle (same list type / heading level toggles back to paragraph) with caret preservation.
- `performSmartBackspace()` — converts an empty list item at line start to a paragraph.
- `exportDocument()` — the only full-document serialization path (ZWSP-stripped), memoized by the view's export cache.

### Input handling

The content view intercepts Lexical commands at high priority: Enter (paragraph insertion + empty-block caret anchoring), Backspace (smart list handling), space (markdown shortcuts: `#`–`######`, `-`/`*`/`+`, `1.`), and paste (markdown detection → block parsing). Compound mutations (shortcut conversion, paste-as-blocks, streaming deltas) snapshot the editor state first and roll back on failure — Lexical commits partial mutations on inner errors, so failures restore the snapshot instead of leaving partial state.

### Caret-anchor (ZWSP) invariant

Empty blocks that must stay selectable (list items, freshly converted headings, empty code blocks) are seeded with a zero-width-space text node. The canonical API lives in the Lexical fork (`emptyTextCaretAnchor`, `emptyTextInvisibleScalarValues`, `textContentRemovingEmptyInvisibles`, `isTextContentEmptyIgnoringEmptyInvisibles`, `emptyTextInvisibleScalarCount`) and is the single source of truth for "visibly empty" decisions in both repos. Export never leaks the anchor.

### Streaming AI editing

`MarkdownStreamingEditing` / `MarkdownStreamingAppending` start token-validated sessions (`ReplacementSession`, `AppendSession`). The editor is read-only while a session is active; callers must end every session with `finish()` (keep content, one undo step) or `cancel()` (restore the original document) on every exit path. Replacement targets a single block chosen by fuzzy matching (`StreamingReplacementMatching`); append re-renders accumulated markdown at the document end per delta. Session bookkeeping advances only after a successful apply.

### Undo/redo

Snapshot-based: cloned `EditorState` stacks (max 200) with markdown-fingerprint grouping (0.75s merge window). Streaming sessions and paste commit one undo step each. Programmatic restores run under reentrancy flags so the history recorder only advances its baseline.

## Dependencies

- **Lexical fork** — `jcfontecha/lexical-ios`, hard fork, pinned by revision in `Package.swift` (see `docs/BUILDING.md` for the bump and local-override workflow). Fork divergence is documented in the fork's README.
- **swift-markdown** — markdown serialization (via the fork's LexicalMarkdown).
- **SwiftSoup** — HTML support for Lexical plugins.

## Testing

All tests exercise the real editor (`MarkdownEditorView`/`LexicalView`); there is no simulation layer.

- `Tests/MarkdownEditorTests/Runtime/` — the runtime behavior suites on a shared `MarkdownRuntimeTestCase` base (390×800 viewport): caret geometry contracts (`CaretGeometryContractTests`), history convergence + round-trips (`BlockCanonicalizationTests`), list enter/exit (`ListEnterExitBehaviorTests`), shortcuts/paste/placeholder (`ShortcutPasteAndPlaceholderTests`), selection robustness (`SelectionRobustnessTests`). Geometry expectations derive from the configuration theme, never from literals.
- `MarkdownRegressionMatrixTests` — node-type and round-trip contracts (the node-type vocabulary home).
- `MarkdownFormattingGuardrailTests` — the three formatting business rules against the live editor.
- `StreamingReplacementTests` / `StreamingAppendTests` / `UndoRedoTests` — behavioral contracts.
- `MarkdownEditorWrappedLineCaretTests` / `MarkdownEditorEnterPolishRegressionTests` — caret regressions pinned against TextKit's glyph-position oracle.

Build and test commands live in `docs/BUILDING.md` and `CLAUDE.md`.
