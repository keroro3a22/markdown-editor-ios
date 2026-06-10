/*
 * MarkdownLexicalBridge
 *
 * Thin Lexical-facing service backing MarkdownEditorContentView's formatting,
 * block-type, smart-backspace, state-read, and export operations. State is
 * always read live from the editor's selection; the only full-document
 * serialization lives in exportDocument() (memoized by the view's export cache).
 */

import Foundation
import Lexical
import LexicalMarkdown
import LexicalListPlugin

final class MarkdownLexicalBridge {

    private weak var editor: Editor?
    private let logger: MarkdownCommandLogger?

    init(logger: MarkdownCommandLogger? = nil) {
        self.logger = logger
    }

    func connect(to editor: Editor) {
        self.editor = editor
    }

    // MARK: - State Reads (selection-scoped; no document serialization)

    func currentBlockType() -> MarkdownBlockType {
        guard let editor else { return .paragraph }
        var blockType: MarkdownBlockType = .paragraph
        try? editor.read {
            blockType = Self.blockTypeAtSelection()
        }
        return blockType
    }

    func currentFormatting() -> InlineFormatting {
        guard let editor else { return [] }
        var formatting: InlineFormatting = []
        try? editor.read {
            formatting = Self.formattingAtSelection()
        }
        return formatting
    }

    // MARK: - Formatting

    /// Toggles inline formatting at the current selection, enforcing the
    /// formatting business rules: no inline formatting inside code blocks,
    /// no multi-block formatting, and code is incompatible with
    /// bold/italic/strikethrough (in the request, and against the selection).
    func applyFormatting(_ formatting: InlineFormatting) -> Result<Void, MarkdownEditorError> {
        guard let editor else { return .failure(.editorStateCorrupted) }

        let before = logger?.createSnapshot(from: editor)
        if let before {
            logger?.logOperationStart("Apply Formatting", beforeState: before)
        }
        logger?.logOperationAction("ApplyFormatting(\(formatting))")

        var rejection: String?
        try? editor.read {
            if Self.blockTypeAtSelection() == .codeBlock {
                rejection = "Inline formatting is not supported in code blocks"
                return
            }
            if formatting.contains(.code),
               !formatting.isDisjoint(with: [.bold, .italic, .strikethrough]) {
                rejection = "Code formatting cannot be combined with other formatting"
                return
            }
            if Self.isSelectionMultiBlock() {
                rejection = "Multi-block formatting is not supported"
                return
            }
            let current = Self.formattingAtSelection()
            let exclusive: InlineFormatting = [.bold, .italic, .strikethrough]
            if (current.contains(.code) && !formatting.isDisjoint(with: exclusive))
                || (formatting.contains(.code) && !current.isDisjoint(with: exclusive)) {
                rejection = "Code formatting cannot be combined with other formatting"
            }
        }

        if let rejection {
            logger?.logOperationComplete("Apply Formatting", afterState: nil, success: false)
            return .failure(.unsupportedFeature(rejection))
        }

        if formatting.contains(.bold) {
            editor.dispatchCommand(type: .formatText, payload: TextFormatType.bold)
        }
        if formatting.contains(.italic) {
            editor.dispatchCommand(type: .formatText, payload: TextFormatType.italic)
        }
        if formatting.contains(.strikethrough) {
            editor.dispatchCommand(type: .formatText, payload: TextFormatType.strikethrough)
        }
        if formatting.contains(.code) {
            editor.dispatchCommand(type: .formatText, payload: TextFormatType.code)
        }

        logger?.logOperationComplete("Apply Formatting", afterState: logger?.createSnapshot(from: editor), success: true)
        return .success(())
    }

    // MARK: - Block Type

