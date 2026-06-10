import Foundation
import Lexical
import LexicalListPlugin
import LexicalMarkdown

public enum StreamingReplacementError: LocalizedError, Equatable {
    case emptyFindText
    case sessionAlreadyActive
    case matchNotFound
    case editorUnavailable
    case invalidMatchRange
    case applyFailed

    public var errorDescription: String? {
        switch self {
        case .emptyFindText:
            return "Find text cannot be empty."
        case .sessionAlreadyActive:
            return "A streaming replacement session is already active."
        case .matchNotFound:
            return "Could not find matching text in the current document."
        case .editorUnavailable:
            return "Editor is unavailable."
        case .invalidMatchRange:
            return "The matching text range was invalid."
        case .applyFailed:
            return "Failed to apply the replacement to the editor."
        }
    }
}

@MainActor
public protocol MarkdownStreamingEditing: AnyObject {
    /// Starts a streaming replacement session over the best match for `findText`.
    ///
    /// The editor stays read-only until `finish()` or `cancel()` is called on the
    /// returned session. Callers own the session lifetime and must call one of
    /// them on every exit path — including stream failure — or the editor remains
    /// locked.
    func startReplacement(
        findText: String,
        beforeContext: String?,
        afterContext: String?
    ) throws -> ReplacementSession
}

/// Handle for one streaming replacement. The owning editor is read-only while
/// the session is active; always end it with `finish()` (keep the streamed
/// content, one undo step) or `cancel()` (restore the original document).
@MainActor
public final class ReplacementSession {
    private weak var owner: MarkdownStreamingEditingInternal?
    private let token: UUID

    internal init(owner: MarkdownStreamingEditingInternal, token: UUID) {
        self.owner = owner
        self.token = token
    }

    public var isActive: Bool {
        owner?.isReplacementSessionActive(token: token) ?? false
    }

    public func append(_ delta: String) {
        owner?.appendReplacementDelta(token: token, delta: delta)
    }

    public func setText(_ fullText: String) {
        owner?.setReplacementText(token: token, fullText: fullText)
    }

    public func finish() {
        owner?.finishReplacement(token: token)
    }

    public func cancel() {
        owner?.cancelReplacement(token: token)
    }
}

@MainActor
public protocol MarkdownStreamingAppending: AnyObject {
    /// Starts a streaming append session at the end of the document.
    ///
    /// The editor stays read-only until `finish()` or `cancel()` is called on the
    /// returned session. Callers own the session lifetime and must call one of
    /// them on every exit path — including stream failure — or the editor remains
    /// locked.
    func startAppend() throws -> AppendSession
}

/// Handle for one streaming append. The owning editor is read-only while the
/// session is active; always end it with `finish()` (keep the streamed content,
/// one undo step) or `cancel()` (restore the original document).
@MainActor
public final class AppendSession {
    private weak var owner: MarkdownStreamingAppendingInternal?
    private let token: UUID

    internal init(owner: MarkdownStreamingAppendingInternal, token: UUID) {
        self.owner = owner
        self.token = token
    }

    public var isActive: Bool {
        owner?.isAppendSessionActive(token: token) ?? false
    }

    public func append(_ delta: String) {
        owner?.appendAppendDelta(token: token, delta: delta)
    }

    public func setText(_ fullText: String) {
        owner?.setAppendText(token: token, fullText: fullText)
    }

    public func finish() {
        owner?.finishAppend(token: token)
    }

    public func cancel() {
        owner?.cancelAppend(token: token)
    }
}

@MainActor
internal protocol MarkdownStreamingEditingInternal: AnyObject {
    func isReplacementSessionActive(token: UUID) -> Bool
    func appendReplacementDelta(token: UUID, delta: String)
    func setReplacementText(token: UUID, fullText: String)
    func finishReplacement(token: UUID)
    func cancelReplacement(token: UUID)
}

@MainActor
internal protocol MarkdownStreamingAppendingInternal: AnyObject {
    func isAppendSessionActive(token: UUID) -> Bool
    func appendAppendDelta(token: UUID, delta: String)
    func setAppendText(token: UUID, fullText: String)
    func finishAppend(token: UUID)
    func cancelAppend(token: UUID)
}

internal struct StreamingReplacementMatchCandidate {
    let nodeKey: NodeKey
    let rawText: String
    let normalizedText: String
    let normalizedMapping: [NSRange]
    let ordinal: Int
}

internal struct StreamingReplacementMatchResult {
    let nodeKey: NodeKey
    let rawText: String
    let matchStartUtf16: Int
    let matchLengthUtf16: Int
}

internal enum StreamingReplacementMatching {
    // Match-normalization set, NOT the emptiness set (Lexical.emptyTextInvisibleScalarValues):
    // U+2060 (word joiner) is deliberately excluded so documents containing it still match.
    private static let zeroWidthScalars = Set<Unicode.Scalar>([
        "\u{200B}", // zero width space
        "\u{200C}", // zero width non-joiner
        "\u{200D}", // zero width joiner
        "\u{FEFF}", // byte order mark
    ])

