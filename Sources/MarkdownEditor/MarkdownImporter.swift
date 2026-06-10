import Foundation
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

// MARK: - Markdown Import

struct MarkdownImporter {
    
    static func importMarkdown(_ markdown: String, into editor: Editor) throws {
        try editor.update {
            guard let root = getRoot() else {
                throw LexicalError.invariantViolation("Could not get root node")
            }
            
            // Clear existing content
            let children = root.getChildren()
            for child in children {
                try child.remove()
            }
            let nodes = makeNodes(from: markdown)
            if !nodes.isEmpty {
                try? root.append(nodes)
            }
            
            // Ensure at least one paragraph exists for empty documents
            if root.getChildren().isEmpty {
                let paragraph = createParagraphNode()
                try root.append([paragraph])
            }

            if let last = root.getLastChild() as? ElementNode {
                _ = try? last.selectEnd()
            }
        }
    }

    static func makeNodes(from markdown: String) -> [Node] {
        let lines = markdown.components(separatedBy: .newlines)
        var currentIndex = 0
        var nodes: [Node] = []
        nodes.reserveCapacity(min(64, lines.count))

        while currentIndex < lines.count {
            let rawLine = lines[currentIndex]
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                // Skip empty lines, they create natural spacing
                currentIndex += 1
                continue
            }

            // Parse different markdown elements
            if let node = parseHeading(trimmedLine) {
                nodes.append(node)
            } else if let (listNode, consumedLines) = parseList(lines: lines, startIndex: currentIndex) {
                nodes.append(listNode)
                currentIndex += consumedLines - 1
            } else if let (quoteNode, consumedLines) = parseQuote(lines: lines, startIndex: currentIndex) {
                nodes.append(quoteNode)
                currentIndex += consumedLines - 1
            } else if let (codeNode, consumedLines) = parseCodeBlock(lines: lines, startIndex: currentIndex) {
                nodes.append(codeNode)
                currentIndex += consumedLines - 1
            } else {
                // Regular paragraph
                let paragraph = createParagraphNode()
                let textNodes = makeInlineNodes(from: rawLine)
                try? paragraph.append(textNodes)
                nodes.append(paragraph)
            }

            currentIndex += 1
        }

