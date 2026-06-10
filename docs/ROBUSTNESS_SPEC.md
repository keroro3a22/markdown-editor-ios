# MarkdownEditor Robustness Spec

## Status
- Historical (June 2026): the domain layer this spec describes was removed in the
  hardening refactor — Lexical is the single source of truth and the
  domain/Lexical drift sections below are resolved by deletion. Kept for the
  reliability goals and reproducibility guidance, which still apply.

## Problem Statement
The repository currently feels “flaky” because build/test execution is not consistently reproducible across environments, and runtime/editor behavior can vary depending on timing and state drift between the domain layer and Lexical.

This spec defines the reliability goals, constraints, and a concrete approach to make the framework deterministic, testable, and predictable under real user input.

## Goals
- Reproducible builds and tests with a single supported invocation (locally and in CI).
- Deterministic Markdown import/export (stable normalization and round-trips).
- Predictable keyboard/command behavior (Enter/Backspace/List toggles) without timing-dependent bugs.
- Clear “source of truth” contract between Lexical and the domain layer.
- Strong regression test coverage around historically fragile areas.

## Non-Goals
- Rewriting Lexical-iOS or testing Lexical itself beyond integration boundaries.
- Implementing a full CommonMark parser/renderer (unless adopted as a dependency deliberately).
- Supporting platforms outside the package’s stated iOS target without an explicit product decision.

## Key Definitions
- **Lexical State**: The editor’s internal node tree and selection.
- **Domain State**: `MarkdownEditorState` and related domain models/services.
- **Source of Truth**: The canonical state that all other layers derive from.
- **Deterministic Markdown**: The same editor state always serializes to the same markdown string (modulo an explicit normalization policy).

## Current Known Sources of Flakiness
### 1) Build/Test Reproducibility
- `swift test` fails in this workspace due to a platform requirement conflict inside the `lexical-ios` dependency (macOS version requirements between `LexicalHTML` and `SwiftSoup`).
- Tests therefore tend to rely on Xcode + iOS Simulator, which must be made the explicit supported path (or the dependency constraints must be resolved).

### 2) Domain ↔ Lexical State Drift
- Some domain services intentionally “simulate” operations without mutating markdown content (notably formatting), while the bridge sometimes regenerates markdown from Lexical and overwrites domain state.
- Selection mapping in the bridge is best-effort and is used for context/logging/validation only; list editing should remain Lexical-driven to avoid “markdown cursor math” bugs.

### 3) Eventing / Threading / Re-entrancy
- Work is performed inside update listeners and command handlers (delegate notifications, autosave, layout invalidation).
- If not carefully scoped, this can lead to re-entrancy, ordering issues, and difficult-to-reproduce behavior.

## Reliability Strategy
### A) Make “Supported Test Runner” Explicit
Pick one of:
1. **Xcode + iOS Simulator is canonical** (recommended for this repo today).
2. **`swift test` is canonical** (requires resolving the dependency platform mismatch in `lexical-ios`).

Once chosen, codify it:
- Add a single documented command in README / testing docs.
- Add CI running that exact command.
- Ensure the command is fast, stable, and failure-output is actionable.

### B) Define a Single Source of Truth (Decision Required)
Choose one of these models and enforce it everywhere:

1) **Lexical is canonical**
- Domain state is derived (selection/block/format context + validated invariants).
- Domain commands translate to Lexical operations plus explicit invariants and validation.
- Tests focus on node tree invariants + markdown serialization normalization.

2) **Domain markdown is canonical**
- Domain services fully implement markdown edits (parse/format/serialize) and selection mapping.
- Lexical is a renderer/view of domain content.
- Tests focus on deterministic content mutations; Lexical is integration-tested only.

**Decision (this repo): Lexical is canonical.**
- The editor node tree + selection are the source of truth.
- Domain state is derived for validation/context and must be refreshed from Lexical after applying commands.
- Markdown strings are treated as a serialization format (with explicit normalization).

## Input Handling Policy (Lists)
Lists are treated as a Lexical-native editing surface:
- Enter/Backspace behaviors inside list items are handled by `LexicalListPlugin` (plus any targeted Lexical plugins like ZWSP fixes).
- The domain layer should not “rewrite” list structure in response to raw keypresses, because that requires perfect selection↔markdown mapping and has historically caused cursor jumps and structural corruption.

### C) Deterministic Markdown I/O
- Define an explicit normalization policy for Markdown export (e.g., line endings, trailing newline, list spacing, code-fence formatting).
- Add round-trip invariants:
  - Import(markdown) → Export() is normalized(markdown)
  - Export() → Import() preserves key semantic structure

### D) Harden Event Handling
- Coalesce update listener side-effects (delegate callbacks, autosave, layout updates).
- Ensure UI-affecting operations occur on the main thread.
- Avoid dispatching editor commands in ways that can re-enter handlers unexpectedly.
- Always store and unregister listener removal handlers to avoid “ghost callbacks”.

### E) Add Regression Tests for Fragile Paths
Prioritize tests for:
- Enter behavior inside lists (empty/non-empty list items).
- Backspace behavior at list boundaries (empty item deletion, start-of-line behavior).
- Block type toggles (unordered/ordered list toggles to paragraph).
- Zero-width-space handling invariants (ZWSP should not cause “non-empty” detection bugs).

## Acceptance Criteria
- There is a single recommended test command, and it runs reliably on a clean machine/CI.
- No silent state-sync failures without telemetry/logging hooks.
- Backspace/Enter behaviors are deterministic and covered by regression tests.
- Listener lifecycles are managed (registered handlers can always be removed on deinit).
- Markdown export is stable under repeated export calls without editor changes.
