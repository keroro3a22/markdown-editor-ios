# MarkdownEditor Architecture Fragility Investigation

This is a point-in-time investigation of the current MarkdownEditor architecture. It is documentation, not a product spec. The goal is to capture why the editor feels stable only because several subsystems are manually kept in sync.

## Executive summary

The editor is not fragile because it is full of obvious bugs. It is fragile because three sources of truth are being coordinated by hand:

- Lexical's document tree
- the domain markdown model
- UIKit's text view and cursor behavior

That arrangement works, but it means the codebase survives by closing every feedback loop with custom logic, tests, and state flags. The result is durable enough to ship, but expensive to evolve.

## Main findings

### 1. Zero-width spaces are a global invariant with no single owner

Empty list items and other empty blocks rely on `\u{200B}` so the caret has a text anchor and bullets can render. That decision now leaks into multiple parts of the system:

- typing shortcuts must strip the marker back out
- emptiness checks must ignore it
- export must not serialize it into markdown
- list behavior and caret logic need to agree on what "empty" means

The problem is not the marker itself. The problem is that the visible-emptiness rule is duplicated in several places, so each feature has to rediscover the same contract.

### 2. The domain layer is larger than the production path it actually serves

The domain layer reads like a clean DDD boundary, but much of it is scaffolding:

- roughly 900 lines are not on the production path
- `MarkdownDomainBridge.execute(...)` computes a new state that the Lexical application path does not fully consume
- there are multiple markdown parsers with overlapping responsibilities
- undo exists in two forms, but only one is wired for live editing

That does not make the domain layer useless. It does mean the layer is carrying more ceremony than actual leverage.

### 3. Error handling prefers best effort over rollback

The editor intentionally swallows many mutation failures. That keeps interactive editing moving, but it also means a partially failed update can leave the tree, undo stack, and derived state temporarily out of sync.

For ordinary UI polish this is acceptable. For structural mutations like markdown shortcut conversion, paste-as-blocks, and streaming replacement, it increases the chance of silent drift.

### 4. The tests lock in the brute-forced state

The test suite is strong at preventing regression, but some of it also freezes the current implementation shape:

- many tests assert pixel geometry at a fixed viewport
- duplicated constants mean theme changes have to be updated in multiple places
- coverage-oriented tests can validate the existence of scenarios without proving they are exercised
- some geometry tests skip when preconditions are not met, which lowers the value of a green run

The most useful tests in the suite are the ones that enforce contracts: round-trips, node type behavior, zero-width-space leakage, and editor command flows.

## What is solid

The investigation also found several things worth keeping:

- no force unwraps in the core path
- no magic `asyncAfter` delays
- notification cleanup is handled correctly
- the streaming session API shape is sensible
- the public API surface is small and readable
- recent caret work moved away from eyeballed constants toward real font-metrics math

This is a useful calibration: the system is not broken in the trivial sense. Its weakness is architectural coupling.

## Fork posture

The Lexical fork is doing real work, but it should be treated as a hard fork rather than a casual upstream mirror.

Observed concerns:

- the fork contains the caret and selection behavior the editor depends on
- upstream rebases already create tension in the changed areas
- `Package.swift` still points at branch `main`, which means package updates can move the editor unexpectedly
- `Package.resolved` can lag behind the fork head

If the fork is the real dependency boundary, the docs and package pinning should say that plainly.

## Recommended hardening order

If this codebase is going to be made easier to change, the investigation points to this order:

1. Delete the dead domain-layer code that is not serving production behavior.
2. Centralize the zero-width-space and visible-emptiness invariant.
3. Make the geometry tests derive their expected values from theme data.
4. Stop swallowing mutation failures on operations where partial commits can corrupt state.
5. Pin the Lexical fork by SHA or tag and document the divergence honestly.
6. Add tighter guards around never-finished streaming sessions and other stateful edge cases.

## References

- `Sources/MarkdownEditor/MarkdownEditor.swift`
- `Sources/MarkdownEditor/Domain/MarkdownDomainBridge.swift`
- `Sources/MarkdownEditor/Domain/MarkdownInputEventProcessor.swift`
- `Tests/MarkdownEditorTests/MarkdownEditorRuntimeBehaviorMatrixTests.swift`
- `Package.swift`
- `Package.resolved`

Related docs:

- `ARCHITECTURE.md`
- `DOMAIN_LAYER_IMPLEMENTATION.md`
- `docs/cursor-height-investigation.md`