        return nodes
    }
    
    // MARK: - Block Parsing
    
    private static func parseHeading(_ line: String) -> HeadingNode? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("# ") {
            let text = String(trimmed.dropFirst(2))
            let heading = createHeadingNode(headingTag: .h1)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        } else if trimmed.hasPrefix("## ") {
            let text = String(trimmed.dropFirst(3))
            let heading = createHeadingNode(headingTag: .h2)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        } else if trimmed.hasPrefix("### ") {
            let text = String(trimmed.dropFirst(4))
            let heading = createHeadingNode(headingTag: .h3)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        } else if trimmed.hasPrefix("#### ") {
            let text = String(trimmed.dropFirst(5))
            let heading = createHeadingNode(headingTag: .h4)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        } else if trimmed.hasPrefix("##### ") {
            let text = String(trimmed.dropFirst(6))
            let heading = createHeadingNode(headingTag: .h5)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        } else if trimmed.hasPrefix("###### ") {
            // Map h6 to h5 since HeadingTagType goes to h5
            let text = String(trimmed.dropFirst(7))
            let heading = createHeadingNode(headingTag: .h5)
            try? heading.append(makeInlineNodes(from: text))
            return heading
        }
        
        return nil
    }
    
    private static func parseList(lines: [String], startIndex: Int) -> (ListNode, Int)? {
        guard startIndex < lines.count else { return nil }
        
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let isUnordered = firstLine.hasPrefix("- ") || firstLine.hasPrefix("* ") || firstLine.hasPrefix("+ ")
        let isOrdered = firstLine.range(of: "^\\d+\\. ", options: .regularExpression) != nil
        
        guard isUnordered || isOrdered else { return nil }
        
        let listType: ListType = isUnordered ? .bullet : .number
        let listStart: Int = {
            guard isOrdered,
                  let range = firstLine.range(of: #"^\d+"#, options: .regularExpression),
                  let parsed = Int(firstLine[range]) else {
                return 1
            }
            return parsed
        }()
        let list = ListNode(listType: listType, start: listStart)

        func stripTaskListMarker(from text: String) -> String {
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") || text.hasPrefix("[ ] ") {
                return String(text.dropFirst(4))
            }
            return text
        }
        
        var currentIndex = startIndex
        var consumedLines = 0
        
        while currentIndex < lines.count {
            let line = lines[currentIndex].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                currentIndex += 1
                consumedLines += 1
                continue
            }
            
            let isCurrentUnordered = line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            let isCurrentOrdered = line.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            
            if (isUnordered && isCurrentUnordered) || (isOrdered && isCurrentOrdered) {
                let listItem = ListItemNode()
                
                let text: String
                if isCurrentUnordered {
                    let raw = String(line.dropFirst(2))
                    text = stripTaskListMarker(from: raw)
                } else {
                    // Remove number and period
                    if let range = line.range(of: "^\\d+\\. ", options: .regularExpression) {
                        let raw = String(line[range.upperBound...])
                        text = stripTaskListMarker(from: raw)
                    } else {
                        text = stripTaskListMarker(from: line)
                    }
                }
                
                let textNodes = makeInlineNodes(from: text)
                try? listItem.append(textNodes)
                if listItem.getChildren().isEmpty {
                    // Keep empty items selectable/editable.
                    try? listItem.append([createTextNode(text: emptyTextCaretAnchor)])
                }
                try? list.append([listItem])
                
                currentIndex += 1
                consumedLines += 1
            } else {
                break
            }
        }
        
        return consumedLines > 0 ? (list, consumedLines) : nil
    }
    
    private static func parseQuote(lines: [String], startIndex: Int) -> (QuoteNode, Int)? {
        guard startIndex < lines.count else { return nil }

        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard firstLine.hasPrefix("> ") else { return nil }

        let quote = createQuoteNode()
        var currentIndex = startIndex
        var consumedLines = 0
        var isFirstLine = true

        while currentIndex < lines.count {
            let trimmedLine = lines[currentIndex].trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("> ") else { break }

            if !isFirstLine {
                try? quote.append([LineBreakNode()])
            }

            let text = String(trimmedLine.dropFirst(2))
            let textNodes = makeInlineNodes(from: text)
            try? quote.append(textNodes)

            isFirstLine = false
            currentIndex += 1
            consumedLines += 1
        }

        return consumedLines > 0 ? (quote, consumedLines) : nil
    }
    
    private static func parseCodeBlock(lines: [String], startIndex: Int) -> (CodeNode, Int)? {
        guard startIndex < lines.count else { return nil }
        
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let fence: String
        if firstLine.hasPrefix("```") {
            fence = "```"
        } else if firstLine.hasPrefix("~~~") {
            fence = "~~~"
        } else {
            return nil
        }
        
        var codeContent: [String] = []
        var currentIndex = startIndex + 1
        var foundClosing = false
        
        while currentIndex < lines.count {
            let line = lines[currentIndex]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                foundClosing = true
                break
            }
            codeContent.append(line)
            currentIndex += 1
        }
        
        if foundClosing {
            let code = createCodeNode()
            let codeText = codeContent.joined(separator: "\n")
            let textNode = createTextNode(text: codeText)
            try? code.append([textNode])
            return (code, currentIndex - startIndex + 1)
        }
        
        return nil
    }
    
    // MARK: - Inline Formatting
    
    static func makeInlineNodes(from text: String) -> [Node] {
        guard !text.isEmpty else { return [] }

        let orderedMarkers: [(marker: String, format: TextFormatType)] = [
            ("**", .bold),
            ("~~", .strikethrough),
            ("`", .code),
            ("*", .italic)
        ]

        var nodes: [Node] = []
        var plainBuffer = ""
        var index = text.startIndex

        func flushPlainBuffer() {
            guard !plainBuffer.isEmpty else { return }
            nodes.append(createTextNode(text: plainBuffer))
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while index < text.endIndex {
            var matched = false

            if text[index] == "[",
               let closeLabel = text[index...].firstIndex(of: "]"),
               closeLabel < text.index(before: text.endIndex) {
                let openURL = text.index(after: closeLabel)
                if text[openURL] == "(",
                   let closeURL = text[openURL...].firstIndex(of: ")") {
                    let labelStart = text.index(after: index)
                    let urlStart = text.index(after: openURL)
                    let label = String(text[labelStart..<closeLabel])
                    let url = String(text[urlStart..<closeURL])
                    if !label.isEmpty {
                        flushPlainBuffer()
                        let link = LinkNode(url: url, key: nil)
                        try? link.append(makeInlineNodes(from: label))
                        nodes.append(link)
                        index = text.index(after: closeURL)
                        matched = true
                    }
                }
            }

            if matched {
                continue
            }

            for marker in orderedMarkers {
                guard text[index...].hasPrefix(marker.marker) else { continue }

                let contentStart = text.index(index, offsetBy: marker.marker.count)
                guard contentStart < text.endIndex,
                      let closingRange = text.range(of: marker.marker, range: contentStart..<text.endIndex),
                      closingRange.lowerBound > contentStart else {
                    continue
                }

                flushPlainBuffer()

                let content = String(text[contentStart..<closingRange.lowerBound])
                let formattedNode = createTextNode(text: content)
                var textFormat = TextFormat()

                switch marker.format {
                case .bold:
                    textFormat.bold = true
                case .italic:
                    textFormat.italic = true
                case .strikethrough:
                    textFormat.strikethrough = true
                case .code:
                    textFormat.code = true
                default:
                    break
                }

                _ = try? formattedNode.setFormat(format: textFormat)
                nodes.append(formattedNode)

                index = closingRange.upperBound
                matched = true
                break
            }

            if matched {
                continue
            }

            plainBuffer.append(text[index])
            index = text.index(after: index)
        }

        flushPlainBuffer()
        return nodes
    }
}
