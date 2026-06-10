/*
 * MarkdownCommandLogger
 * 
 * Provides structured, concise logging for command execution with clear boundaries
 * and state snapshots. Makes it easy to trace command transformations at a glance.
 */

import Foundation
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

/// Provides structured logging for markdown editor commands
public class MarkdownCommandLogger {
    
    private let loggingConfig: LoggingConfiguration
    
    public init(loggingConfig: LoggingConfiguration) {
        self.loggingConfig = loggingConfig
    }
    
    // MARK: - Command Logging
    
    /// Log the start of a command execution with before state
    public func logCommandStart(_ command: MarkdownCommand, beforeState: MarkdownStateSnapshot) {
        guard loggingConfig.isEnabled && loggingConfig.level >= .debug else { return }
        
        let separator = String(repeating: "=", count: 42)
        let commandName = extractCommandName(from: command)
        
        MarkdownLogger.command(
            "\n\(separator) COMMAND: \(commandName) \(separator)",
            level: .debug,
            config: loggingConfig
        )
        if loggingConfig.includeDetailedState {
            MarkdownLogger.command(beforeState.detailedDescription, level: .debug, config: loggingConfig)
        } else {
            MarkdownLogger.command("BEFORE: \(beforeState)", level: .debug, config: loggingConfig)
        }
    }
    
    /// Log the command action being taken
    public func logCommandAction(_ command: MarkdownCommand) {
        guard loggingConfig.isEnabled && loggingConfig.level >= .debug else { return }
        
        let action = extractCommandAction(from: command)
        MarkdownLogger.command("ACTION: \(action)", level: .debug, config: loggingConfig)
    }
    
    /// Log the command completion with after state
    public func logCommandComplete(_ command: MarkdownCommand, afterState: MarkdownStateSnapshot, success: Bool) {
        guard loggingConfig.isEnabled && loggingConfig.level >= .debug else { return }
        
        if success {
            if loggingConfig.includeDetailedState {
                MarkdownLogger.command("AFTER STATE:", level: .debug, config: loggingConfig)
                MarkdownLogger.command(afterState.detailedDescription, level: .debug, config: loggingConfig)
            } else {
                MarkdownLogger.command("AFTER:  \(afterState)", level: .debug, config: loggingConfig)
            }
        } else {
            MarkdownLogger.command("FAILED: Command did not execute successfully", level: .error, config: loggingConfig)
        }
        
        let separator = String(repeating: "=", count: 100)
        MarkdownLogger.command("\(separator)\n", level: .debug, config: loggingConfig)
    }
    
    /// Log a simple command event (for UI layer)
    public func logSimpleEvent(_ event: String, details: String? = nil) {
        guard loggingConfig.isEnabled && loggingConfig.level >= .info else { return }
        
        if let details = details {
            MarkdownLogger.command("[\(event)] \(details)", level: .info, config: loggingConfig)
        } else {
            MarkdownLogger.command("[\(event)]", level: .info, config: loggingConfig)
        }
    }
    
    // MARK: - State Snapshot Creation
    
    /// Create a snapshot from Lexical editor state
    public func createSnapshot(from editor: Editor) -> MarkdownStateSnapshot? {
        do {
            var snapshot: MarkdownStateSnapshot?
            try editor.read {
                let content = self.extractContent(from: editor)
                let blockType = self.extractBlockType(from: editor)
                let selection = self.extractSelection(from: editor)
                let nodeStructure = self.loggingConfig.includeDetailedState ? self.extractNodeStructure(from: editor) : nil
                
                snapshot = MarkdownStateSnapshot(
                    content: content,
                    blockType: blockType,
                    selection: selection,
                    nodeStructure: nodeStructure
                )
            }
            return snapshot
        } catch {
            if loggingConfig.isEnabled && loggingConfig.level >= .error {
                MarkdownLogger.command("[CommandLogger] Failed to create snapshot: \(error)", level: .error, config: loggingConfig)
            }
            return nil
        }
    }
    
