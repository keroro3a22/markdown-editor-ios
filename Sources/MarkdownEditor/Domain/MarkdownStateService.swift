/*
 * MarkdownStateService
 * 
 * Domain service for editor state management operations.
 * Handles state queries and transformations without UI dependencies.
 */

import Foundation

// MARK: - State Service Protocol

/// Service for managing markdown editor state operations
public protocol MarkdownStateService {
    /// Validate that a state is consistent and valid
    func validateState(_ state: MarkdownEditorState) -> ValidationResult
    
    /// Create a new state from markdown content
    func createState(
        from content: String,
        cursorAt position: DocumentPosition
    ) -> Result<MarkdownEditorState, DomainError>
    
    /// Update the selection in a state
    func updateSelection(
        to range: TextRange,
        in state: MarkdownEditorState
    ) -> Result<MarkdownEditorState, DomainError>
    
    /// Check if two states are equivalent (ignoring metadata like timestamps)
    func areStatesEquivalent(_ state1: MarkdownEditorState, _ state2: MarkdownEditorState) -> Bool
}


// MARK: - Default Implementation

/// Default implementation of MarkdownStateService
public class DefaultMarkdownStateService: MarkdownStateService {
    private let documentService: MarkdownDocumentService
    private let formattingService: MarkdownFormattingService
    
    public init(
        documentService: MarkdownDocumentService = DefaultMarkdownDocumentService(),
        formattingService: MarkdownFormattingService? = nil
    ) {
        self.documentService = documentService
        self.formattingService = formattingService ?? DefaultMarkdownFormattingService(documentService: documentService)
    }
    
    public func validateState(_ state: MarkdownEditorState) -> ValidationResult {
        var errors: [DomainError] = []
        var warnings: [String] = []
        
        // Validate document content
        let documentValidation = documentService.validateDocument(state.content)
        errors.append(contentsOf: documentValidation.errors)
        warnings.append(contentsOf: documentValidation.warnings)
        
        // Validate selection using document service
        switch documentService.validatePosition(state.selection.start, in: state.content) {
        case .success:
            break
        case .failure(let error):
            errors.append(error)
        }
        
        switch documentService.validatePosition(state.selection.end, in: state.content) {
        case .success:
            break
        case .failure(let error):
            errors.append(error)
        }
        
        // Validate formatting compatibility with block type
        if !formattingService.canApplyFormatting(
            state.currentFormatting,
            to: state.selection,
            in: state
        ) {
            warnings.append("Current formatting may not be compatible with block type")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    public func createState(
        from content: String,
        cursorAt position: DocumentPosition
    ) -> Result<MarkdownEditorState, DomainError> {
        
        // Validate position using document service
        switch documentService.validatePosition(position, in: content) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }
        
        // Get formatting and block type at position
        let blockType = formattingService.getBlockTypeAt(position: position, in: MarkdownEditorState(
            content: content,
            selection: TextRange(at: position)
        ))
        
        let formatting = formattingService.getFormattingAt(position: position, in: MarkdownEditorState(
            content: content,
            selection: TextRange(at: position)
        ))
        
        let state = MarkdownEditorState(
            content: content,
            selection: TextRange(at: position),
            currentFormatting: formatting,
            currentBlockType: blockType,
            hasUnsavedChanges: false,
            metadata: .default
        )
        
        return .success(state)
    }
    
    public func updateSelection(
        to range: TextRange,
        in state: MarkdownEditorState
    ) -> Result<MarkdownEditorState, DomainError> {
        
        // Validate new selection using document service
        switch documentService.validatePosition(range.start, in: state.content) {
        case .success:
            break
        case .failure:
            return .failure(.invalidRange(range))
        }
        
        switch documentService.validatePosition(range.end, in: state.content) {
        case .success:
            break
        case .failure:
            return .failure(.invalidRange(range))
        }
        
        // Update formatting and block type based on new selection
        let newFormatting = formattingService.getFormattingAt(position: range.start, in: state)
        let newBlockType = formattingService.getBlockTypeAt(position: range.start, in: state)
        
        let newState = MarkdownEditorState(
            content: state.content,
            selection: range,
            currentFormatting: newFormatting,
            currentBlockType: newBlockType,
            hasUnsavedChanges: state.hasUnsavedChanges,
            metadata: state.metadata
        )
        
        return .success(newState)
    }
    
    public func areStatesEquivalent(_ state1: MarkdownEditorState, _ state2: MarkdownEditorState) -> Bool {
        return state1.content == state2.content &&
               state1.selection == state2.selection &&
               state1.currentFormatting == state2.currentFormatting &&
               state1.currentBlockType == state2.currentBlockType
        // Deliberately ignore hasUnsavedChanges and metadata for equivalence
    }
}