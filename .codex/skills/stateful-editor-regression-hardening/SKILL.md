---
name: stateful-editor-regression-hardening
description: Use when fixing stateful editor regressions, especially rich-text or Markdown editor bugs involving caret geometry, cursor jumps, selection deletion crashes, paste formatting, keyboard input, markdown shortcuts, list or heading history bugs, local engine forks, TDD, UI tests, simulator/device validation, and commit/push sequencing across dependent repos.
---

# Stateful Editor Regression Hardening

## Purpose

Use this skill to turn fuzzy editor feel bugs into measurable failures, fix them at the owning layer, and guard the surrounding state space. It is especially useful for editors whose visible behavior depends on hidden document structure, selection state, native text systems, keyboard/autocorrect, import/export, or an engine fork.

## Core Posture

- Treat polish bugs as runtime correctness bugs when users can perceive them.
- Reproduce before fixing. A good fix starts with a failing test or a captured runtime trace.
- Prefer root-owner fixes over app-level workarounds. If the engine owns selection, transforms, deletion, or caret rects, patch the engine fork.
- Make history irrelevant. The same final document and selection should behave the same regardless of how the user got there.
- Validate feel on the real demo/runtime path, but do not let manual validation be the only proof.
- Keep scope honest. Pull every thread that a real red test exposes, then stop once reported repros and adjacent concrete matrices are green.

## Workflow

### 1. Map Ownership

Identify the seams before editing:

- **Engine fork**: document model, nodes, transforms, commands, selection, deletion/merge behavior, native text reconciliation, caret rect calculation.
- **Editor package**: public API, toolbar commands, markdown import/export, placeholder styling, plugin wiring, demo behavior.
- **Host app**: dependency pinning and validation only unless the bug is truly app-specific.

When a package depends on a local engine fork, link to the working directory for development, then relink to the pushed revision before final package commits.

### 2. Build Repro Lanes

Create multiple feedback loops because each catches different failures:

- **Unit tests** for selection math, node transforms, deletion/merge semantics, markdown parsing/export, placeholder attributes, and caret geometry helpers.
- **Runtime/editor tests** for full user sequences: type, toggle command, paste, enter, backspace, select, autocorrect, undo/redo.
- **UI tests** for keyboard and command bar behavior that depends on UIKit/TextKit timing.
- **Demo validation** with `sim`, using the assigned simulator. Do not hard-code a custom simulator.
- **Device/user validation** for subjective smoothness once automated tests are green.

Record exact symptoms before fixing: caret x/y/height, selected range, document structure, typing attributes, attributed text runs, export text, placeholder attributes, and layout timing samples.

### 3. Use TDD Vertically

For each reported bug:

1. Write the smallest failing test at the owning seam.
2. Confirm it fails for the real reason.
3. Fix minimally at the owner.
4. Rerun the focused test.
5. Add adjacent history-invariance cases if the failure came from stale state, hidden anchors, list context, layout timing, or native text replacement.
6. Rerun the broader matrix before moving on.

If a red test reveals a mistaken assumption, correct the test first, then ask: "what adjacent states would be broken by the same misconception?"

### 4. Make History Invariance Explicit

For every important final state, generate it through multiple histories and assert identical behavior.

Useful final states:

- Paragraph, empty paragraph, wrapped paragraph.
- Heading levels supported by the editor, with content and empty placeholder.
- Unordered list item, ordered list item, empty last list item, nested list item.
- Blockquote, code block, horizontal rule boundary, task item if supported.
- Inline styled text: bold, italic, bold+italic, strikethrough, code, link.

Useful histories:

- Clean typing from empty document.
- Enter from previous block.
- Toggle command on empty line.
- Markdown shortcut, such as `# `, `## `, `- `, `1. `.
- Paste markdown into empty document, into a block, and over a selection.
- Delete a following paragraph until selection merges back into a list or heading.
- Select entire line and backspace.
- Native autocorrect/replacement.
- Undo/redo after transform.
- Import/export round trip.

Compare more than plain text:

- Structural signature: node types, nesting, list kind, heading level, empty markers.
- Rendered signature: fonts, traits, paragraph styles, insets, placeholders.
- Selection signature: anchor/focus nodes and offsets.
- Caret signature: rect, font line metrics, baseline relationship, blink target.
- Export signature: no internal sentinel characters or invisible anchors leak to user output.

### 5. Measure Caret Geometry

Caret polish needs numbers, not vibes.

For every supported block type and style:

