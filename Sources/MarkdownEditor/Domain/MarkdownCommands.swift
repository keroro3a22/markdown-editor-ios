/*
 * MarkdownCommands
 * 
 * Command pattern implementation for testable markdown operations.
 * Each command encapsulates a specific operation that can be executed, undone, and tested.
 */

import Foundation

// MARK: - Command Protocol

/// Base protocol for all markdown editor commands
public protocol MarkdownCommand {
    /// Execute this command on the given state
    func execute(on state: MarkdownEditorState) -> Result<MarkdownEditorState, DomainError>
    
    /// Check if this command can be executed on the given state
    func canExecute(on state: MarkdownEditorState) -> Bool
    
    /// Create the inverse command that can undo this operation
    func createUndo(for state: MarkdownEditorState) -> MarkdownCommand?
    
    /// A description of this command for debugging/logging
    var description: String { get }
    
    /// Whether this command should be recorded in undo history
    var isUndoable: Bool { get }
}

// MARK: - Command Execution Context

/// Context for executing commands with services
public class MarkdownCommandContext {
    public let documentService: MarkdownDocumentService
    public let formattingService: MarkdownFormattingService
    public let stateService: MarkdownStateService
    
    public init(
        documentService: MarkdownDocumentService = DefaultMarkdownDocumentService(),
        formattingService: MarkdownFormattingService? = nil,
        stateService: MarkdownStateService? = nil
    ) {
        self.documentService = documentService
        self.formattingService = formattingService ?? DefaultMarkdownFormattingService(documentService: documentService)
        self.stateService = stateService ?? DefaultMarkdownStateService(
            documentService: documentService,
            formattingService: self.formattingService
        )
    }
}

// MARK: - Formatting Commands

/// Command to apply inline formatting
public struct ApplyFormattingCommand: MarkdownCommand {
    public let formatting: InlineFormatting
    public let range: TextRange
    public let operation: FormattingOperation
    private let context: MarkdownCommandContext
    
    public init(
        formatting: InlineFormatting,
        to range: TextRange,
        operation: FormattingOperation = .toggle,
        context: MarkdownCommandContext
    ) {
        self.formatting = formatting
        self.range = range
        self.operation = operation
        self.context = context
    }
    
    public func execute(on state: MarkdownEditorState) -> Result<MarkdownEditorState, DomainError> {
        return context.formattingService.applyInlineFormatting(
            formatting,
            to: range,
            in: state,
            operation: operation
        )
    }
    
    public func canExecute(on state: MarkdownEditorState) -> Bool {
        // Treat Lexical as source of truth: gate only on known business rules.
        if state.currentBlockType == .codeBlock {
            return false
        }
        if formatting.contains(.code) && (formatting.contains(.bold) || formatting.contains(.italic) || formatting.contains(.strikethrough)) {
            return false
        }
        return true
    }
    
    public func createUndo(for state: MarkdownEditorState) -> MarkdownCommand? {
        let undoOperation: FormattingOperation
        switch operation {
        case .apply:
            undoOperation = .remove
        case .remove:
            undoOperation = .apply
        case .toggle:
            undoOperation = .toggle // Toggle is its own inverse
        }
        
        return ApplyFormattingCommand(
            formatting: formatting,
            to: range,
            operation: undoOperation,
            context: context
        )
    }
    
    public var description: String {
        return "\(operation) \(formatting) to range \(range)"
    }
    
    public var isUndoable: Bool { return true }
}

/// Command to set block type with smart list toggle logic
public struct SetBlockTypeCommand: MarkdownCommand {
    public let blockType: MarkdownBlockType
    public let position: DocumentPosition
    private let context: MarkdownCommandContext
    
    public init(blockType: MarkdownBlockType, at position: DocumentPosition, context: MarkdownCommandContext) {
        self.blockType = blockType
        self.position = position
        self.context = context
    }
    
    public func execute(on state: MarkdownEditorState) -> Result<MarkdownEditorState, DomainError> {
        // Get current block type to check for toggle behavior
        let currentBlockType = context.formattingService.getBlockTypeAt(position: position, in: state)
        
        // Apply smart list toggle logic
        let targetBlockType: MarkdownBlockType
        switch (currentBlockType, blockType) {
        case (.unorderedList, .unorderedList):
            // Toggle unordered list back to paragraph
            targetBlockType = .paragraph
        case (.orderedList, .orderedList):
            // Toggle ordered list back to paragraph
            targetBlockType = .paragraph
        default:
            // Normal conversion
            targetBlockType = blockType
        }
        
        return context.formattingService.setBlockType(targetBlockType, at: position, in: state)
    }
    
