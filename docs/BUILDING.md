# Building and Testing

`MarkdownEditor` is an iOS UIKit-based package, so build and test workflows should run through Xcode tooling.

## Recommended build flow (`make`)

- Build the package target:
  - `make build markdown-editor`
- Build the demo app for iOS Simulator:
  - `make build demo-app`
- Build both when you want a broader compile check:
  - `make build`
- Use verbose logs when you need rawer `xcodebuild` output:
  - `make build demo-app --verbose`

## Alternative (Xcode)

- Framework + tests: open `Demo/MarkdownEditor.xcodeproj` or `.swiftpm/xcode/package.xcworkspace` and run the `MarkdownEditor` test target.
- Demo app: open `Demo/MarkdownEditor.xcodeproj` and run the `MarkdownEditorDemo` scheme.

## Dependency notes

The package dependency is remote and pinned to an exact revision (a tagged commit of the hard fork):
- `https://github.com/jcfontecha/lexical-ios.git`

To bump the fork: commit + tag in `../lexical-ios` (continue the `0.x.0` lineage), push with tags, then update the `revision:` SHA in `Package.swift` and re-resolve **both** resolved files (root `Package.resolved` and `Demo/MarkdownEditor.xcodeproj/.../swiftpm/Package.resolved`).

For deep Lexical work, use a local override instead of editing the pin — either drag `../lexical-ios` into the Xcode workspace (local packages shadow remote ones), or temporarily switch `Package.swift` to:
- `.package(path: "../lexical-ios")`

Restore the remote pinned dependency before committing release-facing changes.
