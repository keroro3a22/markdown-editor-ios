/*
 * MarkdownDomainBridge
 * 
 * Critical bridge between domain layer and Lexical.
 * Handles state synchronization, command translation, and business rule enforcement.
 */

import Foundation
import Lexical
import LexicalMarkdown
import LexicalListPlugin
import LexicalLinkPlugin

// MARK: - Domain Bridge

/// Bridges the domain layer with Lexical, enabling testable business logic
public class MarkdownDomainBridge {
    
    // MARK: - Properties
    
    private let stateService: MarkdownStateService
    private let documentService: MarkdownDocumentService
    private let formattingService: MarkdownFormattingService
    public private(set) var currentDomainState: MarkdownEditorState
    private weak var editor: Editor?
    private var logger: MarkdownCommandLogger?
    
    // MARK: - Initialization
    
    public init(
        logger: MarkdownCommandLogger? = nil,
        stateService: MarkdownStateService = DefaultMarkdownStateService(),
        documentService: MarkdownDocumentService = DefaultMarkdownDocumentService(),
        formattingService: MarkdownFormattingService = DefaultMarkdownFormattingService()
    ) {
        self.logger = logger
        self.stateService = stateService
        self.documentService = documentService
        self.formattingService = formattingService
        self.currentDomainState = MarkdownEditorState.empty
    }
    
    /// Connect the bridge to a Lexical editor
    public func connect(to editor: Editor) {
        self.editor = editor
        syncFromLexical()
    }
    
    // MARK: - State Synchronization
    
    /// Synchronize domain state from current Lexical state
    public func syncFromLexical() {
        guard let editor = editor else { return }
        
        do {
            try editor.read {
                self.currentDomainState = self.extractState(from: editor)
            }
        } catch {
            // Log error but don't crash - maintain last known state
            logger?.logSimpleEvent("SYNC_FROM_LEXICAL_ERROR", details: error.localizedDescription)
        }
    }
    
    /// Get current domain state
    public func getCurrentState() -> MarkdownEditorState {
        return currentDomainState
    }
    
    // MARK: - Command Execution
    
    /// Execute a domain command and apply it to Lexical
    public func execute(_ command: MarkdownCommand) -> Result<Void, DomainError> {
        // Capture before state - try to use editor for detailed logging, fallback to domain state
        let beforeSnapshot: MarkdownStateSnapshot? = if let editor = editor, let logger = logger {
            logger.createSnapshot(from: editor) ?? logger.createSnapshot(from: currentDomainState)
        } else if let logger = logger {
            logger.createSnapshot(from: currentDomainState)
        } else {
            nil
        }
        
        if let beforeSnapshot = beforeSnapshot {
            logger?.logCommandStart(command, beforeState: beforeSnapshot)
        }
        
        // First validate against domain rules
        guard command.canExecute(on: currentDomainState) else {
            if let beforeSnapshot = beforeSnapshot {
                logger?.logCommandComplete(command, afterState: beforeSnapshot, success: false)
            }
            return .failure(.commandValidationFailed(String(describing: command)))
        }
        
        logger?.logCommandAction(command)
        
        // Execute in domain to get new state
        let executionResult = command.execute(on: currentDomainState)
        
        switch executionResult {
        case .success(let newState):
            // Apply changes to Lexical
            let applyResult = applyToLexical(command: command, newState: newState)
            
            switch applyResult {
            case .success:
                // Always re-sync from Lexical after applying, to avoid domain↔Lexical drift.
                syncFromLexical()
                
                // Log after state - capture from editor for detailed view
                if let logger = logger {
                    let afterSnapshot = if let editor = editor {
                        logger.createSnapshot(from: editor) ?? logger.createSnapshot(from: currentDomainState)
                    } else {
                        logger.createSnapshot(from: currentDomainState)
                    }
                    
                    logger.logCommandComplete(command, afterState: afterSnapshot, success: true)
                }
                
                return .success(())
            case .failure(let error):
                if let beforeSnapshot = beforeSnapshot {
                    logger?.logCommandComplete(command, afterState: beforeSnapshot, success: false)
                }
                return .failure(error)
            }
            
        case .failure(let error):
            if let beforeSnapshot = beforeSnapshot {
                logger?.logCommandComplete(command, afterState: beforeSnapshot, success: false)
            }
            return .failure(error)
        }
    }
    
    // MARK: - Command Creation
    
    /// Create a formatting command for the given formatting
    public func createFormattingCommand(_ formatting: InlineFormatting) -> MarkdownCommand {
        // Get current selection from domain state
        let selection = currentDomainState.selection
        
        return ApplyFormattingCommand(
            formatting: formatting,
            to: selection,
            operation: .toggle, // Default to toggle for toolbar buttons
            context: MarkdownCommandContext(
                documentService: documentService,
                formattingService: formattingService,
                stateService: stateService
            )
        )
    }
    
