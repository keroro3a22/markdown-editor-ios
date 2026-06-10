import Foundation
import Lexical
import LexicalListPlugin

// MARK: - List Backspace Fix Plugin

/// A plugin that fixes backspace-at-start list behavior.
///
/// LexicalListPlugin’s default `collapseAtStart` currently inserts the resulting paragraph
/// *before the whole list*, which can make backspace on a middle list item jump the cursor
/// above the list and appear to “create a newline at the top”.
///
/// We intercept backward delete when the caret is at the start of a list item and perform
/// a stable “outdent to paragraph” in-place:
/// - First item: paragraph before the list
/// - Middle item: split the list into two lists with the paragraph between
/// - Last item: paragraph after the list
public class ZeroWidthSpaceFixPlugin: Plugin {
    
    public init() {}
    
    weak var editor: Editor?
    private var removeListItemTransform: (() -> Void)?
    
    public func setUp(editor: Editor) {
        self.editor = editor
        
        // Register a high-priority command handler for deleteCharacter that runs before the default one
        _ = editor.registerCommand(
            type: .deleteCharacter,
            listener: { [weak self] payload in
                guard let isBackwards = payload as? Bool, isBackwards else { return false }
                return self?.handleDeleteCharacterBackwards() ?? false
            },
            priority: .High
        )

        // Ensure list items always contain a text anchor. Deleting the last character from a list item can
        // leave an empty ListItemNode with no children, which causes selection to become element-anchored
        // and can manifest as a "short" / odd-height empty line until another edit normalizes it.
        removeListItemTransform = editor.addNodeTransform(nodeType: NodeType(rawValue: "listitem")) { node in
            guard let listItem = node as? ListItemNode else { return }

            // Avoid touching nested list items; their content model can vary (and LexicalListPlugin handles them).
            if listItem.getParent() is ListItemNode { return }

            // If there's already a nested list child, do not inject ZWSP.
            if listItem.getChildren().first is ListNode { return }

            let children = listItem.getChildren()
            if children.isEmpty {
                let zwsp = createTextNode(text: emptyTextCaretAnchor)
                try? listItem.append([zwsp])

                if let selection = try? getSelection() as? RangeSelection,
                   selection.isCollapsed(),
                   selection.anchor.type == .element,
                   let anchorNode = try? selection.anchor.getNode(),
                   anchorNode.key == listItem.key {
                    let p = Point(key: zwsp.key, offset: 0, type: .text)
                    getActiveEditorState()?.selection = RangeSelection(anchor: p, focus: p, format: TextFormat())
                }
                return
            }

            // If the list item has a single empty TextNode, normalize it to ZWSP to keep it from being pruned.
            if children.count == 1, let text = children[0] as? TextNode, text.getTextContent().isEmpty {
                _ = try? text.setText(emptyTextCaretAnchor)

                if let selection = try? getSelection() as? RangeSelection,
                   selection.isCollapsed(),
                   selection.anchor.type == .text,
                   selection.anchor.key == text.key,
                   selection.anchor.offset == 0 {
                    // Keep selection stable.
                    let p = Point(key: text.key, offset: 0, type: .text)
                    getActiveEditorState()?.selection = RangeSelection(anchor: p, focus: p, format: TextFormat())
                }
            }
        }
    }
    
    public func tearDown() {
        removeListItemTransform?()
        removeListItemTransform = nil
        self.editor = nil
    }
    
