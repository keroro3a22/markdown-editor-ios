# MarkdownEditor - Claude Documentation

## Repository Overview

This is a Swift package that provides a rich markdown editor for iOS, built on a hard fork of Meta's Lexical framework. Lexical's editor state is the single source of truth; the package layers markdown import/export, editing behavior, streaming AI editing, undo/redo, and theming on top. See `ARCHITECTURE.md` for the full picture.

## Architecture

### Core Components

1. **Lexical Foundation** (Primary)
   - **LexicalView**: The main text editing component
   - **Lexical Editor**: Handles all real-time editing operations
   - **Lexical Plugins**: Lists, links, markdown export
   - **Hard fork**: `jcfontecha/lexical-ios`, pinned by exact revision in `Package.swift` — we modify it freely (caret geometry, reconciler selection handling, the canonical ZWSP anchor API, list/theme styling)

2. **Editor Layer** (this package)
   - **MarkdownEditorView / MarkdownEditorContentView**: Main editor component (UIKit)
   - **MarkdownLexicalBridge** (internal): formatting (with business-rule guards), block-type toggling, smart backspace, selection-scoped state reads, markdown export
   - **MarkdownImporter**: markdown → Lexical nodes (import and paste)
   - **Streaming sessions**: `startReplacement` / `startAppend` for AI editing; editor is read-only until `finish()`/`cancel()`
   - **Snapshot undo/redo**: cloned `EditorState` stacks with markdown-fingerprint grouping

3. **UI Layer**
   - **SwiftUIMarkdownEditor**: SwiftUI wrapper
   - **MarkdownCommandBar**: keyboard accessory toolbar (iOS 26 glass + scroll-edge effects)
   - **MarkdownAccessoryCoordinator**: keyboard inset coordination

### Design Philosophy

- **Lexical-First**: Lexical remains the single source of truth for all editing operations
- **Hard fork control**: the Lexical fork is ours; root-cause fixes go there, not in package-side workarounds
- **One canonical ZWSP API**: every "is this block visibly empty?" decision goes through the fork's public `emptyText*` helpers — never a local scalar set
- **Rollback over partial state**: compound mutations snapshot the editor state and restore it on failure; failures are loud, never silently degraded
- **Tests exercise the real editor**: there is no simulation layer; geometry expectations derive from the theme, never literals

## Build & Test Workflow

### Prerequisites
- Xcode 26+
- iOS 17.0+ target
- Lexical fork checkout at `/Users/juan/Developer/lexical-ios` for fork work (the package builds from the pinned remote revision; see `docs/BUILDING.md` for the bump/local-override workflow)

### Building

```bash
# Use Xcode workspace (recommended)
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme MarkdownEditor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Testing

```bash
# Run all tests
xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme MarkdownEditor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Key Test Categories

1. **Runtime behavior suites** (`Tests/MarkdownEditorTests/Runtime/`, on the shared `MarkdownRuntimeTestCase` base)
   - `CaretGeometryContractTests` — caret contracts with regression history (height/centering, wrapped lines, Enter jitter)
   - `BlockCanonicalizationTests` — equivalent histories converge; export/import + undo/redo round-trips
   - `ListEnterExitBehaviorTests` — list enter/exit/backspace, generated marker matrices
   - `ShortcutPasteAndPlaceholderTests` — markdown shortcuts, paste parsing, placeholder tracking
   - `SelectionRobustnessTests` — backspace crash matrix, autocorrect replacement, marked text

2. **Contract tests**
   - `MarkdownRegressionMatrixTests` — node types, round-trips, ZWSP-leak checks
   - `MarkdownFormattingGuardrailTests` — the three formatting business rules on the live editor
   - `StreamingReplacementTests` / `StreamingAppendTests` / `UndoRedoTests`

3. **Caret regression files**
   - `MarkdownEditorWrappedLineCaretTests`, `MarkdownEditorEnterPolishRegressionTests` — pinned against TextKit's glyph-position oracle

## Dependencies

- **Lexical**: hard fork `jcfontecha/lexical-ios`, pinned by revision (tagged `0.x.y`)
- **swift-markdown**: Apple's markdown parsing (transitively via the fork)
- **SwiftSoup**: HTML parsing for Lexical plugins

## File Structure

```
Sources/MarkdownEditor/
├── MarkdownEditor.swift              # MarkdownEditorView + ContentView, input handling, undo, streaming
├── MarkdownLexicalBridge.swift       # Internal operations bridge (formatting/block-type/backspace/export)
├── SwiftUIMarkdownEditor.swift       # SwiftUI wrapper
├── MarkdownConfiguration.swift       # Configuration + public API types
├── MarkdownTheme.swift               # Typography/colors/spacing themes
├── MarkdownCommandBar.swift          # Keyboard accessory toolbar
├── MarkdownAccessoryCoordinator.swift# Keyboard inset coordination
├── MarkdownCursorDelegate.swift      # Cursor customization hook
├── MarkdownDocument.swift            # Document model + metadata
├── MarkdownImporter.swift            # Markdown → Lexical nodes
├── StreamingReplacementEditing.swift # Streaming session API + fuzzy matching
├── StreamingTextSmoother.swift       # Streaming display pacing
├── MarkdownCommandLogger.swift       # Structured operation logging
├── MarkdownLogger.swift              # Logging plumbing
└── ZeroWidthSpaceFixPlugin.swift     # List editing fix plugin

Tests/MarkdownEditorTests/
├── Runtime/                          # Runtime behavior suites + RuntimeTestSupport base
├── MarkdownRegressionMatrixTests.swift
├── MarkdownFormattingGuardrailTests.swift
├── Streaming*/UndoRedo/WrappedLineCaret/EnterPolish tests
└── MarkdownTestHelpers.swift         # Scenario DSL base (MarkdownTestCase)
```

## Maintenance Notes

- **Fork bumps**: commit + tag in `../lexical-ios`, push with tags, update the `revision:` in `Package.swift`, re-resolve both `Package.resolved` files (root and Demo). See `docs/BUILDING.md`.
- Some geometry tests may fail on simulator/OS combinations the suite wasn't tuned for; compare against the current baseline before attributing failures to a change.