    /// Create a block type command for the given block type
    public func createBlockTypeCommand(_ blockType: MarkdownBlockType) -> MarkdownCommand {
        return SetBlockTypeCommand(
            blockType: blockType,
            at: currentDomainState.selection.start,
            context: MarkdownCommandContext(
                documentService: documentService,
                formattingService: formattingService,
                stateService: stateService
            )
        )
    }
    
    /// Create a smart backspace command
    public func createSmartBackspaceCommand() -> MarkdownCommand {
        return SmartBackspaceCommand(
            at: currentDomainState.selection.start,
            context: MarkdownCommandContext(
                documentService: documentService,
                formattingService: formattingService,
                stateService: stateService
            )
        )
    }
    
    // MARK: - Document Operations
    
    /// Parse and prepare a document for loading
    public func parseDocument(_ document: MarkdownDocument) -> Result<ParsedMarkdownDocument, DomainError> {
        let parsed = documentService.parseMarkdown(document.content)
        
        // Validate the parsed document
        let validation = documentService.validateDocument(document.content)
        if !validation.isValid {
            return .failure(.documentValidationFailed(validation.errors.first?.localizedDescription ?? "Unknown error"))
        }
        
        return .success(parsed)
    }
    
    /// Apply a parsed document to Lexical
    public func applyToLexical(_ parsed: ParsedMarkdownDocument, editor: Editor) -> Result<Void, DomainError> {
        do {
            try editor.update {
                // Clear existing content by removing all children
                guard let root = getRoot() else { return }
                let children = root.getChildren()
                for child in children {
                    try? child.remove()
                }
                
                // Add each block, or create a default paragraph if empty
                if parsed.blocks.isEmpty {
                    // Create a default paragraph node for empty documents
                    let defaultParagraph = createParagraphNode()
                    try? root.append([defaultParagraph])
                } else {
                for block in parsed.blocks {
                    let lexicalNode = self.createLexicalNode(from: block)
                    try? root.append([lexicalNode])
                    }
                }
                
                // Establish a default selection to the most relevant insertion point
                if let last = root.getLastChild() {
                    if let list = last as? ListNode, let lastItem = list.getLastChild() as? ListItemNode {
                        let point = Point(key: lastItem.key, offset: 0, type: .element)
                        let selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
                        getActiveEditorState()?.selection = selection
                    } else if let element = last as? ElementNode {
                        let point = Point(key: element.key, offset: element.getChildrenSize(), type: .element)
                        let selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
                        getActiveEditorState()?.selection = selection
                    }
                }
            }
            
            // Sync state after applying
            syncFromLexical()
            return .success(())
            
        } catch {
            return .failure(.editorOperationFailed(error.localizedDescription))
        }
    }
    
    /// Export current state as a document
    public func exportDocument() -> Result<MarkdownDocument, DomainError> {
        guard let editor = editor else {
            return .failure(.editorNotConnected)
        }
        
        do {
            var markdownText = try LexicalMarkdown.generateMarkdown(
                from: editor,
                selection: nil
            )

            // Lexical uses ZWSP internally for stable editing of “empty” blocks (especially list items).
            // Never leak ZWSP into exported Markdown.
            markdownText = markdownText.replacingOccurrences(of: "\u{200B}", with: "")
            let document = MarkdownDocument(
                content: markdownText,
                metadata: DocumentMetadata(
                    createdAt: Date(),
                    modifiedAt: Date(),
                    version: "1.0"
                )
            )
            
            return .success(document)
        } catch {
            return .failure(.serializationFailed(error.localizedDescription))
        }
    }
    
    // MARK: - State Extraction
    
    private func extractState(from editor: Editor) -> MarkdownEditorState {
        // Get selection
        let selection = extractSelection(from: editor)
        
        // Get current block context
        let position = selection.start
        let blockType = detectBlockType(at: position, in: editor)
        
        // Get formatting at cursor
        let formatting = extractFormatting(at: position, in: editor)
        
        // Get document content
        let content = (try? LexicalMarkdown.generateMarkdown(from: editor, selection: nil)) ?? ""
        
        return MarkdownEditorState(
            content: content,
            selection: selection,
            currentFormatting: formatting,
            currentBlockType: blockType,
            hasUnsavedChanges: false,
            metadata: DocumentMetadata()
        )
    }
    
    private func extractSelection(from editor: Editor) -> TextRange {
        guard let lexicalSelection = try? getSelection() as? RangeSelection else {
            return TextRange(at: .start)
        }

        let (startPoint, endPoint) = orderedPoints(for: lexicalSelection)

        // Map Lexical selection to a stable “top-level block index + text offset”.
        // This mapping is best-effort and is only used for domain context/logging/validation.
        let start = mapPointToDocumentPosition(startPoint)
        let end = mapPointToDocumentPosition(endPoint)
        return TextRange(start: start, end: end)
    }

