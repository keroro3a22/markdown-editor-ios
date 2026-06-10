/*
 * RuntimeTestSupport
 *
 * Shared base class and helpers for the runtime behavior suites: a real
 * MarkdownEditorView at a fixed 390x800 viewport, typing/selection drivers,
 * structural queries, render/caret signatures, fixtures, and caret samplers.
 * All geometry expectations are derived from the editor's configuration theme,
 * never from literals.
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

class MarkdownRuntimeTestCase: MarkdownTestCase {
    override func setUp() {
        super.setUp()
        markdownEditor = MarkdownEditorView(configuration: .init(behavior: .init(
            autoSave: false,
            autoCorrection: false,
            smartQuotes: false,
            returnKeyBehavior: .smart,
            startWithTitle: false
        )))
        markdownEditor.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        markdownEditor.placeholderText = "Write something"
        markdownEditor.layoutIfNeeded()
    }
    var userReportedPastePayload: String {
        """
        # Heading 1
        ## Heading 2

        **bold** and *italic* and ***both***

        - bullet point
        - another one
          - nested

        1. numbered
        2. list

        [link text](https://example.com)
        ![alt text](image.jpg)

        `inline code` and:

        ```python
        def hello():
            print("hi")
        ```

        > blockquote

        | col1 | col2 |
        |------|------|
        | a    | b    |

        ---

        ~~strikethrough~~ and - [ ] task list
        """
    }

    func prepareEmptyInsertionPoint(_ entryPath: EntryPath) throws {
        switch entryPath {
        case .emptyDocument:
            try resetToEmptyParagraph()
        case .newLineAfterBody:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "Body"))
            try selectText("Body", offset: 4)
            typeText("\n")
        case .newLineAfterTitle:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title"))
            try selectText("Title", offset: 5)
            typeText("\n")
        case .afterListExit:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "- "))
            typeText("\n")
        case .afterParsedPaste:
            try resetToEmptyParagraph()
            let pasteboard = UIPasteboard.withUniqueName()
            pasteboard.string = "# Pasted"
            editor.dispatchCommand(type: .paste, payload: pasteboard)
            typeText("\n")
        }
    }

    enum EntryPath: CaseIterable {
        case emptyDocument
        case newLineAfterBody
        case newLineAfterTitle
        case afterListExit
        case afterParsedPaste
    }

    enum HistoryPath: CaseIterable, CustomStringConvertible {
        case clean
        case afterBodyEnter
        case afterHeadingEnter
        case afterListDoubleEnter
        case afterPasteEnter
        case afterQuoteEnter
        case afterCodeEnter

        var description: String {
            switch self {
            case .clean: return "clean"
            case .afterBodyEnter: return "afterBodyEnter"
            case .afterHeadingEnter: return "afterHeadingEnter"
            case .afterListDoubleEnter: return "afterListDoubleEnter"
            case .afterPasteEnter: return "afterPasteEnter"
            case .afterQuoteEnter: return "afterQuoteEnter"
            case .afterCodeEnter: return "afterCodeEnter"
            }
        }

        var sequenceSeedOffset: Int {
            switch self {
            case .clean: return 0
            case .afterBodyEnter: return 1_000
            case .afterHeadingEnter: return 2_000
            case .afterListDoubleEnter: return 3_000
            case .afterPasteEnter: return 4_000
            case .afterQuoteEnter: return 5_000
            case .afterCodeEnter: return 6_000
            }
        }
    }

    enum EmptyBlockAnchorMode: CustomStringConvertible {
        case noChildren
        case invisibleTextAnchor

        var description: String {
            switch self {
            case .noChildren: return "noChildren"
            case .invisibleTextAnchor: return "invisibleTextAnchor"
            }
        }
    }

    struct CanonicalBlockCase {
        let name: String
        let block: MarkdownBlockType
        let text: String
        let expected: ExpectedCaretContract
    }

    struct ExpectedCaretContract {
        let type: NodeType
        let font: UIFont
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let allowsListAttribute: Bool
    }

    struct DeterministicGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
        }

        mutating func nextIndex(upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state % UInt64(upperBound))
        }
    }

    // Geometry expectations derive from the configuration theme and the Lexical
    // theme the editor actually built — never from literals, so theme changes
    // propagate to expectations automatically.

    /// One indent unit; quotes render at indent level 1 (AttributesUtils).
    var expectedQuoteIndent: CGFloat {
        MarkdownEditorConfiguration.default.theme.spacing.indentSize
    }

    /// Code blocks indent by the paddingHead the editor set on the Lexical theme.
    var expectedCodeIndent: CGFloat {
        if let padding = editor.getTheme().code?[.paddingHead] as? Double {
            return CGFloat(padding)
        }
        XCTFail("Lexical theme has no code paddingHead — createLexicalTheme changed?")
        return 0
    }

    /// List items indent by bullet margin + bullet-to-text spacing (ListItemNode).
    var expectedListIndent: CGFloat {
        let spacing = MarkdownEditorConfiguration.default.theme.spacing
        return spacing.listBulletMargin + spacing.listBulletTextSpacing
    }

    var canonicalBlockCases: [CanonicalBlockCase] {
        let typography = MarkdownEditorConfiguration.default.theme.typography
        return [
            .init(name: "paragraph", block: .paragraph, text: "Body", expected: .init(type: .paragraph, font: typography.body, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h1", block: .heading(level: .h1), text: "Title", expected: .init(type: .heading, font: typography.h1, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h2", block: .heading(level: .h2), text: "Subtitle", expected: .init(type: .heading, font: typography.h2, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h3", block: .heading(level: .h3), text: "Heading 3", expected: .init(type: .heading, font: typography.h3, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h4", block: .heading(level: .h4), text: "Heading 4", expected: .init(type: .heading, font: typography.h4, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h5", block: .heading(level: .h5), text: "Heading 5", expected: .init(type: .heading, font: typography.h5, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h6", block: .heading(level: .h6), text: "Heading 6", expected: .init(type: .heading, font: typography.h5, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "quote", block: .quote, text: "Quote", expected: .init(type: .quote, font: typography.body, firstLineHeadIndent: expectedQuoteIndent, headIndent: expectedQuoteIndent, allowsListAttribute: false)),
            .init(name: "code", block: .codeBlock, text: "code", expected: .init(type: .code, font: typography.code, firstLineHeadIndent: expectedCodeIndent, headIndent: expectedCodeIndent, allowsListAttribute: false)),
            .init(name: "unordered-list", block: .unorderedList, text: "Bullet", expected: .init(type: .list, font: typography.body, firstLineHeadIndent: expectedListIndent, headIndent: expectedListIndent, allowsListAttribute: true)),
            .init(name: "ordered-list", block: .orderedList, text: "Numbered", expected: .init(type: .list, font: typography.body, firstLineHeadIndent: expectedListIndent, headIndent: expectedListIndent, allowsListAttribute: true))
        ]
    }

    func isSameToolbarControl(_ lhs: CanonicalBlockCase, _ rhs: CanonicalBlockCase) -> Bool {
        if lhs.name == rhs.name { return true }
        return Set([lhs.name, rhs.name]) == Set(["h5", "h6"])
    }

    func prepareEmptyCanonicalLine(_ history: HistoryPath) throws {
        switch history {
        case .clean:
            try resetToEmptyParagraph()
        case .afterBodyEnter:
            try resetToEmptyParagraph()
            typeText("Body")
            typeText("\n")
        case .afterHeadingEnter:
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(.heading(level: .h1))
            typeText("Title")
            typeText("\n")
        case .afterListDoubleEnter:
            try resetToEmptyParagraph()
            typeText("-")
            typeText(" ")
            typeText("Item")
            typeText("\n")
            typeText("\n")
        case .afterPasteEnter:
            try resetToEmptyParagraph()
            let pasteboard = UIPasteboard.withUniqueName()
            pasteboard.string = "# Pasted"
            editor.dispatchCommand(type: .paste, payload: pasteboard)
            typeText("\n")
        case .afterQuoteEnter:
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(.quote)
            typeText("Quote")
            typeText("\n")
        case .afterCodeEnter:
            try editor.update {
                guard let root = getRoot() else {
                    XCTFail("Missing root")
                    return
                }
                for child in root.getChildren() {
                    try child.remove()
                }
                let code = createCodeNode()
                try code.append([createTextNode(text: "code")])
                let paragraph = createParagraphNode()
                let anchor = createTextNode(text: "\u{200B}")
                try paragraph.append([anchor])
                try root.append([code, paragraph])
                let point = Point(key: anchor.key, offset: 0, type: .text)
                try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
            }
            syncNativeSelectionFromLexical()
        }
        assertSelectionAndCaretAreHealthy("prepare \(history)")
    }

    func prepareAfterListExit() throws {
        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph)
        XCTAssertNil(caretListItemAttribute())
    }

    func syncNativeSelectionFromLexical() {
        var nativeRange: NSRange?
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            nativeRange = try? createNativeSelection(from: selection, editor: editor).range
        }
        if let nativeRange {
            markdownEditor.textView.selectedRange = nativeRange
        }
    }

    func typeText(_ text: String) {
        for character in text {
            markdownEditor.textView.insertText(String(character))
        }
    }

    func composeMarkedTextSequence() {
        markdownEditor.textView.setMarkedText("s", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("す", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("すs", selectedRange: NSRange(location: 1, length: 1))
        markdownEditor.textView.setMarkedText("すし", selectedRange: NSRange(location: 0, length: 2))
        markdownEditor.textView.unmarkText()
        markdownEditor.textView.insertText(" ")
        markdownEditor.textView.setMarkedText("m", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("も", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("もじ", selectedRange: NSRange(location: 0, length: 2))
        markdownEditor.textView.unmarkText()
    }

    func deleteCharacters(_ count: Int) {
        for _ in 0..<count {
            markdownEditor.textView.deleteBackward()
        }
    }

    func resetToEmptyParagraph() throws {
        let result = markdownEditor.loadMarkdown(MarkdownDocument(content: ""))
        if case .failure(let error) = result {
            XCTFail("Failed to reset editor: \(error)")
        }
        markdownEditor.textView.layoutIfNeeded()
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func loadInvisibleOnlyParagraph(_ text: String, afterList: Bool) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            if afterList {
                let list = createListNode(listType: .bullet)
                let item = ListItemNode()
                try item.append([createTextNode(text: "Before")])
                try list.append([item])
                try root.append([list])
            }

            let paragraph = createParagraphNode()
            let anchor = createTextNode(text: text)
            try paragraph.append([anchor])
            try root.append([paragraph])

            let point = Point(key: anchor.key, offset: anchor.getTextContentSize(), type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func selectText(_ text: String, offset: Int) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            var target: TextNode?
            func visit(_ node: Node) {
                if target != nil { return }
                if let textNode = node as? TextNode, textNode.getTextContent().contains(text) {
                    target = textNode
                    return
                }
                if let element = node as? ElementNode {
                    element.getChildren().forEach(visit)
                }
            }
            visit(root)

            guard let target else {
                XCTFail("Missing text node containing \(text)")
                return
            }

            let clampedOffset = min(offset, target.getTextContentSize())
            let point = Point(key: target.key, offset: clampedOffset, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        if visibleRange.location != NSNotFound {
            markdownEditor.textView.selectedRange = NSRange(location: visibleRange.location + offset, length: 0)
        }
    }

    func moveNativeCaret(toText text: String, offset: Int) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(text)")
        let clampedOffset = min(max(offset, 0), visibleRange.length)
        markdownEditor.textView.selectedRange = NSRange(location: visibleRange.location + clampedOffset, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func selectNativeVisibleText(_ text: String) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(text)")
        markdownEditor.textView.selectedRange = visibleRange
        try editor.update {
            guard let selection = try? getSelection() as? RangeSelection else {
                XCTFail("Missing range selection for native visible text \(text)")
                return
            }
            try selection.applyNativeSelection(NativeSelection(range: visibleRange, affinity: .forward))
        }
        markdownEditor.textView.layoutIfNeeded()
    }

    enum NativeSelectionPropagation {
        case nativeRangeOnly
        case delegateSelectionChange
        case directLexicalSelection
    }

    func selectNativeVisualLine(
        containing text: String,
        includeTrailingLineBreak: Bool,
        propagation: NativeSelectionPropagation
    ) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        let visibleText = markdownEditor.textView.text as NSString
        let textRange = visibleText.range(of: text)
        XCTAssertNotEqual(textRange.location, NSNotFound, "Missing visible text \(text)")

        var lineStart = textRange.location
        while lineStart > 0 && !isUTF16LineBreak(visibleText.character(at: lineStart - 1)) {
            lineStart -= 1
        }

        var lineEnd = textRange.location + textRange.length
        while lineEnd < visibleText.length && !isUTF16LineBreak(visibleText.character(at: lineEnd)) {
            lineEnd += 1
        }

        if includeTrailingLineBreak && lineEnd < visibleText.length && isUTF16LineBreak(visibleText.character(at: lineEnd)) {
            lineEnd += 1
        }

        let range = NSRange(location: lineStart, length: lineEnd - lineStart)
        markdownEditor.textView.selectedRange = range

        switch propagation {
        case .nativeRangeOnly:
            break
        case .delegateSelectionChange:
            markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        case .directLexicalSelection:
            try editor.update {
                guard let selection = try? getSelection() as? RangeSelection else {
                    XCTFail("Missing range selection for native visual line \(text)")
                    return
                }
                try selection.applyNativeSelection(NativeSelection(range: range, affinity: .forward))
            }
        }
        markdownEditor.textView.layoutIfNeeded()
    }

    func isUTF16LineBreak(_ character: unichar) -> Bool {
        character == 10 || character == 13 || character == 0x2029
    }

    func moveNativeCaretToFirstInvisibleAnchor() throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let anchorRange = (markdownEditor.textView.text as NSString).range(of: "\u{200B}")
        XCTAssertNotEqual(anchorRange.location, NSNotFound, "Missing invisible text anchor")
        markdownEditor.textView.selectedRange = NSRange(location: anchorRange.location, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func nativeReplaceVisibleText(_ text: String, with replacement: String) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let range = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing visible text \(text)")
        let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacement))
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func firstTopLevelType() -> NodeType? {
        var result: NodeType?
        try? editor.read {
            result = getRoot()?.getFirstChild().map { type(of: $0).getType() }
        }
        return result
    }

    func activeRootChildType() -> NodeType? {
        var result: NodeType?
        try? editor.read {
            guard let block = activeRootChild() else { return }
            result = type(of: block).getType()
        }
        return result
    }

    func firstHeadingTag(inActiveBlock: Bool = false) -> HeadingTagType? {
        var result: HeadingTagType?
        try? editor.read {
            let node = inActiveBlock ? activeRootChild() : getRoot()?.getFirstChild()
            result = (node as? HeadingNode)?.getTag()
        }
        return result
    }

    func firstListType() -> ListType? {
        var result: ListType?
        try? editor.read {
            result = (getRoot()?.getFirstChild() as? ListNode)?.getListType()
        }
        return result
    }

    func firstListChildCount() -> Int {
        var result = 0
        try? editor.read {
            result = (getRoot()?.getFirstChild() as? ListNode)?.getChildrenSize() ?? 0
        }
        return result
    }

    func activeListType() -> ListType? {
        var result: ListType?
        try? editor.read {
            result = (activeRootChild() as? ListNode)?.getListType()
        }
        return result
    }

    func activeListChildCount() -> Int {
        var result = 0
        try? editor.read {
            result = (activeRootChild() as? ListNode)?.getChildrenSize() ?? 0
        }
        return result
    }

    func activeListItemRawTextContent() -> String {
        var result = ""
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else { return }
            let item = findMatchingParent(startingNode: anchorNode) { $0 is ListItemNode } as? ListItemNode
            result = item?.getTextContent() ?? ""
        }
        return result
    }

    func isVisibleTextEmpty(_ text: String) -> Bool {
        text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func firstTextContent() -> String {
        var result = ""
        try? editor.read {
            result = normalizedVisibleTextContent(getRoot()?.getFirstChild()?.getTextContent() ?? "")
        }
        return result
    }

    func activeRootChildTextContent() -> String {
        var result = ""
        try? editor.read {
            result = normalizedVisibleTextContent(activeRootChild()?.getTextContent() ?? "")
        }
        return result
    }

    func selectedBlockTextContent() -> String {
        var result = ""
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else {
                result = activeRootChild()?.getTextContent() ?? ""
                return
            }

            let selectedBlock = findMatchingParent(startingNode: anchorNode) { candidate in
                candidate is ListItemNode
                    || candidate is ParagraphNode
                    || candidate is HeadingNode
                    || candidate is QuoteNode
                    || candidate is CodeNode
            } ?? anchorNode

            result = selectedBlock.getTextContent()
        }
        return normalizedVisibleTextContent(result)
    }

    func normalizedVisibleTextContent(_ text: String) -> String {
        let withoutAnchors = text.replacingOccurrences(of: "\u{200B}", with: "")
        if withoutAnchors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return withoutAnchors
    }

    struct EmptyLineRenderSignature {
        let blockType: NodeType?
        let selectionType: SelectionType?
        let textContent: String
        let caretX: CGFloat
        let caretHeight: CGFloat
        let listItemAttribute: Any?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let nativeRange: NSRange
        let debugState: String
    }

    struct CaretGeometry {
        let x: CGFloat
        let height: CGFloat
        let listItemAttribute: Any?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
    }

    struct RenderedLineSignature: Equatable {
        let blockType: NodeType?
        let visibleText: String
        let runs: [RenderedRunSignature]
    }

    struct RenderedDocumentSignature: Equatable {
        let visibleText: String
        let runs: [RenderedRunSignature]
    }

    struct ActiveLineVisualSnapshot: Equatable {
        let blockType: NodeType?
        let selectionType: SelectionType?
        let selectedBlockText: String
        let renderedLine: RenderedLineSignature
        let caretX: CGFloat
        let caretHeight: CGFloat
        let caretMidDeltaFromRenderedLine: CGFloat
        let hasListItemAttribute: Bool
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let typingPointSize: CGFloat
        let typingFirstLineHeadIndent: CGFloat
        let typingHeadIndent: CGFloat
        let typingHasListItemAttribute: Bool
        let textViewPointSize: CGFloat
        let extraLineFragment: AttributeSignature?
        let placeholderVisible: Bool
        let placeholderPointSize: CGFloat
    }

    struct AttributeSignature: Equatable {
        let pointSize: CGFloat
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let hasListItemAttribute: Bool
    }

    struct ActiveLineStructuralSignature: Equatable {
        let blockType: NodeType?
        let headingTag: HeadingTagType?
        let listType: ListType?
        let blockIndent: Int?
        let blockChildTypes: [NodeType]
        let textLeafContents: [String]
        let selectionType: SelectionType?
        let selectionOffset: Int?
        let anchorNodeType: NodeType?
        let anchorParentType: NodeType?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let hasListItemAttribute: Bool
    }

    struct RenderedRunSignature: Equatable {
        let location: Int
        let length: Int
        let fontName: String
        let pointSize: CGFloat
        let isBold: Bool
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let lineSpacing: CGFloat
        let paragraphSpacingBefore: CGFloat
        let paragraphSpacing: CGFloat
        let minimumLineHeight: CGFloat
        let hasListItemAttribute: Bool
        let hasCodeBlockDrawing: Bool
    }

    func emptyLineRenderSignature() -> EmptyLineRenderSignature {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        return EmptyLineRenderSignature(
            blockType: activeRootChildType(),
            selectionType: activeSelectionType(),
            textContent: selectedBlockTextContent(),
            caretX: caret.minX,
            caretHeight: caret.height,
            listItemAttribute: caretListItemAttribute(),
            firstLineHeadIndent: paragraphStyle?.firstLineHeadIndent ?? 0,
            headIndent: paragraphStyle?.headIndent ?? 0,
            nativeRange: markdownEditor.textView.selectedRange,
            debugState: debugSelectionState()
        )
    }

    func caretGeometry() -> CaretGeometry {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        return CaretGeometry(
            x: caret.minX,
            height: caret.height,
            listItemAttribute: caretListItemAttribute(),
            firstLineHeadIndent: paragraphStyle?.firstLineHeadIndent ?? 0,
            headIndent: paragraphStyle?.headIndent ?? 0
        )
    }

    func activeLineVisualSnapshot() -> ActiveLineVisualSnapshot {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        let typingAttributes = markdownEditor.textView.typingAttributes
        let typingParagraphStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let typingFont = typingAttributes[.font] as? UIFont
        let extraLineFragmentAttributes = (markdownEditor.textView.textStorage as? TextStorage)?.extraLineFragmentAttributes
        return ActiveLineVisualSnapshot(
            blockType: activeRootChildType(),
            selectionType: activeSelectionType(),
            selectedBlockText: selectedBlockTextContent(),
            renderedLine: renderedLineSignature(),
            caretX: rounded(caret.minX),
            caretHeight: rounded(caret.height),
            caretMidDeltaFromRenderedLine: rounded(caret.midY - renderedLineMidYAtCaret()),
            hasListItemAttribute: caretListItemAttribute() != nil,
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            typingPointSize: rounded(typingFont?.pointSize ?? 0),
            typingFirstLineHeadIndent: rounded(typingParagraphStyle?.firstLineHeadIndent ?? 0),
            typingHeadIndent: rounded(typingParagraphStyle?.headIndent ?? 0),
            typingHasListItemAttribute: typingAttributes[.listItem] != nil,
            textViewPointSize: rounded(markdownEditor.textView.font?.pointSize ?? 0),
            extraLineFragment: extraLineFragmentAttributes.map(attributeSignature),
            placeholderVisible: placeholderLabel()?.isHidden == false,
            placeholderPointSize: rounded(placeholderLabel()?.font.pointSize ?? 0)
        )
    }

    func attributeSignature(_ attributes: [NSAttributedString.Key: Any]) -> AttributeSignature {
        let font = attributes[.font] as? UIFont
        let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        return AttributeSignature(
            pointSize: rounded(font?.pointSize ?? 0),
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            hasListItemAttribute: attributes[.listItem] != nil
        )
    }

    func activeLineStructuralSignature() -> ActiveLineStructuralSignature {
        var blockType: NodeType?
        var headingTag: HeadingTagType?
        var listType: ListType?
        var blockIndent: Int?
        var blockChildTypes: [NodeType] = []
        var textLeafContents: [String] = []
        var selectionType: SelectionType?
        var selectionOffset: Int?
        var anchorNodeType: NodeType?
        var anchorParentType: NodeType?

        try? editor.read {
            let block = activeRootChild()
            blockType = block.map { type(of: $0).getType() }
            headingTag = (block as? HeadingNode)?.getTag()
            listType = (block as? ListNode)?.getListType()
            blockIndent = (block as? ElementNode)?.getIndent()
            blockChildTypes = (block as? ElementNode)?.getChildren().map { type(of: $0).getType() } ?? []

            func collectTextLeaves(_ node: Node?) {
                guard let node else { return }
                if let textNode = node as? TextNode {
                    textLeafContents.append(textNode.getTextContent())
                    return
                }
                guard let element = node as? ElementNode else { return }
                element.getChildren().forEach(collectTextLeaves)
            }
            collectTextLeaves(block)

            if let selection = try? getSelection() as? RangeSelection,
               let anchorNode = try? selection.anchor.getNode() {
                selectionType = selection.anchor.type
                selectionOffset = selection.anchor.offset
                anchorNodeType = type(of: anchorNode).getType()
                anchorParentType = anchorNode.getParent().map { type(of: $0).getType() }
            }
        }

        let paragraphStyle = caretParagraphStyle()
        return ActiveLineStructuralSignature(
            blockType: blockType,
            headingTag: headingTag,
            listType: listType,
            blockIndent: blockIndent,
            blockChildTypes: blockChildTypes,
            textLeafContents: textLeafContents,
            selectionType: selectionType,
            selectionOffset: selectionOffset,
            anchorNodeType: anchorNodeType,
            anchorParentType: anchorParentType,
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            hasListItemAttribute: caretListItemAttribute() != nil
        )
    }

    func renderedLineSignature() -> RenderedLineSignature {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        guard let attributedText = markdownEditor.textView.attributedText,
              attributedText.length > 0 else {
            return RenderedLineSignature(blockType: activeRootChildType(), visibleText: "", runs: [])
        }

        let text = attributedText.string as NSString
        let selectedLocation = min(max(0, markdownEditor.textView.selectedRange.location), attributedText.length - 1)
        let lineRange = text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        let clampedRange = NSRange(
            location: min(lineRange.location, attributedText.length),
            length: max(0, min(lineRange.upperBound, attributedText.length) - min(lineRange.location, attributedText.length))
        )

        let visibleText = attributedText.attributedSubstring(from: clampedRange).string
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\n", with: "")

        var runs: [RenderedRunSignature] = []
        attributedText.enumerateAttributes(in: clampedRange) { attrs, range, _ in
            let font = attrs[.font] as? UIFont
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let relativeLocation = range.location - clampedRange.location
            let rawRunText = attributedText.attributedSubstring(from: range).string
            let visibleLength = (rawRunText
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\n", with: "") as NSString).length

            runs.append(RenderedRunSignature(
                location: relativeLocation,
                length: visibleLength,
                fontName: font?.fontName ?? "",
                pointSize: rounded(font?.pointSize ?? 0),
                isBold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
                headIndent: rounded(paragraphStyle?.headIndent ?? 0),
                lineSpacing: rounded(paragraphStyle?.lineSpacing ?? 0),
                paragraphSpacingBefore: rounded(paragraphStyle?.paragraphSpacingBefore ?? 0),
                paragraphSpacing: rounded(paragraphStyle?.paragraphSpacing ?? 0),
                minimumLineHeight: rounded(paragraphStyle?.minimumLineHeight ?? 0),
                hasListItemAttribute: attrs[.listItem] != nil,
                hasCodeBlockDrawing: attrs[.codeBlockCustomDrawing] != nil
            ))
        }

        return RenderedLineSignature(
            blockType: activeRootChildType(),
            visibleText: visibleText,
            runs: runs.filter { $0.length > 0 || visibleText.isEmpty }
        )
    }

    func renderedDocumentSignature() -> RenderedDocumentSignature {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        guard let attributedText = markdownEditor.textView.attributedText,
              attributedText.length > 0 else {
            return RenderedDocumentSignature(visibleText: "", runs: [])
        }

        let visibleText = attributedText.string.replacingOccurrences(of: "\u{200B}", with: "")
        var runs: [RenderedRunSignature] = []
        var visibleLocation = 0

        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length)) { attrs, range, _ in
            let font = attrs[.font] as? UIFont
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let runText = attributedText.attributedSubstring(from: range).string
            let visibleLength = (runText.replacingOccurrences(of: "\u{200B}", with: "") as NSString).length

            if visibleLength > 0 || visibleText.isEmpty {
                runs.append(RenderedRunSignature(
                    location: visibleLocation,
                    length: visibleLength,
                    fontName: font?.fontName ?? "",
                    pointSize: rounded(font?.pointSize ?? 0),
                    isBold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                    firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
                    headIndent: rounded(paragraphStyle?.headIndent ?? 0),
                    lineSpacing: rounded(paragraphStyle?.lineSpacing ?? 0),
                    paragraphSpacingBefore: rounded(paragraphStyle?.paragraphSpacingBefore ?? 0),
                    paragraphSpacing: rounded(paragraphStyle?.paragraphSpacing ?? 0),
                    minimumLineHeight: rounded(paragraphStyle?.minimumLineHeight ?? 0),
                    hasListItemAttribute: attrs[.listItem] != nil,
                    hasCodeBlockDrawing: attrs[.codeBlockCustomDrawing] != nil
                ))
            }

            visibleLocation += visibleLength
        }

        return RenderedDocumentSignature(visibleText: visibleText, runs: runs)
    }

    func rounded(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100
    }

    func populatedHeadingOffsets(for text: String) -> [Int] {
        let length = (text as NSString).length
        return Array(Set([0, 1, length / 2, length])).sorted()
    }

    func headingTag(for blockType: MarkdownBlockType) -> HeadingTagType? {
        guard case .heading(let level) = blockType else { return nil }
        return level.lexicalType
    }

    func selectActiveTextOffset(_ offset: Int) throws {
        try editor.update {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else {
                XCTFail("Missing active selection")
                return
            }

            let textNode: TextNode? = {
                if let text = anchorNode as? TextNode {
                    return text
                }
                if let element = anchorNode as? ElementNode {
                    return element.getChildren().compactMap { $0 as? TextNode }.first
                }
                return nil
            }()

            guard let textNode else {
                XCTFail("Missing active text node")
                return
            }

            let clampedOffset = min(max(offset, 0), textNode.getTextContentSize())
            let point = Point(key: textNode.key, offset: clampedOffset, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: selection.format))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func selectFirstEmptyHeading(tag: HeadingTagType) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            let heading = root.getChildren().compactMap { $0 as? HeadingNode }.first { heading in
                heading.getTag() == tag && normalizedVisibleTextContent(heading.getTextContent()).isEmpty
            }

            guard let heading else {
                XCTFail("Missing empty heading \(tag)")
                return
            }

            let point = Point(key: heading.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func loadEmptyHeadingFixture(tag: HeadingTagType, context: String) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let heading = createHeadingNode(headingTag: tag)
            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let listBefore = createListNode(listType: .bullet)
            let itemBefore = ListItemNode()
            try itemBefore.append([createTextNode(text: "before")])
            try listBefore.append([itemBefore])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "top-before-paragraph":
                try root.append([heading, trailing])
            case "after-paragraph":
                try root.append([intro, heading])
            case "between-paragraphs":
                try root.append([intro, heading, trailing])
            case "after-unordered-list":
                try root.append([listBefore, heading])
            case "between-lists":
                try root.append([listBefore, heading, listAfter])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: heading.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func loadPopulatedHeadingFixture(tag: HeadingTagType, text: String, context: String) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let heading = createHeadingNode(headingTag: tag)
            let headingText = createTextNode(text: text)
            try heading.append([headingText])

            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let quote = createQuoteNode()
            try quote.append([createTextNode(text: "Quoted context")])
            let code = createCodeNode()
            try code.append([createTextNode(text: "code_context()")])
            let unorderedList = createListNode(listType: .bullet)
            let unorderedItem = ListItemNode()
            try unorderedItem.append([createTextNode(text: "before")])
            try unorderedList.append([unorderedItem])
            let orderedList = createListNode(listType: .number)
            let orderedItem = ListItemNode()
            try orderedItem.append([createTextNode(text: "before")])
            try orderedList.append([orderedItem])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "top-before-paragraph":
                try root.append([heading, trailing])
            case "after-paragraph":
                try root.append([intro, heading])
            case "between-paragraphs":
                try root.append([intro, heading, trailing])
            case "after-unordered-list":
                try root.append([unorderedList, heading])
            case "after-ordered-list":
                try root.append([orderedList, heading])
            case "between-lists":
                try root.append([unorderedList, heading, listAfter])
            case "after-quote":
                try root.append([quote, heading])
            case "after-code":
                try root.append([code, heading])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: headingText.key, offset: 0, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        editor.dispatchCommand(type: .updatePlaceholderVisibility)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func loadEmptyBlockFixture(
        blockCase: CanonicalBlockCase,
        context: String,
        anchorMode: EmptyBlockAnchorMode
    ) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let target = try makeEmptyElement(for: blockCase.block)
            switch anchorMode {
            case .noChildren:
                break
            case .invisibleTextAnchor:
                try target.append([createTextNode(text: "\u{200B}")])
            }

            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let listBefore = createListNode(listType: .bullet)
            let itemBefore = ListItemNode()
            try itemBefore.append([createTextNode(text: "before")])
            try listBefore.append([itemBefore])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "after-paragraph":
                try root.append([intro, target])
            case "after-unordered-list":
                try root.append([listBefore, target])
            case "between-paragraphs":
                try root.append([intro, target, trailing])
            case "between-lists":
                try root.append([listBefore, target, listAfter])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: target.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    func makeEmptyElement(for blockType: MarkdownBlockType) throws -> ElementNode {
        switch blockType {
        case .paragraph:
            return createParagraphNode()
        case .heading(let level):
            return createHeadingNode(headingTag: level.lexicalType)
        case .quote:
            return createQuoteNode()
        case .codeBlock:
            return createCodeNode()
        case .unorderedList, .orderedList:
            // Callers must filter list cases out and drive list coverage through
            // the list suites; reaching this is a test bug, not a skippable state.
            XCTFail("List blocks cannot host empty-text-block fixtures")
            throw LexicalError.invariantViolation("makeEmptyElement does not support list blocks")
        }
    }

    func assertCanonicalSignature(
        _ signature: EmptyLineRenderSignature,
        matches expected: ExpectedCaretContract,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(signature.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(signature.selectionType, .text, context, file: file, line: line)
        XCTAssertEqual(signature.textContent, "", context, file: file, line: line)
        XCTAssertEqual(signature.caretHeight, expected.font.lineHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(signature.firstLineHeadIndent, expected.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.headIndent, expected.headIndent, accuracy: 0.5, context, file: file, line: line)
        if expected.allowsListAttribute {
            XCTAssertNotNil(signature.listItemAttribute, context, file: file, line: line)
        } else {
            XCTAssertNil(signature.listItemAttribute, context, file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(signature.caretX, -1, context, file: file, line: line)
    }

    func assertCanonicalVisualSnapshot(
        _ snapshot: ActiveLineVisualSnapshot,
        matches expected: ExpectedCaretContract,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, .text, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectedBlockText, "", context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine.visibleText, "", context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, rounded(expected.font.lineHeight), accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
        if let extraLineFragment = snapshot.extraLineFragment {
            XCTAssertEqual(extraLineFragment.pointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.firstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.headIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.hasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        }
    }

    func assertActiveLineSnapshot(
        _ snapshot: ActiveLineVisualSnapshot,
        matches reference: ActiveLineVisualSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectedBlockText, reference.selectedBlockText, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine, reference.renderedLine, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretX, reference.caretX, accuracy: 1.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, reference.caretHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, reference.caretMidDeltaFromRenderedLine, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, reference.typingPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, reference.typingFirstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, reference.typingHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, reference.typingHasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, reference.textViewPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.extraLineFragment, reference.extraLineFragment, context, file: file, line: line)
    }

    func assertActiveLineRendering(
        _ snapshot: ActiveLineVisualSnapshot,
        matches reference: ActiveLineVisualSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine, reference.renderedLine, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretX, reference.caretX, accuracy: 1.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, reference.caretHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, reference.caretMidDeltaFromRenderedLine, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, reference.typingPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, reference.typingFirstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, reference.typingHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, reference.typingHasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, reference.textViewPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.extraLineFragment, reference.extraLineFragment, context, file: file, line: line)
        XCTAssertEqual(snapshot.placeholderVisible, reference.placeholderVisible, context, file: file, line: line)
    }

    func assertActiveListItemStructurallyMatchesReference(
        _ signature: ActiveLineStructuralSignature,
        _ reference: ActiveLineStructuralSignature,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(signature.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(signature.listType, reference.listType, context, file: file, line: line)
        XCTAssertEqual(signature.textLeafContents.last, reference.textLeafContents.last, context, file: file, line: line)
        XCTAssertEqual(signature.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(signature.selectionOffset, reference.selectionOffset, context, file: file, line: line)
        XCTAssertEqual(signature.anchorNodeType, reference.anchorNodeType, context, file: file, line: line)
        XCTAssertEqual(signature.anchorParentType, reference.anchorParentType, context, file: file, line: line)
        XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
    }

    func assertCaretIsVerticallyBalancedInRenderedLine(
        expectedFont: UIFont,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let caret = currentCaretRect()
        let textView = markdownEditor.textView
        let attributedText = textView.attributedText ?? NSAttributedString()
        if attributedText.length > 0 {
            let location = caretAttributeLocation(
                in: attributedText.string as NSString,
                selectedLocation: textView.selectedRange.location
            )
            let actualFont = attributedText.attribute(.font, at: location, effectiveRange: nil) as? UIFont
            XCTAssertEqual(actualFont?.pointSize ?? 0, expectedFont.pointSize, accuracy: 0.5, context, file: file, line: line)
        }

        let expectedMidY = renderedLineMidYAtCaret(file: file, line: line)
        XCTAssertEqual(caret.height, expectedFont.lineHeight, accuracy: 1.0, context, file: file, line: line)
        if let oracle = validSystemCaretRectOracle(),
           abs(oracle.midY - expectedMidY) <= 1,
           oracle.height <= expectedFont.lineHeight + 3 {
            XCTAssertEqual(caret.midY, oracle.midY, accuracy: 0.5, context, file: file, line: line)
        } else {
            XCTAssertEqual(caret.midY, expectedMidY, accuracy: 1.0, context, file: file, line: line)
        }
    }

    func validSystemCaretRectOracle(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText else {
            XCTFail("Missing attributed text", file: file, line: line)
            return nil
        }

        let oracle = UITextView(frame: textView.frame)
        oracle.isScrollEnabled = textView.isScrollEnabled
        oracle.textContainerInset = textView.textContainerInset
        oracle.textContainer.lineFragmentPadding = textView.textContainer.lineFragmentPadding
        oracle.attributedText = attributedText
        oracle.selectedRange = textView.selectedRange
        oracle.layoutIfNeeded()

        guard let selectedTextRange = oracle.selectedTextRange else {
            XCTFail("Missing oracle selected text range", file: file, line: line)
            return nil
        }

        let caret = oracle.caretRect(for: selectedTextRange.start)
        guard caret.height > 4,
              caret.midY >= textView.textContainerInset.top - 1,
              caret.maxY <= textView.bounds.height
        else {
            return nil
        }
        return caret
    }

    func renderedLineMidYAtCaret(file: StaticString = #filePath, line: UInt = #line) -> CGFloat {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else {
            XCTFail("Missing attributed text", file: file, line: line)
            return 0
        }

        let text = attributedText.string as NSString
        let selectedLocation = textView.selectedRange.location
        let characterLocation: Int
        if selectedLocation < text.length {
            let location = max(selectedLocation, 0)
            if selectedLocation > 0, isLineBoundary(text.character(at: location)) {
                characterLocation = selectedLocation - 1
            } else {
                characterLocation = location
            }
        } else {
            characterLocation = text.length - 1
        }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: characterLocation)
        guard glyphIndex < textView.layoutManager.numberOfGlyphs else {
            XCTFail("Missing glyph at caret", file: file, line: line)
            return 0
        }

        let usedRect = textView.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if !usedRect.isEmpty {
            // Centre on the visual glyph line (top of used rect + half the
            // font's lineHeight). TextKit extends the used rect downward by
            // lineSpacing as bottom padding, so usedRect.midY sits below the
            // rendered cap-height centre — keep the oracle aligned with the
            // engine's caret formula.
            let font = attributedText.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont
            let lineHeight = font?.lineHeight ?? usedRect.height
            return textView.textContainerInset.top + usedRect.minY + lineHeight / 2
        }

        return textView.textContainerInset.top + logicalLineMidY(
            at: textView.selectedRange.location,
            characterLocation: characterLocation,
            attributedText: attributedText
        )
    }

    func logicalLineMidY(
        at selectedLocation: Int,
        characterLocation: Int,
        attributedText: NSAttributedString
    ) -> CGFloat {
        let text = attributedText.string as NSString
        let targetLineStart = lineStartLocation(containing: selectedLocation, text: text)
        var lineStart = 0
        var y: CGFloat = 0

        while lineStart < targetLineStart {
            let lineEnd = nextLineBoundary(startingAt: lineStart, text: text)
            y += lineAdvance(at: max(lineStart, min(lineEnd, text.length - 1)), attributedText: attributedText)
            lineStart = min(lineEnd + 1, text.length)
        }

        if targetLineStart > 0 {
            let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
            y += paragraphStyle?.paragraphSpacingBefore ?? 0
        }

        return y + lineHeight(at: characterLocation, attributedText: attributedText) / 2
    }

    func lineStartLocation(containing selectedLocation: Int, text: NSString) -> Int {
        guard selectedLocation > 0 else { return 0 }
        var location = min(selectedLocation, text.length)
        while location > 0 {
            if isLineBoundary(text.character(at: location - 1)) {
                return location
            }
            location -= 1
        }
        return 0
    }

    func nextLineBoundary(startingAt startLocation: Int, text: NSString) -> Int {
        var location = max(startLocation, 0)
        while location < text.length {
            if isLineBoundary(text.character(at: location)) {
                return location
            }
            location += 1
        }
        return text.length
    }

    func lineAdvance(at characterLocation: Int, attributedText: NSAttributedString) -> CGFloat {
        let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
        return lineHeight(at: characterLocation, attributedText: attributedText)
            + (paragraphStyle?.lineSpacing ?? 0)
            + (paragraphStyle?.paragraphSpacing ?? 0)
    }

    func lineHeight(at characterLocation: Int, attributedText: NSAttributedString) -> CGFloat {
        let font = attributedText.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont
        let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
        return max(font?.lineHeight ?? 0, paragraphStyle?.minimumLineHeight ?? 0)
    }

    func renderedVisualLineCountForSelectedParagraph() -> Int {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return 0 }

        let text = attributedText.string as NSString
        let location = min(max(textView.selectedRange.location, 0), max(text.length - 1, 0))
        let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: 0))
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: paragraphRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return 0 }

        var lineCount = 0
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }
            lineCount += 1
            glyphIndex = effectiveRange.upperBound
        }

        return lineCount
    }

    func renderedVisualLineCount(forText targetText: String) -> Int {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return 0 }

        let text = attributedText.string as NSString
        let targetRange = text.range(of: targetText)
        guard targetRange.location != NSNotFound else { return 0 }

        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: targetRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return 0 }

        var lineCount = 0
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }
            lineCount += 1
            glyphIndex = min(effectiveRange.upperBound, maxGlyph)
        }

        return lineCount
    }

    func visualLineBoundaryOffsets(forText targetText: String) -> [Int] {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else {
            XCTFail("Missing attributed text")
            return []
        }

        let text = attributedText.string as NSString
        let targetRange = text.range(of: targetText)
        guard targetRange.location != NSNotFound else {
            XCTFail("Missing target text \(targetText)")
            return []
        }

        let paragraphRange = text.paragraphRange(for: NSRange(location: targetRange.location, length: 0))
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: paragraphRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return [] }

        var offsets = Set<Int>()
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }

            let characterRange = textView.layoutManager.characterRange(
                forGlyphRange: effectiveRange,
                actualGlyphRange: nil
            )
            let start = max(characterRange.location, targetRange.location)
            let end = min(characterRange.upperBound, targetRange.upperBound)
            if start <= end {
                offsets.insert(min(max(start - targetRange.location, 0), targetRange.length))
                offsets.insert(min(max(end - targetRange.location, 0), targetRange.length))
            }

            glyphIndex = effectiveRange.upperBound
        }

        return offsets.sorted()
    }

    func isLineBoundary(_ character: unichar) -> Bool {
        character == 0x000A || character == 0x2028 || character == 0x2029
    }

    func currentCaretRect() -> CGRect {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: selectedTextRange.start)
    }

    func rawCaretRect() -> CGRect {
        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: selectedTextRange.start)
    }

    func placeholderLabel() -> UILabel? {
        markdownEditor.textView.subviews.compactMap { $0 as? UILabel }.first
    }

    func assertVisiblePlaceholderFont(
        _ font: UIFont,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = placeholderLabel()
        XCTAssertEqual(label?.text, "Write something", context, file: file, line: line)
        XCTAssertEqual(label?.isHidden, false, context, file: file, line: line)
        XCTAssertEqual(label?.font.pointSize ?? 0, font.pointSize, accuracy: 0.5, context, file: file, line: line)
    }

    func caretListItemAttribute() -> Any? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return nil }
        let location = min(max(0, textView.selectedRange.location), attributedText.length - 1)
        return attributedText.attribute(.listItem, at: location, effectiveRange: nil)
    }

    func caretParagraphStyle() -> NSParagraphStyle? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return nil }
        let location = min(max(0, textView.selectedRange.location), attributedText.length - 1)
        return attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    func caretAttributeLocation(in text: NSString, selectedLocation: Int) -> Int {
        guard text.length > 0 else { return 0 }
        if selectedLocation < text.length {
            let location = max(selectedLocation, 0)
            if selectedLocation > 0, isLineBoundary(text.character(at: location)) {
                return selectedLocation - 1
            }
            return location
        }
        return text.length - 1
    }

    func visibleDocumentText() -> String {
        var result = ""
        try? editor.read {
            result = getRoot()?.getTextContent()
                .replacingOccurrences(of: "\u{200B}", with: "") ?? ""
        }
        return result
    }

    func activeSelectionType() -> SelectionType? {
        var result: SelectionType?
        try? editor.read {
            result = (try? getSelection() as? RangeSelection)?.anchor.type
        }
        return result
    }

    func debugSelectionState() -> String {
        var result = ""
        try? editor.read {
            let rootChildren = getRoot()?.getChildren().map { type(of: $0).getType().rawValue } ?? []
            guard let selection = try? getSelection() as? RangeSelection,
                  let node = try? selection.anchor.getNode() else {
                result = "root=\(rootChildren) selection=nil"
                return
            }
            let parentType = node.getParent().map { type(of: $0).getType().rawValue } ?? "nil"
            let nodeType = type(of: node).getType().rawValue
            let childrenSize = (node as? ElementNode)?.getChildrenSize() ?? -1
            let text = node.getTextContent().debugDescription
            result = "root=\(rootChildren) anchor=(type:\(selection.anchor.type), offset:\(selection.anchor.offset), node:\(nodeType), parent:\(parentType), children:\(childrenSize), text:\(text)) native=\(markdownEditor.textView.selectedRange)"
        }
        return result
    }

    func activeRootChild() -> Node? {
        guard let selection = try? getSelection() as? RangeSelection,
              let anchorNode = try? selection.anchor.getNode() else {
            return getRoot()?.getFirstChild()
        }

        if anchorNode is RootNode {
            return getRoot()?.getChildAtIndex(index: selection.anchor.offset)
        }

        return findMatchingParent(startingNode: anchorNode) { candidate in
            candidate.getParent() is RootNode
        } ?? anchorNode
    }

    func inspectDocument() -> (topLevelTypes: Set<NodeType>, inlineTraits: Set<String>) {
        var topLevelTypes = Set<NodeType>()
        var inlineTraits = Set<String>()

        try? editor.read {
            guard let root = getRoot() else { return }
            topLevelTypes = Set(root.getChildren().map { type(of: $0).getType() })

            func visit(_ node: Node) {
                if let text = node as? TextNode {
                    if text.getFormat().bold { inlineTraits.insert("bold") }
                    if text.getFormat().italic { inlineTraits.insert("italic") }
                    if text.getFormat().code { inlineTraits.insert("code") }
                    if text.getFormat().strikethrough { inlineTraits.insert("strike") }
                }
                if node is LinkNode {
                    inlineTraits.insert("link")
                }
                if let element = node as? ElementNode {
                    element.getChildren().forEach(visit)
                }
            }
            visit(root)
        }

        return (topLevelTypes, inlineTraits)
    }

    func assertSelectionAndCaretAreHealthy(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        var hasCollapsedSelection = false
        try? editor.read {
            if let selection = try? getSelection() as? RangeSelection {
                hasCollapsedSelection = selection.isCollapsed()
            }
        }
        XCTAssertTrue(hasCollapsedSelection, "Lexical selection should stay collapsed: \(context)", file: file, line: line)

        XCTAssertEqual(markdownEditor.textView.selectedRange.length, 0, "Native selection should stay collapsed: \(context)", file: file, line: line)

        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else {
            return XCTFail("Missing native selectedTextRange: \(context)", file: file, line: line)
        }

        let caret = markdownEditor.textView.caretRect(for: selectedTextRange.start)
        XCTAssertFalse(caret.isNull, "Caret should not be null: \(context)", file: file, line: line)
        XCTAssertTrue(caret.origin.x.isFinite, "Caret x should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.origin.y.isFinite, "Caret y should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.size.width.isFinite, "Caret width should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.size.height.isFinite, "Caret height should be finite: \(context)", file: file, line: line)
        XCTAssertGreaterThan(caret.height, 4, "Caret should have visible height: \(context)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minX, -1, "Caret should stay inside left editor bounds: \(context)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minY, -1, "Caret should stay inside top editor bounds: \(context)", file: file, line: line)
        assertTypingAttributesMatchCaretAttributes(context, file: file, line: line)
    }

    func assertTypingAttributesMatchCaretAttributes(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return }

        let location = caretAttributeLocation(
            in: attributedText.string as NSString,
            selectedLocation: textView.selectedRange.location
        )
        let caretAttributes = attributedText.attributes(at: location, effectiveRange: nil)
        let typingAttributes = textView.typingAttributes

        let caretFont = caretAttributes[.font] as? UIFont
        let typingFont = typingAttributes[.font] as? UIFont
        XCTAssertEqual(typingFont?.pointSize ?? 0, caretFont?.pointSize ?? 0, accuracy: 0.5, "Typing font should match caret font: \(context)", file: file, line: line)

        let caretStyle = caretAttributes[.paragraphStyle] as? NSParagraphStyle
        let typingStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(typingStyle?.firstLineHeadIndent ?? 0, caretStyle?.firstLineHeadIndent ?? 0, accuracy: 0.5, "Typing firstLineHeadIndent should match caret: \(context)", file: file, line: line)
        XCTAssertEqual(typingStyle?.headIndent ?? 0, caretStyle?.headIndent ?? 0, accuracy: 0.5, "Typing headIndent should match caret: \(context)", file: file, line: line)
        XCTAssertEqual(typingAttributes[.listItem] != nil, caretAttributes[.listItem] != nil, "Typing list item attribute should match caret: \(context)", file: file, line: line)
    }
    func applyEmptyBlockTransition(_ blockCase: CanonicalBlockCase) {
        markdownEditor.setBlockType(blockCase.block)
        typeText(blockCase.text)
        deleteCharacters(blockCase.text.utf16.count)
    }
}

final class LayoutCaretSampler: NSObject, NSLayoutManagerDelegate {
    struct Sample: CustomStringConvertible {
        let selectedRange: NSRange
        let caret: CGRect
        let textContainsNewLine: Bool

        var description: String {
            "range=\(NSStringFromRange(selectedRange)) caret=\(caret) hasNewline=\(textContainsNewLine)"
        }
    }

    weak var textView: UITextView?
    private(set) var samples: [Sample] = []

    init(textView: UITextView) {
        self.textView = textView
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinishedFlag: Bool
    ) {
        guard let textView,
              let selectedTextRange = textView.selectedTextRange else { return }

        samples.append(Sample(
            selectedRange: textView.selectedRange,
            caret: textView.caretRect(for: selectedTextRange.start),
            textContainsNewLine: textView.text.contains("\n")
        ))
    }
}

final class TextStorageCaretSampler: NSObject, NSTextStorageDelegate {
    struct Sample: CustomStringConvertible {
        let selectedRange: NSRange
        let caret: CGRect
        let textContainsInsertedNewline: Bool
        let editedRange: NSRange
        let changeInLength: Int

        var description: String {
            "range=\(NSStringFromRange(selectedRange)) caret=\(caret) edited=\(NSStringFromRange(editedRange)) delta=\(changeInLength) hasInsertedNewline=\(textContainsInsertedNewline)"
        }
    }

    weak var textView: UITextView?
    private(set) var samples: [Sample] = []

    init(textView: UITextView, previousLineMaxY: CGFloat) {
        self.textView = textView
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters),
              let textView,
              let selectedTextRange = textView.selectedTextRange
        else { return }

        let text = textStorage.string as NSString
        let insertedNewlineRange = NSRange(location: max(0, editedRange.location), length: max(0, delta))
        let textContainsInsertedNewline = insertedNewlineRange.length > 0
            && insertedNewlineRange.upperBound <= text.length
            && text.substring(with: insertedNewlineRange).contains("\n")

        let caret = textView.caretRect(for: selectedTextRange.start)
        samples.append(Sample(
            selectedRange: textView.selectedRange,
            caret: caret,
            textContainsInsertedNewline: textContainsInsertedNewline,
            editedRange: editedRange,
            changeInLength: delta
        ))
    }
}
