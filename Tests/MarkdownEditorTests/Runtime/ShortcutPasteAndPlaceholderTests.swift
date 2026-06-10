/*
 * ShortcutPasteAndPlaceholderTests
 *
 * Markdown shortcuts, markdown paste parsing, placeholder font tracking, and
 * invisible caret-anchor canonicalization (the runtime-view vocabulary; the
 * node-type vocabulary home is MarkdownRegressionMatrixTests).
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class ShortcutPasteAndPlaceholderTests: MarkdownRuntimeTestCase {
    func testToolbarHeadingToggleAndPlaceholderMatrix() throws {
        let headingCases: [(name: String, block: MarkdownBlockType, tag: HeadingTagType, font: UIFont)] = [
            ("h1", .heading(level: .h1), .h1, MarkdownEditorConfiguration.default.theme.typography.h1),
            ("h2", .heading(level: .h2), .h2, MarkdownEditorConfiguration.default.theme.typography.h2),
            ("h3", .heading(level: .h3), .h3, MarkdownEditorConfiguration.default.theme.typography.h3),
            ("h4", .heading(level: .h4), .h4, MarkdownEditorConfiguration.default.theme.typography.h4),
            ("h5", .heading(level: .h5), .h5, MarkdownEditorConfiguration.default.theme.typography.h5),
            ("h6", .heading(level: .h6), .h5, MarkdownEditorConfiguration.default.theme.typography.h5)
        ]

        for testCase in headingCases {
            try resetToEmptyParagraph()

            markdownEditor.setBlockType(testCase.block)
            XCTAssertEqual(firstHeadingTag(), testCase.tag, testCase.name)
            XCTAssertEqual(try XCTUnwrap(markdownEditor.textView.font?.pointSize), testCase.font.pointSize, accuracy: 0.5, testCase.name)
            XCTAssertEqual(try XCTUnwrap(placeholderLabel()?.font.pointSize), testCase.font.pointSize, accuracy: 0.5, "\(testCase.name) placeholder label")
            assertSelectionAndCaretAreHealthy(testCase.name)

            markdownEditor.setBlockType(testCase.block)
            XCTAssertEqual(firstTopLevelType(), .paragraph, "toggling \(testCase.name) should return to paragraph")
            XCTAssertEqual(
                try XCTUnwrap(markdownEditor.textView.font?.pointSize),
                MarkdownEditorConfiguration.default.theme.typography.body.pointSize,
                accuracy: 0.5,
                "placeholder font should reset after toggling \(testCase.name) off"
            )
            XCTAssertEqual(
                try XCTUnwrap(placeholderLabel()?.font.pointSize),
                MarkdownEditorConfiguration.default.theme.typography.body.pointSize,
                accuracy: 0.5,
                "placeholder label font should reset after toggling \(testCase.name) off"
            )
            assertSelectionAndCaretAreHealthy("toggle-off \(testCase.name)")
        }
    }

    func testPlaceholderLabelFontTracksEmptyBlockAcrossHistories() throws {
        let cases = canonicalBlockCases.filter { ["paragraph", "h1", "h2", "h3", "h4", "h5", "h6"].contains($0.name) }

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in cases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)

                let label = try XCTUnwrap(placeholderLabel(), "\(history) / \(testCase.name)")
                XCTAssertEqual(label.text, "Write something", "\(history) / \(testCase.name)")
                if visibleDocumentText().isEmpty {
                    XCTAssertFalse(label.isHidden, "\(history) / \(testCase.name)")
                    XCTAssertEqual(label.font.pointSize, testCase.expected.font.pointSize, accuracy: 0.5, "\(history) / \(testCase.name)")
                } else {
                    XCTAssertTrue(label.isHidden, "\(history) / \(testCase.name)")
                }
                assertSelectionAndCaretAreHealthy("\(history) / \(testCase.name) placeholder")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * cases.count)
    }

    func testPlaceholderLabelFontTracksEmptyHeadingShortcutAndDeletion() throws {
        let font = MarkdownEditorConfiguration.default.theme.typography.h1

        try resetToEmptyParagraph()
        typeText("#")
        typeText(" ")
        assertVisiblePlaceholderFont(font, "empty h1 shortcut")

        typeText("Title")
        XCTAssertTrue(try XCTUnwrap(placeholderLabel()).isHidden, "placeholder should hide once heading has content")

        deleteCharacters("Title".utf16.count)
        assertVisiblePlaceholderFont(font, "deleted h1 shortcut")

        try resetToEmptyParagraph()
        markdownEditor.setBlockType(.heading(level: .h1))
        assertVisiblePlaceholderFont(font, "empty h1 toolbar")

        typeText("Title")
        deleteCharacters("Title".utf16.count)
        assertVisiblePlaceholderFont(font, "deleted h1 toolbar")
    }

    func testInvisibleTextAnchorsBehaveLikeEmptyTextForPlaceholderShortcutsAndCaret() throws {
        let blockCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for testCase in blockCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(testCase.block)
            XCTAssertEqual(activeRootChildTextContent(), "", testCase.name)

            if visibleDocumentText().isEmpty {
                XCTAssertFalse(try XCTUnwrap(placeholderLabel(), testCase.name).isHidden, "\(testCase.name) placeholder")
            }
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: testCase.expected.font, context: "\(testCase.name) invisible anchor")
            assertSelectionAndCaretAreHealthy("\(testCase.name) invisible anchor")
            exercised += 1
        }

        try resetToEmptyParagraph()
        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("#")
        typeText(" ")
        XCTAssertEqual(activeRootChildType(), .heading)
        XCTAssertEqual(firstHeadingTag(inActiveBlock: true), .h1)
        XCTAssertEqual(activeRootChildTextContent(), "# ", "shortcut text should be literal inside existing heading, not re-trigger")
        exercised += 1

        try resetToEmptyParagraph()
        markdownEditor.setBlockType(.paragraph)
        typeText("#")
        typeText(" ")
        XCTAssertEqual(activeRootChildType(), .heading)
        XCTAssertEqual(firstHeadingTag(inActiveBlock: true), .h1)
        XCTAssertEqual(activeRootChildTextContent(), "")
        assertVisiblePlaceholderFont(MarkdownEditorConfiguration.default.theme.typography.h1, "paragraph zwsp heading shortcut")
        exercised += 1

        XCTAssertEqual(exercised, blockCases.count + 2)
    }

    func testInvisibleOnlyParagraphsCanonicalizeLikeEmptyParagraphsAcrossTransformPaths() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let shortcutByName = [
            "h1": "#",
            "h2": "##",
            "h3": "###",
            "h4": "####",
            "h5": "#####",
            "h6": "######"
        ]
        let invisibleCases: [(name: String, text: String)] = [
            ("zwsp", "\u{200B}"),
            ("zwnj", "\u{200C}"),
            ("zwj", "\u{200D}"),
            ("word-joiner", "\u{2060}"),
            ("bom", "\u{FEFF}"),
            ("mixed", "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
        ]
        let origins: [(name: String, prepare: (String) throws -> Void)] = [
            ("clean", { text in
                try self.loadInvisibleOnlyParagraph(text, afterList: false)
            }),
            ("after-list", { text in
                try self.loadInvisibleOnlyParagraph(text, afterList: true)
            })
        ]

        var exercised = 0
        for invisible in invisibleCases {
            for origin in origins {
                try origin.prepare(invisible.text)
                editor.dispatchCommand(type: .updatePlaceholderVisibility)
                if origin.name == "clean" {
                    assertVisiblePlaceholderFont(paragraph.expected.font, "\(origin.name) / \(invisible.name) initial placeholder")
                } else {
                    XCTAssertTrue(try XCTUnwrap(placeholderLabel()).isHidden, "\(origin.name) / \(invisible.name) should hide placeholder because previous content exists")
                }

                for heading in headingCases {
                    try origin.prepare(invisible.text)
                    markdownEditor.setBlockType(heading.block)
                    let headingSnapshot = activeLineVisualSnapshot()
                    assertCanonicalVisualSnapshot(
                        headingSnapshot,
                        matches: heading.expected,
                        context: "\(origin.name) / \(invisible.name) / \(heading.name) toolbar heading"
                    )
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(origin.name) / \(invisible.name) / \(heading.name) toolbar heading"
                    )

                    try origin.prepare(invisible.text)
                    typeText(try XCTUnwrap(shortcutByName[heading.name]))
                    typeText(" ")
                    let shortcutSnapshot = activeLineVisualSnapshot()
                    assertCanonicalVisualSnapshot(
                        shortcutSnapshot,
                        matches: heading.expected,
                        context: "\(origin.name) / \(invisible.name) / \(heading.name) shortcut heading"
                    )
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(origin.name) / \(invisible.name) / \(heading.name) shortcut heading"
                    )
                    exercised += 2
                }

                try origin.prepare(invisible.text)
                typeText("Body")
                deleteCharacters("Body".utf16.count)
                let paragraphSnapshot = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(
                    paragraphSnapshot,
                    matches: paragraph.expected,
                    context: "\(origin.name) / \(invisible.name) typing cleanup"
                )
                XCTAssertEqual(activeLineStructuralSignature().textLeafContents, ["\u{200B}"], "\(origin.name) / \(invisible.name) should collapse to one canonical anchor")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, invisibleCases.count * origins.count * ((headingCases.count * 2) + 1))
    }

    func testInvisibleCanonicalizationDoesNotStripJoinersFromVisibleEmojiContent() throws {
        try resetToEmptyParagraph()

        let emoji = "👩🏽‍💻"
        typeText(emoji)
        typeText("!")

        XCTAssertEqual(activeRootChildTextContent(), "\(emoji)!")
        XCTAssertTrue(markdownEditor.textView.text.contains("\(emoji)!"))
        XCTAssertEqual(markdownEditor.exportMarkdown().value?.content, "\(emoji)!")
        assertSelectionAndCaretAreHealthy("emoji zwj content")
    }

    func testGeneratedMarkdownShortcutMatrixForHeadingsListsAndFalsePositives() throws {
        let headingShortcuts: [(marker: String, tag: HeadingTagType, font: UIFont)] = [
            ("#", .h1, MarkdownEditorConfiguration.default.theme.typography.h1),
            ("##", .h2, MarkdownEditorConfiguration.default.theme.typography.h2),
            ("###", .h3, MarkdownEditorConfiguration.default.theme.typography.h3),
            ("####", .h4, MarkdownEditorConfiguration.default.theme.typography.h4),
            ("#####", .h5, MarkdownEditorConfiguration.default.theme.typography.h5),
            ("######", .h5, MarkdownEditorConfiguration.default.theme.typography.h5)
        ]

        for testCase in headingShortcuts {
            try resetToEmptyParagraph()

            typeText(testCase.marker)
            typeText(" ")

            XCTAssertEqual(firstTopLevelType(), .heading, "\(testCase.marker) should create heading")
            XCTAssertEqual(firstHeadingTag(), testCase.tag, "\(testCase.marker) should create expected heading level")
            XCTAssertEqual(try XCTUnwrap(markdownEditor.textView.font?.pointSize), testCase.font.pointSize, accuracy: 0.5, testCase.marker)
            assertSelectionAndCaretAreHealthy(testCase.marker)

            typeText("Title")
            XCTAssertEqual(firstTextContent(), "Title", "\(testCase.marker) typed text")
        }

        let listShortcuts: [(marker: String, expectedListType: ListType)] = [
            ("-", .bullet),
            ("*", .bullet),
            ("+", .bullet),
            ("1.", .number),
            ("01.", .number),
            ("10.", .number),
            ("999.", .number)
        ]

        for testCase in listShortcuts {
            try resetToEmptyParagraph()

            typeText(testCase.marker)
            typeText(" ")

            XCTAssertEqual(firstTopLevelType(), .list, "\(testCase.marker) should create list")
            XCTAssertEqual(firstListType(), testCase.expectedListType, "\(testCase.marker) list type")
            XCTAssertEqual(activeSelectionType(), .text, "\(testCase.marker) should leave a text caret anchor")
            assertSelectionAndCaretAreHealthy(testCase.marker)
        }

        let falsePositiveCases: [(name: String, initialMarkdown: String, typed: String, expectedText: String)] = [
            ("escaped heading", "", "\\# ", "\\# "),
            ("mid paragraph heading", "hello", "# ", "hello# "),
            ("heading needs space", "", "#x ", "#x "),
            ("overlong heading", "", "####### ", "####### "),
            ("escaped list", "", "\\- ", "\\- "),
            ("mid paragraph list", "hello", "- ", "hello- "),
            ("ordered missing dot", "", "1 ", "1 "),
            ("ordered alpha prefix", "", "a1. ", "a1. ")
        ]

        for testCase in falsePositiveCases {
            if testCase.initialMarkdown.isEmpty {
                try resetToEmptyParagraph()
            } else {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.initialMarkdown))
                try selectText(testCase.initialMarkdown, offset: testCase.initialMarkdown.count)
            }

            typeText(testCase.typed)

            XCTAssertEqual(firstTopLevelType(), .paragraph, testCase.name)
            XCTAssertEqual(firstTextContent(), testCase.expectedText, testCase.name)
            assertSelectionAndCaretAreHealthy(testCase.name)
        }
    }

    func testGeneratedMarkdownPasteMatrixParsesStructuredMarkdownInsteadOfRawText() throws {
        let payloads: [(name: String, markdown: String, expectedTypes: Set<NodeType>, expectedInline: Set<String>)] = [
            ("heading pair", "# Heading 1\n## Heading 2", [.heading], []),
            ("inline marks", "**bold** and *italic* and ***both*** and ~~gone~~ and `code`", [], ["bold", "italic", "code", "strike"]),
            ("unordered nested", "- bullet point\n- another one\n  - nested", [.list], []),
            ("ordered", "1. numbered\n2. list", [.list], []),
            ("link", "[link text](https://example.com)", [], ["link"]),
            ("image as safe text", "![alt text](image.jpg)", [], []),
            ("code fence", "```python\ndef hello():\n    print(\"hi\")\n```", [.code], []),
            ("blockquote", "> blockquote", [.quote], []),
            ("table as safe paragraphs", "| col1 | col2 |\n|------|------|\n| a    | b    |", [.paragraph], []),
            ("horizontal rule safe", "---", [], []),
            ("task list", "- [ ] task list\n- [x] done", [.list], []),
            ("mixed user sample", userReportedPastePayload, [.heading, .list, .code, .quote, .paragraph], ["bold", "italic", "code", "strike", "link"])
        ]

        let destinations: [(name: String, prepare: () throws -> Void)] = [
            ("empty", { try self.resetToEmptyParagraph() }),
            ("after body", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "Before"))
                try self.selectText("Before", offset: 6)
            }),
            ("after title", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "# Before"))
                try self.selectText("Before", offset: 6)
            })
        ]

        var exercised = 0
        for destination in destinations {
            for payload in payloads {
                try destination.prepare()

                let pasteboard = UIPasteboard.withUniqueName()
                pasteboard.string = payload.markdown
                editor.dispatchCommand(type: .paste, payload: pasteboard)

                let inspection = inspectDocument()
                if !payload.expectedTypes.isEmpty {
                    XCTAssertTrue(payload.expectedTypes.isSubset(of: inspection.topLevelTypes), "\(destination.name) / \(payload.name)")
                }
                XCTAssertFalse(markdownEditor.textView.text.contains("# Heading 1"), "\(destination.name) / \(payload.name) should not show raw heading markers")
                XCTAssertFalse(markdownEditor.textView.text.contains("**bold**"), "\(destination.name) / \(payload.name) should not show raw bold markers")
                XCTAssertFalse(markdownEditor.textView.text.contains("```python"), "\(destination.name) / \(payload.name) should not show raw code fence")
                XCTAssertFalse(markdownEditor.exportMarkdown().value?.content.contains("\u{200B}") ?? true, "\(destination.name) / \(payload.name)")

                XCTAssertTrue(payload.expectedInline.subtracting(inspection.inlineTraits).isEmpty, "\(destination.name) / \(payload.name)")
                assertSelectionAndCaretAreHealthy("\(destination.name) / \(payload.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, destinations.count * payloads.count)
    }
}