    /// Sets the block type at the current selection with smart toggling
    /// (re-applying the current list type or heading level toggles back to a
    /// paragraph), preserving the caret position for collapsed selections.
    func setBlockType(_ blockType: MarkdownBlockType) -> Result<Void, MarkdownEditorError> {
        guard let editor else { return .failure(.editorStateCorrupted) }

        let before = logger?.createSnapshot(from: editor)
        if let before {
            logger?.logOperationStart("Toggle Block Type", beforeState: before)
        }
        logger?.logOperationAction("SetBlockType(\(blockType))")

        do {
            try editor.update {
                guard let selection = try? getSelection() as? RangeSelection else { return }

                let currentType = Self.blockTypeAtSelection()

                // Preserve caret position for collapsed selections
                let shouldPreserveCaret = selection.isCollapsed()
                let previousOffset: Int = selection.anchor.offset
                let blockIndex = Self.topLevelBlockIndex(of: selection.anchor)

                // Smart toggle: if applying the same list type again, or same heading level, toggle to paragraph
                let effectiveTarget: MarkdownBlockType = {
                    switch (currentType, blockType) {
                    case (.unorderedList, .unorderedList): return .paragraph
                    case (.orderedList, .orderedList): return .paragraph
                    case (.heading(let cur), .heading(let req)) where cur == req: return .paragraph
                    default: return blockType
                    }
                }()

                switch effectiveTarget {
                case .paragraph:
                    setBlocksType(selection: selection) { createParagraphNode() }
                case .heading(let level):
                    setBlocksType(selection: selection) { createHeadingNode(headingTag: level.lexicalType) }
                case .codeBlock:
                    setBlocksType(selection: selection) { createCodeNode() }
                case .quote:
                    setBlocksType(selection: selection) { createQuoteNode() }
                case .unorderedList:
                    editor.dispatchCommand(type: .insertUnorderedList)
                case .orderedList:
                    editor.dispatchCommand(type: .insertOrderedList)
                }

                // Keep selection anchored in the transformed block so repeated toggles can detect current type.
                if shouldPreserveCaret, let root = getRoot(), root.getChildrenSize() > 0 {
                    let clampedBlockIndex = max(0, min(blockIndex, root.getChildrenSize() - 1))
                    guard let transformedBlock = root.getChildAtIndex(index: clampedBlockIndex) else { return }

                    if let textNode = Self.collectTextNodes(from: transformedBlock).first {
                        let textLength = textNode.getTextContentSize()
                        let clampedOffset = max(0, min(previousOffset, textLength))
                        let anchor = Point(key: textNode.key, offset: clampedOffset, type: .text)
                        let restoredSelection = RangeSelection(anchor: anchor, focus: anchor, format: selection.format)
                        getActiveEditorState()?.selection = restoredSelection
                    } else if let elementNode = transformedBlock as? ElementNode {
                        let anchor = Point(key: elementNode.key, offset: 0, type: .element)
                        let restoredSelection = RangeSelection(anchor: anchor, focus: anchor, format: selection.format)
                        getActiveEditorState()?.selection = restoredSelection
                    }
                }
            }
        } catch {
            logger?.logOperationComplete("Toggle Block Type", afterState: nil, success: false)
            return .failure(.editorStateCorrupted)
        }

        logger?.logOperationComplete("Toggle Block Type", afterState: logger?.createSnapshot(from: editor), success: true)
        return .success(())
    }

    // MARK: - Smart Backspace

    /// Converts an empty list item at the start of its line to a paragraph;
    /// otherwise deletes one character backwards. Returns false only when no
    /// editor is connected or the update throws, so the caller can fall back
    /// to Lexical's default handling.
    func performSmartBackspace() -> Bool {
        guard let editor else { return false }

        let before = logger?.createSnapshot(from: editor)
        if let before {
            logger?.logOperationStart("Smart Backspace", beforeState: before)
        }
        logger?.logOperationAction("SmartBackspace")

        do {
            try editor.update {
                guard let selection = try? getSelection() as? RangeSelection else { return }

                // Determine list item at selection and whether at start
                let anchor = selection.anchor
                let listItem: ListItemNode? = {
                    if anchor.type == .element, let node = try? anchor.getNode() as? ListItemNode {
                        return node
                    } else if let node = try? anchor.getNode() {
                        return Self.findParentListItem(node)
                    }
                    return nil
                }()

                if let listItem {
                    let isAtStart: Bool = {
                        if anchor.type == .element { return selection.isCollapsed() && anchor.offset == 0 }
                        if anchor.type == .text { return selection.isCollapsed() && anchor.offset == 0 }
                        return false
                    }()

                    if listItem.isEffectivelyEmpty() && isAtStart {
                        setBlocksType(selection: selection) { createParagraphNode() }
                        return
                    }
                }

                // Normal backspace behavior
                try? selection.deleteCharacter(isBackwards: true)
            }
        } catch {
            logger?.logOperationComplete("Smart Backspace", afterState: nil, success: false)
            return false
        }

        logger?.logOperationComplete("Smart Backspace", afterState: logger?.createSnapshot(from: editor), success: true)
        return true
    }