    private static let nbspScalars = Set<Unicode.Scalar>([
        "\u{00A0}", // nbsp
        "\u{202F}", // narrow no-break space
        "\u{2007}", // figure space
        "\u{2009}", // thin space
    ])

    private static let punctuationMap: [Unicode.Scalar: String] = [
        "\u{2018}": "'", // ‘
        "\u{2019}": "'", // ’
        "\u{201C}": "\"", // “
        "\u{201D}": "\"", // ”
        "\u{2013}": "-", // –
        "\u{2014}": "-", // —
        "\u{2212}": "-", // −
        "\u{2026}": "...", // …
    ]

    static func normalizeForMatching(_ input: String) -> String {
        normalizeForMatchingWithMapping(input).normalized
    }

    static func normalizeForMatchingWithMapping(_ input: String) -> (normalized: String, mapping: [NSRange]) {
        if input.isEmpty { return ("", []) }

        var characters: [Character] = []
        var mapping: [NSRange] = []
        characters.reserveCapacity(input.count)
        mapping.reserveCapacity(input.count)

        func utf16Offset(_ index: String.Index) -> Int {
            input.utf16.distance(from: input.utf16.startIndex, to: index)
        }

        var lastWasSpace = false

        var iterator = input.unicodeScalars.makeIterator()
        var currentStringIndex = input.unicodeScalars.startIndex
        func currentScalarRange(_ start: String.Index, _ end: String.Index) -> NSRange {
            let location = utf16Offset(start)
            let length = utf16Offset(end) - location
            return NSRange(location: location, length: length)
        }

        // The UnicodeScalarView iterator does not expose the underlying indices, so we keep a parallel index.
        // We advance `currentStringIndex` manually in lockstep with the iterator.
        while let scalar = iterator.next() {
            let startIndex = currentStringIndex
            currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
            let endIndex = currentStringIndex

            if zeroWidthScalars.contains(scalar) { continue }

            if scalar == "\r" {
                // Normalize CRLF / CR -> LF.
                var rangeEnd = endIndex
                if let nextScalar = iterator.next() {
                    let nextStart = currentStringIndex
                    currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
                    let nextEnd = currentStringIndex
                    if nextScalar == "\n" {
                        rangeEnd = nextEnd
                    } else {
                        // Put the scalar back is not possible with IteratorProtocol; treat as separate scalar.
                        // We conservatively include only the CR here, and handle the next scalar as already-consumed
                        // by emitting it immediately.
                        // Emit the next scalar as part of this loop iteration by processing it inline.
                        let crRange = currentScalarRange(startIndex, endIndex)
                        characters.append("\n")
                        mapping.append(crRange)
                        lastWasSpace = false

                        // Process `nextScalar` as if it was the next loop iteration.
                        if zeroWidthScalars.contains(nextScalar) { continue }
                        if nextScalar == "\n" {
                            characters.append("\n")
                            mapping.append(currentScalarRange(nextStart, nextEnd))
                            lastWasSpace = false
                            continue
                        }
                        if nbspScalars.contains(nextScalar) || nextScalar == "\t" || nextScalar == "\u{000B}" || nextScalar == "\u{000C}" ||
                            CharacterSet.whitespaces.contains(nextScalar) {
                            if !lastWasSpace {
                                characters.append(" ")
                                mapping.append(currentScalarRange(nextStart, nextEnd))
                                lastWasSpace = true
                            }
                            continue
                        }
                        if let mapped = punctuationMap[nextScalar] {
                            for ch in mapped {
                                characters.append(ch)
                                mapping.append(currentScalarRange(nextStart, nextEnd))
                            }
                            lastWasSpace = false
                            continue
                        }
                        characters.append(Character(nextScalar))
                        mapping.append(currentScalarRange(nextStart, nextEnd))
                        lastWasSpace = false
                        continue
                    }
                }

                let crlfRange = currentScalarRange(startIndex, rangeEnd)
                characters.append("\n")
                mapping.append(crlfRange)
                lastWasSpace = false
                continue
            }

            if scalar == "\n" {
                characters.append("\n")
                mapping.append(currentScalarRange(startIndex, endIndex))
                lastWasSpace = false
                continue
            }

            if nbspScalars.contains(scalar) || scalar == "\t" || scalar == "\u{000B}" || scalar == "\u{000C}" {
                if !lastWasSpace {
                    // Collapse runs of whitespace to a single space, and map to the full whitespace run.
                    var runEnd = endIndex
                    while currentStringIndex < input.unicodeScalars.endIndex {
                        let peek = input.unicodeScalars[currentStringIndex]
                        if peek == "\n" || peek == "\r" { break }
                        if zeroWidthScalars.contains(peek) {
                            currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
                            _ = iterator.next()
                            runEnd = currentStringIndex
                            continue
                        }
                        if nbspScalars.contains(peek) || peek == "\t" || peek == "\u{000B}" || peek == "\u{000C}" ||
                            CharacterSet.whitespaces.contains(peek) {
                            currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
                            _ = iterator.next()
                            runEnd = currentStringIndex
                            continue
                        }
                        break
                    }
                    characters.append(" ")
                    mapping.append(currentScalarRange(startIndex, runEnd))
                    lastWasSpace = true
                }
                continue
            }

            if let mapped = punctuationMap[scalar] {
                for ch in mapped {
                    characters.append(ch)
                    mapping.append(currentScalarRange(startIndex, endIndex))
                }
                lastWasSpace = false
                continue
            }

            if CharacterSet.whitespaces.contains(scalar) {
                if !lastWasSpace {
                    var runEnd = endIndex
                    while currentStringIndex < input.unicodeScalars.endIndex {
                        let peek = input.unicodeScalars[currentStringIndex]
                        if peek == "\n" || peek == "\r" { break }
                        if zeroWidthScalars.contains(peek) {
                            currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
                            _ = iterator.next()
                            runEnd = currentStringIndex
                            continue
                        }
                        if nbspScalars.contains(peek) || peek == "\t" || peek == "\u{000B}" || peek == "\u{000C}" ||
                            CharacterSet.whitespaces.contains(peek) {
                            currentStringIndex = input.unicodeScalars.index(after: currentStringIndex)
                            _ = iterator.next()
                            runEnd = currentStringIndex
                            continue
                        }
                        break
                    }
                    characters.append(" ")
                    mapping.append(currentScalarRange(startIndex, runEnd))
                    lastWasSpace = true
                }
                continue
            }

            characters.append(Character(scalar))
            mapping.append(currentScalarRange(startIndex, endIndex))
            lastWasSpace = false
        }

        // Trim leading/trailing whitespace/newlines to match normalizeForMatching behavior.
        while let first = characters.first, (first == " " || first == "\n") {
            characters.removeFirst()
            mapping.removeFirst()
        }
        while let last = characters.last, (last == " " || last == "\n") {
            characters.removeLast()
            mapping.removeLast()
        }

        return (String(characters), mapping)
    }