    private func orderedPoints(for selection: RangeSelection) -> (Point, Point) {
        guard (try? selection.isBackward()) == true else {
            return (selection.anchor, selection.focus)
        }
        return (selection.focus, selection.anchor)
    }

    private func mapPointToDocumentPosition(_ point: Point) -> DocumentPosition {
        guard let root = getRoot(),
              let anchorNode = try? point.getNode() else {
            return .start
        }

        // Find the top-level element directly under root (paragraph, heading, list, code, quote, ...)
        let topLevel = isRootNode(node: anchorNode) ? anchorNode :
            findMatchingParent(startingNode: anchorNode) { e in
                let parent = e.getParent()
                return parent != nil && isRootNode(node: parent)
            }

        guard let element = topLevel as? ElementNode else {
            return .start
        }

        let children = root.getChildren()
        let blockIndex = children.firstIndex(where: { $0.key == element.key }) ?? 0

        if point.type == .text, let textNode = try? point.getNode() as? TextNode {
            let absoluteOffset = computeTextOffset(in: element, anchorTextNodeKey: textNode.key, localOffset: point.offset)
            return DocumentPosition(blockIndex: blockIndex, offset: absoluteOffset)
        }

        return DocumentPosition(blockIndex: blockIndex, offset: 0)
    }

    private func computeTextOffset(in element: ElementNode, anchorTextNodeKey: NodeKey, localOffset: Int) -> Int {
        let textNodes = collectTextNodes(from: element)
        var offset = 0
        for node in textNodes {
            if node.key == anchorTextNodeKey {
                return offset + max(0, min(localOffset, node.getTextContentSize()))
            }
            offset += node.getTextContentSize()
        }
        return offset
    }

    private func collectTextNodes(from node: Node) -> [TextNode] {
        if let text = node as? TextNode { return [text] }
        guard let element = node as? ElementNode else { return [] }
        return element.getChildren().flatMap(collectTextNodes(from:))
    }
    