    /// Create a snapshot from domain state
    public func createSnapshot(from state: MarkdownEditorState) -> MarkdownStateSnapshot {
        let content = extractContentPreview(from: state.content)
        let selectionDesc = "\(state.selection.start.offset)"
        if state.selection.start != state.selection.end {
            let endOffset = state.selection.end.offset
            return MarkdownStateSnapshot(
                content: content,
                blockType: describeBlockType(state.currentBlockType),
                selection: "\(state.selection.start.offset)-\(endOffset)",
                nodeStructure: nil // Domain state doesn't have node structure
            )
        }
        
        return MarkdownStateSnapshot(
            content: content,
            blockType: describeBlockType(state.currentBlockType),
            selection: selectionDesc,
            nodeStructure: nil // Domain state doesn't have node structure
        )
    }
    
    // MARK: - Private Helpers
    
    private func extractCommandName(from command: MarkdownCommand) -> String {
        switch command {
        case is SetBlockTypeCommand: return "Toggle Block Type"
        case is SmartBackspaceCommand: return "Smart Backspace"
        case is ApplyFormattingCommand: return "Apply Formatting"
        default: return "Unknown Command"
        }
    }
    
    private func extractCommandAction(from command: MarkdownCommand) -> String {
        switch command {
        case let cmd as SetBlockTypeCommand:
            return "SetBlockType(\(cmd.blockType))"
        case let cmd as SmartBackspaceCommand:
            return "SmartBackspace(at: \(cmd.position.offset))"
        case let cmd as ApplyFormattingCommand:
            return "ApplyFormatting(\(cmd.formatting))"
        default:
            return command.description
        }
    }
    
    private func extractContent(from editor: Editor) -> String {
        guard let root = getRoot() else {
            return ""
        }
        
        let text = root.getTextContent()
        return extractContentPreview(from: text)
    }
    
    private func extractContentPreview(from text: String) -> String {
        // Show cursor position with | and limit content around it
        let lines = text.components(separatedBy: "\n")
        
        if lines.count == 1 {
            // Single line - show with cursor
            return "\"\(text)|\"" 
        } else if lines.count <= 3 {
            // Few lines - show all
            return "\"\(text.replacingOccurrences(of: "\n", with: "\\n"))\""
        } else {
            // Many lines - show summary
            let firstLine = lines[0]
            let lastLine = lines[lines.count - 1]
            return "\"\(firstLine)\\n...(\(lines.count) lines)...\\n\(lastLine)\""
        }
    }
    
    private func extractBlockType(from editor: Editor) -> String {
        guard let selection = try? getSelection() as? RangeSelection,
              let anchorNode = try? selection.anchor.getNode() else {
            return "unknown"
        }
        
        let element = findBlockElement(from: anchorNode)
        
        if element is HeadingNode {
            return "heading"
        } else if element is ListItemNode {
            return "list"
        } else if element is CodeNode {
            return "code"
        } else if element is QuoteNode {
            return "quote"
        } else {
            return "paragraph"
        }
    }
    
    private func findBlockElement(from node: Node) -> ElementNode? {
        if let element = node as? ElementNode {
            return element
        }
        
        var current: Node? = node
        while let parent = current?.getParent() {
            if let element = parent as? ElementNode,
               !(element is RootNode) {
                return element
            }
            current = parent
        }
        
        return nil
    }
    
    private func extractSelection(from editor: Editor) -> String {
        guard let selection = try? getSelection() as? RangeSelection else {
            return "none"
        }
        
        let anchorOffset = selection.anchor.offset
        let focusOffset = selection.focus.offset
        
        if selection.isCollapsed() {
            return "\(anchorOffset)"
        } else {
            return "\(anchorOffset)-\(focusOffset)"
        }
    }
    
    // MARK: - Node Structure Extraction
    