    public func canExecute(on state: MarkdownEditorState) -> Bool {
        // Lexical applies block changes; domain-level validation here is intentionally permissive.
        return true
    }
    
    public func createUndo(for state: MarkdownEditorState) -> MarkdownCommand? {
        let currentBlockType = context.formattingService.getBlockTypeAt(position: position, in: state)
        return SetBlockTypeCommand(blockType: currentBlockType, at: position, context: context)
    }
    
    public var description: String {
        return "Set block type to \(blockType) at \(position)"
    }
    
    public var isUndoable: Bool { return true }
}

// MARK: - Smart Commands

/// Command for smart enter key behavior in lists
public struct SmartBackspaceCommand: MarkdownCommand {
    public let position: DocumentPosition
    private let context: MarkdownCommandContext
    
    public init(at position: DocumentPosition, context: MarkdownCommandContext) {
        self.position = position
        self.context = context
    }
    
    public func execute(on state: MarkdownEditorState) -> Result<MarkdownEditorState, DomainError> {
        let currentBlockType = context.formattingService.getBlockTypeAt(position: position, in: state)
        
        // Handle list-specific backspace behavior
        switch currentBlockType {
        case .unorderedList, .orderedList:
            let lines = state.content.components(separatedBy: .newlines)
            guard position.blockIndex < lines.count else {
                return .failure(.invalidPosition(position))
            }
            
            let currentLine = lines[position.blockIndex]
            
            // Check for list prefix
            let isAtListMarker = position.offset <= 2 && (
                currentLine.hasPrefix("- ") ||
                currentLine.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            )
            
            // Check if we're at the beginning of a list item
            if isAtListMarker { // At or near the list marker
                let isEmptyListItem = currentLine.range(of: #"^\s*[-*+]\s+$"#, options: .regularExpression) != nil ||
                                      currentLine.range(of: #"^\s*\d+\.\s+$"#, options: .regularExpression) != nil
                
                if isEmptyListItem {
                    if position.blockIndex == 0 {
                        // First item - convert to paragraph
                        return context.formattingService.setBlockType(.paragraph, at: position, in: state)
                    } else {
                        // Middle item - remove it
                        let range = TextRange(
                            start: DocumentPosition(blockIndex: position.blockIndex - 1, offset: lines[position.blockIndex - 1].count),
                            end: DocumentPosition(blockIndex: position.blockIndex, offset: currentLine.count)
                        )
                        return context.documentService.deleteText(in: range, from: state.content)
                            .flatMap { newContent in
                                context.stateService.createState(
                                    from: newContent,
                                    cursorAt: DocumentPosition(blockIndex: position.blockIndex - 1, offset: lines[position.blockIndex - 1].count)
                                )
                            }
                    }
                }
            }
            
            // Normal backspace
            if position.offset > 0 {
                let deleteRange = TextRange(
                    start: DocumentPosition(blockIndex: position.blockIndex, offset: position.offset - 1),
                    end: position
                )
                return context.documentService.deleteText(in: deleteRange, from: state.content)
                    .flatMap { newContent in
                        context.stateService.createState(from: newContent, cursorAt: DocumentPosition(blockIndex: position.blockIndex, offset: position.offset - 1))
                    }
            }
            
        default:
            break
        }
        
        // Normal backspace behavior
        if position.offset > 0 {
            let deleteRange = TextRange(
                start: DocumentPosition(blockIndex: position.blockIndex, offset: position.offset - 1),
                end: position
            )
            return context.documentService.deleteText(in: deleteRange, from: state.content)
                .flatMap { newContent in
                    context.stateService.createState(from: newContent, cursorAt: DocumentPosition(blockIndex: position.blockIndex, offset: position.offset - 1))
                }
        } else if position.blockIndex > 0 {
            // Join with previous line
            let lines = state.content.components(separatedBy: .newlines)
            let prevLineLength = lines[position.blockIndex - 1].count
            let deleteRange = TextRange(
                start: DocumentPosition(blockIndex: position.blockIndex - 1, offset: prevLineLength),
                end: position
            )
            return context.documentService.deleteText(in: deleteRange, from: state.content)
                .flatMap { newContent in
                    context.stateService.createState(from: newContent, cursorAt: DocumentPosition(blockIndex: position.blockIndex - 1, offset: prevLineLength))
                }
        }
        
        return .success(state) // Nothing to delete
    }
    
    public func canExecute(on state: MarkdownEditorState) -> Bool {
        return true
    }
    
    public func createUndo(for state: MarkdownEditorState) -> MarkdownCommand? {
        return nil
    }
    
    public var description: String {
        return "Smart backspace at \(position)"
    }
    
    public var isUndoable: Bool { return true }
}