- Compute the expected caret height from the rendered font line height, not the row/container height.
- Assert the caret `midY` is visually centered against the rendered glyph line.
- Assert the caret `x` is at the text insertion point, respecting block insets, list markers, nesting, alignment, and trailing positions.
- Assert empty-block placeholders use the same visual font and paragraph metrics as typed content.
- Sample immediately after mutating operations, especially Enter and Backspace, to catch transient stale rects.
- Test both the "final settled rect" and "no wrong intermediate rect was published" path when the editor has async layout reconciliation.

Important operations to cover:

- Enter from paragraph, heading, list item, quote, code block, empty block, and wrapped line.
- Backspace at start, middle, end, and with full-line selection.
- Toggle heading/list on empty and non-empty lines.
- Paste formatted markdown and plain text.
- Autocorrect suggestion acceptance and marked-text composition.
- Undo/redo after each transform.

### 6. Pull Adjacent Threads

When one failure goes red, enumerate nearby risk before declaring victory:

- **Markdown shortcuts**: `# `, `## `, all heading levels, `- `, `* `, `+ `, `1. `, nested markers, shortcut after list, shortcut after deletion.
- **Placeholders**: initial empty page, empty heading, empty list item, empty quote/code block, style toggle before typing, style toggle after deleting content.
- **Selections**: collapsed caret, full line, partial word, multi-block, triple tap, select all, selected backspace, selected paste, selected toolbar toggle.
- **Deletion/merge**: backspace across block boundaries, after list exit, after heading, empty last list item, nested list outdent, delete into previous block.
- **Keyboard/native text**: autocorrect pill, smart quotes/dashes, marked text, dictation, hardware keyboard, keyboard show/dismiss, command bar focus changes.
- **Paste/import**: headings, nested lists, ordered lists with gaps, task lists, tables, blockquotes, code fences, inline code, links, images, thematic breaks, malformed markdown.
- **Unicode**: composed accents, emoji, ZWJ emoji, skin tones, flags, RTL text, CJK, zero-width characters, non-breaking spaces, tabs, CRLF, trailing newlines.
- **Layout/perf**: long documents, wrapped lines, rapid typing, scrolling while typing, dynamic type, safe area/keyboard overlap, toolbar animation, repeated command toggles.

Do not add infinite abstract coverage. Add cases that protect a real invariant discovered during diagnosis.

### 7. Fix at the Owner

Choose the lowest correct layer:

- Engine selection bugs belong in the engine.
- TextKit/native reconciliation bugs belong where native text and editor state synchronize.
- Caret rect bugs belong where insertion rects are calculated or cached.
- Node transform/delete/list bugs belong in node/command logic.
- Placeholder and command-bar API issues usually belong in the package integration layer.
- Host apps should mostly point at the right package revision and validate behavior.

Avoid fixes that only hide symptoms in the demo app while leaving the engine inconsistent.

### 8. Validate in a Ladder

Run validation from narrow to broad:

1. Focused failing tests.
2. Engine tests for changed internals.
3. Package/editor tests for public behavior.
4. UI tests for keyboard, toolbar, and transient caret behavior.
5. Build the demo app.
6. Run the demo with `sim` and manually exercise the exact repros plus adjacent paths.
7. Check diffs and exported content for leaked sentinels, fixture churn, or unrelated changes.

Prefer compile-only validation when simulator runs would disturb the user's workflow, unless runtime behavior is the actual target. For editor feel work, runtime validation is usually required.

### 9. Commit and Push Across Repos

When changes span an engine fork and package:

1. Commit the engine fork first.
2. Push the engine fork.
3. Update the package dependency to the latest pushed engine state.
4. Commit only the dependency update in the package when requested.
5. Push the package.
6. If a host app was temporarily relinked to a local working directory for validation, restore it to the pushed package before committing.

Keep dependency relinks separate from behavioral changes when the user asks for "that change only."

## Completion Criteria

Done means:

- Every reported repro has a failing automated test or a documented runtime trace that would have caught it.
- Tests fail before the fix and pass after, when practical.
- Adjacent history-invariance cases pass.
- Caret geometry is measured for all supported block types touched by the bug.
- Markdown paste, shortcut, placeholder, selection, deletion, and list edge cases have targeted coverage.
- The fix lives in the owning repo.
- Demo/device validation agrees with automated proof.
- Commits and pushes are sequenced correctly if requested.

## Stop Rule

This workflow invites deep exploration, but it should still converge. Once the user's current repros are green on device, the broad matrix is green, and no concrete red thread remains, stop widening scope and report what is still unproven instead of inventing new work.