    // MARK: - Export

    /// Serializes the full document to markdown. This is the only
    /// full-document serialization path in the bridge.
    func exportDocument() -> Result<MarkdownDocument, MarkdownEditorError> {
        guard let editor else { return .failure(.editorStateCorrupted) }

        do {
            var markdownText = try LexicalMarkdown.generateMarkdown(
                from: editor,
                selection: nil
            )

            // Lexical uses ZWSP internally for stable editing of "empty" blocks (especially list items).
            // Never leak it into exported Markdown.
            markdownText = markdownText.replacingOccurrences(of: emptyTextCaretAnchor, with: "")
            return .success(MarkdownDocument(
                content: markdownText,
                metadata: DocumentMetadata(
                    createdAt: Date(),
                    modifiedAt: Date(),
                    version: "1.0"
                )
            ))
        } catch {
            return .failure(.serializationFailed)
        }
    }

    // MARK: - Selection Inspection (must run inside editor.read/update)

    private static func blockTypeAtSelection() -> MarkdownBlockType {
        guard let selection = try? getSelection() as? RangeSelection,
              let anchorNode = try? selection.anchor.getNode() else {
            return .paragraph
        }

        let element = isRootNode(node: anchorNode) ? anchorNode :
            findMatchingParent(startingNode: anchorNode) { e in
                let parent = e.getParent()
                return parent != nil && isRootNode(node: parent)
            }

        if let heading = element as? HeadingNode {
            switch heading.getTag() {
            case .h1: return .heading(level: .h1)
            case .h2: return .heading(level: .h2)
            case .h3: return .heading(level: .h3)
            case .h4: return .heading(level: .h4)
            case .h5: return .heading(level: .h5)
            }
        } else if element is CodeNode {
            return .codeBlock
        } else if element is QuoteNode {
            return .quote
        } else if let listNode = element as? ListNode {
            return listNode.getListType() == .bullet ? .unorderedList : .orderedList
        } else if element is ListItemNode {
            if let parentList = element?.getParent() as? ListNode {
                return parentList.getListType() == .bullet ? .unorderedList : .orderedList
            }
        }

        return .paragraph
    }

    private static func formattingAtSelection() -> InlineFormatting {
        guard let selection = try? getSelection() as? RangeSelection else {
            return []
        }

        var formatting: InlineFormatting = []
        if selection.hasFormat(type: .bold) { formatting.insert(.bold) }
        if selection.hasFormat(type: .italic) { formatting.insert(.italic) }
        if selection.hasFormat(type: .strikethrough) { formatting.insert(.strikethrough) }
        if selection.hasFormat(type: .code) { formatting.insert(.code) }
        return formatting
    }

    private static func isSelectionMultiBlock() -> Bool {
        guard let selection = try? getSelection() as? RangeSelection,
              !selection.isCollapsed() else {
            return false
        }
        let anchorIndex = topLevelBlockIndex(of: selection.anchor)
        let focusIndex = topLevelBlockIndex(of: selection.focus)
        return anchorIndex != focusIndex
    }

    private static func topLevelBlockIndex(of point: Point) -> Int {
        guard let root = getRoot(),
              let node = try? point.getNode() else {
            return 0
        }

        let topLevel = isRootNode(node: node) ? node :
            findMatchingParent(startingNode: node) { e in
                let parent = e.getParent()
                return parent != nil && isRootNode(node: parent)
            }

        guard let element = topLevel else { return 0 }
        return root.getChildren().firstIndex(where: { $0.key == element.key }) ?? 0
    }

    private static func collectTextNodes(from node: Node) -> [TextNode] {
        if let text = node as? TextNode { return [text] }
        guard let element = node as? ElementNode else { return [] }
        return element.getChildren().flatMap(collectTextNodes(from:))
    }

    private static func findParentListItem(_ node: Node) -> ListItemNode? {
        var current: Node? = node
        while let n = current {
            if let li = n as? ListItemNode { return li }
            current = n.getParent()
        }
        return nil
    }
}