    /// Handles backward delete at the start of a list item.
    /// Returns true if handled; false to fall back to Lexical defaults.
    private func handleDeleteCharacterBackwards() -> Bool {
        guard let editor = self.editor else { return false }
        
        do {
            var listItemKeyToFix: NodeKey? = nil
            
            // Detect the start-of-list-item condition in a read transaction.
            try editor.read {
                guard let selection = try getSelection() as? RangeSelection else { return }
                
                // Only handle backward deletion when selection is collapsed
                if !selection.isCollapsed() {
                    return
                }
                
                let anchor = selection.anchor
                guard anchor.offset == 0 else { return }
                guard anchor.type == .element || anchor.type == .text else { return }

                guard let anchorNode = try? anchor.getNode() else { return }
                guard let listItem = (anchorNode as? ListItemNode) ?? findParentListItem(anchorNode) else { return }

                listItemKeyToFix = listItem.key
            }
            
            guard let listItemKeyToFix else { return false }

            try editor.update {
                guard let listItem: ListItemNode = getNodeByKey(key: listItemKeyToFix) else { return }
                guard let listNode = listItem.getParent() as? ListNode else { return }

                // Avoid messing with nested lists for now; defer to Lexical defaults.
                if listNode.getParent() is ListItemNode { return }

                // If the current list item is effectively empty, treat backspace as “remove this item” and
                // move the caret to a sensible neighbor (prefer end of previous item).
                if isEffectivelyEmpty(listItem) {
                    let prev = listItem.getPreviousSibling() as? ListItemNode
                    let next = listItem.getNextSibling() as? ListItemNode

                    try? listItem.remove()

                    if listNode.getChildrenSize() == 0 {
                        // List became empty; replace it with a paragraph to keep the document editable.
                        let paragraph = createParagraphNode()
                        _ = try? listNode.insertBefore(nodeToInsert: paragraph)
                        try? listNode.remove()
                        _ = try? paragraph.selectStart()
                        return
                    }

                    try? updateChildrenListItemValue(list: listNode, children: nil)

                    if let prev {
                        _ = try? prev.selectEnd()
                        return
                    }
                    if let next {
                        _ = try? next.selectStart()
                        return
                    }

                    return
                }

                let listChildren = listNode.getChildren()
                guard let index = listChildren.firstIndex(where: { $0.key == listItem.key }) else { return }

                // Prefer reusing an existing paragraph child to avoid nesting paragraphs.
                let listItemChildren = listItem.getChildren()
                let paragraph: ParagraphNode
                let usesExistingParagraph: Bool
                if listItemChildren.count == 1, let existing = listItemChildren[0] as? ParagraphNode {
                    paragraph = existing
                    usesExistingParagraph = true
                } else {
                    let p = createParagraphNode()
                    try? p.append(listItemChildren)
                    paragraph = p
                    usesExistingParagraph = false
                }

                let afterSiblings = Array(listChildren.dropFirst(index + 1))

                if index == 0 {
                    // First item: paragraph goes before the list.
                    _ = try? listNode.insertBefore(nodeToInsert: paragraph)
                    _ = try? paragraph.selectStart()
                } else {
                    // Middle/last: paragraph goes after the (remaining) first-part list.
                    _ = try? listNode.insertAfter(nodeToInsert: paragraph)
                    _ = try? paragraph.selectStart()
                }

                // Now that the paragraph has been moved out, remove the list item itself.
                // (If we reused an existing paragraph child, removing first would delete it.)
                if usesExistingParagraph {
                    // `paragraph` is no longer a child of `listItem` after insertion above.
                    try? listItem.remove()
                } else {
                    try? listItem.remove()
                }

                // If we had trailing siblings (middle case), move them into a new list after the paragraph.
                if !afterSiblings.isEmpty {
                    let listType = listNode.getListType()
                    let start = listNode.getStart()

                    let newStart: Int = {
                        // Preserve ordinal continuity when splitting ordered lists.
                        // (If original list started at `start`, and we split after `index` items,
                        // the next item’s number is `start + index` after removing the current item.)
                        if listType == .number {
                            return max(1, start + index)
                        }
                        return 1
                    }()

                    let newList = ListNode(listType: listType, start: newStart)
                    try? newList.append(afterSiblings)
                    _ = try? paragraph.insertAfter(nodeToInsert: newList)
                    try? updateChildrenListItemValue(list: newList, children: nil)
                }

                // Clean up empty list and re-number/re-bullet remaining items.
                if listNode.getChildrenSize() == 0 {
                    try? listNode.remove()
                } else {
                    try? updateChildrenListItemValue(list: listNode, children: nil)
                }
            }

            // Keep selection stable.
            editor.dispatchCommand(type: .selectionChange)
            return true
            
        } catch {
            MarkdownLogger.plugin("Error in ZeroWidthSpaceFixPlugin: \(error)")
        }
        
        return false // Let default handler process the command
    }

    private func isEffectivelyEmpty(_ listItem: ListItemNode) -> Bool {
        // Treat items with nested lists as non-empty (defer to Lexical defaults).
        if listItem.getChildren().first is ListNode { return false }
        return listItem.isEffectivelyEmpty()
    }

    private func findParentListItem(_ node: Node) -> ListItemNode? {
        var currentNode: Node? = node
        
        while let node = currentNode {
            if let listItem = node as? ListItemNode {
                return listItem
            }
            currentNode = node.getParent()
        }
        
        return nil
    }
}
