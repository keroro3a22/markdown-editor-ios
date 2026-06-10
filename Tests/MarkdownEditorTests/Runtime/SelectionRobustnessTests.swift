/*
 * SelectionRobustnessTests
 *
 * Selection robustness: backspace crash matrix over selection shapes,
 * autocorrect-style replacements, marked-text composition, and
 * select-existing-empty-block canonicalization.
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class SelectionRobustnessTests: MarkdownRuntimeTestCase {
    func testMarkedTextCompositionCommitsWithoutHistoryDependentCaretState() throws {
        let blockCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "unordered-list", "ordered-list"].contains($0.name)
        }
        let histories: [HistoryPath] = [
            .clean,
            .afterHeadingEnter,
            .afterListDoubleEnter,
            .afterQuoteEnter
        ]

        var exercised = 0
        for history in histories {
            for blockCase in blockCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(blockCase.block)

                composeMarkedTextSequence()

                XCTAssertTrue(markdownEditor.textView.text.contains("すし もじ"), "\(history) / \(blockCase.name)")
                XCTAssertEqual(markdownEditor.textView.selectedRange.length, 0, "\(history) / \(blockCase.name)")
                XCTAssertNil((markdownEditor.textView as? TextView)?.editor.compositionKey, "\(history) / \(blockCase.name)")
                let snapshot = activeLineVisualSnapshot()
                XCTAssertEqual(snapshot.blockType, blockCase.expected.type, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.selectionType, .text, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.selectedBlockText, "すし もじ", "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.renderedLine.blockType, blockCase.expected.type, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.renderedLine.visibleText, "すし もじ", "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.caretHeight, rounded(blockCase.expected.font.lineHeight), accuracy: 1.0, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.firstLineHeadIndent, rounded(blockCase.expected.firstLineHeadIndent), accuracy: 0.5, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.headIndent, rounded(blockCase.expected.headIndent), accuracy: 0.5, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.hasListItemAttribute, blockCase.expected.allowsListAttribute, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.typingPointSize, rounded(blockCase.expected.font.pointSize), accuracy: 0.5, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.typingFirstLineHeadIndent, rounded(blockCase.expected.firstLineHeadIndent), accuracy: 0.5, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.typingHeadIndent, rounded(blockCase.expected.headIndent), accuracy: 0.5, "\(history) / \(blockCase.name)")
                XCTAssertEqual(snapshot.typingHasListItemAttribute, blockCase.expected.allowsListAttribute, "\(history) / \(blockCase.name)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: blockCase.expected.font,
                    context: "\(history) / \(blockCase.name) marked text"
                )
                assertSelectionAndCaretAreHealthy("\(history) / \(blockCase.name) marked text")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, histories.count * blockCases.count)
    }

    func testAutocorrectReplacementMatrixTargetsNativeRangeWithoutJumpingBlocks() throws {
        let document = "# Hdre title\n## Subtutle line\nBody hwre"
        let cases: [(misspelled: String, corrected: String, expectedLines: [String])] = [
            ("Hdre", "Here", ["Here title", "Subtutle line", "Body hwre"]),
            ("Subtutle", "Subtitle", ["Hdre title", "Subtitle line", "Body hwre"]),
            ("hwre", "here", ["Hdre title", "Subtutle line", "Body here"])
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document))
            markdownEditor.textView.layoutIfNeeded()

            let visibleText = markdownEditor.textView.text as NSString
            let range = visibleText.range(of: testCase.misspelled)
            XCTAssertNotEqual(range.location, NSNotFound, testCase.misspelled)

            let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
            textStorage.replaceCharacters(in: range, with: NSAttributedString(string: testCase.corrected))

            for line in testCase.expectedLines {
                XCTAssertTrue(markdownEditor.textView.text.contains(line), "\(testCase.misspelled) -> \(testCase.corrected) should leave \(line.debugDescription)")
            }
            assertSelectionAndCaretAreHealthy("\(testCase.misspelled) autocorrect")
        }
    }

    func testAutocorrectStyleReplacementPreservesBlockStateAfterListDerivedHistories() throws {
        let cases: [(name: String, markdown: String, target: String, replacement: String, expectedBlock: NodeType, expectedFont: UIFont)] = [
            (
                "h1-after-list",
                "- item\n# Hdre title\nBody",
                "Hdre",
                "Here",
                .heading,
                MarkdownEditorConfiguration.default.theme.typography.h1
            ),
            (
                "h2-after-list",
                "- item\n## Subtutle line\nBody",
                "Subtutle",
                "Subtitle",
                .heading,
                MarkdownEditorConfiguration.default.theme.typography.h2
            ),
            (
                "paragraph-after-list",
                "- item\nBody hwre",
                "hwre",
                "here",
                .paragraph,
                MarkdownEditorConfiguration.default.theme.typography.body
            )
        ]

        let replacementPaths: [(name: String, apply: (NSRange, String) throws -> Void)] = [
            ("text-storage", { range, replacement in
                let textStorage = try XCTUnwrap(self.markdownEditor.textView.textStorage as? TextStorage)
                textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacement))
            }),
            ("text-input-replace", { range, replacement in
                self.markdownEditor.textView.selectedRange = range
                let selectedTextRange = try XCTUnwrap(self.markdownEditor.textView.selectedTextRange)
                self.markdownEditor.textView.replace(selectedTextRange, withText: replacement)
            })
        ]

        for testCase in cases {
            for path in replacementPaths {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
                markdownEditor.textView.layoutIfNeeded()

                let visibleText = markdownEditor.textView.text as NSString
                let range = visibleText.range(of: testCase.target)
                XCTAssertNotEqual(range.location, NSNotFound, "\(testCase.name) / \(path.name)")

                try path.apply(range, testCase.replacement)
                syncNativeSelectionFromLexical()
                markdownEditor.textView.layoutIfNeeded()

                XCTAssertEqual(activeRootChildType(), testCase.expectedBlock, "\(testCase.name) / \(path.name)")
                XCTAssertTrue(markdownEditor.textView.text.contains(testCase.replacement), "\(testCase.name) / \(path.name)")
                XCTAssertEqual(currentCaretRect().height, testCase.expectedFont.lineHeight, accuracy: 1.0, "\(testCase.name) / \(path.name)")
                XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, 0, accuracy: 0.5, "\(testCase.name) / \(path.name)")
                XCTAssertEqual(caretParagraphStyle()?.headIndent ?? 0, 0, accuracy: 0.5, "\(testCase.name) / \(path.name)")
                XCTAssertNil(caretListItemAttribute(), "\(testCase.name) / \(path.name)")
                assertTypingAttributesMatchCaretAttributes("\(testCase.name) / \(path.name)")
                assertSelectionAndCaretAreHealthy("\(testCase.name) / \(path.name)")
            }
        }
    }

    func testNativeFullLineBackspaceAfterTripleTapStyleSelectionDoesNotCrash() throws {
        let cases: [(name: String, markdown: String, line: String)] = [
            ("top-heading", "# Selected heading\nTrailing paragraph", "Selected heading"),
            ("embedded-heading", "Intro paragraph\n## Selected subtitle\nTrailing paragraph", "Selected subtitle"),
            ("paragraph", "# Title\nSelected paragraph\nTrailing paragraph", "Selected paragraph"),
            ("unordered-list-item", "- Selected bullet\n- Trailing bullet", "Selected bullet"),
            ("ordered-list-item", "1. Selected number\n2. Trailing number", "Selected number"),
            ("quote", "> Selected quote\nTrailing paragraph", "Selected quote"),
            ("code-line", "```swift\nlet selected = true\nlet trailing = true\n```", "let selected = true"),
            ("link-text", "[Selected link](https://example.com)\nTrailing paragraph", "Selected link")
        ]

        let selectionShapes: [(name: String, includeTrailingLineBreak: Bool)] = [
            ("content-only", false),
            ("triple-tap-line-with-break", true)
        ]
        let propagationModes: [(name: String, mode: NativeSelectionPropagation)] = [
            ("native-range-only", .nativeRangeOnly),
            ("delegate-selection-change", .delegateSelectionChange),
            ("direct-lexical-selection", .directLexicalSelection)
        ]
        let deletionActions: [(name: String, action: () throws -> Void)] = [
            ("deleteBackward", { self.markdownEditor.textView.deleteBackward() }),
            ("replace-selected-text-range", {
                let selectedTextRange = try XCTUnwrap(self.markdownEditor.textView.selectedTextRange)
                self.markdownEditor.textView.replace(selectedTextRange, withText: "")
            }),
            ("text-storage-replace", {
                let range = self.markdownEditor.textView.selectedRange
                let textStorage = try XCTUnwrap(self.markdownEditor.textView.textStorage as? TextStorage)
                textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
            })
        ]

        for testCase in cases {
            for shape in selectionShapes {
                for propagation in propagationModes {
                    for deletion in deletionActions {
                        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
                        try selectNativeVisualLine(
                            containing: testCase.line,
                            includeTrailingLineBreak: shape.includeTrailingLineBreak,
                            propagation: propagation.mode
                        )

                        XCTAssertNoThrow(
                            try deletion.action(),
                            "\(testCase.name) / \(shape.name) / \(propagation.name) / \(deletion.name) should delete without crashing"
                        )
                        syncNativeSelectionFromLexical()
                        markdownEditor.textView.layoutIfNeeded()
                        assertSelectionAndCaretAreHealthy("\(testCase.name) / \(shape.name) / \(propagation.name) / \(deletion.name) selected line delete")
                    }
                }
            }
        }
    }

    func testExactTrailingBodyLineTripleTapBackspaceAfterTitleDoesNotCrash() throws {
        let deletionActions: [(name: String, action: () throws -> Void)] = [
            ("deleteBackward", { self.markdownEditor.textView.deleteBackward() }),
            ("replace-selected-text-range", {
                let selectedTextRange = try XCTUnwrap(self.markdownEditor.textView.selectedTextRange)
                self.markdownEditor.textView.replace(selectedTextRange, withText: "")
            })
        ]

        for deletion in deletionActions {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(.heading(level: .h1))
            typeText("Title")
            typeText("\n")
            typeText("a few words")

            try selectNativeVisualLine(
                containing: "a few words",
                includeTrailingLineBreak: false,
                propagation: .nativeRangeOnly
            )
            XCTAssertEqual(markdownEditor.textView.selectedRange.length, "a few words".utf16.count, deletion.name)

            XCTAssertNoThrow(try deletion.action(), "\(deletion.name) should delete a triple-tapped trailing body line without crashing")
            syncNativeSelectionFromLexical()
            markdownEditor.textView.layoutIfNeeded()
            assertSelectionAndCaretAreHealthy("exact trailing body line triple tap \(deletion.name)")
        }
    }

    func testNativeBackspaceAfterSelectingOnlyRenderedLineDoesNotCrash() throws {
        let cases: [(name: String, markdown: String, selectedText: String)] = [
            ("single-heading", "# Only heading", "Only heading"),
            ("single-h2", "## Only subtitle", "Only subtitle"),
            ("single-paragraph", "Only paragraph", "Only paragraph"),
            ("single-unordered-list", "- Only bullet", "Only bullet"),
            ("single-ordered-list", "1. Only number", "Only number"),
            ("single-quote", "> Only quote", "Only quote"),
            ("single-code-line", "```swift\nlet only = true\n```", "let only = true"),
            ("single-bold-line", "**Only bold**", "Only bold"),
            ("single-link-line", "[Only link](https://example.com)", "Only link")
        ]

        let selectionShapes: [(name: String, rangeFor: (NSString, NSRange) -> NSRange)] = [
            ("visible-text-only", { _, visibleRange in visibleRange }),
            ("entire-rendered-document", { text, _ in NSRange(location: 0, length: text.length) })
        ]
        let deletionActions: [(name: String, action: () throws -> Void)] = [
            ("deleteBackward", { self.markdownEditor.textView.deleteBackward() }),
            ("replace-selected-text-range", {
                let selectedTextRange = try XCTUnwrap(self.markdownEditor.textView.selectedTextRange)
                self.markdownEditor.textView.replace(selectedTextRange, withText: "")
            }),
            ("text-storage-replace", {
                let range = self.markdownEditor.textView.selectedRange
                let textStorage = try XCTUnwrap(self.markdownEditor.textView.textStorage as? TextStorage)
                textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
            })
        ]

        for testCase in cases {
            for shape in selectionShapes {
                for deletion in deletionActions {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
                    markdownEditor.layoutIfNeeded()
                    markdownEditor.textView.layoutIfNeeded()

                    let text = markdownEditor.textView.text as NSString
                    let visibleRange = text.range(of: testCase.selectedText)
                    XCTAssertNotEqual(visibleRange.location, NSNotFound, "\(testCase.name) / \(shape.name) / \(deletion.name)")
                    markdownEditor.textView.selectedRange = shape.rangeFor(text, visibleRange)

                    XCTAssertNoThrow(
                        try deletion.action(),
                        "\(testCase.name) / \(shape.name) / \(deletion.name) should delete without crashing"
                    )
                    syncNativeSelectionFromLexical()
                    markdownEditor.textView.layoutIfNeeded()
                    assertSelectionAndCaretAreHealthy("\(testCase.name) / \(shape.name) / \(deletion.name) only line delete")
                }
            }
        }
    }

    func testNativeBackspaceDoesNotCrashForEverySelectionRangeInShortRenderedDocuments() throws {
        let documents: [(name: String, markdown: String)] = [
            ("heading-then-body", "# ABC\nDEF"),
            ("body-then-heading", "ABC\n## DEF"),
            ("unordered-list", "- ABC\n- DEF"),
            ("ordered-list", "1. ABC\n2. DEF"),
            ("quote-then-body", "> ABC\nDEF"),
            ("code-lines", "```swift\nABC\nDEF\n```"),
            ("formatted-inline", "**ABC**\n*DEF*"),
            ("link-then-body", "[ABC](https://example.com)\nDEF")
        ]

        for document in documents {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
            markdownEditor.layoutIfNeeded()
            markdownEditor.textView.layoutIfNeeded()
            let renderedLength = (markdownEditor.textView.text as NSString).length
            XCTAssertGreaterThan(renderedLength, 0, document.name)

            for location in 0..<renderedLength {
                for length in 1...(renderedLength - location) {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                    markdownEditor.layoutIfNeeded()
                    markdownEditor.textView.layoutIfNeeded()
                    markdownEditor.textView.selectedRange = NSRange(location: location, length: length)

                    XCTAssertNoThrow(
                        markdownEditor.textView.deleteBackward(),
                        "\(document.name) range=\(NSStringFromRange(NSRange(location: location, length: length))) text=\(markdownEditor.textView.text.debugDescription)"
                    )
                    syncNativeSelectionFromLexical()
                    markdownEditor.textView.layoutIfNeeded()
                    assertSelectionAndCaretAreHealthy("\(document.name) native range delete \(location)/\(length)")
                }
            }
        }
    }

    func testSelectingExistingEmptyEmbeddedHeadingCanonicalizesCaretAndPlaceholder() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), .h3)
        ]

        var exercised = 0
        for headingCase in headingCases {
            let contexts = ["top-before-paragraph", "after-paragraph", "between-paragraphs", "after-unordered-list", "between-lists"]

            for context in contexts {
                try loadEmptyHeadingFixture(tag: headingCase.tag, context: context)
                try selectFirstEmptyHeading(tag: headingCase.tag)
                editor.dispatchCommand(type: .selectionChange)
                syncNativeSelectionFromLexical()

                let signature = emptyLineRenderSignature()
                XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(context)")
                XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(context)")
                assertCanonicalSignature(signature, matches: headingCase.blockCase.expected, context: "\(headingCase.blockCase.name) / \(context)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: headingCase.blockCase.expected.font,
                    context: "\(headingCase.blockCase.name) / \(context)"
                )
                assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) existing empty \(context)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 5)
    }

    func testSelectingExistingEmptyHeadingDoesNotCreateUserVisibleUndoStep() throws {
        let h1 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" })

        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "Intro paragraph\n# Undo heading\nTrailing paragraph"))
        try selectText("Undo heading", offset: "Undo heading".utf16.count)
        deleteCharacters("Undo heading".utf16.count)

        try selectFirstEmptyHeading(tag: .h1)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexical()
        let selectedSnapshot = activeLineVisualSnapshot()
        assertCanonicalVisualSnapshot(selectedSnapshot, matches: h1.expected, context: "selected empty heading")

        markdownEditor.undo()
        let afterUndo = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content)

        XCTAssertTrue(afterUndo.contains("Undo heading"), "First undo should restore user text, not spend a step on selection canonicalization: \(afterUndo)")
        XCTAssertEqual(activeRootChildType(), .heading)
        assertSelectionAndCaretAreHealthy("undo after selection canonicalization")
    }

    func testSelectingExistingEmptyEmbeddedBlocksCanonicalizesAllSupportedNonListTypes() throws {
        let blockCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code"].contains($0.name)
        }
        let contexts = ["after-paragraph", "after-unordered-list", "between-paragraphs", "between-lists"]
        let anchorModes: [EmptyBlockAnchorMode] = [.noChildren, .invisibleTextAnchor]

        var exercised = 0
        for blockCase in blockCases {
            for context in contexts {
                for anchorMode in anchorModes {
                    try loadEmptyBlockFixture(blockCase: blockCase, context: context, anchorMode: anchorMode)
                    editor.dispatchCommand(type: .selectionChange)
                    syncNativeSelectionFromLexical()

                    let signature = emptyLineRenderSignature()
                    assertCanonicalSignature(
                        signature,
                        matches: blockCase.expected,
                        context: "\(blockCase.name) / \(context) / \(anchorMode)"
                    )
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: blockCase.expected.font,
                        context: "\(blockCase.name) / \(context) / \(anchorMode)"
                    )
                    assertSelectionAndCaretAreHealthy("\(blockCase.name) / \(context) / \(anchorMode)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, blockCases.count * contexts.count * anchorModes.count)
    }

    func testNativeCaretSelectionOnExistingEmptyEmbeddedBlocksCanonicalizesGeometry() throws {
        let blockCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "h3", "h4", "h5", "h6", "quote", "code"].contains($0.name)
        }
        let contexts = ["after-paragraph", "after-unordered-list", "between-paragraphs", "between-lists"]

        var exercised = 0
        for blockCase in blockCases {
            try loadEmptyBlockFixture(blockCase: blockCase, context: "after-paragraph", anchorMode: .invisibleTextAnchor)
            try moveNativeCaretToFirstInvisibleAnchor()
            let referenceVisual = activeLineVisualSnapshot()
            let referenceStructural = activeLineStructuralSignature()
            assertCanonicalVisualSnapshot(referenceVisual, matches: blockCase.expected, context: "\(blockCase.name) native empty reference")

            for context in contexts {
                try loadEmptyBlockFixture(blockCase: blockCase, context: context, anchorMode: .invisibleTextAnchor)
                try moveNativeCaretToFirstInvisibleAnchor()

                let visual = activeLineVisualSnapshot()
                let structural = activeLineStructuralSignature()
                assertCanonicalVisualSnapshot(visual, matches: blockCase.expected, context: "\(blockCase.name) / native empty \(context)")
                assertActiveLineSnapshot(visual, matches: referenceVisual, context: "\(blockCase.name) / native empty \(context)")
                XCTAssertEqual(structural, referenceStructural, "\(blockCase.name) / native empty \(context)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: blockCase.expected.font,
                    context: "\(blockCase.name) / native empty \(context)"
                )
                assertSelectionAndCaretAreHealthy("\(blockCase.name) native empty \(context)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, blockCases.count * contexts.count)
    }

    func testSelectionChangeCanonicalizationImmediatelyUpdatesNativeCaretGeometry() throws {
        let blockCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code"].contains($0.name)
        }
        let contexts = ["after-paragraph", "after-unordered-list", "between-paragraphs", "between-lists"]

        var exercised = 0
        for blockCase in blockCases {
            for context in contexts {
                try loadEmptyBlockFixture(blockCase: blockCase, context: context, anchorMode: .noChildren)

                editor.dispatchCommand(type: .selectionChange)

                let immediate = rawCaretRect()
                let paragraphStyle = caretParagraphStyle()
                XCTAssertEqual(immediate.height, blockCase.expected.font.lineHeight, accuracy: 1.0, "\(blockCase.name) / \(context)")
                XCTAssertEqual(paragraphStyle?.firstLineHeadIndent ?? 0, blockCase.expected.firstLineHeadIndent, accuracy: 0.5, "\(blockCase.name) / \(context)")
                XCTAssertEqual(paragraphStyle?.headIndent ?? 0, blockCase.expected.headIndent, accuracy: 0.5, "\(blockCase.name) / \(context)")
                XCTAssertGreaterThanOrEqual(immediate.minX, -1, "\(blockCase.name) / \(context) should not flash off the left edge")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: blockCase.expected.font,
                    context: "\(blockCase.name) / \(context)"
                )
                assertSelectionAndCaretAreHealthy("\(blockCase.name) / \(context) immediate selectionChange")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, blockCases.count * contexts.count)
    }
}
