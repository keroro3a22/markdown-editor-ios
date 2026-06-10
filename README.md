# MarkdownEditor for iOS

An iOS-focused WYSIWYG markdown editor built on [Lexical-iOS](https://github.com/jcfontecha/lexical-ios) with a Swift API designed for app integration.

![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)
![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)

## Overview

`MarkdownEditor` ships two supported entry points:

- `MarkdownEditorView` (UIKit)
- `MarkdownEditor` (SwiftUI)

Lexical is the single source of truth; a thin internal bridge owns formatting, block-type, smart-backspace, and export operations on top of it.

## Key Features

- ⚡ Real-time WYSIWYG markdown editing
- 🧱 Optional SwiftUI wrapper with UIKit implementation under the hood
- 🎨 Theme system with spacing and typography customization
- 📚 Built-in list and block styling presets
- 🧠 Structured command and logging infrastructure
- ✂️ Streaming replacement helpers for LLM-style text updates
- 🧪 Swift Testing + XCTest coverage in the demo test target

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
// Package.swift
let package = Package(
    dependencies: [
        .package(url: "https://github.com/jcfontecha/markdown-editor-ios.git", from: "1.0.0")
    ]
)
```

In Xcode, add package URL:
`https://github.com/jcfontecha/markdown-editor-ios.git`

### Lexical dependency

The default dependency is remote:

- `https://github.com/jcfontecha/lexical-ios.git`

If you are working on Lexical internals, temporarily switch the package dependency in `Package.swift` to a local checkout:

```swift
.package(path: "../lexical-ios")
```

## Quick Start

### SwiftUI

```swift
import SwiftUI
import MarkdownEditor

struct ContentView: View {
    @State private var markdownText = "# Hello world\n\nStart writing…"

    var body: some View {
        MarkdownEditor(
            text: $markdownText,
            configuration: .default
                .theme(.default)
                .features(.standard),
            placeholderText: "Write something…"
        )
        .padding()
    }
}
```

### UIKit

```swift
import UIKit
import MarkdownEditor

final class EditorViewController: UIViewController {
    private let editor = MarkdownEditorView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(editor)
        editor.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let document = MarkdownDocument(content: "# Title\n\nSwiftUI and UIKit integration sample.")
        _ = editor.loadMarkdown(document)
    }
}
```

For a content-only UIKit surface (no internal scroll container), use:

- `MarkdownEditorContentView` in place of `MarkdownEditorView`.
- `isScrollEnabled: false` on the SwiftUI wrapper.

## Core Components

- `MarkdownEditorView`: Full-screen iOS text editor component
- `MarkdownEditorContentView`: Embeddable content view when you manage scrolling yourself
- `MarkdownCommandBar`: Optional glass keyboard command bar for format actions
- `ZeroWidthSpaceFixPlugin`: Internal list-editing resilience
- `StreamingTextSmoother`: Streaming cadence helper for incremental text replacement
- `MarkdownEditor`: SwiftUI wrapper around `MarkdownEditorView`

## Configuration

### Theme presets

```swift
let defaultEditor = MarkdownEditorView(configuration: .init(theme: .default))
let compactEditor = MarkdownEditorView(configuration: .init(theme: .compact))
let spaciousEditor = MarkdownEditorView(configuration: .init(theme: .spacious))
let traditionalEditor = MarkdownEditorView(configuration: .init(theme: .traditional))
```

### Feature sets

```swift
let features: MarkdownFeatureSet = [.headers, .lists, .codeBlocks, .quotes, .links, .inlineFormatting]
let editor = MarkdownEditorView(configuration: .init(features: features))
```

### Behavior

```swift
let behavior = EditorBehavior(
    autoSave: true,
    autoCorrection: true,
    smartQuotes: true,
    returnKeyBehavior: .smart,
    startWithTitle: true
)

let editor = MarkdownEditorView(configuration: .init(behavior: behavior))
```

### Logging

```swift
let logging = LoggingConfiguration(
    isEnabled: true,
    level: .debug,
    includeTimestamps: true,
    includeDetailedState: false
)

let editor = MarkdownEditorView(configuration: .init(logging: logging))
```

## API Reference

### Load / Export

```swift
let result = editor.loadMarkdown(MarkdownDocument(content: markdownString))
switch result {
case .success:
    // document loaded
case .failure(let error):
    // handle MarkdownEditorError
    let _ = error
}

let exportResult = editor.exportMarkdown()
switch exportResult {
case .success(let document):
    let markdown = document.content
case .failure(let error):
    // handle MarkdownEditorError
    let _ = error
}
```

### Commands

```swift
// Use InlineFormatting(rawValue:) for combinations
editor.applyFormatting(.init(rawValue: InlineFormatting.bold.rawValue | InlineFormatting.italic.rawValue))
editor.setBlockType(.heading(level: .h1))
editor.setBlockType(.unorderedList)
let current = editor.getCurrentFormatting()
let blockType = editor.getCurrentBlockType()
editor.undo()
editor.redo()
```

### Delegate

```swift
class MyController: UIViewController, MarkdownEditorDelegate {
    func markdownEditorDidChange(_ editor: any MarkdownEditorInterface) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didLoadDocument document: MarkdownDocument) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didAutoSave document: MarkdownDocument) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didEncounterError error: MarkdownEditorError) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didChangeEditingState isEditing: Bool) {}
}
```

### Command bar integration

```swift
let commandBar = MarkdownCommandBar()
commandBar.editor = editor
editor.textView.inputAccessoryView = commandBar
```

## Repository layout

```text
MarkdownEditor/
├── Package.swift
├── README.md
├── Sources/
│   └── MarkdownEditor/
│       ├── MarkdownConfiguration.swift
│       ├── MarkdownDocument.swift
│       ├── MarkdownEditor.swift          # UIKit surface + protocolized interface
│       ├── MarkdownTheme.swift
│       ├── StreamingReplacementEditing.swift
│       ├── StreamingTextSmoother.swift
│       ├── MarkdownCommandBar.swift
│       ├── MarkdownCommandLogger.swift
│       ├── MarkdownLogger.swift
│       ├── ZeroWidthSpaceFixPlugin.swift
│       ├── SwiftUIMarkdownEditor.swift  # SwiftUI wrapper
│       └── MarkdownLexicalBridge.swift  # Internal operations bridge
├── Tests/
│   └── MarkdownEditorTests/
└── Demo/
    ├── MarkdownEditor.xcodeproj
    └── MarkdownEditor/
```

## Build and development commands

- `make build markdown-editor`
- `make build demo-app`
- `make build`
- `make build demo-app --verbose`
- `sim run`

## Docs

- `docs/BUILDING.md`
- `Demo/LIST_STYLING_EXAMPLES.md`
- `Tests/MarkdownEditorTests/README.md`

## Security & Governance

- See `SECURITY.md`
- See `CONTRIBUTING.md`
- See `CODE_OF_CONDUCT.md`
- See `CHANGELOG.md`

## License

MIT License. See `LICENSE`.