    private func detectBlockType(at position: DocumentPosition, in editor: Editor) -> MarkdownBlockType {
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
            let tagType = heading.getTag()
            let level: MarkdownBlockType.HeadingLevel
            switch tagType {
            case .h1: level = .h1
            case .h2: level = .h2
            case .h3: level = .h3
            case .h4: level = .h4
            case .h5: level = .h5
            }
            return .heading(level: level)
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
    
    private func extractFormatting(at position: DocumentPosition, in editor: Editor) -> InlineFormatting {
        var formatting: InlineFormatting = []
        
        guard let selection = try? getSelection() as? RangeSelection else {
            return formatting
        }
        
        if selection.hasFormat(type: .bold) { formatting.insert(.bold) }
        if selection.hasFormat(type: .italic) { formatting.insert(.italic) }
        if selection.hasFormat(type: .strikethrough) { formatting.insert(.strikethrough) }
        if selection.hasFormat(type: .code) { formatting.insert(.code) }
        
        return formatting
    }
    
    // MARK: - Lexical Application
    
    private func applyToLexical(command: MarkdownCommand, newState: MarkdownEditorState) -> Result<Void, DomainError> {
        guard let editor = editor else {
            return .failure(.editorNotConnected)
        }
        
        do {
            try editor.update {
                // Translate domain command to Lexical operations
                self.translateAndApply(command, to: editor)
            }
            return .success(())
        } catch {
            return .failure(.editorOperationFailed(error.localizedDescription))
        }
    }
    
    private func translateAndApply(_ command: MarkdownCommand, to editor: Editor) {
        switch command {
        case let formatCommand as ApplyFormattingCommand:
            applyFormattingCommand(formatCommand, to: editor)
            
        case let blockCommand as SetBlockTypeCommand:
            applyBlockTypeCommand(blockCommand, to: editor)
            
        case let smartBackspaceCommand as SmartBackspaceCommand:
            applySmartBackspaceCommand(smartBackspaceCommand, to: editor)
            
        default:
            break
        }
    }
    
    private func applyFormattingCommand(_ command: ApplyFormattingCommand, to editor: Editor) {
        let formatting = command.formatting
        
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
    }
    
    private func applyBlockTypeCommand(_ command: SetBlockTypeCommand, to editor: Editor) {
        guard let selection = try? getSelection() as? RangeSelection else { return }
        
        // Determine current block type at selection
        let currentType = extractCurrentBlockType(from: editor)
        
        // Preserve caret position for collapsed selections
        let shouldPreserveCaret = selection.isCollapsed()
        let previousAnchorPoint = selection.anchor
        let previousOffset: Int = previousAnchorPoint.offset
        
        // Smart toggle: if applying the same list type again, or same heading level, toggle to paragraph
        let effectiveTarget: MarkdownBlockType = {
            switch (currentType, command.blockType) {
            case (.unorderedList, .unorderedList): return .paragraph
            case (.orderedList, .orderedList): return .paragraph
            case (.heading(let cur), .heading(let req)) where cur == req: return .paragraph
            default: return command.blockType
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
            let clampedBlockIndex = max(0, min(command.position.blockIndex, root.getChildrenSize() - 1))
            guard let transformedBlock = root.getChildAtIndex(index: clampedBlockIndex) else { return }

            if let textNode = collectTextNodes(from: transformedBlock).first {
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
    
    private func extractCurrentBlockType(from editor: Editor) -> MarkdownBlockType {
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
            let tagType = heading.getTag()
            let level: MarkdownBlockType.HeadingLevel
            switch tagType {
            case .h1: level = .h1
            case .h2: level = .h2
            case .h3: level = .h3
            case .h4: level = .h4
            case .h5: level = .h5
            }
            return .heading(level: level)
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
    
    private func applySmartBackspaceCommand(_ command: SmartBackspaceCommand, to editor: Editor) {
        // Smart backspace: Handle empty list item deletion in one press
        guard let selection = try? getSelection() as? RangeSelection else { return }
        
        // Determine list item at selection and whether at start
        let anchor = selection.anchor
        let listItem: ListItemNode? = {
            if anchor.type == .element, let node = try? anchor.getNode() as? ListItemNode {
                return node
            } else if let node = try? anchor.getNode() {
                return self.findParentListItem(node)
            }
            return nil
        }()
        
        if let listItem = listItem {
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
    
    // MARK: - Node Creation
    
    private func createLexicalNode(from block: MarkdownBlock) -> Node {
        switch block {
        case .paragraph(let para):
            let node = createParagraphNode()
            if !para.text.isEmpty {
                let textNodes = MarkdownImporter.makeInlineNodes(from: para.text)
                try? node.append(textNodes)
            }
            return node
            
        case .heading(let heading):
            let node = createHeadingNode(headingTag: heading.level.lexicalType)
            if !heading.text.isEmpty {
                let textNodes = MarkdownImporter.makeInlineNodes(from: heading.text)
                try? node.append(textNodes)
            }
            return node
            
        case .codeBlock(let code):
            let node = createCodeNode()
            if let language = code.language {
                try? node.setLanguage(language)
            }
            
            if !code.content.isEmpty {
                let lines = code.content.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, line) in lines.enumerated() {
                    let textNode = TextNode(text: String(line))
                    try? node.append([textNode])
                    if index < (lines.count - 1) {
                        try? node.append([LineBreakNode()])
                    }
                }
            } else {
                // Keep the code block selectable/editable even when empty.
                let zwsp = createTextNode(text: "\u{200B}")
                try? node.append([zwsp])
            }
            return node
            
        case .quote(let quote):
            let node = createQuoteNode()
            if !quote.text.isEmpty {
                let textNodes = MarkdownImporter.makeInlineNodes(from: quote.text)
                try? node.append(textNodes)
            }
            return node
            
        case .list(let list):
            let listNode = ListNode(listType: list.type == .bullet ? .bullet : .number, start: 1)
            for item in list.items {
                let itemNode = ListItemNode()

                // Important: List items should contain direct text children (not nested paragraphs)
                // so that `RangeSelection.insertParagraph()` calls `ListItemNode.insertNewAfter(...)`
                // and creates a new list item (with a bullet) on Enter.
                if !item.text.isEmpty {
                    let textNodes = MarkdownImporter.makeInlineNodes(from: item.text)
                    try? itemNode.append(textNodes)
                } else {
                    // Keep the empty item selectable/editable.
                    let zwsp = createTextNode(text: "\u{200B}")
                    try? itemNode.append([zwsp])
                }
                try? listNode.append([itemNode])
            }
            // Ensure bullets/numbers are computed and rendered consistently.
            try? updateChildrenListItemValue(list: listNode, children: nil)
            return listNode
        }
    }
}

// MARK: - Domain Error Extensions

extension DomainError {
    static let editorNotConnected = DomainError.unsupportedOperation("Editor not connected to bridge")
    static func editorOperationFailed(_ reason: String) -> DomainError {
        return DomainError.unsupportedOperation("Editor operation failed: \(reason)")
    }
    static let commandValidationFailed = { (command: String) in
        DomainError.unsupportedOperation("Command validation failed: \(command)")
    }
}

// MARK: - Helpers

private extension MarkdownDomainBridge {
    func findParentListItem(_ node: Node) -> ListItemNode? {
        var current: Node? = node
        while let n = current {
            if let li = n as? ListItemNode { return li }
            current = n.getParent()
        }
        return nil
    }
}