    private func extractNodeStructure(from editor: Editor) -> String {
        guard let root = getRoot() else {
            return "<no root>"
        }
        
        var output = ""
        renderNode(root, depth: 0, output: &output)
        return output
    }
    
    private func renderNode(_ node: Node, depth: Int, output: inout String) {
        let indent = String(repeating: "  ", count: depth)
        
        // Node type and key
        let nodeType = describeNodeType(node)
        output += "\(indent)\(nodeType) [key: \(node.key)]"
        
        // Add text content for text nodes
        if let textNode = node as? TextNode {
            let text = textNode.getTextContent()
            let preview = text.count > 30 ? String(text.prefix(30)) + "..." : text
            output += " \"\(preview.replacingOccurrences(of: "\n", with: "\\n"))\""
            
            // Show formatting
            let format = textNode.getFormat()
            var formats: [String] = []
            if format.bold { formats.append("bold") }
            if format.italic { formats.append("italic") }
            if format.strikethrough { formats.append("strikethrough") }
            if format.code { formats.append("code") }
            if format.underline { formats.append("underline") }
            if format.subScript { formats.append("subscript") }
            if format.superScript { formats.append("superscript") }
            if !formats.isEmpty {
                output += " [\(formats.joined(separator: ", "))]"
            }
        }
        
        // Selection info
        if let selection = try? getSelection() as? RangeSelection {
            if selection.anchor.key == node.key {
                output += " <-- anchor(\(selection.anchor.offset))"
            }
            if selection.focus.key == node.key {
                output += " <-- focus(\(selection.focus.offset))"
            }
        }
        
        output += "\n"
        
        // Render children
        if let element = node as? ElementNode {
            for child in element.getChildren() {
                renderNode(child, depth: depth + 1, output: &output)
            }
        }
    }
    
    private func describeNodeType(_ node: Node) -> String {
        switch node {
        case is RootNode: return "RootNode"
        case is ParagraphNode: return "ParagraphNode"
        case is HeadingNode:
            if let heading = node as? HeadingNode {
                return "HeadingNode(\(heading.getTag()))"
            }
            return "HeadingNode"
        case is ListNode:
            if let list = node as? ListNode {
                let kind: String
                switch list.getListType() {
                case .bullet:
                    kind = "bullet"
                case .number:
                    kind = "number"
                case .check:
                    kind = "check"
                }
                return "ListNode(\(kind))"
            }
            return "ListNode"
        case is ListItemNode: return "ListItemNode"
        case is TextNode: return "TextNode"
        case is LineBreakNode: return "LineBreakNode"
        case is CodeNode: return "CodeNode"
        case is QuoteNode: return "QuoteNode"
        case is LinkNode: return "LinkNode"
        default: return "\(type(of: node))"
        }
    }
}

// MARK: - State Snapshot

/// Lightweight representation of editor state for logging
public struct MarkdownStateSnapshot: CustomStringConvertible {
    let content: String
    let blockType: String
    let selection: String
    let nodeStructure: String?
    
    public var description: String {
        "\(content) [\(blockType)] (\(selection))"
    }
    
    public var detailedDescription: String {
        var desc = "CONTENT: \(content)\n"
        desc += "TYPE: [\(blockType)] SELECTION: (\(selection))\n"
        if let nodeStructure = nodeStructure {
            desc += "NODES:\n\(nodeStructure)"
        }
        return desc
    }
}

// MARK: - Shared Logger Instance

// Global logger instance removed - logger is now created per editor instance

// MARK: - Helpers

private func describeBlockType(_ blockType: MarkdownBlockType) -> String {
    switch blockType {
    case .paragraph: return "paragraph"
    case .heading(let level):
        switch level {
        case .h1: return "h1"
        case .h2: return "h2"
        case .h3: return "h3"
        case .h4: return "h4"
        case .h5: return "h5"
        case .h6: return "h6"
        }
    case .codeBlock: return "code"
    case .quote: return "quote"
    case .unorderedList: return "list"
    case .orderedList: return "list"
    }
}
