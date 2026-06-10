import Foundation

// MARK: - Document Model

public struct MarkdownDocument {
    public let content: String
    public let metadata: DocumentMetadata

    public init(content: String, metadata: DocumentMetadata = .default) {
        self.content = content
        self.metadata = metadata
    }
}

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