    static func bestMatch(
        candidates: [StreamingReplacementMatchCandidate],
        findText: String,
        beforeContext: String?,
        afterContext: String?
    ) -> StreamingReplacementMatchResult? {
        let needle = normalizeForMatching(findText)
        guard !needle.isEmpty else { return nil }

        let before = normalizeForMatching(beforeContext ?? "")
        let after = normalizeForMatching(afterContext ?? "")

        var best: (score: Int, matchIndex: Int, ordinal: Int, result: StreamingReplacementMatchResult)? = nil

        for candidate in candidates {
            guard let range = candidate.normalizedText.range(of: needle) else { continue }
            let matchIndex = candidate.normalizedText.distance(from: candidate.normalizedText.startIndex, to: range.lowerBound)
            let matchEnd = candidate.normalizedText.distance(from: candidate.normalizedText.startIndex, to: range.upperBound)
            guard matchIndex >= 0, matchEnd > matchIndex else { continue }
            guard matchIndex < candidate.normalizedMapping.count else { continue }
            guard (matchEnd - 1) < candidate.normalizedMapping.count else { continue }

            let rawStart = candidate.normalizedMapping[matchIndex].location
            let rawEndRange = candidate.normalizedMapping[matchEnd - 1]
            let rawEnd = rawEndRange.location + rawEndRange.length
            let rawLength = max(0, rawEnd - rawStart)
            guard rawLength >= 0 else { continue }

            var score = 1_000

            if !before.isEmpty {
                let beforeText = String(candidate.normalizedText.prefix(matchIndex))
                let overlap = commonSuffixLength(beforeText, before)
                score += Int((Double(overlap) / Double(max(1, before.count))) * 500.0)
            }

            if !after.isEmpty {
                let start = candidate.normalizedText.index(range.upperBound, offsetBy: 0)
                let afterText = String(candidate.normalizedText[start...])
                let overlap = commonPrefixLength(afterText, after)
                score += Int((Double(overlap) / Double(max(1, after.count))) * 500.0)
            }

            let result = StreamingReplacementMatchResult(
                nodeKey: candidate.nodeKey,
                rawText: candidate.rawText,
                matchStartUtf16: rawStart,
                matchLengthUtf16: rawLength
            )

            if let currentBest = best {
                if score > currentBest.score ||
                    (score == currentBest.score && matchIndex < currentBest.matchIndex) ||
                    (score == currentBest.score && matchIndex == currentBest.matchIndex && candidate.ordinal < currentBest.ordinal) {
                    best = (score, matchIndex, candidate.ordinal, result)
                }
            } else {
                best = (score, matchIndex, candidate.ordinal, result)
            }
        }

        return best?.result
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        let maxLen = min(a.count, b.count)
        if maxLen == 0 { return 0 }

        var length = 0
        let aChars = Array(a)
        let bChars = Array(b)
        for i in 0..<maxLen {
            if aChars[i] != bChars[i] { break }
            length += 1
        }
        return length
    }

    private static func commonSuffixLength(_ a: String, _ b: String) -> Int {
        let maxLen = min(a.count, b.count)
        if maxLen == 0 { return 0 }

        var length = 0
        let aChars = Array(a)
        let bChars = Array(b)
        for i in 1...maxLen {
            if aChars[aChars.count - i] != bChars[bChars.count - i] { break }
            length += 1
        }
        return length
    }
}
