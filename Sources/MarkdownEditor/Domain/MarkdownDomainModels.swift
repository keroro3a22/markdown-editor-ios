/*
 * MarkdownEditor Domain Models
 * 
 * Core domain abstractions for unit-testable markdown operations.
 * These models are independent of Lexical and UI concerns.
 */

import Foundation

// MARK: - Document Position and Range

/// Represents a position within a markdown document
public struct DocumentPosition: Equatable {
    /// The paragraph/block index (0-based)
    public let blockIndex: Int
    /// The character offset within the block (0-based)
    public let offset: Int
    
    public init(blockIndex: Int, offset: Int) {
        self.blockIndex = blockIndex
        self.offset = offset
    }
    
    /// Creates a position at the beginning of the document
    public static let start = DocumentPosition(blockIndex: 0, offset: 0)
}

/// Represents a range of text within a markdown document
public struct TextRange: Equatable {
    /// The start position of the range
    public let start: DocumentPosition
    /// The end position of the range
    public let end: DocumentPosition
    
    public init(start: DocumentPosition, end: DocumentPosition) {
        self.start = start
        self.end = end
    }
    
    /// Creates a range that represents just a cursor position
    public init(at position: DocumentPosition) {
        self.start = position
        self.end = position
    }
    
    /// Whether this range represents just a cursor position (no selection)
    public var isCursor: Bool {
        return start == end
    }
    
    /// Whether this range spans multiple blocks
    public var isMultiBlock: Bool {
        return start.blockIndex != end.blockIndex
    }
}

// MARK: - Editor State

/// Represents the complete state of a markdown editor at a point in time
public struct MarkdownEditorState: Equatable {
    /// The complete document content as markdown text
    public let content: String
    /// The current cursor position or selection
    public let selection: TextRange
    /// The formatting applied at the current position
    public let currentFormatting: InlineFormatting
    /// The block type at the current position
    public let currentBlockType: MarkdownBlockType
    /// Whether the document has unsaved changes
    public let hasUnsavedChanges: Bool
    /// Document metadata
    public let metadata: DocumentMetadata
    
    public init(
        content: String,
        selection: TextRange,
        currentFormatting: InlineFormatting = [],
        currentBlockType: MarkdownBlockType = .paragraph,
        hasUnsavedChanges: Bool = false,
        metadata: DocumentMetadata = .default
    ) {
        self.content = content
        self.selection = selection
        self.currentFormatting = currentFormatting
        self.currentBlockType = currentBlockType
        self.hasUnsavedChanges = hasUnsavedChanges
        self.metadata = metadata
    }
    
    /// Creates an empty editor state
    public static let empty = MarkdownEditorState(
        content: "",
        selection: TextRange(at: .start)
    )
    
    /// Creates an editor state with a single paragraph
    public static func withParagraph(_ text: String) -> MarkdownEditorState {
        return MarkdownEditorState(
            content: text,
            selection: TextRange(at: DocumentPosition(blockIndex: 0, offset: text.count))
        )
    }
    
    /// Creates an editor state with a header
    public static func withHeader(_ level: MarkdownBlockType.HeadingLevel, text: String) -> MarkdownEditorState {
        let prefix = String(repeating: "#", count: level.rawValue) + " "
        let content = prefix + text
        return MarkdownEditorState(
            content: content,
            selection: TextRange(at: DocumentPosition(blockIndex: 0, offset: content.count)),
            currentBlockType: .heading(level: level)
        )
    }
}

// MARK: - Domain Errors

/// Errors that can occur in the domain layer
public enum DomainError: Error {
    case invalidPosition(DocumentPosition)
    case invalidRange(TextRange)
    case invalidBlockType(MarkdownBlockType)
    case unsupportedOperation(String)
    case documentValidationFailed(String)
    case notImplemented(String)
    case serializationFailed(String)
    case stateError(String)
    case undoFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidPosition(let position):
            return "Invalid document position: \(position)"
        case .invalidRange(let range):
            return "Invalid text range: \(range)"
        case .invalidBlockType(let blockType):
            return "Invalid block type: \(blockType)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .documentValidationFailed(let reason):
            return "Document validation failed: \(reason)"
        case .notImplemented(let feature):
            return "Not implemented: \(feature)"
        case .serializationFailed(let reason):
            return "Serialization failed: \(reason)"
        case .stateError(let reason):
            return "State error: \(reason)"
        case .undoFailed(let reason):
            return "Undo failed: \(reason)"
        }
    }
}

// MARK: - Validation Results

/// Result of validating a document or operation
public struct ValidationResult {
    public let isValid: Bool
    public let errors: [DomainError]
    public let warnings: [String]
    
    public init(isValid: Bool, errors: [DomainError] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
    
    public static let valid = ValidationResult(isValid: true)
    
    public static func invalid(errors: [DomainError]) -> ValidationResult {
        return ValidationResult(isValid: false, errors: errors)
    }
    
    public static func invalid(error: DomainError) -> ValidationResult {
        return ValidationResult(isValid: false, errors: [error])
    }
}

// MARK: - Document Metadata

/// Metadata associated with a markdown document
public struct DocumentMetadata: Equatable {
    public let createdAt: Date
    public let modifiedAt: Date
    public let version: String
    
    public init(createdAt: Date = Date(), modifiedAt: Date = Date(), version: String = "1.0") {
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.version = version
    }
    
    public static let `default` = DocumentMetadata()
}