import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class MarkdownEditorRuntimeBehaviorMatrixTests: MarkdownTestCase {
    override func setUp() {
        super.setUp()
        markdownEditor = MarkdownEditorView(configuration: .init(behavior: .init(
            autoSave: false,
            autoCorrection: false,
            smartQuotes: false,
            returnKeyBehavior: .smart,
            startWithTitle: false
        )))
        markdownEditor.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        markdownEditor.placeholderText = "Write something"
        markdownEditor.layoutIfNeeded()
    }

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

    func testLoadedAndInitialEmptyDocumentsAreCanonicalParagraphStates() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })

        let initialSnapshot = activeLineVisualSnapshot()
        assertCanonicalVisualSnapshot(initialSnapshot, matches: paragraph.expected, context: "initial empty")
        assertVisiblePlaceholderFont(MarkdownEditorConfiguration.default.theme.typography.body, "initial empty")

        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: ""))
        syncNativeSelectionFromLexical()

        let loadedSnapshot = activeLineVisualSnapshot()
        assertCanonicalVisualSnapshot(loadedSnapshot, matches: paragraph.expected, context: "loaded empty")
        assertActiveLineSnapshot(loadedSnapshot, matches: initialSnapshot, context: "loaded empty")
        assertVisiblePlaceholderFont(MarkdownEditorConfiguration.default.theme.typography.body, "loaded empty")
    }

    func testGeneratedFormattingEntryPathsKeepPlaceholdersAndSelectionsConsistent() throws {
        let blockCases: [(name: String, block: MarkdownBlockType, expectedType: NodeType, expectedFont: UIFont)] = [
            ("paragraph", .paragraph, .paragraph, MarkdownEditorConfiguration.default.theme.typography.body),
            ("title", .heading(level: .h1), .heading, MarkdownEditorConfiguration.default.theme.typography.h1),
            ("subtitle", .heading(level: .h2), .heading, MarkdownEditorConfiguration.default.theme.typography.h2),
            ("quote", .quote, .quote, MarkdownEditorConfiguration.default.theme.typography.body),
            ("code", .codeBlock, .code, MarkdownEditorConfiguration.default.theme.typography.code)
        ]

        var exercised = 0
        for entryPath in EntryPath.allCases {
            for blockCase in blockCases {
                try prepareEmptyInsertionPoint(entryPath)

                markdownEditor.setBlockType(blockCase.block)

                XCTAssertEqual(activeRootChildType(), blockCase.expectedType, "\(entryPath) -> \(blockCase.name)")
                if case .heading(let level) = blockCase.block {
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), level.lexicalType, "\(entryPath) -> \(blockCase.name)")
                }
                if visibleDocumentText().isEmpty {
                    XCTAssertEqual(
                        try XCTUnwrap(markdownEditor.textView.font?.pointSize),
                        blockCase.expectedFont.pointSize,
                        accuracy: 0.5,
                        "\(entryPath) -> \(blockCase.name)"
                    )
                }
                assertSelectionAndCaretAreHealthy("\(entryPath) -> \(blockCase.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, EntryPath.allCases.count * blockCases.count)
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

    func testHeadingShortcutWorksFromEveryHistoryAndDoesNotRetainListGeometry() throws {
        let headingShortcuts: [(marker: String, tag: HeadingTagType, font: UIFont)] = [
            ("#", .h1, MarkdownEditorConfiguration.default.theme.typography.h1),
            ("##", .h2, MarkdownEditorConfiguration.default.theme.typography.h2),
            ("###", .h3, MarkdownEditorConfiguration.default.theme.typography.h3),
            ("####", .h4, MarkdownEditorConfiguration.default.theme.typography.h4),
            ("#####", .h5, MarkdownEditorConfiguration.default.theme.typography.h5),
            ("######", .h5, MarkdownEditorConfiguration.default.theme.typography.h5)
        ]

        var exercised = 0
        for history in HistoryPath.allCases {
            for shortcut in headingShortcuts {
                try prepareEmptyCanonicalLine(history)

                typeText(shortcut.marker)
                typeText(" ")

                XCTAssertEqual(activeRootChildType(), .heading, "\(history) / \(shortcut.marker)")
                XCTAssertEqual(firstHeadingTag(inActiveBlock: true), shortcut.tag, "\(history) / \(shortcut.marker)")
                XCTAssertNil(caretListItemAttribute(), "\(history) / \(shortcut.marker)")
                XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, 0, accuracy: 0.5, "\(history) / \(shortcut.marker)")
                XCTAssertEqual(currentCaretRect().height, shortcut.font.lineHeight, accuracy: 1.0, "\(history) / \(shortcut.marker)")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: shortcut.font, context: "\(history) / \(shortcut.marker)")

                typeText("Heading")
                XCTAssertEqual(activeRootChildTextContent(), "Heading", "\(history) / \(shortcut.marker)")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: shortcut.font, context: "\(history) / \(shortcut.marker) content")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * headingShortcuts.count)
    }

    func testGeneratedListEnterExitAndShortcutRegressionMatrix() throws {
        let listDocuments: [(name: String, markdown: String, search: String, offsets: [Int], expectedType: ListType)] = [
            ("dash", "- first", "first", [0, 2, 5], .bullet),
            ("star", "* first", "first", [0, 2, 5], .bullet),
            ("plus", "+ first", "first", [0, 2, 5], .bullet),
            ("ordered", "1. first", "first", [0, 2, 5], .number),
            ("ordered-ten", "10. first", "first", [0, 2, 5], .number),
            ("emoji", "- 👩🏽‍💻 coder", "coder", [0, 3, 5], .bullet),
            ("rtl", "- שלום", "שלום", [0, 2, 4], .bullet),
            ("cjk", "- 日本語", "日本語", [0, 2, 3], .bullet)
        ]

        var exercised = 0
        for testCase in listDocuments {
            for offset in testCase.offsets {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
                try selectText(testCase.search, offset: offset)

                typeText("\n")

                XCTAssertEqual(firstTopLevelType(), .list, "\(testCase.name) offset \(offset)")
                XCTAssertEqual(firstListType(), testCase.expectedType, "\(testCase.name) offset \(offset)")
                XCTAssertGreaterThanOrEqual(firstListChildCount(), 2, "\(testCase.name) offset \(offset)")
                assertSelectionAndCaretAreHealthy("\(testCase.name) offset \(offset)")
                exercised += 1
            }
        }

        let emptyListDocuments = ["- ", "* ", "+ ", "1. ", "10. "]
        for markdown in emptyListDocuments {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: markdown))

            typeText("\n")

            XCTAssertEqual(firstTopLevelType(), .paragraph, "\(markdown.debugDescription) should exit empty list")
            assertSelectionAndCaretAreHealthy("empty list exit \(markdown)")
            exercised += 1
        }

        XCTAssertGreaterThanOrEqual(exercised, 29)
    }

    func testToolbarListToggleOffThirdItemAfterHeadingDoesNotCrash() throws {
        let cases: [(name: String, block: MarkdownBlockType, expectedListType: ListType)] = [
            ("unordered", .unorderedList, .bullet),
            ("ordered", .orderedList, .number)
        ]
        let finalItemContents: [(name: String, text: String)] = [
            ("populated-third-item", "Three"),
            ("empty-third-item", "")
        ]

        for testCase in cases {
            for finalItem in finalItemContents {
                try resetToEmptyParagraph()
                markdownEditor.setBlockType(.heading(level: .h1))
                typeText("Title")
                typeText("\n")

                markdownEditor.setBlockType(testCase.block)
                typeText("One")
                typeText("\n")
                typeText("Two")
                typeText("\n")
                typeText(finalItem.text)

                let context = "\(testCase.name) / \(finalItem.name)"
                XCTAssertEqual(activeRootChildType(), .list, context)
                XCTAssertEqual(activeListType(), testCase.expectedListType, context)
                XCTAssertEqual(activeListChildCount(), 3, context)
                XCTAssertNoThrow(markdownEditor.setBlockType(testCase.block), "\(context) toolbar toggle should not crash")

                syncNativeSelectionFromLexical()
                markdownEditor.textView.layoutIfNeeded()
                XCTAssertNil(caretListItemAttribute(), "\(context) toggled-off third item should not keep list drawing")
                XCTAssertEqual(selectedBlockTextContent(), finalItem.text, context)
                assertSelectionAndCaretAreHealthy("\(context) third item toolbar toggle")
            }
        }
    }

    func testEnterAfterEmptyListItemExitsToBodyAlignedParagraphCaret() throws {
        try resetToEmptyParagraph()
        let baselineX = currentCaretRect().minX

        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        XCTAssertEqual(firstTopLevelType(), .list)

        typeText("\n")
        markdownEditor.textView.layoutIfNeeded()

        XCTAssertEqual(firstTopLevelType(), .paragraph)
        XCTAssertEqual(firstTextContent(), "")
        XCTAssertEqual(activeSelectionType(), .text, debugSelectionState())

        let exitedCaret = currentCaretRect()
        XCTAssertEqual(exitedCaret.minX, baselineX, accuracy: 1.5, "Paragraph after empty list exit should align with body text, not list indentation. \(debugSelectionState())")
        XCTAssertNil(caretListItemAttribute(), "Paragraph after empty list exit must not keep list item attributes")

        typeText("Body")
        XCTAssertEqual(firstTextContent(), "Body")

        markdownEditor.textView.deleteBackward()
        XCTAssertEqual(firstTextContent(), "Bod", "Backspace in exited paragraph should delete one character, not remove the whole line")
        XCTAssertEqual(firstTopLevelType(), .paragraph)
        assertSelectionAndCaretAreHealthy("empty list exit paragraph")
    }

    func testListExitIsCanonicalBeforeEveryFollowingBlockAction() throws {
        let followUps = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for followUp in followUps {
            try resetToEmptyParagraph()
            typeText("-")
            typeText(" ")
            typeText("Item")
            typeText("\n")
            typeText("\n")

            XCTAssertEqual(activeRootChildType(), .paragraph, followUp.name)
            XCTAssertNil(caretListItemAttribute(), followUp.name)
            XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, 0, accuracy: 0.5, followUp.name)
            XCTAssertEqual(caretParagraphStyle()?.headIndent ?? 0, 0, accuracy: 0.5, followUp.name)

            markdownEditor.setBlockType(followUp.block)
            typeText(followUp.text)
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: followUp.expected.font, context: "list exit -> \(followUp.name)")
            XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, followUp.expected.firstLineHeadIndent, accuracy: 0.5, followUp.name)
            XCTAssertEqual(caretParagraphStyle()?.headIndent ?? 0, followUp.expected.headIndent, accuracy: 0.5, followUp.name)
            if followUp.expected.allowsListAttribute {
                XCTAssertNotNil(caretListItemAttribute(), followUp.name)
            } else {
                XCTAssertNil(caretListItemAttribute(), followUp.name)
            }
            exercised += 1
        }

        XCTAssertEqual(exercised, followUps.count)
    }

    func testEnterOnEmptyLastListItemAfterDeletingFollowingParagraphExitsList() throws {
        try resetToEmptyParagraph()

        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph)

        typeText("Below")
        XCTAssertEqual(activeRootChildType(), .paragraph)

        deleteCharacters("Below".utf16.count)
        XCTAssertEqual(activeRootChildType(), .paragraph, "body line should be empty before merging back")

        markdownEditor.textView.deleteBackward()
        XCTAssertEqual(activeRootChildType(), .list, "backspace on empty paragraph below list should return to list")
        XCTAssertEqual(firstListChildCount(), 1, "merging back should not leave phantom empty list items")

        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .list, "enter at end of restored list item should create one empty list item")
        XCTAssertEqual(firstListChildCount(), 2)

        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph, "second enter on empty last list item should exit list")
        XCTAssertEqual(activeRootChildTextContent(), "")
        XCTAssertNil(caretListItemAttribute())
        XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, 0, accuracy: 0.5)
        assertSelectionAndCaretAreHealthy("delete below list then exit")
    }

    func testDeletingFollowingParagraphThenListExitIsHistoryIndependentAcrossListMarkers() throws {
        let cases: [(marker: String, expectedType: ListType)] = [
            ("-", .bullet),
            ("*", .bullet),
            ("+", .bullet),
            ("1.", .number),
            ("2.", .number),
            ("10.", .number)
        ]

        var exercised = 0
        for testCase in cases {
            try resetToEmptyParagraph()

            typeText(testCase.marker)
            typeText(" ")
            XCTAssertEqual(firstListType(), testCase.expectedType, testCase.marker)
            typeText("Item")
            typeText("\n")
            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.marker) initial list exit")

            typeText("Below")
            deleteCharacters("Below".utf16.count)
            markdownEditor.textView.deleteBackward()
            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.marker) should re-enter list after deleting following paragraph")
            XCTAssertEqual(firstListChildCount(), 1, "\(testCase.marker) should not keep a phantom empty item after re-entry")

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.marker) first enter should create an empty last item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(testCase.marker) empty item should have one caret anchor")

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.marker) second enter should exit list")
            XCTAssertEqual(activeRootChildTextContent(), "", "\(testCase.marker) exited paragraph should be visibly empty")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.marker) exited paragraph should not draw a list marker")
            XCTAssertEqual(caretParagraphStyle()?.firstLineHeadIndent ?? 0, 0, accuracy: 0.5, "\(testCase.marker) exited paragraph should not keep list indentation")

            typeText("Body")
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.marker) follow-up typing should stay paragraph")
            XCTAssertEqual(activeRootChildTextContent(), "Body", "\(testCase.marker) follow-up text")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.marker) follow-up typing should not restore list attributes")
            assertSelectionAndCaretAreHealthy("\(testCase.marker) delete below list then exit")
            exercised += 1
        }

        XCTAssertEqual(exercised, cases.count)
    }

    func testEquivalentEmptyHeadingStatesHaveIdenticalActiveLineVisualSnapshots() throws {
        let h1 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" })
        let paths: [(name: String, prepare: () throws -> Void)] = [
            ("direct-toolbar-empty", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("direct-toolbar-type-delete", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("direct-shortcut-empty", {
                try self.resetToEmptyParagraph()
                self.typeText("#")
                self.typeText(" ")
            }),
            ("direct-shortcut-type-delete", {
                try self.resetToEmptyParagraph()
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("after-list-exit-toolbar-empty", {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("after-list-exit-toolbar-type-delete", {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("after-list-exit-shortcut-empty", {
                try self.prepareAfterListExit()
                self.typeText("#")
                self.typeText(" ")
            }),
            ("after-list-exit-shortcut-type-delete", {
                try self.prepareAfterListExit()
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("after-paste-enter-toolbar-type-delete", {
                try self.prepareEmptyCanonicalLine(.afterPasteEnter)
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("after-code-enter-toolbar-type-delete", {
                try self.prepareEmptyCanonicalLine(.afterCodeEnter)
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            })
        ]

        var reference: ActiveLineVisualSnapshot?
        for path in paths {
            try path.prepare()
            let snapshot = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(snapshot, matches: h1.expected, context: path.name)

            if path.name == "direct-toolbar-empty" {
                reference = snapshot
            } else {
                let reference = try XCTUnwrap(reference, path.name)
                assertActiveLineSnapshot(snapshot, matches: reference, context: path.name)
            }
        }

        XCTAssertEqual(paths.count, 10)
    }

    func testEquivalentEmptyParagraphStatesHaveIdenticalActiveLineVisualSnapshots() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let paths: [(name: String, prepare: () throws -> Void)] = [
            ("direct-empty", {
                try self.resetToEmptyParagraph()
            }),
            ("direct-type-delete", {
                try self.resetToEmptyParagraph()
                self.typeText("Body")
                self.deleteCharacters("Body".utf16.count)
            }),
            ("after-list-exit", {
                try self.prepareAfterListExit()
            }),
            ("after-list-exit-type-delete", {
                try self.prepareAfterListExit()
                self.typeText("Body")
                self.deleteCharacters("Body".utf16.count)
            }),
            ("after-list-exit-heading-toggle-off", {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("after-heading-enter", {
                try self.prepareEmptyCanonicalLine(.afterHeadingEnter)
            }),
            ("after-paste-enter", {
                try self.prepareEmptyCanonicalLine(.afterPasteEnter)
            })
        ]

        var reference: ActiveLineVisualSnapshot?
        for path in paths {
            try path.prepare()
            let snapshot = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(snapshot, matches: paragraph.expected, context: path.name)

            if path.name == "direct-empty" {
                reference = snapshot
            } else {
                let reference = try XCTUnwrap(reference, path.name)
                assertActiveLineSnapshot(snapshot, matches: reference, context: path.name)
            }
        }

        XCTAssertEqual(paths.count, 7)
    }

    func testComplexHistoriesConvergeToIdenticalEmptyParagraphAndHeadingRenderStates() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let h1 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" })
        let h2 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" })

        let paragraphOrigins: [(name: String, prepare: () throws -> Void)] = [
            ("clean", {
                try self.resetToEmptyParagraph()
            }),
            ("typed-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("toolbar-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("ordered-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.typeText("1.")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("delete-following-heading-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("list-exit-heading-toggle-off", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.markdownEditor.setBlockType(.heading(level: .h1))
            })
        ]

        let headingOrigins: [(name: String, block: CanonicalBlockCase, prepare: () throws -> Void)] = [
            ("clean-toolbar-h1-empty", h1, {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("clean-toolbar-h1-type-delete", h1, {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("list-exit-toolbar-h1-empty", h1, {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("list-exit-toolbar-h1-type-delete", h1, {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("deleted-following-paragraph-exit-toolbar-h1-type-delete", h1, {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("toolbar-list-exit-toolbar-h1-type-delete", h1, {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("imported-list-delete-following-paragraph-h1-type-delete", h1, {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("list-exit-shortcut-h1-empty", h1, {
                try self.prepareAfterListExit()
                self.typeText("#")
                self.typeText(" ")
            }),
            ("list-exit-shortcut-h1-type-delete", h1, {
                try self.prepareAfterListExit()
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("list-exit-toolbar-h2-type-delete", h2, {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h2))
                self.typeText("Subtitle")
                self.deleteCharacters("Subtitle".utf16.count)
            }),
            ("list-exit-shortcut-h2-type-delete", h2, {
                try self.prepareAfterListExit()
                self.typeText("##")
                self.typeText(" ")
                self.typeText("Subtitle")
                self.deleteCharacters("Subtitle".utf16.count)
            })
        ]

        var paragraphReference: ActiveLineVisualSnapshot?
        for origin in paragraphOrigins {
            try origin.prepare()
            let snapshot = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(snapshot, matches: paragraph.expected, context: origin.name)
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: paragraph.expected.font, context: origin.name)

            if paragraphReference == nil {
                paragraphReference = snapshot
            } else {
                assertActiveLineSnapshot(snapshot, matches: try XCTUnwrap(paragraphReference), context: origin.name)
            }
        }

        var headingReferences: [String: ActiveLineVisualSnapshot] = [:]
        for origin in headingOrigins {
            try origin.prepare()
            let snapshot = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(snapshot, matches: origin.block.expected, context: origin.name)
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: origin.block.expected.font, context: origin.name)

            if let reference = headingReferences[origin.block.name] {
                assertActiveLineSnapshot(snapshot, matches: reference, context: origin.name)
            } else {
                headingReferences[origin.block.name] = snapshot
            }
        }

        XCTAssertEqual(paragraphOrigins.count, 8)
        XCTAssertEqual(headingOrigins.count, 11)
    }

    func testEveryHeadingLevelTypeDeleteConvergesAcrossComplexOrigins() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let shortcutByName = [
            "h1": "#",
            "h2": "##",
            "h3": "###",
            "h4": "####",
            "h5": "#####",
            "h6": "######"
        ]

        let origins: [(name: String, prepare: (CanonicalBlockCase) throws -> Void)] = [
            ("clean-toolbar-empty", { blockCase in
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("clean-toolbar-type-delete", { blockCase in
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("list-exit-toolbar-empty", { blockCase in
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("list-exit-toolbar-type-delete", { blockCase in
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("deleted-following-paragraph-exit-toolbar-type-delete", { blockCase in
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("toolbar-list-exit-toolbar-type-delete", { blockCase in
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("imported-list-delete-following-paragraph-toolbar-type-delete", { blockCase in
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("list-exit-shortcut-empty", { blockCase in
                try self.prepareAfterListExit()
                self.typeText(try XCTUnwrap(shortcutByName[blockCase.name]))
                self.typeText(" ")
            }),
            ("list-exit-shortcut-type-delete", { blockCase in
                try self.prepareAfterListExit()
                self.typeText(try XCTUnwrap(shortcutByName[blockCase.name]))
                self.typeText(" ")
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            })
        ]

        var exercised = 0
        for blockCase in headingCases {
            var reference: ActiveLineVisualSnapshot?
            for origin in origins {
                try origin.prepare(blockCase)
                let snapshot = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(snapshot, matches: blockCase.expected, context: "\(blockCase.name) / \(origin.name)")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: blockCase.expected.font, context: "\(blockCase.name) / \(origin.name)")

                if let reference {
                    assertActiveLineSnapshot(snapshot, matches: reference, context: "\(blockCase.name) / \(origin.name)")
                } else {
                    reference = snapshot
                }
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * origins.count)
    }

    func testEveryHeadingLevelDeletionModeConvergesAcrossHistoryOrigins() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let shortcutByName = [
            "h1": "#",
            "h2": "##",
            "h3": "###",
            "h4": "####",
            "h5": "#####",
            "h6": "######"
        ]
        let origins: [(name: String, prepare: () throws -> Void)] = [
            ("clean", {
                try self.resetToEmptyParagraph()
            }),
            ("list-double-enter", {
                try self.prepareAfterListExit()
            }),
            ("toolbar-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]
        let creationModes: [(name: String, apply: (CanonicalBlockCase) throws -> Void)] = [
            ("toolbar", { blockCase in
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("shortcut", { blockCase in
                self.typeText(try XCTUnwrap(shortcutByName[blockCase.name]))
                self.typeText(" ")
            })
        ]
        let deletionModes: [(name: String, apply: (String) throws -> Void)] = [
            ("key-repeat", { text in
                self.deleteCharacters(text.utf16.count)
            }),
            ("selected-deleteBackward", { text in
                try self.selectNativeVisibleText(text)
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
                self.markdownEditor.textView.layoutIfNeeded()
            }),
            ("native-replacement", { text in
                try self.nativeReplaceVisibleText(text, with: "")
            })
        ]

        var references: [String: (visual: ActiveLineVisualSnapshot, structural: ActiveLineStructuralSignature)] = [:]
        var exercised = 0
        for heading in headingCases {
            for origin in origins {
                for creationMode in creationModes {
                    for deletionMode in deletionModes {
                        try origin.prepare()
                        try creationMode.apply(heading)

                        let text = "Delete \(heading.name)"
                        typeText(text)
                        try deletionMode.apply(text)

                        let visual = activeLineVisualSnapshot()
                        let structural = activeLineStructuralSignature()
                        assertCanonicalVisualSnapshot(
                            visual,
                            matches: heading.expected,
                            context: "\(heading.name) / \(origin.name) / \(creationMode.name) / \(deletionMode.name)"
                        )
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: heading.expected.font,
                            context: "\(heading.name) / \(origin.name) / \(creationMode.name) / \(deletionMode.name)"
                        )
                        XCTAssertEqual(structural.textLeafContents, ["\u{200B}"], "\(heading.name) / \(origin.name) / \(creationMode.name) / \(deletionMode.name)")

                        if let reference = references[heading.name] {
                            assertActiveLineSnapshot(
                                visual,
                                matches: reference.visual,
                                context: "\(heading.name) / \(origin.name) / \(creationMode.name) / \(deletionMode.name)"
                            )
                            XCTAssertEqual(structural, reference.structural, "\(heading.name) / \(origin.name) / \(creationMode.name) / \(deletionMode.name)")
                        } else {
                            references[heading.name] = (visual, structural)
                        }
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * origins.count * creationModes.count * deletionModes.count)
    }

    func testActiveLineStructuralSignaturesConvergeAcrossComplexOrigins() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let headingCases = canonicalBlockCases.filter { ["h1", "h2", "h3"].contains($0.name) }

        let paragraphOrigins: [(name: String, prepare: () throws -> Void)] = [
            ("clean-empty", {
                try self.resetToEmptyParagraph()
            }),
            ("type-delete", {
                try self.resetToEmptyParagraph()
                self.typeText("Body")
                self.deleteCharacters("Body".utf16.count)
            }),
            ("list-double-enter", {
                try self.prepareAfterListExit()
            }),
            ("list-double-enter-type-delete", {
                try self.prepareAfterListExit()
                self.typeText("Body")
                self.deleteCharacters("Body".utf16.count)
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]

        var paragraphReference: ActiveLineStructuralSignature?
        for origin in paragraphOrigins {
            try origin.prepare()
            assertCanonicalSignature(emptyLineRenderSignature(), matches: paragraph.expected, context: origin.name)
            let signature = activeLineStructuralSignature()
            if let paragraphReference {
                XCTAssertEqual(signature, paragraphReference, origin.name)
            } else {
                paragraphReference = signature
            }
        }

        let headingOrigins: [(name: String, prepare: (CanonicalBlockCase) throws -> Void)] = [
            ("toolbar-empty", { blockCase in
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("toolbar-type-delete", { blockCase in
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("list-exit-toolbar-empty", { blockCase in
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("list-exit-toolbar-type-delete", { blockCase in
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("delete-following-paragraph-exit-toolbar-type-delete", { blockCase in
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            }),
            ("imported-list-delete-following-paragraph-toolbar-type-delete", { blockCase in
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(blockCase.text)
                self.deleteCharacters(blockCase.text.utf16.count)
            })
        ]

        var exercised = paragraphOrigins.count
        for blockCase in headingCases {
            var reference: ActiveLineStructuralSignature?
            for origin in headingOrigins {
                try origin.prepare(blockCase)
                assertCanonicalSignature(emptyLineRenderSignature(), matches: blockCase.expected, context: "\(blockCase.name) / \(origin.name)")
                let signature = activeLineStructuralSignature()
                if let reference {
                    XCTAssertEqual(signature, reference, "\(blockCase.name) / \(origin.name)")
                } else {
                    reference = signature
                }
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, paragraphOrigins.count + headingCases.count * headingOrigins.count)
    }

    func testComposedHistoryNormalizersStillConvergeBeforeHeadingTypeDelete() throws {
        let h1 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" })
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let normalizers: [(name: String, apply: () throws -> Void)] = [
            ("body-enter", {
                self.typeText("Body")
                self.typeText("\n")
            }),
            ("toolbar-heading-enter", {
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.typeText("\n")
            }),
            ("shortcut-heading-enter", {
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                self.typeText("\n")
            }),
            ("typed-list-exit", {
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("toolbar-list-exit", {
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("quote-enter", {
                self.markdownEditor.setBlockType(.quote)
                self.typeText("Quote")
                self.typeText("\n")
            }),
            ("delete-following-paragraph-merge-back-exit", {
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]

        var paragraphReference: ActiveLineStructuralSignature?
        var headingReference: ActiveLineStructuralSignature?
        var exercised = 0

        for first in normalizers {
            for second in normalizers {
                try resetToEmptyParagraph()
                try first.apply()
                try second.apply()

                let paragraphVisual = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(paragraphVisual, matches: paragraph.expected, context: "\(first.name) -> \(second.name) paragraph")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: paragraph.expected.font, context: "\(first.name) -> \(second.name) paragraph")
                let paragraphStructural = activeLineStructuralSignature()
                if let paragraphReference {
                    XCTAssertEqual(paragraphStructural, paragraphReference, "\(first.name) -> \(second.name) paragraph")
                } else {
                    paragraphReference = paragraphStructural
                }

                markdownEditor.setBlockType(.heading(level: .h1))
                typeText("Title")
                deleteCharacters("Title".utf16.count)

                let headingVisual = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(headingVisual, matches: h1.expected, context: "\(first.name) -> \(second.name) h1")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: h1.expected.font, context: "\(first.name) -> \(second.name) h1")
                let headingStructural = activeLineStructuralSignature()
                if let headingReference {
                    XCTAssertEqual(headingStructural, headingReference, "\(first.name) -> \(second.name) h1")
                } else {
                    headingReference = headingStructural
                }

                exercised += 1
            }
        }

        XCTAssertEqual(exercised, normalizers.count * normalizers.count)
    }

    func testRandomizedTransitionPrefixesConvergeToIdenticalFinalBlockState() throws {
        let highRiskCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "h3", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }
        let targetCases = highRiskCases.filter {
            ["paragraph", "h1", "h2", "h3", "quote", "code"].contains($0.name)
        }
        let prefixCases = highRiskCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for (targetIndex, targetBlock) in targetCases.enumerated() {
            try resetToEmptyParagraph()
            applyEmptyBlockTransition(targetBlock)
            let referenceVisual = activeLineVisualSnapshot()
            let referenceStructural = activeLineStructuralSignature()
            assertCanonicalVisualSnapshot(referenceVisual, matches: targetBlock.expected, context: "\(targetBlock.name) / reference")

            for history in HistoryPath.allCases {
                for seed in 1...12 {
                    try prepareEmptyCanonicalLine(history)
                    var generator = DeterministicGenerator(
                        seed: UInt64(seed) &+ UInt64(history.sequenceSeedOffset) &+ UInt64(targetIndex * 10_000)
                    )

                    for _ in 0..<5 {
                        var prefix = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                        while isSameToolbarControl(prefix, targetBlock) {
                            prefix = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                        }
                        applyEmptyBlockTransition(prefix)
                    }

                    applyEmptyBlockTransition(targetBlock)

                    let visual = activeLineVisualSnapshot()
                    let structural = activeLineStructuralSignature()
                    assertCanonicalVisualSnapshot(visual, matches: targetBlock.expected, context: "\(targetBlock.name) / \(history) / seed \(seed)")
                    assertActiveLineSnapshot(visual, matches: referenceVisual, context: "\(targetBlock.name) / \(history) / seed \(seed)")
                    XCTAssertEqual(structural, referenceStructural, "\(targetBlock.name) / \(history) / seed \(seed)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: targetBlock.expected.font,
                        context: "\(targetBlock.name) / \(history) / seed \(seed)"
                    )
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, targetCases.count * HistoryPath.allCases.count * 12)
    }

    func testRandomizedHistoriesConvergeAfterDeletingHeadingContentToEmptyHeading() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let paragraphCase = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let prefixCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var references: [String: (visual: ActiveLineVisualSnapshot, structural: ActiveLineStructuralSignature)] = [:]
        for heading in headingCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(heading.block)
            typeText(heading.text)
            deleteCharacters(heading.text.utf16.count)

            let visual = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(visual, matches: heading.expected, context: "\(heading.name) reference")
            references[heading.name] = (visual, activeLineStructuralSignature())
        }

        var exercised = 0
        for (headingIndex, heading) in headingCases.enumerated() {
            let reference = try XCTUnwrap(references[heading.name], "\(heading.name) reference")

            for history in HistoryPath.allCases {
                for seed in 1...10 {
                    try prepareEmptyCanonicalLine(history)

                    var generator = DeterministicGenerator(
                        seed: UInt64(seed) &+ UInt64(history.sequenceSeedOffset) &+ UInt64(headingIndex * 10_000)
                    )
                    var previous = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]

                    for _ in 0..<6 {
                        var next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                        while isSameToolbarControl(previous, next) {
                            next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                        }
                        applyEmptyBlockTransition(next)
                        previous = next
                    }

                    if isSameToolbarControl(previous, heading) {
                        applyEmptyBlockTransition(paragraphCase)
                    }

                    markdownEditor.setBlockType(heading.block)
                    typeText(heading.text)
                    deleteCharacters(heading.text.utf16.count)

                    let visual = activeLineVisualSnapshot()
                    let structural = activeLineStructuralSignature()
                    assertCanonicalVisualSnapshot(visual, matches: heading.expected, context: "\(heading.name) / \(history) / seed \(seed)")
                    assertActiveLineSnapshot(visual, matches: reference.visual, context: "\(heading.name) / \(history) / seed \(seed)")
                    XCTAssertEqual(structural, reference.structural, "\(heading.name) / \(history) / seed \(seed)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(heading.name) / \(history) / seed \(seed)"
                    )
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * HistoryPath.allCases.count * 10)
    }

    func testLiveRenderingMatchesFreshImportOracleAfterGeneratedHistories() throws {
        let targetCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "h3", "quote", "code"].contains($0.name)
        }
        let paragraphCase = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let prefixCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for (targetIndex, target) in targetCases.enumerated() {
            for history in HistoryPath.allCases {
                for seed in 1...6 {
                    let text = "Oracle \(target.name) \(history.description) \(seed)"
                    let offsets = [0, (text as NSString).length / 2, (text as NSString).length]

                    for offset in offsets {
                        try prepareEmptyCanonicalLine(history)

                        var generator = DeterministicGenerator(
                            seed: UInt64(seed)
                                &+ UInt64(history.sequenceSeedOffset)
                                &+ UInt64(targetIndex * 10_000)
                                &+ UInt64(offset * 100)
                        )
                        var previous = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]

                        for _ in 0..<5 {
                            var next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                            while isSameToolbarControl(previous, next) {
                                next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                            }
                            applyEmptyBlockTransition(next)
                            previous = next
                        }

                        if isSameToolbarControl(previous, target) {
                            applyEmptyBlockTransition(paragraphCase)
                        }

                        markdownEditor.setBlockType(target.block)
                        typeText(text)
                        try selectActiveTextOffset(offset)

                        let liveVisual = activeLineVisualSnapshot()
                        let liveStructural = activeLineStructuralSignature()
                        let exported = try XCTUnwrap(
                            markdownEditor.exportMarkdown().value?.content,
                            "\(target.name) / \(history) / seed \(seed) / offset \(offset)"
                        )
                        XCTAssertFalse(exported.contains("\u{200B}"), "\(target.name) / \(history) / seed \(seed) / offset \(offset)")

                        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: exported))
                        try selectText(text, offset: offset)
                        editor.dispatchCommand(type: .selectionChange)
                        syncNativeSelectionFromLexical()

                        let importedVisual = activeLineVisualSnapshot()
                        let importedStructural = activeLineStructuralSignature()
                        XCTAssertEqual(importedVisual.blockType, target.expected.type, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.selectionType, .text, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.selectedBlockText.trimmingCharacters(in: .newlines), text, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.renderedLine.blockType, target.expected.type, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.renderedLine.visibleText, text, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.caretHeight, rounded(target.expected.font.lineHeight), accuracy: 1.0, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.firstLineHeadIndent, rounded(target.expected.firstLineHeadIndent), accuracy: 0.5, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.headIndent, rounded(target.expected.headIndent), accuracy: 0.5, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        XCTAssertEqual(importedVisual.hasListItemAttribute, target.expected.allowsListAttribute, "\(target.name) / \(history) / seed \(seed) / offset \(offset) import")
                        assertActiveLineSnapshot(importedVisual, matches: liveVisual, context: "\(target.name) / \(history) / seed \(seed) / offset \(offset) live-vs-import")
                        XCTAssertEqual(importedStructural, liveStructural, "\(target.name) / \(history) / seed \(seed) / offset \(offset)")
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: target.expected.font,
                            context: "\(target.name) / \(history) / seed \(seed) / offset \(offset) live-vs-import"
                        )
                        assertSelectionAndCaretAreHealthy("\(target.name) / \(history) / seed \(seed) / offset \(offset) live-vs-import")
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, targetCases.count * HistoryPath.allCases.count * 6 * 3)
    }

    func testPopulatedHeadingCaretGeometryConvergesAcrossRandomBlockHistoriesAndOffsets() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let paragraphCase = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let prefixCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var references: [String: (visual: ActiveLineVisualSnapshot, structural: ActiveLineStructuralSignature)] = [:]
        for heading in headingCases {
            for offset in populatedHeadingOffsets(for: heading.text) {
                try resetToEmptyParagraph()
                markdownEditor.setBlockType(heading.block)
                typeText(heading.text)
                try selectActiveTextOffset(offset)

                let visual = activeLineVisualSnapshot()
                XCTAssertEqual(visual.blockType, .heading, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(visual.selectedBlockText, heading.text, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(visual.renderedLine.visibleText, heading.text, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(visual.caretHeight, rounded(heading.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(visual.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, "\(heading.name) reference offset \(offset)")
                XCTAssertFalse(visual.placeholderVisible, "\(heading.name) reference offset \(offset)")
                XCTAssertNil(caretListItemAttribute(), "\(heading.name) reference offset \(offset)")
                references["\(heading.name)-\(offset)"] = (visual, activeLineStructuralSignature())
            }
        }

        var exercised = 0
        for (headingIndex, heading) in headingCases.enumerated() {
            for offset in populatedHeadingOffsets(for: heading.text) {
                let reference = try XCTUnwrap(references["\(heading.name)-\(offset)"], "\(heading.name) offset \(offset) reference")

                for history in HistoryPath.allCases {
                    for seed in 1...6 {
                        try prepareEmptyCanonicalLine(history)

                        var generator = DeterministicGenerator(
                            seed: UInt64(seed) &+ UInt64(history.sequenceSeedOffset) &+ UInt64(headingIndex * 10_000) &+ UInt64(offset * 100)
                        )
                        var previous = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]

                        for _ in 0..<6 {
                            var next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                            while isSameToolbarControl(previous, next) {
                                next = prefixCases[generator.nextIndex(upperBound: prefixCases.count)]
                            }
                            applyEmptyBlockTransition(next)
                            previous = next
                        }

                        if isSameToolbarControl(previous, heading) {
                            applyEmptyBlockTransition(paragraphCase)
                        }

                        markdownEditor.setBlockType(heading.block)
                        typeText(heading.text)
                        try selectActiveTextOffset(offset)

                        let visual = activeLineVisualSnapshot()
                        let structural = activeLineStructuralSignature()
                        XCTAssertEqual(activeRootChildType(), .heading, "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        XCTAssertEqual(visual.selectedBlockText, heading.text, "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        XCTAssertEqual(visual.renderedLine.visibleText, heading.text, "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        XCTAssertFalse(visual.placeholderVisible, "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        XCTAssertNil(caretListItemAttribute(), "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        assertActiveLineSnapshot(visual, matches: reference.visual, context: "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        XCTAssertEqual(structural, reference.structural, "\(heading.name) / offset \(offset) / \(history) / seed \(seed)")
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: heading.expected.font,
                            context: "\(heading.name) / offset \(offset) / \(history) / seed \(seed)"
                        )
                        assertSelectionAndCaretAreHealthy("\(heading.name) populated offset \(offset) \(history) seed \(seed)")
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 4 * HistoryPath.allCases.count * 6)
    }

    func testSelectingPopulatedEmbeddedHeadingsMatchesTopLevelCaretGeometryAcrossContexts() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let contexts = [
            "top-before-paragraph",
            "after-paragraph",
            "between-paragraphs",
            "after-unordered-list",
            "after-ordered-list",
            "between-lists",
            "after-quote",
            "after-code"
        ]

        var exercised = 0
        for heading in headingCases {
            let tag = try XCTUnwrap(headingTag(for: heading.block), heading.name)
            for offset in populatedHeadingOffsets(for: heading.text) {
                try loadPopulatedHeadingFixture(tag: tag, text: heading.text, context: "top-before-paragraph")
                try selectText(heading.text, offset: offset)
                editor.dispatchCommand(type: .selectionChange)
                syncNativeSelectionFromLexical()

                let referenceVisual = activeLineVisualSnapshot()
                let referenceStructural = activeLineStructuralSignature()
                XCTAssertEqual(referenceVisual.blockType, .heading, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(referenceVisual.selectedBlockText.replacingOccurrences(of: "\n", with: ""), heading.text, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(referenceVisual.renderedLine.visibleText, heading.text, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(referenceVisual.caretHeight, rounded(heading.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) reference offset \(offset)")
                XCTAssertEqual(referenceVisual.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, "\(heading.name) reference offset \(offset)")
                XCTAssertFalse(referenceVisual.placeholderVisible, "\(heading.name) reference offset \(offset)")
                XCTAssertNil(caretListItemAttribute(), "\(heading.name) reference offset \(offset)")

                for context in contexts {
                    try loadPopulatedHeadingFixture(tag: tag, text: heading.text, context: context)
                    try selectText(heading.text, offset: offset)
                    editor.dispatchCommand(type: .selectionChange)
                    syncNativeSelectionFromLexical()

                    let visual = activeLineVisualSnapshot()
                    let structural = activeLineStructuralSignature()
                    XCTAssertEqual(activeRootChildType(), .heading, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), tag, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(visual.selectedBlockText.replacingOccurrences(of: "\n", with: ""), heading.text, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(visual.renderedLine.visibleText, heading.text, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertFalse(visual.placeholderVisible, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertNil(caretListItemAttribute(), "\(heading.name) / \(context) / offset \(offset)")
                    assertActiveLineRendering(
                        visual,
                        matches: referenceVisual,
                        context: "\(heading.name) / \(context) / offset \(offset)"
                    )
                    XCTAssertEqual(structural, referenceStructural, "\(heading.name) / \(context) / offset \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(heading.name) / \(context) / offset \(offset)"
                    )
                    assertSelectionAndCaretAreHealthy("\(heading.name) embedded \(context) offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 4 * contexts.count)
    }

    func testNativeCaretSelectionOnPopulatedEmbeddedHeadingsMatchesCanonicalGeometryAcrossContexts() throws {
        let headingCases = canonicalBlockCases.filter { ["h1", "h2", "h3", "h4", "h5", "h6"].contains($0.name) }
        let contexts = [
            "top-before-paragraph",
            "after-paragraph",
            "between-paragraphs",
            "after-unordered-list",
            "after-ordered-list",
            "between-lists",
            "after-quote",
            "after-code"
        ]

        var exercised = 0
        for heading in headingCases {
            let tag = try XCTUnwrap(headingTag(for: heading.block), heading.name)
            for offset in populatedHeadingOffsets(for: heading.text) {
                try loadPopulatedHeadingFixture(tag: tag, text: heading.text, context: "top-before-paragraph")
                try moveNativeCaret(toText: heading.text, offset: offset)

                let referenceVisual = activeLineVisualSnapshot()
                let referenceStructural = activeLineStructuralSignature()
                XCTAssertEqual(referenceVisual.blockType, .heading, "\(heading.name) native reference offset \(offset)")
                XCTAssertEqual(referenceVisual.renderedLine.visibleText, heading.text, "\(heading.name) native reference offset \(offset)")
                XCTAssertEqual(referenceVisual.caretHeight, rounded(heading.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) native reference offset \(offset)")
                XCTAssertEqual(referenceVisual.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, "\(heading.name) native reference offset \(offset)")
                XCTAssertFalse(referenceVisual.placeholderVisible, "\(heading.name) native reference offset \(offset)")
                XCTAssertNil(caretListItemAttribute(), "\(heading.name) native reference offset \(offset)")

                for context in contexts {
                    try loadPopulatedHeadingFixture(tag: tag, text: heading.text, context: context)
                    try moveNativeCaret(toText: heading.text, offset: offset)

                    let visual = activeLineVisualSnapshot()
                    let structural = activeLineStructuralSignature()
                    XCTAssertEqual(activeRootChildType(), .heading, "\(heading.name) / native \(context) / offset \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), tag, "\(heading.name) / native \(context) / offset \(offset)")
                    XCTAssertEqual(visual.renderedLine.visibleText, heading.text, "\(heading.name) / native \(context) / offset \(offset)")
                    XCTAssertFalse(visual.placeholderVisible, "\(heading.name) / native \(context) / offset \(offset)")
                    XCTAssertNil(caretListItemAttribute(), "\(heading.name) / native \(context) / offset \(offset)")
                    assertActiveLineRendering(
                        visual,
                        matches: referenceVisual,
                        context: "\(heading.name) / native \(context) / offset \(offset)"
                    )
                    XCTAssertEqual(structural, referenceStructural, "\(heading.name) / native \(context) / offset \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(heading.name) / native \(context) / offset \(offset)"
                    )
                    assertSelectionAndCaretAreHealthy("\(heading.name) native embedded \(context) offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 4 * contexts.count)
    }

    func testTypingAfterNativeTapInsideEmbeddedHeadingsKeepsHeadingAttributesAcrossContexts() throws {
        let headingCases = canonicalBlockCases.filter { ["h1", "h2", "h3", "h4", "h5", "h6"].contains($0.name) }
        let contexts = [
            "top-before-paragraph",
            "after-unordered-list",
            "after-ordered-list",
            "between-lists",
            "after-quote",
            "after-code"
        ]

        var exercised = 0
        for heading in headingCases {
            let tag = try XCTUnwrap(headingTag(for: heading.block), heading.name)
            let offsets = [0, (heading.text as NSString).length]

            for context in contexts {
                for offset in offsets {
                    try loadPopulatedHeadingFixture(tag: tag, text: heading.text, context: context)
                    try moveNativeCaret(toText: heading.text, offset: offset)

                    typeText("X")
                    let expectedText = (heading.text as NSString).replacingCharacters(
                        in: NSRange(location: offset, length: 0),
                        with: "X"
                    )

                    let typedVisual = activeLineVisualSnapshot()
                    XCTAssertEqual(activeRootChildType(), .heading, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), tag, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.renderedLine.visibleText, expectedText, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.selectedBlockText.replacingOccurrences(of: "\n", with: ""), expectedText, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.caretHeight, rounded(heading.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.typingPointSize, rounded(heading.expected.font.pointSize), accuracy: 0.5, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.firstLineHeadIndent, 0, accuracy: 0.5, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertEqual(typedVisual.typingFirstLineHeadIndent, 0, accuracy: 0.5, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertFalse(typedVisual.hasListItemAttribute, "\(heading.name) / \(context) / offset \(offset)")
                    XCTAssertFalse(typedVisual.typingHasListItemAttribute, "\(heading.name) / \(context) / offset \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: heading.expected.font,
                        context: "\(heading.name) / typed \(context) / offset \(offset)"
                    )

                    markdownEditor.textView.deleteBackward()
                    let restoredVisual = activeLineVisualSnapshot()
                    XCTAssertEqual(restoredVisual.renderedLine.visibleText, heading.text, "\(heading.name) / \(context) / offset \(offset) restored")
                    XCTAssertEqual(restoredVisual.caretHeight, rounded(heading.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) / \(context) / offset \(offset) restored")
                    XCTAssertEqual(restoredVisual.typingPointSize, rounded(heading.expected.font.pointSize), accuracy: 0.5, "\(heading.name) / \(context) / offset \(offset) restored")
                    XCTAssertFalse(restoredVisual.typingHasListItemAttribute, "\(heading.name) / \(context) / offset \(offset) restored")
                    assertSelectionAndCaretAreHealthy("\(heading.name) / typed embedded \(context) offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * contexts.count * 2)
    }

    func testHeadingCaretGeometryIsCanonicalAcrossSurroundingBlockPairs() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#"),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##"),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###"),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h4" }), "####"),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h5" }), "#####"),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h6" }), "######")
        ]
        let surroundingBlocks: [(name: String, markdown: String)] = [
            ("none", ""),
            ("paragraph", "Plain paragraph"),
            ("h1", "# Neighbor title"),
            ("h2", "## Neighbor subtitle"),
            ("quote", "> Neighbor quote"),
            ("code", "```swift\nlet neighbor = 1\n```"),
            ("unordered-list", "- Neighbor bullet"),
            ("ordered-list", "1. Neighbor number")
        ]

        var exercised = 0
        for headingCase in headingCases {
            let heading = headingCase.blockCase
            let headingText = "Canonical \(heading.name)"
            let tag = try XCTUnwrap(headingTag(for: heading.block), heading.name)
            let offsets = [0, (headingText as NSString).length]

            for offset in offsets {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "\(headingCase.marker) \(headingText)"))
                try moveNativeCaret(toText: headingText, offset: offset)
                let referenceVisual = activeLineVisualSnapshot()
                let referenceStructural = activeLineStructuralSignature()
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: heading.expected.font,
                    context: "\(heading.name) clean surrounding reference offset \(offset)"
                )

                for prefix in surroundingBlocks {
                    for suffix in surroundingBlocks {
                        let content = [prefix.markdown, "\(headingCase.marker) \(headingText)", suffix.markdown]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n\n")
                        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: content))
                        try moveNativeCaret(toText: headingText, offset: offset)

                        let visual = activeLineVisualSnapshot()
                        let structural = activeLineStructuralSignature()
                        XCTAssertEqual(activeRootChildType(), .heading, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        XCTAssertEqual(firstHeadingTag(inActiveBlock: true), tag, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        XCTAssertEqual(visual.renderedLine.visibleText, headingText, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        XCTAssertEqual(visual.selectedBlockText.replacingOccurrences(of: "\n", with: ""), headingText, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        XCTAssertFalse(visual.placeholderVisible, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        XCTAssertNil(caretListItemAttribute(), "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        assertActiveLineRendering(
                            visual,
                            matches: referenceVisual,
                            context: "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)"
                        )
                        XCTAssertEqual(structural, referenceStructural, "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: heading.expected.font,
                            context: "\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)"
                        )
                        assertSelectionAndCaretAreHealthy("\(heading.name) / \(prefix.name) -> \(suffix.name) / offset \(offset)")
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 2 * surroundingBlocks.count * surroundingBlocks.count)
    }

    func testDeletingHeadingContentAfterListExitCanonicalizesEmptyLineGeometry() throws {
        try resetToEmptyParagraph()
        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("A")
        markdownEditor.textView.deleteBackward()
        let directHeadingSignature = emptyLineRenderSignature()

        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .list)
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph)
        XCTAssertNil(caretListItemAttribute())

        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("A")
        markdownEditor.textView.deleteBackward()
        let afterListHeadingSignature = emptyLineRenderSignature()

        XCTAssertEqual(afterListHeadingSignature.blockType, directHeadingSignature.blockType)
        XCTAssertEqual(afterListHeadingSignature.selectionType, directHeadingSignature.selectionType)
        XCTAssertEqual(afterListHeadingSignature.textContent, directHeadingSignature.textContent)
        XCTAssertNil(afterListHeadingSignature.listItemAttribute)
        XCTAssertEqual(afterListHeadingSignature.caretX, directHeadingSignature.caretX, accuracy: 1.5)
        XCTAssertEqual(afterListHeadingSignature.caretHeight, directHeadingSignature.caretHeight, accuracy: 1.0)
        XCTAssertEqual(afterListHeadingSignature.firstLineHeadIndent, directHeadingSignature.firstLineHeadIndent, accuracy: 0.5)
        XCTAssertEqual(afterListHeadingSignature.headIndent, directHeadingSignature.headIndent, accuracy: 0.5)
        assertSelectionAndCaretAreHealthy("heading delete after list exit")
    }

    func testHeadingShortcutAfterListExitThenDeleteCanonicalizesCaretGeometry() throws {
        try resetToEmptyParagraph()
        typeText("#")
        typeText(" ")
        typeText("Heading")
        deleteCharacters("Heading".utf16.count)
        let directShortcutSignature = emptyLineRenderSignature()

        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .list)
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph)
        XCTAssertNil(caretListItemAttribute())

        typeText("#")
        typeText(" ")
        XCTAssertEqual(activeRootChildType(), .heading)
        typeText("Heading")
        assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: MarkdownEditorConfiguration.default.theme.typography.h1, context: "shortcut heading after list content")
        deleteCharacters("Heading".utf16.count)
        let afterListShortcutSignature = emptyLineRenderSignature()

        XCTAssertEqual(afterListShortcutSignature.blockType, directShortcutSignature.blockType)
        XCTAssertEqual(afterListShortcutSignature.selectionType, directShortcutSignature.selectionType)
        XCTAssertEqual(afterListShortcutSignature.textContent, directShortcutSignature.textContent)
        XCTAssertNil(afterListShortcutSignature.listItemAttribute)
        XCTAssertEqual(afterListShortcutSignature.caretX, directShortcutSignature.caretX, accuracy: 1.5)
        XCTAssertEqual(afterListShortcutSignature.caretHeight, directShortcutSignature.caretHeight, accuracy: 1.0)
        XCTAssertEqual(afterListShortcutSignature.firstLineHeadIndent, directShortcutSignature.firstLineHeadIndent, accuracy: 0.5)
        XCTAssertEqual(afterListShortcutSignature.headIndent, directShortcutSignature.headIndent, accuracy: 0.5)
        assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: MarkdownEditorConfiguration.default.theme.typography.h1, context: "shortcut heading after list delete")
        assertSelectionAndCaretAreHealthy("shortcut heading delete after list exit")
    }

    func testRetypingAfterEmptyHeadingFromListExitDoesNotRestoreListIndentation() throws {
        let h1 = try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" })
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })

        try resetToEmptyParagraph()
        typeText("Body")
        let cleanParagraphContent = activeLineVisualSnapshot()
        XCTAssertEqual(cleanParagraphContent.blockType, paragraph.expected.type, "clean typed paragraph")
        XCTAssertEqual(cleanParagraphContent.selectedBlockText, "Body", "clean typed paragraph")
        XCTAssertEqual(cleanParagraphContent.caretHeight, rounded(paragraph.expected.font.lineHeight), accuracy: 1.0, "clean typed paragraph")
        XCTAssertEqual(cleanParagraphContent.firstLineHeadIndent, rounded(paragraph.expected.firstLineHeadIndent), accuracy: 0.5, "clean typed paragraph")
        XCTAssertEqual(cleanParagraphContent.headIndent, rounded(paragraph.expected.headIndent), accuracy: 0.5, "clean typed paragraph")

        try resetToEmptyParagraph()
        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("Again")
        let cleanHeadingContent = activeLineVisualSnapshot()
        XCTAssertEqual(cleanHeadingContent.blockType, h1.expected.type, "clean retyped heading")
        XCTAssertEqual(cleanHeadingContent.selectedBlockText, "Again", "clean retyped heading")
        XCTAssertEqual(cleanHeadingContent.caretHeight, rounded(h1.expected.font.lineHeight), accuracy: 1.0, "clean retyped heading")
        XCTAssertEqual(cleanHeadingContent.firstLineHeadIndent, rounded(h1.expected.firstLineHeadIndent), accuracy: 0.5, "clean retyped heading")
        XCTAssertEqual(cleanHeadingContent.headIndent, rounded(h1.expected.headIndent), accuracy: 0.5, "clean retyped heading")

        try prepareAfterListExit()
        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("Title")
        deleteCharacters("Title".utf16.count)
        XCTAssertEqual(activeLineStructuralSignature().textLeafContents, ["\u{200B}"], "emptied heading should be anchored before retyping")

        typeText("Again")
        let afterListRetypedHeading = activeLineVisualSnapshot()
        XCTAssertEqual(afterListRetypedHeading.blockType, h1.expected.type, "after list retyped heading")
        XCTAssertEqual(afterListRetypedHeading.selectedBlockText, "Again", "after list retyped heading")
        XCTAssertEqual(afterListRetypedHeading.caretHeight, rounded(h1.expected.font.lineHeight), accuracy: 1.0, "after list retyped heading")
        XCTAssertEqual(afterListRetypedHeading.firstLineHeadIndent, rounded(h1.expected.firstLineHeadIndent), accuracy: 0.5, "after list retyped heading")
        XCTAssertEqual(afterListRetypedHeading.headIndent, rounded(h1.expected.headIndent), accuracy: 0.5, "after list retyped heading")
        assertActiveLineSnapshot(afterListRetypedHeading, matches: cleanHeadingContent, context: "after list retyped heading should match clean heading")
        XCTAssertNil(caretListItemAttribute(), "retyping into emptied heading should not restore list drawing")
        assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: h1.expected.font, context: "after list retyped heading")

        deleteCharacters("Again".utf16.count)
        markdownEditor.setBlockType(.heading(level: .h1))
        typeText("Body")
        let paragraphAfterHeadingToggle = activeLineVisualSnapshot()
        XCTAssertEqual(paragraphAfterHeadingToggle.blockType, paragraph.expected.type, "paragraph after heading toggle")
        XCTAssertEqual(paragraphAfterHeadingToggle.selectedBlockText, "Body", "paragraph after heading toggle")
        XCTAssertEqual(paragraphAfterHeadingToggle.caretHeight, rounded(paragraph.expected.font.lineHeight), accuracy: 1.0, "paragraph after heading toggle")
        XCTAssertEqual(paragraphAfterHeadingToggle.firstLineHeadIndent, rounded(paragraph.expected.firstLineHeadIndent), accuracy: 0.5, "paragraph after heading toggle")
        XCTAssertEqual(paragraphAfterHeadingToggle.headIndent, rounded(paragraph.expected.headIndent), accuracy: 0.5, "paragraph after heading toggle")
        assertActiveLineSnapshot(paragraphAfterHeadingToggle, matches: cleanParagraphContent, context: "paragraph after heading toggle should match clean paragraph")
        XCTAssertNil(caretListItemAttribute(), "paragraph after toggling emptied heading off should not inherit list drawing")
    }

    func testRetypingAfterEmptyHeadingDeletionIsCanonicalAcrossListDerivedHistories() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let origins: [(name: String, prepare: () throws -> Void)] = [
            ("list-double-enter", {
                try self.prepareAfterListExit()
            }),
            ("toolbar-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]
        let deletionModes: [(name: String, apply: (String) throws -> Void)] = [
            ("key-repeat", { text in
                self.deleteCharacters(text.utf16.count)
            }),
            ("selected-deleteBackward", { text in
                try self.selectNativeVisibleText(text)
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
                self.markdownEditor.textView.layoutIfNeeded()
            }),
            ("native-replacement", { text in
                try self.nativeReplaceVisibleText(text, with: "")
            })
        ]

        try resetToEmptyParagraph()
        typeText("Body")
        let cleanParagraph = activeLineVisualSnapshot()

        var cleanHeadingSnapshots: [String: ActiveLineVisualSnapshot] = [:]
        for heading in headingCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(heading.block)
            typeText("Again")
            cleanHeadingSnapshots[heading.name] = activeLineVisualSnapshot()
        }

        var exercised = 0
        for heading in headingCases {
            for origin in origins {
                for deletionMode in deletionModes {
                    try origin.prepare()
                    markdownEditor.setBlockType(heading.block)
                    let text = "Delete \(heading.name)"
                    typeText(text)
                    try deletionMode.apply(text)

                    XCTAssertEqual(activeLineStructuralSignature().textLeafContents, ["\u{200B}"], "\(heading.name) / \(origin.name) / \(deletionMode.name) emptied heading")

                    typeText("Again")
                    let retypedHeading = activeLineVisualSnapshot()
                    let cleanHeading = try XCTUnwrap(cleanHeadingSnapshots[heading.name], "\(heading.name) clean heading")
                    assertActiveLineSnapshot(retypedHeading, matches: cleanHeading, context: "\(heading.name) / \(origin.name) / \(deletionMode.name) retyped heading")
                    XCTAssertNil(caretListItemAttribute(), "\(heading.name) / \(origin.name) / \(deletionMode.name) retyped heading should not inherit list drawing")
                    assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: heading.expected.font, context: "\(heading.name) / \(origin.name) / \(deletionMode.name) retyped heading")

                    deleteCharacters("Again".utf16.count)
                    markdownEditor.setBlockType(heading.block)
                    typeText("Body")
                    let paragraphAfterToggle = activeLineVisualSnapshot()
                    assertActiveLineSnapshot(paragraphAfterToggle, matches: cleanParagraph, context: "\(heading.name) / \(origin.name) / \(deletionMode.name) paragraph after toggle")
                    XCTAssertNil(caretListItemAttribute(), "\(heading.name) / \(origin.name) / \(deletionMode.name) paragraph should not inherit list drawing")
                    XCTAssertEqual(paragraphAfterToggle.caretHeight, rounded(paragraph.expected.font.lineHeight), accuracy: 1.0, "\(heading.name) / \(origin.name) / \(deletionMode.name) paragraph")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * origins.count * deletionModes.count)
    }

    func testEmptyBlockRenderingIsCanonicalAcrossGeneratedOperationHistories() throws {
        let targetBlocks = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "h3", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }
        let origins: [(name: String, prepare: () throws -> Void)] = [
            ("clean", {
                try self.prepareEmptyCanonicalLine(.clean)
            }),
            ("body-enter", {
                try self.prepareEmptyCanonicalLine(.afterBodyEnter)
            }),
            ("heading-enter", {
                try self.prepareEmptyCanonicalLine(.afterHeadingEnter)
            }),
            ("list-double-enter", {
                try self.prepareEmptyCanonicalLine(.afterListDoubleEnter)
            }),
            ("paste-enter", {
                try self.prepareEmptyCanonicalLine(.afterPasteEnter)
            }),
            ("quote-enter", {
                try self.prepareEmptyCanonicalLine(.afterQuoteEnter)
            }),
            ("code-enter", {
                try self.prepareEmptyCanonicalLine(.afterCodeEnter)
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]
        let emptyingMethods: [(name: String, apply: (CanonicalBlockCase, String) throws -> Void)] = [
            ("direct-empty", { blockCase, _ in
                self.markdownEditor.setBlockType(blockCase.block)
            }),
            ("type-key-delete", { blockCase, payload in
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(payload)
                self.deleteCharacters(payload.utf16.count)
            }),
            ("type-select-delete", { blockCase, payload in
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(payload)
                try self.selectNativeVisibleText(payload)
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
                self.markdownEditor.textView.layoutIfNeeded()
            }),
            ("type-native-replace", { blockCase, payload in
                self.markdownEditor.setBlockType(blockCase.block)
                self.typeText(payload)
                try self.nativeReplaceVisibleText(payload, with: "")
            })
        ]

        var referenceVisuals: [String: ActiveLineVisualSnapshot] = [:]
        var referenceStructurals: [String: ActiveLineStructuralSignature] = [:]
        for blockCase in targetBlocks {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(blockCase.block)
            referenceVisuals[blockCase.name] = activeLineVisualSnapshot()
            referenceStructurals[blockCase.name] = activeLineStructuralSignature()
        }

        var exercised = 0
        for blockCase in targetBlocks {
            for origin in origins {
                for emptyingMethod in emptyingMethods {
                    try origin.prepare()
                    let payload = "Canonical \(blockCase.name)"
                    try emptyingMethod.apply(blockCase, payload)

                    let visual = activeLineVisualSnapshot()
                    let structural = activeLineStructuralSignature()
                    let referenceVisual = try XCTUnwrap(referenceVisuals[blockCase.name], blockCase.name)
                    let referenceStructural = try XCTUnwrap(referenceStructurals[blockCase.name], blockCase.name)

                    assertActiveLineSnapshot(visual, matches: referenceVisual, context: "\(blockCase.name) / \(origin.name) / \(emptyingMethod.name)")
                    if blockCase.expected.type == .list {
                        assertActiveListItemStructurallyMatchesReference(structural, referenceStructural, context: "\(blockCase.name) / \(origin.name) / \(emptyingMethod.name)")
                    } else {
                        XCTAssertEqual(structural, referenceStructural, "\(blockCase.name) / \(origin.name) / \(emptyingMethod.name)")
                    }
                    assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: blockCase.expected.font, context: "\(blockCase.name) / \(origin.name) / \(emptyingMethod.name)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, targetBlocks.count * origins.count * emptyingMethods.count)
    }

    func testCanonicalEmptyParagraphHistoriesProduceIdenticalFollowUpBehavior() throws {
        let origins: [(name: String, prepare: () throws -> Void)] = [
            ("clean", {
                try self.resetToEmptyParagraph()
            }),
            ("body-enter", {
                try self.prepareEmptyCanonicalLine(.afterBodyEnter)
            }),
            ("heading-enter", {
                try self.prepareEmptyCanonicalLine(.afterHeadingEnter)
            }),
            ("list-double-enter", {
                try self.prepareEmptyCanonicalLine(.afterListDoubleEnter)
            }),
            ("toolbar-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("ordered-list-double-enter", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.orderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("quote-enter", {
                try self.prepareEmptyCanonicalLine(.afterQuoteEnter)
            }),
            ("code-enter", {
                try self.prepareEmptyCanonicalLine(.afterCodeEnter)
            }),
            ("heading-delete-toggle-off", {
                try self.prepareAfterListExit()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]
        let followUps: [(name: String, apply: () throws -> Void)] = [
            ("type-body", {
                self.typeText("Body")
            }),
            ("type-delete-retype-body", {
                self.typeText("Draft")
                self.deleteCharacters("Draft".utf16.count)
                self.typeText("Body")
            }),
            ("toolbar-h1-type-delete", {
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("shortcut-h1-type-delete", {
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                self.deleteCharacters("Title".utf16.count)
            }),
            ("toolbar-h2-type", {
                self.markdownEditor.setBlockType(.heading(level: .h2))
                self.typeText("Subtitle")
            }),
            ("toolbar-quote-type-delete", {
                self.markdownEditor.setBlockType(.quote)
                self.typeText("Quote")
                self.deleteCharacters("Quote".utf16.count)
            }),
            ("toolbar-code-type-delete", {
                self.markdownEditor.setBlockType(.codeBlock)
                self.typeText("code")
                self.deleteCharacters("code".utf16.count)
            }),
            ("shortcut-list-exit", {
                self.typeText("-")
                self.typeText(" ")
                self.typeText("Item")
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("toolbar-unordered-list-type-delete", {
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("Item")
                self.deleteCharacters("Item".utf16.count)
            }),
            ("toolbar-ordered-list-type-delete", {
                self.markdownEditor.setBlockType(.orderedList)
                self.typeText("Item")
                self.deleteCharacters("Item".utf16.count)
            })
        ]

        var references: [String: (visual: ActiveLineVisualSnapshot, structural: ActiveLineStructuralSignature)] = [:]
        for followUp in followUps {
            try resetToEmptyParagraph()
            try followUp.apply()
            references[followUp.name] = (activeLineVisualSnapshot(), activeLineStructuralSignature())
            XCTAssertFalse(
                try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(followUp.name) reference").contains("\u{200B}"),
                "\(followUp.name) reference should not export caret anchors"
            )
        }

        var exercised = 0
        for origin in origins {
            for followUp in followUps {
                try origin.prepare()
                try followUp.apply()

                let reference = try XCTUnwrap(references[followUp.name], followUp.name)
                let visual = activeLineVisualSnapshot()
                let structural = activeLineStructuralSignature()
                assertActiveLineSnapshot(visual, matches: reference.visual, context: "\(origin.name) -> \(followUp.name)")
                if reference.visual.blockType == .list {
                    assertActiveListItemStructurallyMatchesReference(structural, reference.structural, context: "\(origin.name) -> \(followUp.name)")
                } else {
                    XCTAssertEqual(structural, reference.structural, "\(origin.name) -> \(followUp.name)")
                }
                XCTAssertFalse(
                    try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(origin.name) -> \(followUp.name)").contains("\u{200B}"),
                    "\(origin.name) -> \(followUp.name) should not export caret anchors"
                )
                assertSelectionAndCaretAreHealthy("\(origin.name) -> \(followUp.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, origins.count * followUps.count)
    }

    func testWholeDocumentRenderingIsCanonicalAfterTemporaryFormattingHistories() throws {
        let baseMarkdown = """
        # Title
        ## Subtitle
        Body
        - One
        - Two
        Tail
        """
        let activeText = "Tail"
        let histories: [(name: String, apply: () throws -> Void)] = [
            ("clean", {}),
            ("heading-type-delete-toggle-off", {
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("unordered-list-type-delete-toggle-off", {
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.unorderedList)
            }),
            ("ordered-list-type-delete-toggle-off", {
                self.markdownEditor.setBlockType(.orderedList)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.orderedList)
            }),
            ("quote-type-delete-toggle-off", {
                self.markdownEditor.setBlockType(.quote)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("code-type-delete-toggle-off", {
                self.markdownEditor.setBlockType(.codeBlock)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("select-delete-retype", {
                try self.selectNativeVisibleText(activeText)
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
                self.typeText(activeText)
            }),
            ("native-replace-same-text", {
                try self.nativeReplaceVisibleText(activeText, with: activeText)
            }),
            ("enter-empty-line-then-backspace", {
                self.typeText("\n")
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
            })
        ]

        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: baseMarkdown))
        try selectText(activeText, offset: activeText.utf16.count)
        let referenceExport = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "reference export")
        let referenceDocument = renderedDocumentSignature()
        let referenceVisual = activeLineVisualSnapshot()
        let referenceStructural = activeLineStructuralSignature()

        var exercised = 0
        for history in histories {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: baseMarkdown))
            try selectText(activeText, offset: activeText.utf16.count)
            try history.apply()

            let exported = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history.name) export")
            XCTAssertEqual(exported, referenceExport, history.name)
            XCTAssertFalse(exported.contains("\u{200B}"), "\(history.name) should not export caret anchors")
            XCTAssertEqual(renderedDocumentSignature(), referenceDocument, history.name)
            assertActiveLineSnapshot(activeLineVisualSnapshot(), matches: referenceVisual, context: history.name)
            XCTAssertEqual(activeLineStructuralSignature(), referenceStructural, history.name)
            assertSelectionAndCaretAreHealthy(history.name)
            exercised += 1
        }

        XCTAssertEqual(exercised, histories.count)
    }

    func testWholeDocumentRenderingIsCanonicalForFinalBlockTypesAfterTemporaryHistories() throws {
        let baseMarkdown = """
        # Title
        Intro
        - One
        - Two
        Tail
        """
        let activeText = "Tail"
        let finalBlocks = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }
        let histories: [(name: String, apply: () throws -> Void)] = [
            ("clean", {}),
            ("heading-detour", {
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.heading(level: .h1))
            }),
            ("quote-detour", {
                self.markdownEditor.setBlockType(.quote)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("code-detour", {
                self.markdownEditor.setBlockType(.codeBlock)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("unordered-list-detour", {
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("ordered-list-detour", {
                self.markdownEditor.setBlockType(.orderedList)
                self.typeText(" scratch")
                self.deleteCharacters(" scratch".utf16.count)
                self.markdownEditor.setBlockType(.paragraph)
            }),
            ("enter-backspace-detour", {
                self.typeText("\n")
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
            }),
            ("select-delete-retype-detour", {
                try self.selectNativeVisibleText(activeText)
                self.markdownEditor.textView.deleteBackward()
                self.syncNativeSelectionFromLexical()
                self.typeText(activeText)
            })
        ]

        let offsets = [0, 2, activeText.utf16.count]
        var exercised = 0
        for finalBlock in finalBlocks {
            for offset in offsets {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: baseMarkdown))
                try selectText(activeText, offset: activeText.utf16.count)
                markdownEditor.setBlockType(finalBlock.block)
                try selectText(activeText, offset: offset)
                let referenceExport = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(finalBlock.name) reference export")
                let referenceDocument = renderedDocumentSignature()
                let referenceVisual = activeLineVisualSnapshot()
                let referenceStructural = activeLineStructuralSignature()

                for history in histories {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: baseMarkdown))
                    try selectText(activeText, offset: activeText.utf16.count)
                    try history.apply()
                    markdownEditor.setBlockType(finalBlock.block)
                    try selectText(activeText, offset: offset)

                    let context = "\(history.name) -> \(finalBlock.name) @\(offset)"
                    let exported = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(context) export")
                    XCTAssertEqual(exported, referenceExport, context)
                    XCTAssertFalse(exported.contains("\u{200B}"), "\(context) should not export caret anchors")
                    XCTAssertEqual(renderedDocumentSignature(), referenceDocument, context)
                    assertActiveLineSnapshot(activeLineVisualSnapshot(), matches: referenceVisual, context: context)
                    if referenceVisual.blockType == .list {
                        assertActiveListItemStructurallyMatchesReference(activeLineStructuralSignature(), referenceStructural, context: context)
                    } else {
                        XCTAssertEqual(activeLineStructuralSignature(), referenceStructural, context)
                    }
                    assertSelectionAndCaretAreHealthy(context)
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, finalBlocks.count * offsets.count * histories.count)
    }

    func testGeneratedEmptyListExitCaretMatrixCoversEightHundredRuntimeScenarios() throws {
        let markers = ["-", "*", "+", "1.", "01.", "9.", "10.", "999."]
        let followUps = [
            "a",
            "word",
            "two words",
            "punctuation.!?",
            "emoji 👩🏽‍💻",
            "RTL שלום",
            "CJK 日本語",
            "combining e\u{301}",
            "hash # heading-ish",
            "dash - list-ish",
            "one 1. ordered-ish",
            "tick `code-ish`",
            "stars **bold-ish**",
            "[link-ish](x)",
            "slash / backslash \\",
            "quote \" apostrophe '",
            "paren () bracket []",
            "math +-=*/",
            "accent ñ ü",
            "zero\u{200B}width"
        ]

        var exercised = 0
        for marker in markers {
            for entryPath in EntryPath.allCases {
                for followUp in followUps {
                    try prepareEmptyInsertionPoint(entryPath)
                    let baselineX = currentCaretRect().minX

                    typeText(marker)
                    typeText(" ")
                    XCTAssertEqual(activeRootChildType(), .list, "\(marker) / \(entryPath) / \(followUp)")

                    typeText("\n")
                    markdownEditor.textView.layoutIfNeeded()

                    XCTAssertEqual(activeRootChildType(), .paragraph, "\(marker) / \(entryPath) / \(followUp)")
                    XCTAssertEqual(activeSelectionType(), .text, debugSelectionState())
                    XCTAssertEqual(activeRootChildTextContent(), "", "\(marker) / \(entryPath) / \(followUp)")
                    XCTAssertEqual(
                        currentCaretRect().minX,
                        baselineX,
                        accuracy: 1.5,
                        "Exited paragraph should align with body text: \(marker) / \(entryPath) / \(followUp). \(debugSelectionState())"
                    )
                    XCTAssertNil(caretListItemAttribute(), "Exited paragraph must not retain list drawing attributes: \(marker) / \(entryPath) / \(followUp)")

                    typeText(followUp)
                    XCTAssertEqual(activeRootChildTextContent(), followUp.replacingOccurrences(of: "\u{200B}", with: ""), "\(marker) / \(entryPath) / \(followUp)")
                    XCTAssertFalse(markdownEditor.exportMarkdown().value?.content.contains("\u{200B}") ?? true, "\(marker) / \(entryPath) / \(followUp)")
                    assertSelectionAndCaretAreHealthy("\(marker) / \(entryPath) / \(followUp)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, 800)
    }

    func testDeletingParagraphBelowListThenEnterTwiceStillExitsList() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })

        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph, "double-enter should start a plain paragraph before the repro")
        XCTAssertNil(caretListItemAttribute(), "plain paragraph should not retain list drawing before the repro")

        typeText("Below")
        deleteCharacters("Below".utf16.count)
        markdownEditor.textView.deleteBackward()

        XCTAssertEqual(activeRootChildType(), .list, "backspacing an empty paragraph below a list should move into the previous list item")
        XCTAssertEqual(activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""), "Item")

        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .list, "first enter from the last visible list item should create one empty list item")
        XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "new list item should be canonically empty")

        typeText("\n")
        let snapshot = activeLineVisualSnapshot()
        assertCanonicalVisualSnapshot(snapshot, matches: paragraph.expected, context: "second enter after deleted following paragraph")
        XCTAssertNil(caretListItemAttribute(), "second enter should clear list drawing after deleted following paragraph")
        XCTAssertEqual(firstListChildCount(), 1, "exiting should not append unbounded empty list items")
        assertSelectionAndCaretAreHealthy("deleted paragraph below list then exit")
    }

    func testDeletingParagraphBelowToolbarListThenEnterTwiceStillExitsList() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let cases: [(name: String, block: MarkdownBlockType)] = [
            ("unordered", .unorderedList),
            ("ordered", .orderedList)
        ]

        var exercised = 0
        for testCase in cases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(testCase.block)
            typeText("Item")
            typeText("\n")
            typeText("\n")

            XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.name) toolbar list should exit before the repro")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.name) plain paragraph should not retain list drawing before the repro")

            typeText("Below")
            deleteCharacters("Below".utf16.count)
            markdownEditor.textView.deleteBackward()

            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.name) should return to the previous list item")
            XCTAssertEqual(
                activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""),
                "Item",
                "\(testCase.name) should return to the visible last list item"
            )

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.name) first enter should create one empty list item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(testCase.name) new item should be canonically empty")

            typeText("\n")
            assertCanonicalVisualSnapshot(
                activeLineVisualSnapshot(),
                matches: paragraph.expected,
                context: "\(testCase.name) toolbar list second enter after deleted following paragraph"
            )
            XCTAssertEqual(firstListChildCount(), 1, "\(testCase.name) should leave the original single-item list")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.name) second enter should clear list drawing")
            assertSelectionAndCaretAreHealthy("\(testCase.name) toolbar deleted paragraph below list")
            exercised += 1
        }

        XCTAssertEqual(exercised, cases.count)
    }

    func testDeletingParagraphBelowImportedListThenEnterTwiceStillExitsList() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let cases: [(name: String, markdown: String)] = [
            ("unordered", "- Item\n\nBelow"),
            ("ordered", "1. Item\n\nBelow")
        ]

        var exercised = 0
        for testCase in cases {
            let result = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            if case .failure(let error) = result {
                XCTFail("Failed to load \(testCase.name) repro: \(error)")
            }
            markdownEditor.textView.layoutIfNeeded()
            try selectText("Below", offset: "Below".utf16.count)
            syncNativeSelectionFromLexical()

            deleteCharacters("Below".utf16.count)
            markdownEditor.textView.deleteBackward()

            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.name) imported list should return to previous list item")
            XCTAssertEqual(
                activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""),
                "Item",
                "\(testCase.name) imported list should return to the visible last list item"
            )

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .list, "\(testCase.name) imported first enter should create one empty list item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(testCase.name) imported empty item should be canonical")

            typeText("\n")
            assertCanonicalVisualSnapshot(
                activeLineVisualSnapshot(),
                matches: paragraph.expected,
                context: "\(testCase.name) imported list second enter after deleted following paragraph"
            )
            XCTAssertEqual(firstListChildCount(), 1, "\(testCase.name) imported list should leave the original single-item list")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.name) imported second enter should clear list drawing")
            assertSelectionAndCaretAreHealthy("\(testCase.name) imported deleted paragraph below list")
            exercised += 1
        }

        XCTAssertEqual(exercised, cases.count)
    }

    func testDeletingTextFromFollowingListItemThenBackspaceDoesNotAppendListItems() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let markers = ["-", "*", "+", "1.", "2.", "10."]

        var exercised = 0
        for marker in markers {
            try resetToEmptyParagraph()
            typeText(marker)
            typeText(" ")
            typeText("Item")
            typeText("\n")
            typeText("Below")

            deleteCharacters("Below".utf16.count)
            XCTAssertEqual(activeRootChildType(), .list, "\(marker) deleting text should leave an empty list item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(marker) deleted list item should be canonically empty")

            markdownEditor.textView.deleteBackward()
            typeText("\n")
            typeText("\n")

            assertCanonicalVisualSnapshot(
                activeLineVisualSnapshot(),
                matches: paragraph.expected,
                context: "\(marker) following list item deletion eventual exit"
            )
            XCTAssertEqual(firstListChildCount(), 1, "\(marker) following list item deletion should not append unbounded empty items")
            XCTAssertNil(caretListItemAttribute(), "\(marker) following list item deletion should clear list drawing")
            assertSelectionAndCaretAreHealthy("\(marker) following list item deletion")
            exercised += 1
        }

        XCTAssertEqual(exercised, markers.count)
    }

    func testNativeReplacementDeletingParagraphBelowListThenEnterTwiceStillExitsList() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let markers = ["-", "*", "+", "1.", "2.", "10."]

        var exercised = 0
        for marker in markers {
            try resetToEmptyParagraph()
            typeText(marker)
            typeText(" ")
            typeText("Item")
            typeText("\n")
            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(marker) should begin with a paragraph below the list")

            typeText("Below")
            let visibleText = markdownEditor.textView.text as NSString
            let range = visibleText.range(of: "Below")
            XCTAssertNotEqual(range.location, NSNotFound, "\(marker) should render Below before native deletion")

            let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
            textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(marker) native deletion should leave an empty paragraph before boundary backspace")

            markdownEditor.textView.deleteBackward()
            XCTAssertEqual(activeRootChildType(), .list, "\(marker) boundary backspace should return to previous list item")
            XCTAssertEqual(
                activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""),
                "Item",
                "\(marker) boundary backspace should return to the visible last list item"
            )
            XCTAssertEqual(firstListChildCount(), 1, "\(marker) boundary backspace should not leave a phantom empty item")

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .list, "\(marker) first enter should create one empty item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(marker) new item should be canonically empty")

            typeText("\n")
            assertCanonicalVisualSnapshot(
                activeLineVisualSnapshot(),
                matches: paragraph.expected,
                context: "\(marker) native deletion below list second enter"
            )
            XCTAssertEqual(firstListChildCount(), 1, "\(marker) second enter should exit instead of appending empty items")
            XCTAssertNil(caretListItemAttribute(), "\(marker) second enter should clear list drawing")
            assertSelectionAndCaretAreHealthy("\(marker) native deletion below list")
            exercised += 1
        }

        XCTAssertEqual(exercised, markers.count)
    }

    func testEnterOnWhitespaceOnlyLastListItemExitsListAcrossMarkers() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let whitespaceCases = [" ", "\t", "\u{00A0}", "\u{200B}", "\u{200B} ", "\u{FEFF}", "\u{2060}", "\u{200C}", "\u{200D}"]
        let markers = ["-", "*", "+", "1.", "2.", "10."]

        var exercised = 0
        for marker in markers {
            for whitespace in whitespaceCases {
                try resetToEmptyParagraph()
                typeText(marker)
                typeText(" ")
                typeText("Item")
                typeText("\n")
                typeText(whitespace)

                XCTAssertEqual(activeRootChildType(), .list, "\(marker) / \(whitespace.debugDescription) should still be in the last list item before Enter")
                XCTAssertTrue(
                    isVisibleTextEmpty(activeListItemRawTextContent()),
                    "\(marker) / \(whitespace.debugDescription) should be visually empty before Enter"
                )

                typeText("\n")
                assertCanonicalVisualSnapshot(
                    activeLineVisualSnapshot(),
                    matches: paragraph.expected,
                    context: "\(marker) whitespace-only last list item exit"
                )
                XCTAssertEqual(firstListChildCount(), 1, "\(marker) / \(whitespace.debugDescription) should not append another empty item")
                XCTAssertNil(caretListItemAttribute(), "\(marker) / \(whitespace.debugDescription) should clear list drawing")
                assertSelectionAndCaretAreHealthy("\(marker) whitespace-only last list item exit")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, markers.count * whitespaceCases.count)
    }

    func testEnterOnLastListItemEmptiedByDeletingContentExitsListAcrossMarkersAndDeletionPaths() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let markers = ["-", "*", "+", "1.", "2.", "10."]
        let deletionPaths: [(name: String, delete: (String) throws -> Void)] = [
            ("key-repeat", { text in
                self.deleteCharacters(text.utf16.count)
            }),
            ("native-replacement", { text in
                let visibleText = self.markdownEditor.textView.text as NSString
                let range = visibleText.range(of: text)
                XCTAssertNotEqual(range.location, NSNotFound, "native replacement should find \(text)")
                let textStorage = try XCTUnwrap(self.markdownEditor.textView.textStorage as? TextStorage)
                textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
            })
        ]

        var exercised = 0
        for marker in markers {
            for deletionPath in deletionPaths {
                try resetToEmptyParagraph()
                typeText(marker)
                typeText(" ")
                typeText("Item")
                typeText("\n")
                typeText("Temp")

                try deletionPath.delete("Temp")
                XCTAssertEqual(activeRootChildType(), .list, "\(marker) / \(deletionPath.name) should remain in the list before Enter")
                XCTAssertTrue(
                    isVisibleTextEmpty(activeListItemRawTextContent()),
                    "\(marker) / \(deletionPath.name) should produce a visually empty last list item"
                )

                typeText("\n")
                assertCanonicalVisualSnapshot(
                    activeLineVisualSnapshot(),
                    matches: paragraph.expected,
                    context: "\(marker) / \(deletionPath.name) emptied last list item exit"
                )
                XCTAssertEqual(firstListChildCount(), 1, "\(marker) / \(deletionPath.name) should not append another empty item")
                XCTAssertNil(caretListItemAttribute(), "\(marker) / \(deletionPath.name) should clear list drawing")
                assertSelectionAndCaretAreHealthy("\(marker) / \(deletionPath.name) emptied last item")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, markers.count * deletionPaths.count)
    }

    func testDeletingFormattedBlocksBelowListsThenEnterTwiceExitsListAcrossHistories() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let markers = ["-", "*", "+", "1.", "09.", "42."]
        let followingBlocks: [(name: String, prepare: () -> Void)] = [
            ("paragraph", {
                self.typeText("Below")
            }),
            ("h1-toolbar", {
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Below")
            }),
            ("h2-toolbar", {
                self.markdownEditor.setBlockType(.heading(level: .h2))
                self.typeText("Below")
            }),
            ("h1-shortcut", {
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Below")
            }),
            ("quote", {
                self.markdownEditor.setBlockType(.quote)
                self.typeText("Below")
            }),
            ("code", {
                self.markdownEditor.setBlockType(.codeBlock)
                self.typeText("Below")
            })
        ]

        var exercised = 0
        for marker in markers {
            for followingBlock in followingBlocks {
                try resetToEmptyParagraph()
                typeText(marker)
                typeText(" ")
                typeText("Item")
                typeText("\n")
                typeText("\n")
                XCTAssertEqual(activeRootChildType(), .paragraph, "\(marker) / \(followingBlock.name) should start below the list")

                followingBlock.prepare()
                deleteCharacters("Below".utf16.count)
                markdownEditor.textView.deleteBackward()

                XCTAssertEqual(activeRootChildType(), .list, "\(marker) / \(followingBlock.name) should collapse into the previous list item")
                XCTAssertEqual(
                    activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""),
                    "Item",
                    "\(marker) / \(followingBlock.name) should return to the visible last list item"
                )

                typeText("\n")
                XCTAssertEqual(activeRootChildType(), .list, "\(marker) / \(followingBlock.name) first enter should create one empty item")
                XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(marker) / \(followingBlock.name) empty item should be canonical")

                typeText("\n")
                let snapshot = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(snapshot, matches: paragraph.expected, context: "\(marker) / \(followingBlock.name)")
                XCTAssertEqual(firstListChildCount(), 1, "\(marker) / \(followingBlock.name) should leave the original single-item list")
                XCTAssertNil(caretListItemAttribute(), "\(marker) / \(followingBlock.name) should clear list drawing")
                assertSelectionAndCaretAreHealthy("\(marker) / \(followingBlock.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, markers.count * followingBlocks.count)
    }

    func testDeletingLineBelowListThenExitingIsIndependentOfListConstructionAndShape() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let scenarios: [(name: String, expectedType: ListType, expectedVisibleItems: Int, expectedLandingText: String, prepare: () throws -> Void)] = [
            ("typed-bullet-single", .bullet, 1, "One", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
            }),
            ("typed-bullet-multiple", .bullet, 2, "Two", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("Two")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
            }),
            ("typed-ordered-multiple", .number, 2, "Two", {
                try self.resetToEmptyParagraph()
                self.typeText("1.")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("Two")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
            }),
            ("toolbar-bullet-multiple", .bullet, 2, "Two", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.unorderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("Two")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
            }),
            ("toolbar-ordered-multiple", .number, 2, "Two", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.orderedList)
                self.typeText("One")
                self.typeText("\n")
                self.typeText("Two")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
            }),
            ("imported-bullet-multiple", .bullet, 2, "Two", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n- Two\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
            }),
            ("imported-ordered-starting-at-nine", .number, 2, "Two", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "9. One\n10. Two\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
            }),
            ("imported-indented-item-before-last-item", .bullet, 3, "Two", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n  - Nested\n- Two\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
            }),
            ("imported-following-heading", .bullet, 2, "Two", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n- Two\n\n# Below"))
                try self.selectText("Below", offset: "Below".utf16.count)
            }),
            ("imported-following-quote", .bullet, 2, "Two", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n- Two\n\n> Below"))
                try self.selectText("Below", offset: "Below".utf16.count)
            })
        ]

        var exercised = 0
        for scenario in scenarios {
            try scenario.prepare()
            XCTAssertEqual(firstListType(), scenario.expectedType, scenario.name)
            XCTAssertEqual(firstListChildCount(), scenario.expectedVisibleItems, "\(scenario.name) starts with the expected visible list shape")

            deleteCharacters("Below".utf16.count)
            XCTAssertEqual(selectedBlockTextContent(), "", "\(scenario.name) should have an empty following line before the merge-back backspace")

            markdownEditor.textView.deleteBackward()
            XCTAssertEqual(activeRootChildType(), .list, "\(scenario.name) should return to the previous list item")
            XCTAssertEqual(firstListChildCount(), scenario.expectedVisibleItems, "\(scenario.name) should not create phantom list items while merging back")
            XCTAssertEqual(activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""), scenario.expectedLandingText, "\(scenario.name) should land in the last visible item")

            typeText("\n")
            XCTAssertEqual(activeRootChildType(), .list, "\(scenario.name) first enter should create one empty trailing list item")
            XCTAssertEqual(firstListChildCount(), scenario.expectedVisibleItems + 1, "\(scenario.name) should have exactly one temporary empty trailing item")
            XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(scenario.name) temporary item should be canonically empty")

            typeText("\n")
            let snapshot = activeLineVisualSnapshot()
            assertCanonicalVisualSnapshot(snapshot, matches: paragraph.expected, context: scenario.name)
            XCTAssertEqual(firstListType(), scenario.expectedType, "\(scenario.name) should preserve the original list kind")
            XCTAssertEqual(firstListChildCount(), scenario.expectedVisibleItems, "\(scenario.name) should remove the temporary empty item on exit")
            XCTAssertNil(caretListItemAttribute(), "\(scenario.name) exited paragraph should clear list rendering attributes")
            assertSelectionAndCaretAreHealthy(scenario.name)
            exercised += 1
        }

        XCTAssertEqual(exercised, scenarios.count)
    }

    func testDeletingLineBetweenListAndFollowingContentThenExitingPreservesDocumentOrder() throws {
        let paragraph = try XCTUnwrap(canonicalBlockCases.first { $0.name == "paragraph" })
        let scenarios: [(name: String, markdown: String, tail: String)] = [
            ("paragraph-tail", "- One\n- Two\n\nBelow\n\nAfter", "After"),
            ("heading-tail", "1. One\n2. Two\n\nBelow\n\n# After", "After"),
            ("list-tail", "- One\n- Two\n\nBelow\n\n- After item", "After item")
        ]
        let deletionPaths: [(name: String, delete: () throws -> Void)] = [
            ("key-repeat", {
                self.deleteCharacters("Below".utf16.count)
            }),
            ("native-replacement", {
                let visibleText = self.markdownEditor.textView.text as NSString
                let range = visibleText.range(of: "Below")
                XCTAssertNotEqual(range.location, NSNotFound, "native replacement should find Below")
                let textStorage = try XCTUnwrap(self.markdownEditor.textView.textStorage as? TextStorage)
                textStorage.replaceCharacters(in: range, with: NSAttributedString(string: ""))
            })
        ]

        var exercised = 0
        for scenario in scenarios {
            for deletionPath in deletionPaths {
                let result = markdownEditor.loadMarkdown(MarkdownDocument(content: scenario.markdown))
                if case .failure(let error) = result {
                    XCTFail("Failed to load \(scenario.name): \(error)")
                }
                markdownEditor.textView.layoutIfNeeded()
                try selectText("Below", offset: "Below".utf16.count)

                try deletionPath.delete()
                XCTAssertEqual(selectedBlockTextContent(), "", "\(scenario.name) / \(deletionPath.name) should empty the middle line before merging back")

                markdownEditor.textView.deleteBackward()
                XCTAssertEqual(activeRootChildType(), .list, "\(scenario.name) / \(deletionPath.name) should merge back into the previous list item")
                XCTAssertEqual(activeListItemRawTextContent().replacingOccurrences(of: "\u{200B}", with: ""), "Two", "\(scenario.name) / \(deletionPath.name)")
                XCTAssertTrue(markdownEditor.textView.text.contains(scenario.tail), "\(scenario.name) / \(deletionPath.name) should preserve following content while merged into list")

                typeText("\n")
                XCTAssertEqual(activeRootChildType(), .list, "\(scenario.name) / \(deletionPath.name) first enter should create one empty item")
                XCTAssertEqual(activeListItemRawTextContent(), "\u{200B}", "\(scenario.name) / \(deletionPath.name) temporary item should be canonical")

                typeText("\n")
                assertCanonicalVisualSnapshot(
                    activeLineVisualSnapshot(),
                    matches: paragraph.expected,
                    context: "\(scenario.name) / \(deletionPath.name)"
                )
                XCTAssertEqual(firstListChildCount(), 2, "\(scenario.name) / \(deletionPath.name) should keep the original visible list items only")
                XCTAssertNil(caretListItemAttribute(), "\(scenario.name) / \(deletionPath.name) exited paragraph should not draw list attributes")

                typeText("Inserted")
                let exported = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(scenario.name) / \(deletionPath.name) export")
                let insertedRange = try XCTUnwrap(exported.range(of: "Inserted"), "\(scenario.name) / \(deletionPath.name) inserted text")
                let tailRange = try XCTUnwrap(exported.range(of: scenario.tail), "\(scenario.name) / \(deletionPath.name) tail text")
                XCTAssertLessThan(insertedRange.lowerBound, tailRange.lowerBound, "\(scenario.name) / \(deletionPath.name) should insert between list and following content")
                XCTAssertEqual(
                    activeRootChildTextContent().trimmingCharacters(in: .newlines),
                    "Inserted",
                    "\(scenario.name) / \(deletionPath.name) follow-up typing should stay in the exited paragraph"
                )
                assertSelectionAndCaretAreHealthy("\(scenario.name) / \(deletionPath.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, scenarios.count * deletionPaths.count)
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

    func testCaretHeightMatrixMatchesVisibleBlockFonts() throws {
        let cases: [(name: String, block: MarkdownBlockType, text: String, font: UIFont)] = [
            ("title", .heading(level: .h1), "Title", MarkdownEditorConfiguration.default.theme.typography.h1),
            ("subtitle", .heading(level: .h2), "Subtitle", MarkdownEditorConfiguration.default.theme.typography.h2),
            ("body", .paragraph, "Body", MarkdownEditorConfiguration.default.theme.typography.body)
        ]

        for testCase in cases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(testCase.block)
            typeText(testCase.text)

            let caret = currentCaretRect()
            XCTAssertEqual(caret.height, testCase.font.lineHeight, accuracy: 1.0, testCase.name)
            assertSelectionAndCaretAreHealthy(testCase.name)
        }
    }

    func testCanonicalCaretContractsForEverySupportedBlockAcrossHistories() throws {
        for testCase in canonicalBlockCases {
            var signatures: [(HistoryPath, EmptyLineRenderSignature)] = []
            for history in HistoryPath.allCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)
                typeText(testCase.text)
                deleteCharacters(testCase.text.utf16.count)
                signatures.append((history, emptyLineRenderSignature()))
            }

            let reference = try XCTUnwrap(signatures.first?.1, testCase.name)
            for (history, signature) in signatures {
                assertCanonicalSignature(signature, matches: testCase.expected, context: "\(testCase.name) / \(history)")
                XCTAssertEqual(signature.caretX, reference.caretX, accuracy: 1.5, "\(testCase.name) / \(history): \(signature.debugState), reference native=\(reference.nativeRange)")
                XCTAssertEqual(signature.caretHeight, reference.caretHeight, accuracy: 1.0, "\(testCase.name) / \(history)")
                XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, "\(testCase.name) / \(history)")
                XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, "\(testCase.name) / \(history)")
            }
        }
    }

    func testRenderedLineAttributeFingerprintsAreHistoryIndependentForEmptyBlocks() throws {
        for testCase in canonicalBlockCases {
            var signatures: [(HistoryPath, RenderedLineSignature)] = []
            for history in HistoryPath.allCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)
                signatures.append((history, renderedLineSignature()))
            }

            let reference = try XCTUnwrap(signatures.first?.1, testCase.name)
            for (history, signature) in signatures {
                XCTAssertEqual(signature, reference, "\(testCase.name) / \(history)")
            }
        }
    }

    func testRenderedLineAttributeFingerprintsAreHistoryIndependentForContentBlocks() throws {
        for testCase in canonicalBlockCases {
            var signatures: [(HistoryPath, RenderedLineSignature)] = []
            for history in HistoryPath.allCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)
                typeText("Canonical text")
                signatures.append((history, renderedLineSignature()))
            }

            let reference = try XCTUnwrap(signatures.first?.1, testCase.name)
            for (history, signature) in signatures {
                XCTAssertEqual(signature, reference, "\(testCase.name) / \(history)")
            }
        }
    }

    func testCanonicalCaretContractsSurviveEveryPairwiseBlockTransition() throws {
        var exercised = 0
        let transitionPairs = canonicalBlockCases.flatMap { firstBlock in
            canonicalBlockCases.compactMap { secondBlock in
                isSameToolbarControl(firstBlock, secondBlock) ? nil : (firstBlock, secondBlock)
            }
        }
        for history in HistoryPath.allCases {
            for (firstBlock, secondBlock) in transitionPairs {
                try prepareEmptyCanonicalLine(history)

                markdownEditor.setBlockType(firstBlock.block)
                typeText(firstBlock.text)
                deleteCharacters(firstBlock.text.utf16.count)

                markdownEditor.setBlockType(secondBlock.block)
                typeText(secondBlock.text)
                deleteCharacters(secondBlock.text.utf16.count)

                let signature = emptyLineRenderSignature()
                assertCanonicalSignature(signature, matches: secondBlock.expected, context: "\(history) / \(firstBlock.name) -> \(secondBlock.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * transitionPairs.count)
    }

    func testCanonicalCaretContractsSurviveHighRiskTripleBlockTransitions() throws {
        let highRiskCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for history in HistoryPath.allCases {
            for firstBlock in highRiskCases {
                for secondBlock in highRiskCases where !isSameToolbarControl(firstBlock, secondBlock) {
                    for targetBlock in highRiskCases where !isSameToolbarControl(secondBlock, targetBlock) {
                        try prepareEmptyCanonicalLine(history)

                        applyEmptyBlockTransition(firstBlock)
                        applyEmptyBlockTransition(secondBlock)
                        applyEmptyBlockTransition(targetBlock)

                        let signature = emptyLineRenderSignature()
                        assertCanonicalSignature(
                            signature,
                            matches: targetBlock.expected,
                            context: "\(history) / \(firstBlock.name) -> \(secondBlock.name) -> \(targetBlock.name)"
                        )
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * highRiskCases.count * 6 * 6)
    }

    func testCanonicalCaretContractsSurviveDeterministicLongSequenceFuzzer() throws {
        let highRiskCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for history in HistoryPath.allCases {
            for seed in 1...20 {
                try prepareEmptyCanonicalLine(history)

                var generator = DeterministicGenerator(seed: UInt64(seed) &+ UInt64(history.sequenceSeedOffset))
                var previous = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]

                for step in 0..<8 {
                    var next = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]
                    while isSameToolbarControl(previous, next) {
                        next = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]
                    }

                    applyEmptyBlockTransition(next)
                    let signature = emptyLineRenderSignature()
                    assertCanonicalSignature(
                        signature,
                        matches: next.expected,
                        context: "\(history) / seed \(seed) / step \(step) / \(previous.name) -> \(next.name)"
                    )

                    previous = next
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * 20 * 8)
    }

    private func applyEmptyBlockTransition(_ blockCase: CanonicalBlockCase) {
        markdownEditor.setBlockType(blockCase.block)
        typeText(blockCase.text)
        deleteCharacters(blockCase.text.utf16.count)
    }

    func testCanonicalCaretContractsSurviveUnicodeTypingAndDeletion() throws {
        let inputs = [
            "A",
            "ñ",
            "e\u{301}",
            "👩🏽‍💻",
            "🙂",
            "שלום",
            "日本語",
            "مرحبا",
            "नमस्ते",
            "a\u{FE0F}\u{20E3}"
        ]

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in canonicalBlockCases {
                for input in inputs {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(input)
                    deleteCharacters(input.count)

                    let signature = emptyLineRenderSignature()
                    assertCanonicalSignature(signature, matches: testCase.expected, context: "\(history) / \(testCase.name) / \(input.debugDescription)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * canonicalBlockCases.count * inputs.count)
    }

    func testHeadingCaretGeometryIsCanonicalWithContentAtStartMiddleAndEnd() throws {
        let headingCases = canonicalBlockCases.filter { $0.expected.type == .heading }
        let text = "Heading content"
        let offsets = [0, 7, (text as NSString).length]

        var exercised = 0
        for testCase in headingCases {
            for offset in offsets {
                var reference: CaretGeometry?
                for history in HistoryPath.allCases {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(text)
                    try selectActiveTextOffset(offset)

                    let geometry = caretGeometry()
                    if reference == nil {
                        reference = geometry
                    }
                    let expectedFont = testCase.expected.font

                    XCTAssertEqual(geometry.height, expectedFont.lineHeight, accuracy: 1.0, "\(testCase.name) / offset \(offset) / \(history)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(testCase.name) / offset \(offset) / \(history)")
                    XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(testCase.name) / offset \(offset) / \(history)")
                    XCTAssertNil(geometry.listItemAttribute, "\(testCase.name) / offset \(offset) / \(history)")

                    if let reference {
                        XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(testCase.name) / offset \(offset) / \(history): \(debugSelectionState()), native=\(markdownEditor.textView.selectedRange)")
                        XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(testCase.name) / offset \(offset) / \(history)")
                    }
                    assertSelectionAndCaretAreHealthy("\(testCase.name) content offset \(offset) \(history)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * offsets.count * HistoryPath.allCases.count)
    }

    func testHeadingCaretGeometryIsCanonicalWhenHeadingIsEmbeddedAmongOtherBlocks() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3)
        ]
        let text = "Shared heading"
        let offsets = [0, 6, (text as NSString).length]

        var exercised = 0
        for headingCase in headingCases {
            let documents: [(name: String, markdown: String)] = [
                ("top-only", "\(headingCase.marker) \(text)"),
                ("before-paragraph", "\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(text)"),
                ("between-paragraphs", "Intro paragraph\n\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(text)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(text)"),
                ("after-quote", "> quoted\n\(headingCase.marker) \(text)"),
                ("after-code", "```swift\nlet value = 1\n```\n\(headingCase.marker) \(text)"),
                ("between-lists", "- before\n\(headingCase.marker) \(text)\n- after")
            ]

            for offset in offsets {
                var reference: CaretGeometry?
                for document in documents {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                    try selectText(text, offset: offset)

                    XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: headingCase.blockCase.expected.font,
                        context: "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)"
                    )

                    let geometry = caretGeometry()
                    XCTAssertEqual(geometry.height, headingCase.blockCase.expected.font.lineHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertNil(geometry.listItemAttribute, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")

                    if let reference {
                        XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset): \(debugSelectionState())")
                        XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    } else {
                        reference = geometry
                    }

                    assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) embedded \(document.name) offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * offsets.count * 9)
    }

    func testWrappedHeadingCaretGeometryIsCanonicalAcrossVisualLinesAndContexts() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3)
        ]
        let text = "Wrapped heading text should occupy multiple visual lines so caret metrics stay tied to glyphs instead of paragraph row height"
        let offsets = [
            0,
            16,
            44,
            78,
            (text as NSString).length
        ]

        var exercised = 0
        for headingCase in headingCases {
            let documents: [(name: String, markdown: String)] = [
                ("top-only", "\(headingCase.marker) \(text)"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(text)"),
                ("between-paragraphs", "Intro paragraph\n\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(text)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(text)"),
                ("between-lists", "- before\n\(headingCase.marker) \(text)\n- after")
            ]

            for offset in offsets {
                var reference: CaretGeometry?
                for document in documents {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                    try selectText(text, offset: offset)

                    XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")

                    let lineCount = renderedVisualLineCountForSelectedParagraph()
                    XCTAssertGreaterThanOrEqual(lineCount, 2, "\(headingCase.blockCase.name) / \(document.name) should wrap")

                    let geometry = caretGeometry()
                    XCTAssertEqual(geometry.height, headingCase.blockCase.expected.font.lineHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    XCTAssertNil(geometry.listItemAttribute, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: headingCase.blockCase.expected.font,
                        context: "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)"
                    )

                    if let reference {
                        XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset): \(debugSelectionState())")
                        XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / offset \(offset)")
                    } else {
                        reference = geometry
                    }

                    assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) wrapped \(document.name) offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * offsets.count * 6)
    }

    func testNativeCaretOnWrappedHeadingVisualLineBoundariesIsCanonicalAcrossContexts() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h4" }), "####", .h4),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h5" }), "#####", .h5)
        ]
        let text = "Wrapped native heading selection should span several visual lines so every line-start and line-end caret stays tied to heading glyph metrics"
        let documents: [(name: String, markdown: (String, String) -> String)] = [
            ("top-only", { marker, text in "\(marker) \(text)" }),
            ("after-paragraph", { marker, text in "Intro paragraph\n\(marker) \(text)" }),
            ("between-paragraphs", { marker, text in "Intro paragraph\n\(marker) \(text)\nTrailing paragraph" }),
            ("after-unordered-list", { marker, text in "- item\n\(marker) \(text)" }),
            ("after-ordered-list", { marker, text in "1. item\n\(marker) \(text)" }),
            ("after-quote", { marker, text in "> quoted\n\(marker) \(text)" }),
            ("after-code", { marker, text in "```swift\nlet value = 1\n```\n\(marker) \(text)" }),
            ("between-lists", { marker, text in "- before\n\(marker) \(text)\n- after" })
        ]

        var exercised = 0
        var expectedExercised = 0
        for headingCase in headingCases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: documents[0].markdown(headingCase.marker, text)))
            try moveNativeCaret(toText: text, offset: 0)
            let boundaryOffsets = visualLineBoundaryOffsets(forText: text)
            XCTAssertGreaterThanOrEqual(boundaryOffsets.count, 3, "\(headingCase.blockCase.name) should expose multiple visual line boundaries")
            XCTAssertGreaterThanOrEqual(renderedVisualLineCount(forText: text), 2, "\(headingCase.blockCase.name) should wrap")
            expectedExercised += documents.count * boundaryOffsets.count

            var references: [Int: CaretGeometry] = [:]
            for offset in boundaryOffsets {
                try moveNativeCaret(toText: text, offset: offset)
                references[offset] = caretGeometry()
            }

            for document in documents {
                for offset in boundaryOffsets {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown(headingCase.marker, text)))
                    try moveNativeCaret(toText: text, offset: offset)

                    XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")

                    let geometry = caretGeometry()
                    let reference = try XCTUnwrap(references[offset], "\(headingCase.blockCase.name) reference boundary \(offset)")
                    XCTAssertEqual(geometry.height, headingCase.blockCase.expected.font.lineHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    XCTAssertNil(geometry.listItemAttribute, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset): \(debugSelectionState())")
                    XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)")
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: headingCase.blockCase.expected.font,
                        context: "\(headingCase.blockCase.name) / \(document.name) / boundary \(offset)"
                    )
                    assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) native wrapped \(document.name) boundary \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, expectedExercised)
    }

    func testInlineFormattedHeadingCaretGeometryStaysHeadingSizedAcrossContexts() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3)
        ]
        let headingMarkdown = "Plain **bold** and *italic* and ~~strike~~ plus [link text](https://example.com)"
        let probes: [(text: String, offsets: [Int])] = [
            ("bold", [0, 2, 4]),
            ("italic", [0, 3, 6]),
            ("strike", [0, 3, 6]),
            ("link text", [0, 4, 9])
        ]

        var exercised = 0
        for headingCase in headingCases {
            let documents: [(name: String, markdown: String)] = [
                ("top-only", "\(headingCase.marker) \(headingMarkdown)"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(headingMarkdown)"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(headingMarkdown)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(headingMarkdown)"),
                ("between-lists", "- before\n\(headingCase.marker) \(headingMarkdown)\n- after")
            ]

            for probe in probes {
                for offset in probe.offsets {
                    var reference: CaretGeometry?
                    for document in documents {
                        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                        try selectText(probe.text, offset: offset)

                        XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(probe.text) / \(document.name)")
                        XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(probe.text) / \(document.name)")
                        let inspection = inspectDocument()
                        XCTAssertTrue(["bold", "italic", "strike", "link"].allSatisfy { inspection.inlineTraits.contains($0) }, "\(headingCase.blockCase.name) / \(document.name)")

                        let geometry = caretGeometry()
                        XCTAssertEqual(geometry.height, headingCase.blockCase.expected.font.lineHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertNil(geometry.listItemAttribute, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)")
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: headingCase.blockCase.expected.font,
                            context: "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)"
                        )

                        if let reference {
                            XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name): \(debugSelectionState())")
                            XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(headingCase.blockCase.name) / \(probe.text) / offset \(offset) / \(document.name)")
                        } else {
                            reference = geometry
                        }

                        assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) inline \(probe.text) offset \(offset) \(document.name)")
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * probes.reduce(0) { $0 + $1.offsets.count } * 5)
    }

    func testNativeCaretAtInlineFormattedHeadingBoundariesStaysHeadingSizedAcrossContexts() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h4" }), "####", .h4),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h5" }), "#####", .h5),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h6" }), "######", .h5)
        ]
        let headingMarkdown = "Plain **bold** and *italic* and ~~strike~~ plus [link text](https://example.com)"
        let probes: [(text: String, offsets: [Int])] = [
            ("bold", [0, 1, 4]),
            ("italic", [0, 3, 6]),
            ("strike", [0, 3, 6]),
            ("link text", [0, 4, 9])
        ]
        let documents: [(name: String, markdown: (String, String) -> String)] = [
            ("top-only", { marker, text in "\(marker) \(text)" }),
            ("after-paragraph", { marker, text in "Intro paragraph\n\(marker) \(text)" }),
            ("after-unordered-list", { marker, text in "- item\n\(marker) \(text)" }),
            ("after-ordered-list", { marker, text in "1. item\n\(marker) \(text)" }),
            ("after-quote", { marker, text in "> quoted\n\(marker) \(text)" }),
            ("after-code", { marker, text in "```swift\nlet value = 1\n```\n\(marker) \(text)" }),
            ("between-lists", { marker, text in "- before\n\(marker) \(text)\n- after" })
        ]

        var exercised = 0
        for headingCase in headingCases {
            for probe in probes {
                for offset in probe.offsets {
                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: documents[0].markdown(headingCase.marker, headingMarkdown)))
                    try moveNativeCaret(toText: probe.text, offset: offset)
                    let reference = caretGeometry()

                    for document in documents {
                        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown(headingCase.marker, headingMarkdown)))
                        try moveNativeCaret(toText: probe.text, offset: offset)

                        XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / native \(probe.text) / \(document.name)")
                        XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / native \(probe.text) / \(document.name)")
                        let inspection = inspectDocument()
                        XCTAssertTrue(["bold", "italic", "strike", "link"].allSatisfy { inspection.inlineTraits.contains($0) }, "\(headingCase.blockCase.name) / native \(document.name)")

                        let geometry = caretGeometry()
                        XCTAssertEqual(geometry.height, headingCase.blockCase.expected.font.lineHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertNil(geometry.listItemAttribute, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)")
                        XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name): \(debugSelectionState())")
                        XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)")
                        assertCaretIsVerticallyBalancedInRenderedLine(
                            expectedFont: headingCase.blockCase.expected.font,
                            context: "\(headingCase.blockCase.name) / native \(probe.text) / offset \(offset) / \(document.name)"
                        )
                        assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) native inline \(probe.text) offset \(offset) \(document.name)")
                        exercised += 1
                    }
                }
            }
        }

        XCTAssertEqual(exercised, headingCases.count * probes.reduce(0) { $0 + $1.offsets.count } * documents.count)
    }

    func testDeletingEmbeddedHeadingContentLeavesCanonicalEmptyHeadingLine() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3)
        ]
        let text = "Deleted heading"

        var exercised = 0
        for headingCase in headingCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(headingCase.blockCase.block)
            typeText(text)
            deleteCharacters(text.utf16.count)
            let reference = emptyLineRenderSignature()

            let documents: [(name: String, markdown: String)] = [
                ("top-before-paragraph", "\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(text)"),
                ("between-paragraphs", "Intro paragraph\n\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(text)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(text)"),
                ("after-quote", "> quoted\n\(headingCase.marker) \(text)"),
                ("after-code", "```swift\nlet value = 1\n```\n\(headingCase.marker) \(text)"),
                ("between-lists", "- before\n\(headingCase.marker) \(text)\n- after")
            ]

            for document in documents {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                try selectText(text, offset: text.utf16.count)
                deleteCharacters(text.utf16.count)

                XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / \(document.name)")
                XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / \(document.name)")
                let signature = emptyLineRenderSignature()
                assertCanonicalSignature(signature, matches: headingCase.blockCase.expected, context: "\(headingCase.blockCase.name) / \(document.name)")
                XCTAssertEqual(signature.caretX, reference.caretX, accuracy: 1.5, "\(headingCase.blockCase.name) / \(document.name): \(debugSelectionState())")
                XCTAssertEqual(signature.caretHeight, reference.caretHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / \(document.name)")
                XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name)")
                XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / \(document.name)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: headingCase.blockCase.expected.font,
                    context: "\(headingCase.blockCase.name) / \(document.name)"
                )
                assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) deleted embedded \(document.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 8)
    }

    func testNativeReplacementDeletingEmbeddedHeadingContentLeavesCanonicalEmptyHeadingLine() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h4" }), "####", .h4),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h5" }), "#####", .h5),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h6" }), "######", .h5)
        ]
        let text = "Native deleted heading"

        var exercised = 0
        for headingCase in headingCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(headingCase.blockCase.block)
            typeText(text)
            try nativeReplaceVisibleText(text, with: "")
            let reference = emptyLineRenderSignature()

            let documents: [(name: String, markdown: String)] = [
                ("top-before-paragraph", "\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(text)"),
                ("between-paragraphs", "Intro paragraph\n\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(text)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(text)"),
                ("after-quote", "> quoted\n\(headingCase.marker) \(text)"),
                ("after-code", "```swift\nlet value = 1\n```\n\(headingCase.marker) \(text)"),
                ("between-lists", "- before\n\(headingCase.marker) \(text)\n- after")
            ]

            for document in documents {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                try moveNativeCaret(toText: text, offset: text.utf16.count)
                try nativeReplaceVisibleText(text, with: "")

                XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / native delete \(document.name)")
                XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / native delete \(document.name)")
                let signature = emptyLineRenderSignature()
                assertCanonicalSignature(signature, matches: headingCase.blockCase.expected, context: "\(headingCase.blockCase.name) / native delete \(document.name)")
                XCTAssertEqual(signature.caretX, reference.caretX, accuracy: 1.5, "\(headingCase.blockCase.name) / native delete \(document.name): \(debugSelectionState())")
                XCTAssertEqual(signature.caretHeight, reference.caretHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / native delete \(document.name)")
                XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / native delete \(document.name)")
                XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / native delete \(document.name)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: headingCase.blockCase.expected.font,
                    context: "\(headingCase.blockCase.name) / native delete \(document.name)"
                )
                assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) native deleted embedded \(document.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 8)
    }

    func testSelectedDeletionOfEmbeddedHeadingContentLeavesCanonicalEmptyHeadingLine() throws {
        let headingCases: [(blockCase: CanonicalBlockCase, marker: String, tag: HeadingTagType)] = [
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h1" }), "#", .h1),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h2" }), "##", .h2),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h3" }), "###", .h3),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h4" }), "####", .h4),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h5" }), "#####", .h5),
            (try XCTUnwrap(canonicalBlockCases.first { $0.name == "h6" }), "######", .h5)
        ]
        let text = "Selected deleted heading"

        var exercised = 0
        for headingCase in headingCases {
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(headingCase.blockCase.block)
            typeText(text)
            try selectNativeVisibleText(text)
            markdownEditor.textView.deleteBackward()
            syncNativeSelectionFromLexical()
            markdownEditor.textView.layoutIfNeeded()
            let reference = emptyLineRenderSignature()

            let documents: [(name: String, markdown: String)] = [
                ("top-before-paragraph", "\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-paragraph", "Intro paragraph\n\(headingCase.marker) \(text)"),
                ("between-paragraphs", "Intro paragraph\n\(headingCase.marker) \(text)\nTrailing paragraph"),
                ("after-unordered-list", "- item\n\(headingCase.marker) \(text)"),
                ("after-ordered-list", "1. item\n\(headingCase.marker) \(text)"),
                ("after-quote", "> quoted\n\(headingCase.marker) \(text)"),
                ("after-code", "```swift\nlet value = 1\n```\n\(headingCase.marker) \(text)"),
                ("between-lists", "- before\n\(headingCase.marker) \(text)\n- after")
            ]

            for document in documents {
                _ = markdownEditor.loadMarkdown(MarkdownDocument(content: document.markdown))
                try selectNativeVisibleText(text)
                markdownEditor.textView.deleteBackward()
                syncNativeSelectionFromLexical()
                markdownEditor.textView.layoutIfNeeded()

                XCTAssertEqual(activeRootChildType(), .heading, "\(headingCase.blockCase.name) / selected delete \(document.name)")
                XCTAssertEqual(firstHeadingTag(inActiveBlock: true), headingCase.tag, "\(headingCase.blockCase.name) / selected delete \(document.name)")
                let signature = emptyLineRenderSignature()
                assertCanonicalSignature(signature, matches: headingCase.blockCase.expected, context: "\(headingCase.blockCase.name) / selected delete \(document.name)")
                XCTAssertEqual(signature.caretX, reference.caretX, accuracy: 1.5, "\(headingCase.blockCase.name) / selected delete \(document.name): \(debugSelectionState())")
                XCTAssertEqual(signature.caretHeight, reference.caretHeight, accuracy: 1.0, "\(headingCase.blockCase.name) / selected delete \(document.name)")
                XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / selected delete \(document.name)")
                XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, "\(headingCase.blockCase.name) / selected delete \(document.name)")
                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: headingCase.blockCase.expected.font,
                    context: "\(headingCase.blockCase.name) / selected delete \(document.name)"
                )
                assertSelectionAndCaretAreHealthy("\(headingCase.blockCase.name) selected deleted embedded \(document.name)")
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * 8)
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

    func testCaretGeometryIsCanonicalWithContentAtStartMiddleAndEndForEveryBlock() throws {
        let text = "Canonical content"
        let offsets = [0, 9, (text as NSString).length]

        var exercised = 0
        for testCase in canonicalBlockCases {
            for offset in offsets {
                var reference: CaretGeometry?
                for history in HistoryPath.allCases {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(text)
                    try selectActiveTextOffset(offset)

                    let geometry = caretGeometry()
                    if reference == nil {
                        reference = geometry
                    }

                    XCTAssertEqual(geometry.height, testCase.expected.font.lineHeight, accuracy: 1.0, "\(testCase.name) / offset \(offset) / \(history)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, testCase.expected.firstLineHeadIndent, accuracy: 0.5, "\(testCase.name) / offset \(offset) / \(history)")
                    XCTAssertEqual(geometry.headIndent, testCase.expected.headIndent, accuracy: 0.5, "\(testCase.name) / offset \(offset) / \(history)")
                    if testCase.expected.allowsListAttribute {
                        XCTAssertNotNil(geometry.listItemAttribute, "\(testCase.name) / offset \(offset) / \(history)")
                    } else {
                        XCTAssertNil(geometry.listItemAttribute, "\(testCase.name) / offset \(offset) / \(history)")
                    }

                    if let reference {
                        XCTAssertEqual(geometry.x, reference.x, accuracy: 1.5, "\(testCase.name) / offset \(offset) / \(history): \(debugSelectionState()), native=\(markdownEditor.textView.selectedRange)")
                        XCTAssertEqual(geometry.height, reference.height, accuracy: 1.0, "\(testCase.name) / offset \(offset) / \(history)")
                    }
                    assertSelectionAndCaretAreHealthy("\(testCase.name) content offset \(offset) \(history)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, canonicalBlockCases.count * offsets.count * HistoryPath.allCases.count)
    }

    func testCaretVerticalBalanceMatchesRenderedGlyphLineForEveryEmptyBlockAcrossHistories() throws {
        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in canonicalBlockCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)

                assertCaretIsVerticallyBalancedInRenderedLine(
                    expectedFont: testCase.expected.font,
                    context: "\(history) / \(testCase.name) / empty"
                )
                exercised += 1
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * canonicalBlockCases.count)
    }

    func testCaretVerticalBalanceMatchesRenderedGlyphLineForEveryContentBlockAcrossHistories() throws {
        let text = "Balanced content"
        let offsets = [0, 8, (text as NSString).length]

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in canonicalBlockCases {
                for offset in offsets {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(text)
                    try selectActiveTextOffset(offset)

                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: testCase.expected.font,
                        context: "\(history) / \(testCase.name) / offset \(offset)"
                    )
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * canonicalBlockCases.count * offsets.count)
    }

    func testCaretVerticalBalanceSurvivesHighRiskTransitionsAndSequences() throws {
        let highRiskCases = canonicalBlockCases.filter {
            ["paragraph", "h1", "h2", "quote", "code", "unordered-list", "ordered-list"].contains($0.name)
        }

        var exercised = 0
        for history in HistoryPath.allCases {
            for firstBlock in highRiskCases {
                for targetBlock in highRiskCases where !isSameToolbarControl(firstBlock, targetBlock) {
                    try prepareEmptyCanonicalLine(history)
                    applyEmptyBlockTransition(firstBlock)
                    applyEmptyBlockTransition(targetBlock)

                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: targetBlock.expected.font,
                        context: "\(history) / vertical \(firstBlock.name) -> \(targetBlock.name)"
                    )
                    exercised += 1
                }
            }

            for seed in 1...10 {
                try prepareEmptyCanonicalLine(history)

                var generator = DeterministicGenerator(seed: UInt64(seed) &+ UInt64(history.sequenceSeedOffset))
                var previous = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]

                for step in 0..<6 {
                    var next = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]
                    while isSameToolbarControl(previous, next) {
                        next = highRiskCases[generator.nextIndex(upperBound: highRiskCases.count)]
                    }

                    applyEmptyBlockTransition(next)
                    assertCaretIsVerticallyBalancedInRenderedLine(
                        expectedFont: next.expected.font,
                        context: "\(history) / vertical seed \(seed) / step \(step) / \(previous.name) -> \(next.name)"
                    )
                    previous = next
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * ((highRiskCases.count * 6) + (10 * 6)))
    }

    func testCanonicalCaretGeometrySurvivesMarkdownExportImportRoundTrips() throws {
        let roundTripCases = canonicalBlockCases.filter { $0.name != "h6" }
        let text = "Roundtrip text"
        let offsets = [0, 5, (text as NSString).length]

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in roundTripCases {
                for offset in offsets {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(text)
                    try selectActiveTextOffset(offset)
                    let liveGeometry = caretGeometry()
                    let exported = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history) / \(testCase.name)")
                    XCTAssertFalse(exported.contains("\u{200B}"), "\(history) / \(testCase.name)")

                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: exported))
                    try selectText(text, offset: offset)
                    let roundTrippedGeometry = caretGeometry()

                    XCTAssertEqual(activeRootChildType(), testCase.expected.type, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(roundTrippedGeometry.height, liveGeometry.height, accuracy: 1.0, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(roundTrippedGeometry.x, liveGeometry.x, accuracy: 1.5, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(roundTrippedGeometry.firstLineHeadIndent, liveGeometry.firstLineHeadIndent, accuracy: 0.5, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(roundTrippedGeometry.headIndent, liveGeometry.headIndent, accuracy: 0.5, "\(history) / \(testCase.name) / offset \(offset)")
                    assertSelectionAndCaretAreHealthy("\(history) / \(testCase.name) roundtrip offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * roundTripCases.count * offsets.count)
    }

    func testActiveLineStateSurvivesMarkdownExportImportRoundTrips() throws {
        let roundTripCases = canonicalBlockCases.filter { $0.name != "h6" }
        let text = "Roundtrip state"
        let offsets = [0, (text as NSString).length]

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in roundTripCases {
                for offset in offsets {
                    try prepareEmptyCanonicalLine(history)
                    markdownEditor.setBlockType(testCase.block)
                    typeText(text)
                    try selectActiveTextOffset(offset)

                    let liveVisual = activeLineVisualSnapshot()
                    let liveStructural = activeLineStructuralSignature()
                    let exported = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history) / \(testCase.name)")
                    XCTAssertFalse(exported.contains("\u{200B}"), "\(history) / \(testCase.name)")

                    _ = markdownEditor.loadMarkdown(MarkdownDocument(content: exported))
                    try selectText(text, offset: offset)

                    let roundTrippedVisual = activeLineVisualSnapshot()
                    let roundTrippedStructural = activeLineStructuralSignature()
                    assertActiveLineSnapshot(
                        roundTrippedVisual,
                        matches: liveVisual,
                        context: "\(history) / \(testCase.name) / offset \(offset)"
                    )
                    XCTAssertEqual(roundTrippedStructural, liveStructural, "\(history) / \(testCase.name) / offset \(offset)")
                    assertSelectionAndCaretAreHealthy("\(history) / \(testCase.name) active-line roundtrip offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * roundTripCases.count * offsets.count)
    }

    func testHeadingCaretGeometrySurvivesUndoRedoEditorStateRoundTrips() throws {
        let headingCases = canonicalBlockCases.filter { ["h1", "h2"].contains($0.name) }
        let text = "Undo heading"
        let offsets = [0, 5, (text as NSString).length]

        var exercised = 0
        for history in HistoryPath.allCases {
            for testCase in headingCases {
                try prepareEmptyCanonicalLine(history)
                markdownEditor.setBlockType(testCase.block)
                typeText(text)

                let finalMarkdown = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history) / \(testCase.name)")
                markdownEditor.undo()
                let undoneMarkdown = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history) / \(testCase.name)")
                XCTAssertNotEqual(undoneMarkdown, finalMarkdown, "\(history) / \(testCase.name)")

                markdownEditor.redo()
                let redoneMarkdown = try XCTUnwrap(markdownEditor.exportMarkdown().value?.content, "\(history) / \(testCase.name)")
                XCTAssertEqual(redoneMarkdown, finalMarkdown, "\(history) / \(testCase.name)")

                for offset in offsets {
                    try selectText(text, offset: offset)
                    let geometry = caretGeometry()
                    XCTAssertEqual(geometry.height, testCase.expected.font.lineHeight, accuracy: 1.0, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(geometry.firstLineHeadIndent, 0, accuracy: 0.5, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertEqual(geometry.headIndent, 0, accuracy: 0.5, "\(history) / \(testCase.name) / offset \(offset)")
                    XCTAssertNil(geometry.listItemAttribute, "\(history) / \(testCase.name) / offset \(offset)")
                    assertSelectionAndCaretAreHealthy("\(history) / \(testCase.name) undo-redo offset \(offset)")
                    exercised += 1
                }
            }
        }

        XCTAssertEqual(exercised, HistoryPath.allCases.count * headingCases.count * offsets.count)
    }

    func testEmptyHeadingAfterDeleteStaysCanonicalThroughUndoRedoAcrossHistories() throws {
        let headingCases = canonicalBlockCases.filter { ["h1", "h2", "h3"].contains($0.name) }
        let text = "Undo redo heading"
        let histories: [(name: String, prepare: () throws -> Void)] = [
            ("clean", {
                try self.resetToEmptyParagraph()
            }),
            ("list-exit", {
                try self.prepareAfterListExit()
            }),
            ("delete-following-paragraph-merge-back-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("One")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("Below")
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            }),
            ("imported-list-delete-following-paragraph-merge-back-exit", {
                _ = self.markdownEditor.loadMarkdown(MarkdownDocument(content: "- One\n\nBelow"))
                try self.selectText("Below", offset: "Below".utf16.count)
                self.deleteCharacters("Below".utf16.count)
                self.markdownEditor.textView.deleteBackward()
                self.typeText("\n")
                self.typeText("\n")
            })
        ]

        var exercised = 0
        for headingCase in headingCases {
            var emptyReference: ActiveLineVisualSnapshot?
            var structuralReference: ActiveLineStructuralSignature?
            for history in histories {
                try history.prepare()
                markdownEditor.setBlockType(headingCase.block)
                typeText(text)
                deleteCharacters(text.utf16.count)

                let emptyBeforeUndo = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(emptyBeforeUndo, matches: headingCase.expected, context: "\(headingCase.name) / \(history.name) / before undo")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: headingCase.expected.font, context: "\(headingCase.name) / \(history.name) / before undo")

                markdownEditor.undo()
                assertSelectionAndCaretAreHealthy("\(headingCase.name) / \(history.name) / undo")

                markdownEditor.redo()
                try selectFirstEmptyHeading(tag: headingCase.name == "h1" ? .h1 : headingCase.name == "h2" ? .h2 : .h3)
                editor.dispatchCommand(type: .selectionChange)
                syncNativeSelectionFromLexical()

                let emptyAfterRedo = activeLineVisualSnapshot()
                assertCanonicalVisualSnapshot(emptyAfterRedo, matches: headingCase.expected, context: "\(headingCase.name) / \(history.name) / redo")
                assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: headingCase.expected.font, context: "\(headingCase.name) / \(history.name) / redo")
                let structuralAfterRedo = activeLineStructuralSignature()

                if let emptyReference, let structuralReference {
                    assertActiveLineSnapshot(emptyAfterRedo, matches: emptyReference, context: "\(headingCase.name) / \(history.name) / redo")
                    XCTAssertEqual(structuralAfterRedo, structuralReference, "\(headingCase.name) / \(history.name) / redo")
                } else {
                    emptyReference = emptyAfterRedo
                    structuralReference = structuralAfterRedo
                }

                exercised += 1
            }
        }

        XCTAssertEqual(exercised, headingCases.count * histories.count)
    }

    func testEnterAtEndOfFinalTextBlocksMovesCaretToNextLineStart() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("body", "And some text here", "And some text here"),
            ("title", "# Here's a title", "Here's a title"),
            ("subtitle", "## And a subtitle", "And a subtitle"),
            ("body after headings", "# Here's a title\n## And a subtitle\nAnd some text here", "And some text here")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try selectText(testCase.search, offset: testCase.search.utf16.count)
            markdownEditor.textView.layoutIfNeeded()

            let beforeRange = try XCTUnwrap(markdownEditor.textView.selectedTextRange, testCase.name)
            let beforeRect = markdownEditor.textView.caretRect(for: beforeRange.start)

            typeText("\n")
            markdownEditor.textView.layoutIfNeeded()

            let afterRange = try XCTUnwrap(markdownEditor.textView.selectedTextRange, testCase.name)
            let afterRect = markdownEditor.textView.caretRect(for: afterRange.start)

            if afterRect.midY == beforeRect.midY {
                XCTAssertEqual(activeSelectionType(), .text, "\(testCase.name) should remain text anchored when TextKit reports unchanged off-window geometry")
                XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.name) should land in a paragraph")
                XCTAssertEqual(activeRootChildTextContent(), "", "\(testCase.name) should create an empty paragraph")
            } else {
                XCTAssertGreaterThan(afterRect.midY, beforeRect.midY, "\(testCase.name) should move down to the inserted line")
            }
            XCTAssertGreaterThanOrEqual(afterRect.minX, 8, "\(testCase.name) should land on the body text inset")
            XCTAssertLessThanOrEqual(afterRect.minX, 20, "\(testCase.name) should not keep the previous line-end x")
            XCTAssertGreaterThanOrEqual(afterRect.minY, -1, "\(testCase.name) should not jump above the editor content")
            assertSelectionAndCaretAreHealthy(testCase.name)
        }
    }

    func testImmediateEnterCaretNeverFlashesToUpperLeftAcrossBlockHistories() throws {
        let cases: [(name: String, prepare: () throws -> UIFont)] = [
            ("body", {
                try self.resetToEmptyParagraph()
                self.typeText("Body")
                return MarkdownEditorConfiguration.default.theme.typography.body
            }),
            ("title", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                return MarkdownEditorConfiguration.default.theme.typography.body
            }),
            ("subtitle", {
                try self.resetToEmptyParagraph()
                self.markdownEditor.setBlockType(.heading(level: .h2))
                self.typeText("Subtitle")
                return MarkdownEditorConfiguration.default.theme.typography.body
            }),
            ("after-list-exit-heading", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("Item")
                self.typeText("\n")
                self.typeText("\n")
                self.markdownEditor.setBlockType(.heading(level: .h1))
                self.typeText("Title")
                return MarkdownEditorConfiguration.default.theme.typography.body
            }),
            ("shortcut-heading-after-list-exit", {
                try self.resetToEmptyParagraph()
                self.typeText("-")
                self.typeText(" ")
                self.typeText("Item")
                self.typeText("\n")
                self.typeText("\n")
                self.typeText("#")
                self.typeText(" ")
                self.typeText("Title")
                return MarkdownEditorConfiguration.default.theme.typography.body
            })
        ]

        for testCase in cases {
            let expectedNextLineFont = try testCase.prepare()
            let before = currentCaretRect()

            markdownEditor.textView.insertText("\n")
            let immediate = rawCaretRect()

            XCTAssertGreaterThanOrEqual(immediate.minX, 8, "\(testCase.name) should not flash to the left edge")
            XCTAssertLessThanOrEqual(immediate.minX, 20, "\(testCase.name) should land near body inset")
            XCTAssertGreaterThan(immediate.midY, before.midY + 2, "\(testCase.name) should immediately move to the newly-created line")
            XCTAssertGreaterThanOrEqual(immediate.height, expectedNextLineFont.lineHeight - 1, "\(testCase.name)")
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: expectedNextLineFont, context: "\(testCase.name) immediate enter")
            assertSelectionAndCaretAreHealthy("\(testCase.name) immediate enter")
        }
    }

    func testNativeEnterAfterEmbeddedBlocksNeverFlashesToUpperLeftOrStaleBlockHeight() throws {
        let bodyFont = MarkdownEditorConfiguration.default.theme.typography.body
        let cases: [(name: String, markdown: String, search: String)] = [
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-paragraph", "Intro\n# Title", "Title"),
            ("h2-between-paragraphs", "Intro\n## Subtitle\nTrailing", "Subtitle"),
            ("h1-after-unordered-list", "- item\n# Title", "Title"),
            ("h2-after-ordered-list", "1. item\n## Subtitle", "Subtitle"),
            ("h1-after-quote", "> quoted\n# Title", "Title"),
            ("h2-after-code", "```swift\nlet value = 1\n```\n## Subtitle", "Subtitle"),
            ("body-after-list-exit-shape", "- item\n\nBody", "Body")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let before = currentCaretRect()
            markdownEditor.textView.insertText("\n")
            let immediate = rawCaretRect()

            XCTAssertGreaterThanOrEqual(immediate.minX, 8, "\(testCase.name) should not flash to the left edge")
            XCTAssertLessThanOrEqual(immediate.minX, 24, "\(testCase.name) should land near body inset")
            XCTAssertGreaterThan(immediate.midY, before.midY + 2, "\(testCase.name) should immediately move to the newly-created line")
            XCTAssertGreaterThanOrEqual(immediate.height, bodyFont.lineHeight - 1, "\(testCase.name) should use body-height caret immediately")
            assertCaretIsVerticallyBalancedInRenderedLine(expectedFont: bodyFont, context: "\(testCase.name) native immediate enter")
            XCTAssertEqual(activeRootChildType(), .paragraph, "\(testCase.name) should create/select a paragraph after enter")
            XCTAssertNil(caretListItemAttribute(), "\(testCase.name) should not retain list drawing")
            assertSelectionAndCaretAreHealthy("\(testCase.name) native immediate enter")
        }
    }

    func testEnterDoesNotPublishPreviousLineCaretDuringTextStorageLayout() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("paragraph", "Body", "Body"),
            ("h1", "# Title", "Title"),
            ("h2", "## Subtitle", "Subtitle"),
            ("h3-after-body", "Body\n### Detail", "Detail"),
            ("quote", "> Quoted", "Quoted"),
            ("code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("unordered-list", "- Item", "Item"),
            ("ordered-list", "1. Item", "Item"),
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-list", "- Item\n# Title", "Title")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let before = currentCaretRect()
            let sampler = LayoutCaretSampler(textView: markdownEditor.textView)
            let previousLayoutDelegate = markdownEditor.textView.layoutManager.delegate
            markdownEditor.textView.layoutManager.delegate = sampler

            markdownEditor.textView.insertText("\n")
            let final = currentCaretRect()
            markdownEditor.textView.layoutManager.delegate = previousLayoutDelegate

            XCTAssertGreaterThan(final.midY, before.midY + 2, "\(testCase.name) should settle on the newly-created line")
            XCTAssertFalse(sampler.samples.isEmpty, "\(testCase.name) should exercise layout-time caret sampling")

            let staleSamples = sampler.samples.filter { sample in
                sample.textContainsNewLine && sample.caret.midY <= before.midY + 2
            }
            XCTAssertTrue(
                staleSamples.isEmpty,
                "\(testCase.name) published stale previous-line caret samples during text layout: \(staleSamples)"
            )
            assertSelectionAndCaretAreHealthy("\(testCase.name) layout-time enter")
        }
    }

    func testEnterDoesNotExposePreviousLineCaretDuringTextStorageProcessing() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("paragraph", "Body", "Body"),
            ("h1", "# Title", "Title"),
            ("h2", "## Subtitle", "Subtitle"),
            ("quote", "> Quoted", "Quoted"),
            ("code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("unordered-list", "- Item", "Item"),
            ("ordered-list", "1. Item", "Item"),
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-list", "- Item\n# Title", "Title")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let before = currentCaretRect()
            let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
            let sampler = TextStorageCaretSampler(textView: markdownEditor.textView, previousLineMaxY: before.maxY)
            textStorage.delegate = sampler

            markdownEditor.textView.insertText("\n")
            textStorage.delegate = nil

            XCTAssertFalse(sampler.samples.isEmpty, "\(testCase.name) should sample TextStorage processing")
            let exposedPreviousLineSamples = sampler.samples.filter { sample in
                sample.textContainsInsertedNewline && sample.caret.midY <= before.midY + 2
            }
            XCTAssertTrue(
                exposedPreviousLineSamples.isEmpty,
                "\(testCase.name) exposed previous-line caret during text storage processing: \(exposedPreviousLineSamples)"
            )
            assertSelectionAndCaretAreHealthy("\(testCase.name) text-storage enter")
        }
    }

    func testEnterDoesNotExposeCurrentLineStartSelectionDuringTextStorageProcessing() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("paragraph", "Body", "Body"),
            ("h1", "# Title", "Title"),
            ("h2", "## Subtitle", "Subtitle"),
            ("quote", "> Quoted", "Quoted"),
            ("code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("unordered-list", "- Item", "Item"),
            ("ordered-list", "1. Item", "Item"),
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-list", "- Item\n# Title", "Title")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let visibleText = markdownEditor.textView.text as NSString
            let selectedLocation = markdownEditor.textView.selectedRange.location
            let currentLineStart = visibleText.lineRange(for: NSRange(location: selectedLocation, length: 0)).location
            let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
            let sampler = TextStorageCaretSampler(textView: markdownEditor.textView, previousLineMaxY: currentCaretRect().maxY)
            textStorage.delegate = sampler

            markdownEditor.textView.insertText("\n")
            textStorage.delegate = nil

            XCTAssertFalse(sampler.samples.isEmpty, "\(testCase.name) should sample TextStorage processing")
            let exposedCurrentLineStartSamples = sampler.samples.filter { sample in
                sample.textContainsInsertedNewline
                    && sample.selectedRange.length == 0
                    && sample.selectedRange.location == currentLineStart
            }
            XCTAssertTrue(
                exposedCurrentLineStartSamples.isEmpty,
                "\(testCase.name) exposed current-line start selection during text storage processing: \(exposedCurrentLineStartSamples)"
            )
            assertSelectionAndCaretAreHealthy("\(testCase.name) text-storage current-line-start enter")
        }
    }

    func testEnterDoesNotPublishCurrentLineStartBeforeNewLineSelection() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("paragraph", "Body", "Body"),
            ("h1", "# Title", "Title"),
            ("h2", "## Subtitle", "Subtitle"),
            ("quote", "> Quoted", "Quoted"),
            ("code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("unordered-list", "- Item", "Item"),
            ("ordered-list", "1. Item", "Item"),
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-list", "- Item\n# Title", "Title")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let visibleText = markdownEditor.textView.text as NSString
            let lineRange = visibleText.lineRange(for: NSRange(location: markdownEditor.textView.selectedRange.location, length: 0))
            let currentLineStart = lineRange.location
            let currentLineEnd = markdownEditor.textView.selectedRange.location

            let lexicalTextView = try XCTUnwrap(markdownEditor.textView as? TextView)
            var published: [(text: String, range: NSRange)] = []
            lexicalTextView.nativeSelectionUpdateRecorder = { range in
                published.append((self.markdownEditor.textView.text, range))
            }

            markdownEditor.textView.insertText("\n")
            lexicalTextView.nativeSelectionUpdateRecorder = nil

            XCTAssertFalse(published.isEmpty, "\(testCase.name) should publish a native selection update")
            let staleStarts = published.filter { sample in
                sample.text.count > visibleText.length
                    && sample.range.length == 0
                    && sample.range.location == currentLineStart
            }
            XCTAssertTrue(
                staleStarts.isEmpty,
                "\(testCase.name) published current-line start after Enter from \(currentLineEnd): \(published)"
            )
            assertSelectionAndCaretAreHealthy("\(testCase.name) native range publication")
        }
    }

    func testEnterCaretRectIgnoresStaleCurrentLineStartPositionsAcrossBlockTypes() throws {
        let cases: [(name: String, markdown: String, search: String)] = [
            ("paragraph", "Body", "Body"),
            ("h1", "# Title", "Title"),
            ("h2", "## Subtitle", "Subtitle"),
            ("quote", "> Quoted", "Quoted"),
            ("code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("unordered-list", "- Item", "Item"),
            ("ordered-list", "1. Item", "Item"),
            ("body-after-heading", "# Title\nBody", "Body"),
            ("h1-after-list", "- Item\n# Title", "Title")
        ]

        for testCase in cases {
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: testCase.markdown))
            try moveNativeCaret(toText: testCase.search, offset: testCase.search.utf16.count)

            let visibleText = markdownEditor.textView.text as NSString
            let selectedLocation = markdownEditor.textView.selectedRange.location
            let currentLineStart = visibleText.lineRange(for: NSRange(location: selectedLocation, length: 0)).location

            markdownEditor.textView.insertText("\n")
            markdownEditor.textView.layoutIfNeeded()

            let currentPosition = try XCTUnwrap(markdownEditor.textView.selectedTextRange?.start, testCase.name)
            let staleLineStartPosition = try XCTUnwrap(
                markdownEditor.textView.position(from: markdownEditor.textView.beginningOfDocument, offset: currentLineStart),
                testCase.name
            )
            let currentCaret = markdownEditor.textView.caretRect(for: currentPosition)
            let stalePositionCaret = markdownEditor.textView.caretRect(for: staleLineStartPosition)

            XCTAssertEqual(stalePositionCaret.minX, currentCaret.minX, accuracy: 0.5, testCase.name)
            XCTAssertEqual(stalePositionCaret.midY, currentCaret.midY, accuracy: 0.5, testCase.name)
            assertSelectionAndCaretAreHealthy("\(testCase.name) stale line-start caret rect")
        }
    }

    private var userReportedPastePayload: String {
        """
        # Heading 1
        ## Heading 2

        **bold** and *italic* and ***both***

        - bullet point
        - another one
          - nested

        1. numbered
        2. list

        [link text](https://example.com)
        ![alt text](image.jpg)

        `inline code` and:

        ```python
        def hello():
            print("hi")
        ```

        > blockquote

        | col1 | col2 |
        |------|------|
        | a    | b    |

        ---

        ~~strikethrough~~ and - [ ] task list
        """
    }

    private func prepareEmptyInsertionPoint(_ entryPath: EntryPath) throws {
        switch entryPath {
        case .emptyDocument:
            try resetToEmptyParagraph()
        case .newLineAfterBody:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "Body"))
            try selectText("Body", offset: 4)
            typeText("\n")
        case .newLineAfterTitle:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title"))
            try selectText("Title", offset: 5)
            typeText("\n")
        case .afterListExit:
            _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "- "))
            typeText("\n")
        case .afterParsedPaste:
            try resetToEmptyParagraph()
            let pasteboard = UIPasteboard.withUniqueName()
            pasteboard.string = "# Pasted"
            editor.dispatchCommand(type: .paste, payload: pasteboard)
            typeText("\n")
        }
    }

    private enum EntryPath: CaseIterable {
        case emptyDocument
        case newLineAfterBody
        case newLineAfterTitle
        case afterListExit
        case afterParsedPaste
    }

    private enum HistoryPath: CaseIterable, CustomStringConvertible {
        case clean
        case afterBodyEnter
        case afterHeadingEnter
        case afterListDoubleEnter
        case afterPasteEnter
        case afterQuoteEnter
        case afterCodeEnter

        var description: String {
            switch self {
            case .clean: return "clean"
            case .afterBodyEnter: return "afterBodyEnter"
            case .afterHeadingEnter: return "afterHeadingEnter"
            case .afterListDoubleEnter: return "afterListDoubleEnter"
            case .afterPasteEnter: return "afterPasteEnter"
            case .afterQuoteEnter: return "afterQuoteEnter"
            case .afterCodeEnter: return "afterCodeEnter"
            }
        }

        var sequenceSeedOffset: Int {
            switch self {
            case .clean: return 0
            case .afterBodyEnter: return 1_000
            case .afterHeadingEnter: return 2_000
            case .afterListDoubleEnter: return 3_000
            case .afterPasteEnter: return 4_000
            case .afterQuoteEnter: return 5_000
            case .afterCodeEnter: return 6_000
            }
        }
    }

    private enum EmptyBlockAnchorMode: CustomStringConvertible {
        case noChildren
        case invisibleTextAnchor

        var description: String {
            switch self {
            case .noChildren: return "noChildren"
            case .invisibleTextAnchor: return "invisibleTextAnchor"
            }
        }
    }

    private struct CanonicalBlockCase {
        let name: String
        let block: MarkdownBlockType
        let text: String
        let expected: ExpectedCaretContract
    }

    private struct ExpectedCaretContract {
        let type: NodeType
        let font: UIFont
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let allowsListAttribute: Bool
    }

    private struct DeterministicGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
        }

        mutating func nextIndex(upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state % UInt64(upperBound))
        }
    }

    private var canonicalBlockCases: [CanonicalBlockCase] {
        [
            .init(name: "paragraph", block: .paragraph, text: "Body", expected: .init(type: .paragraph, font: MarkdownEditorConfiguration.default.theme.typography.body, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h1", block: .heading(level: .h1), text: "Title", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h1, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h2", block: .heading(level: .h2), text: "Subtitle", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h2, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h3", block: .heading(level: .h3), text: "Heading 3", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h3, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h4", block: .heading(level: .h4), text: "Heading 4", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h4, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h5", block: .heading(level: .h5), text: "Heading 5", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h5, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "h6", block: .heading(level: .h6), text: "Heading 6", expected: .init(type: .heading, font: MarkdownEditorConfiguration.default.theme.typography.h5, firstLineHeadIndent: 0, headIndent: 0, allowsListAttribute: false)),
            .init(name: "quote", block: .quote, text: "Quote", expected: .init(type: .quote, font: MarkdownEditorConfiguration.default.theme.typography.body, firstLineHeadIndent: 40, headIndent: 40, allowsListAttribute: false)),
            .init(name: "code", block: .codeBlock, text: "code", expected: .init(type: .code, font: MarkdownEditorConfiguration.default.theme.typography.code, firstLineHeadIndent: 16, headIndent: 16, allowsListAttribute: false)),
            .init(name: "unordered-list", block: .unorderedList, text: "Bullet", expected: .init(type: .list, font: MarkdownEditorConfiguration.default.theme.typography.body, firstLineHeadIndent: 36, headIndent: 36, allowsListAttribute: true)),
            .init(name: "ordered-list", block: .orderedList, text: "Numbered", expected: .init(type: .list, font: MarkdownEditorConfiguration.default.theme.typography.body, firstLineHeadIndent: 36, headIndent: 36, allowsListAttribute: true))
        ]
    }

    private func isSameToolbarControl(_ lhs: CanonicalBlockCase, _ rhs: CanonicalBlockCase) -> Bool {
        if lhs.name == rhs.name { return true }
        return Set([lhs.name, rhs.name]) == Set(["h5", "h6"])
    }

    private func prepareEmptyCanonicalLine(_ history: HistoryPath) throws {
        switch history {
        case .clean:
            try resetToEmptyParagraph()
        case .afterBodyEnter:
            try resetToEmptyParagraph()
            typeText("Body")
            typeText("\n")
        case .afterHeadingEnter:
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(.heading(level: .h1))
            typeText("Title")
            typeText("\n")
        case .afterListDoubleEnter:
            try resetToEmptyParagraph()
            typeText("-")
            typeText(" ")
            typeText("Item")
            typeText("\n")
            typeText("\n")
        case .afterPasteEnter:
            try resetToEmptyParagraph()
            let pasteboard = UIPasteboard.withUniqueName()
            pasteboard.string = "# Pasted"
            editor.dispatchCommand(type: .paste, payload: pasteboard)
            typeText("\n")
        case .afterQuoteEnter:
            try resetToEmptyParagraph()
            markdownEditor.setBlockType(.quote)
            typeText("Quote")
            typeText("\n")
        case .afterCodeEnter:
            try editor.update {
                guard let root = getRoot() else {
                    XCTFail("Missing root")
                    return
                }
                for child in root.getChildren() {
                    try child.remove()
                }
                let code = createCodeNode()
                try code.append([createTextNode(text: "code")])
                let paragraph = createParagraphNode()
                let anchor = createTextNode(text: "\u{200B}")
                try paragraph.append([anchor])
                try root.append([code, paragraph])
                let point = Point(key: anchor.key, offset: 0, type: .text)
                try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
            }
            syncNativeSelectionFromLexical()
        }
        assertSelectionAndCaretAreHealthy("prepare \(history)")
    }

    private func prepareAfterListExit() throws {
        try resetToEmptyParagraph()
        typeText("-")
        typeText(" ")
        typeText("Item")
        typeText("\n")
        typeText("\n")
        XCTAssertEqual(activeRootChildType(), .paragraph)
        XCTAssertNil(caretListItemAttribute())
    }

    private func syncNativeSelectionFromLexical() {
        var nativeRange: NSRange?
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            nativeRange = try? createNativeSelection(from: selection, editor: editor).range
        }
        if let nativeRange {
            markdownEditor.textView.selectedRange = nativeRange
        }
    }

    private func typeText(_ text: String) {
        for character in text {
            markdownEditor.textView.insertText(String(character))
        }
    }

    private func composeMarkedTextSequence() {
        markdownEditor.textView.setMarkedText("s", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("す", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("すs", selectedRange: NSRange(location: 1, length: 1))
        markdownEditor.textView.setMarkedText("すし", selectedRange: NSRange(location: 0, length: 2))
        markdownEditor.textView.unmarkText()
        markdownEditor.textView.insertText(" ")
        markdownEditor.textView.setMarkedText("m", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("も", selectedRange: NSRange(location: 0, length: 1))
        markdownEditor.textView.setMarkedText("もじ", selectedRange: NSRange(location: 0, length: 2))
        markdownEditor.textView.unmarkText()
    }

    private func deleteCharacters(_ count: Int) {
        for _ in 0..<count {
            markdownEditor.textView.deleteBackward()
        }
    }

    private func resetToEmptyParagraph() throws {
        let result = markdownEditor.loadMarkdown(MarkdownDocument(content: ""))
        if case .failure(let error) = result {
            XCTFail("Failed to reset editor: \(error)")
        }
        markdownEditor.textView.layoutIfNeeded()
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func loadInvisibleOnlyParagraph(_ text: String, afterList: Bool) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            if afterList {
                let list = createListNode(listType: .bullet)
                let item = ListItemNode()
                try item.append([createTextNode(text: "Before")])
                try list.append([item])
                try root.append([list])
            }

            let paragraph = createParagraphNode()
            let anchor = createTextNode(text: text)
            try paragraph.append([anchor])
            try root.append([paragraph])

            let point = Point(key: anchor.key, offset: anchor.getTextContentSize(), type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func selectText(_ text: String, offset: Int) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            var target: TextNode?
            func visit(_ node: Node) {
                if target != nil { return }
                if let textNode = node as? TextNode, textNode.getTextContent().contains(text) {
                    target = textNode
                    return
                }
                if let element = node as? ElementNode {
                    element.getChildren().forEach(visit)
                }
            }
            visit(root)

            guard let target else {
                XCTFail("Missing text node containing \(text)")
                return
            }

            let clampedOffset = min(offset, target.getTextContentSize())
            let point = Point(key: target.key, offset: clampedOffset, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        if visibleRange.location != NSNotFound {
            markdownEditor.textView.selectedRange = NSRange(location: visibleRange.location + offset, length: 0)
        }
    }

    private func moveNativeCaret(toText text: String, offset: Int) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(text)")
        let clampedOffset = min(max(offset, 0), visibleRange.length)
        markdownEditor.textView.selectedRange = NSRange(location: visibleRange.location + clampedOffset, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func selectNativeVisibleText(_ text: String) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(text)")
        markdownEditor.textView.selectedRange = visibleRange
        try editor.update {
            guard let selection = try? getSelection() as? RangeSelection else {
                XCTFail("Missing range selection for native visible text \(text)")
                return
            }
            try selection.applyNativeSelection(NativeSelection(range: visibleRange, affinity: .forward))
        }
        markdownEditor.textView.layoutIfNeeded()
    }

    private enum NativeSelectionPropagation {
        case nativeRangeOnly
        case delegateSelectionChange
        case directLexicalSelection
    }

    private func selectNativeVisualLine(
        containing text: String,
        includeTrailingLineBreak: Bool,
        propagation: NativeSelectionPropagation
    ) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        let visibleText = markdownEditor.textView.text as NSString
        let textRange = visibleText.range(of: text)
        XCTAssertNotEqual(textRange.location, NSNotFound, "Missing visible text \(text)")

        var lineStart = textRange.location
        while lineStart > 0 && !isUTF16LineBreak(visibleText.character(at: lineStart - 1)) {
            lineStart -= 1
        }

        var lineEnd = textRange.location + textRange.length
        while lineEnd < visibleText.length && !isUTF16LineBreak(visibleText.character(at: lineEnd)) {
            lineEnd += 1
        }

        if includeTrailingLineBreak && lineEnd < visibleText.length && isUTF16LineBreak(visibleText.character(at: lineEnd)) {
            lineEnd += 1
        }

        let range = NSRange(location: lineStart, length: lineEnd - lineStart)
        markdownEditor.textView.selectedRange = range

        switch propagation {
        case .nativeRangeOnly:
            break
        case .delegateSelectionChange:
            markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        case .directLexicalSelection:
            try editor.update {
                guard let selection = try? getSelection() as? RangeSelection else {
                    XCTFail("Missing range selection for native visual line \(text)")
                    return
                }
                try selection.applyNativeSelection(NativeSelection(range: range, affinity: .forward))
            }
        }
        markdownEditor.textView.layoutIfNeeded()
    }

    private func isUTF16LineBreak(_ character: unichar) -> Bool {
        character == 10 || character == 13 || character == 0x2029
    }

    private func moveNativeCaretToFirstInvisibleAnchor() throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let anchorRange = (markdownEditor.textView.text as NSString).range(of: "\u{200B}")
        XCTAssertNotEqual(anchorRange.location, NSNotFound, "Missing invisible text anchor")
        markdownEditor.textView.selectedRange = NSRange(location: anchorRange.location, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func nativeReplaceVisibleText(_ text: String, with replacement: String) throws {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        let range = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing visible text \(text)")
        let textStorage = try XCTUnwrap(markdownEditor.textView.textStorage as? TextStorage)
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacement))
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func firstTopLevelType() -> NodeType? {
        var result: NodeType?
        try? editor.read {
            result = getRoot()?.getFirstChild().map { type(of: $0).getType() }
        }
        return result
    }

    private func activeRootChildType() -> NodeType? {
        var result: NodeType?
        try? editor.read {
            guard let block = activeRootChild() else { return }
            result = type(of: block).getType()
        }
        return result
    }

    private func firstHeadingTag(inActiveBlock: Bool = false) -> HeadingTagType? {
        var result: HeadingTagType?
        try? editor.read {
            let node = inActiveBlock ? activeRootChild() : getRoot()?.getFirstChild()
            result = (node as? HeadingNode)?.getTag()
        }
        return result
    }

    private func firstListType() -> ListType? {
        var result: ListType?
        try? editor.read {
            result = (getRoot()?.getFirstChild() as? ListNode)?.getListType()
        }
        return result
    }

    private func firstListChildCount() -> Int {
        var result = 0
        try? editor.read {
            result = (getRoot()?.getFirstChild() as? ListNode)?.getChildrenSize() ?? 0
        }
        return result
    }

    private func activeListType() -> ListType? {
        var result: ListType?
        try? editor.read {
            result = (activeRootChild() as? ListNode)?.getListType()
        }
        return result
    }

    private func activeListChildCount() -> Int {
        var result = 0
        try? editor.read {
            result = (activeRootChild() as? ListNode)?.getChildrenSize() ?? 0
        }
        return result
    }

    private func activeListItemRawTextContent() -> String {
        var result = ""
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else { return }
            let item = findMatchingParent(startingNode: anchorNode) { $0 is ListItemNode } as? ListItemNode
            result = item?.getTextContent() ?? ""
        }
        return result
    }

    private func isVisibleTextEmpty(_ text: String) -> Bool {
        text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func firstTextContent() -> String {
        var result = ""
        try? editor.read {
            result = normalizedVisibleTextContent(getRoot()?.getFirstChild()?.getTextContent() ?? "")
        }
        return result
    }

    private func activeRootChildTextContent() -> String {
        var result = ""
        try? editor.read {
            result = normalizedVisibleTextContent(activeRootChild()?.getTextContent() ?? "")
        }
        return result
    }

    private func selectedBlockTextContent() -> String {
        var result = ""
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else {
                result = activeRootChild()?.getTextContent() ?? ""
                return
            }

            let selectedBlock = findMatchingParent(startingNode: anchorNode) { candidate in
                candidate is ListItemNode
                    || candidate is ParagraphNode
                    || candidate is HeadingNode
                    || candidate is QuoteNode
                    || candidate is CodeNode
            } ?? anchorNode

            result = selectedBlock.getTextContent()
        }
        return normalizedVisibleTextContent(result)
    }

    private func normalizedVisibleTextContent(_ text: String) -> String {
        let withoutAnchors = text.replacingOccurrences(of: "\u{200B}", with: "")
        if withoutAnchors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return withoutAnchors
    }

    private struct EmptyLineRenderSignature {
        let blockType: NodeType?
        let selectionType: SelectionType?
        let textContent: String
        let caretX: CGFloat
        let caretHeight: CGFloat
        let listItemAttribute: Any?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let nativeRange: NSRange
        let debugState: String
    }

    private struct CaretGeometry {
        let x: CGFloat
        let height: CGFloat
        let listItemAttribute: Any?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
    }

    private struct RenderedLineSignature: Equatable {
        let blockType: NodeType?
        let visibleText: String
        let runs: [RenderedRunSignature]
    }

    private struct RenderedDocumentSignature: Equatable {
        let visibleText: String
        let runs: [RenderedRunSignature]
    }

    private struct ActiveLineVisualSnapshot: Equatable {
        let blockType: NodeType?
        let selectionType: SelectionType?
        let selectedBlockText: String
        let renderedLine: RenderedLineSignature
        let caretX: CGFloat
        let caretHeight: CGFloat
        let caretMidDeltaFromRenderedLine: CGFloat
        let hasListItemAttribute: Bool
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let typingPointSize: CGFloat
        let typingFirstLineHeadIndent: CGFloat
        let typingHeadIndent: CGFloat
        let typingHasListItemAttribute: Bool
        let textViewPointSize: CGFloat
        let extraLineFragment: AttributeSignature?
        let placeholderVisible: Bool
        let placeholderPointSize: CGFloat
    }

    private struct AttributeSignature: Equatable {
        let pointSize: CGFloat
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let hasListItemAttribute: Bool
    }

    private struct ActiveLineStructuralSignature: Equatable {
        let blockType: NodeType?
        let headingTag: HeadingTagType?
        let listType: ListType?
        let blockIndent: Int?
        let blockChildTypes: [NodeType]
        let textLeafContents: [String]
        let selectionType: SelectionType?
        let selectionOffset: Int?
        let anchorNodeType: NodeType?
        let anchorParentType: NodeType?
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let hasListItemAttribute: Bool
    }

    private struct RenderedRunSignature: Equatable {
        let location: Int
        let length: Int
        let fontName: String
        let pointSize: CGFloat
        let isBold: Bool
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let lineSpacing: CGFloat
        let paragraphSpacingBefore: CGFloat
        let paragraphSpacing: CGFloat
        let minimumLineHeight: CGFloat
        let hasListItemAttribute: Bool
        let hasCodeBlockDrawing: Bool
    }

    private func emptyLineRenderSignature() -> EmptyLineRenderSignature {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        return EmptyLineRenderSignature(
            blockType: activeRootChildType(),
            selectionType: activeSelectionType(),
            textContent: selectedBlockTextContent(),
            caretX: caret.minX,
            caretHeight: caret.height,
            listItemAttribute: caretListItemAttribute(),
            firstLineHeadIndent: paragraphStyle?.firstLineHeadIndent ?? 0,
            headIndent: paragraphStyle?.headIndent ?? 0,
            nativeRange: markdownEditor.textView.selectedRange,
            debugState: debugSelectionState()
        )
    }

    private func caretGeometry() -> CaretGeometry {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        return CaretGeometry(
            x: caret.minX,
            height: caret.height,
            listItemAttribute: caretListItemAttribute(),
            firstLineHeadIndent: paragraphStyle?.firstLineHeadIndent ?? 0,
            headIndent: paragraphStyle?.headIndent ?? 0
        )
    }

    private func activeLineVisualSnapshot() -> ActiveLineVisualSnapshot {
        let caret = currentCaretRect()
        let paragraphStyle = caretParagraphStyle()
        let typingAttributes = markdownEditor.textView.typingAttributes
        let typingParagraphStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let typingFont = typingAttributes[.font] as? UIFont
        let extraLineFragmentAttributes = (markdownEditor.textView.textStorage as? TextStorage)?.extraLineFragmentAttributes
        return ActiveLineVisualSnapshot(
            blockType: activeRootChildType(),
            selectionType: activeSelectionType(),
            selectedBlockText: selectedBlockTextContent(),
            renderedLine: renderedLineSignature(),
            caretX: rounded(caret.minX),
            caretHeight: rounded(caret.height),
            caretMidDeltaFromRenderedLine: rounded(caret.midY - renderedLineMidYAtCaret()),
            hasListItemAttribute: caretListItemAttribute() != nil,
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            typingPointSize: rounded(typingFont?.pointSize ?? 0),
            typingFirstLineHeadIndent: rounded(typingParagraphStyle?.firstLineHeadIndent ?? 0),
            typingHeadIndent: rounded(typingParagraphStyle?.headIndent ?? 0),
            typingHasListItemAttribute: typingAttributes[.listItem] != nil,
            textViewPointSize: rounded(markdownEditor.textView.font?.pointSize ?? 0),
            extraLineFragment: extraLineFragmentAttributes.map(attributeSignature),
            placeholderVisible: placeholderLabel()?.isHidden == false,
            placeholderPointSize: rounded(placeholderLabel()?.font.pointSize ?? 0)
        )
    }

    private func attributeSignature(_ attributes: [NSAttributedString.Key: Any]) -> AttributeSignature {
        let font = attributes[.font] as? UIFont
        let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        return AttributeSignature(
            pointSize: rounded(font?.pointSize ?? 0),
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            hasListItemAttribute: attributes[.listItem] != nil
        )
    }

    private func activeLineStructuralSignature() -> ActiveLineStructuralSignature {
        var blockType: NodeType?
        var headingTag: HeadingTagType?
        var listType: ListType?
        var blockIndent: Int?
        var blockChildTypes: [NodeType] = []
        var textLeafContents: [String] = []
        var selectionType: SelectionType?
        var selectionOffset: Int?
        var anchorNodeType: NodeType?
        var anchorParentType: NodeType?

        try? editor.read {
            let block = activeRootChild()
            blockType = block.map { type(of: $0).getType() }
            headingTag = (block as? HeadingNode)?.getTag()
            listType = (block as? ListNode)?.getListType()
            blockIndent = (block as? ElementNode)?.getIndent()
            blockChildTypes = (block as? ElementNode)?.getChildren().map { type(of: $0).getType() } ?? []

            func collectTextLeaves(_ node: Node?) {
                guard let node else { return }
                if let textNode = node as? TextNode {
                    textLeafContents.append(textNode.getTextContent())
                    return
                }
                guard let element = node as? ElementNode else { return }
                element.getChildren().forEach(collectTextLeaves)
            }
            collectTextLeaves(block)

            if let selection = try? getSelection() as? RangeSelection,
               let anchorNode = try? selection.anchor.getNode() {
                selectionType = selection.anchor.type
                selectionOffset = selection.anchor.offset
                anchorNodeType = type(of: anchorNode).getType()
                anchorParentType = anchorNode.getParent().map { type(of: $0).getType() }
            }
        }

        let paragraphStyle = caretParagraphStyle()
        return ActiveLineStructuralSignature(
            blockType: blockType,
            headingTag: headingTag,
            listType: listType,
            blockIndent: blockIndent,
            blockChildTypes: blockChildTypes,
            textLeafContents: textLeafContents,
            selectionType: selectionType,
            selectionOffset: selectionOffset,
            anchorNodeType: anchorNodeType,
            anchorParentType: anchorParentType,
            firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
            headIndent: rounded(paragraphStyle?.headIndent ?? 0),
            hasListItemAttribute: caretListItemAttribute() != nil
        )
    }

    private func renderedLineSignature() -> RenderedLineSignature {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        guard let attributedText = markdownEditor.textView.attributedText,
              attributedText.length > 0 else {
            return RenderedLineSignature(blockType: activeRootChildType(), visibleText: "", runs: [])
        }

        let text = attributedText.string as NSString
        let selectedLocation = min(max(0, markdownEditor.textView.selectedRange.location), attributedText.length - 1)
        let lineRange = text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        let clampedRange = NSRange(
            location: min(lineRange.location, attributedText.length),
            length: max(0, min(lineRange.upperBound, attributedText.length) - min(lineRange.location, attributedText.length))
        )

        let visibleText = attributedText.attributedSubstring(from: clampedRange).string
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\n", with: "")

        var runs: [RenderedRunSignature] = []
        attributedText.enumerateAttributes(in: clampedRange) { attrs, range, _ in
            let font = attrs[.font] as? UIFont
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let relativeLocation = range.location - clampedRange.location
            let rawRunText = attributedText.attributedSubstring(from: range).string
            let visibleLength = (rawRunText
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\n", with: "") as NSString).length

            runs.append(RenderedRunSignature(
                location: relativeLocation,
                length: visibleLength,
                fontName: font?.fontName ?? "",
                pointSize: rounded(font?.pointSize ?? 0),
                isBold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
                headIndent: rounded(paragraphStyle?.headIndent ?? 0),
                lineSpacing: rounded(paragraphStyle?.lineSpacing ?? 0),
                paragraphSpacingBefore: rounded(paragraphStyle?.paragraphSpacingBefore ?? 0),
                paragraphSpacing: rounded(paragraphStyle?.paragraphSpacing ?? 0),
                minimumLineHeight: rounded(paragraphStyle?.minimumLineHeight ?? 0),
                hasListItemAttribute: attrs[.listItem] != nil,
                hasCodeBlockDrawing: attrs[.codeBlockCustomDrawing] != nil
            ))
        }

        return RenderedLineSignature(
            blockType: activeRootChildType(),
            visibleText: visibleText,
            runs: runs.filter { $0.length > 0 || visibleText.isEmpty }
        )
    }

    private func renderedDocumentSignature() -> RenderedDocumentSignature {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        guard let attributedText = markdownEditor.textView.attributedText,
              attributedText.length > 0 else {
            return RenderedDocumentSignature(visibleText: "", runs: [])
        }

        let visibleText = attributedText.string.replacingOccurrences(of: "\u{200B}", with: "")
        var runs: [RenderedRunSignature] = []
        var visibleLocation = 0

        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length)) { attrs, range, _ in
            let font = attrs[.font] as? UIFont
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let runText = attributedText.attributedSubstring(from: range).string
            let visibleLength = (runText.replacingOccurrences(of: "\u{200B}", with: "") as NSString).length

            if visibleLength > 0 || visibleText.isEmpty {
                runs.append(RenderedRunSignature(
                    location: visibleLocation,
                    length: visibleLength,
                    fontName: font?.fontName ?? "",
                    pointSize: rounded(font?.pointSize ?? 0),
                    isBold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false,
                    firstLineHeadIndent: rounded(paragraphStyle?.firstLineHeadIndent ?? 0),
                    headIndent: rounded(paragraphStyle?.headIndent ?? 0),
                    lineSpacing: rounded(paragraphStyle?.lineSpacing ?? 0),
                    paragraphSpacingBefore: rounded(paragraphStyle?.paragraphSpacingBefore ?? 0),
                    paragraphSpacing: rounded(paragraphStyle?.paragraphSpacing ?? 0),
                    minimumLineHeight: rounded(paragraphStyle?.minimumLineHeight ?? 0),
                    hasListItemAttribute: attrs[.listItem] != nil,
                    hasCodeBlockDrawing: attrs[.codeBlockCustomDrawing] != nil
                ))
            }

            visibleLocation += visibleLength
        }

        return RenderedDocumentSignature(visibleText: visibleText, runs: runs)
    }

    private func rounded(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100
    }

    private func populatedHeadingOffsets(for text: String) -> [Int] {
        let length = (text as NSString).length
        return Array(Set([0, 1, length / 2, length])).sorted()
    }

    private func headingTag(for blockType: MarkdownBlockType) -> HeadingTagType? {
        guard case .heading(let level) = blockType else { return nil }
        return level.lexicalType
    }

    private func selectActiveTextOffset(_ offset: Int) throws {
        try editor.update {
            guard let selection = try? getSelection() as? RangeSelection,
                  let anchorNode = try? selection.anchor.getNode() else {
                XCTFail("Missing active selection")
                return
            }

            let textNode: TextNode? = {
                if let text = anchorNode as? TextNode {
                    return text
                }
                if let element = anchorNode as? ElementNode {
                    return element.getChildren().compactMap { $0 as? TextNode }.first
                }
                return nil
            }()

            guard let textNode else {
                XCTFail("Missing active text node")
                return
            }

            let clampedOffset = min(max(offset, 0), textNode.getTextContentSize())
            let point = Point(key: textNode.key, offset: clampedOffset, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: selection.format))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func selectFirstEmptyHeading(tag: HeadingTagType) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            let heading = root.getChildren().compactMap { $0 as? HeadingNode }.first { heading in
                heading.getTag() == tag && normalizedVisibleTextContent(heading.getTextContent()).isEmpty
            }

            guard let heading else {
                XCTFail("Missing empty heading \(tag)")
                return
            }

            let point = Point(key: heading.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func loadEmptyHeadingFixture(tag: HeadingTagType, context: String) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let heading = createHeadingNode(headingTag: tag)
            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let listBefore = createListNode(listType: .bullet)
            let itemBefore = ListItemNode()
            try itemBefore.append([createTextNode(text: "before")])
            try listBefore.append([itemBefore])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "top-before-paragraph":
                try root.append([heading, trailing])
            case "after-paragraph":
                try root.append([intro, heading])
            case "between-paragraphs":
                try root.append([intro, heading, trailing])
            case "after-unordered-list":
                try root.append([listBefore, heading])
            case "between-lists":
                try root.append([listBefore, heading, listAfter])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: heading.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func loadPopulatedHeadingFixture(tag: HeadingTagType, text: String, context: String) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let heading = createHeadingNode(headingTag: tag)
            let headingText = createTextNode(text: text)
            try heading.append([headingText])

            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let quote = createQuoteNode()
            try quote.append([createTextNode(text: "Quoted context")])
            let code = createCodeNode()
            try code.append([createTextNode(text: "code_context()")])
            let unorderedList = createListNode(listType: .bullet)
            let unorderedItem = ListItemNode()
            try unorderedItem.append([createTextNode(text: "before")])
            try unorderedList.append([unorderedItem])
            let orderedList = createListNode(listType: .number)
            let orderedItem = ListItemNode()
            try orderedItem.append([createTextNode(text: "before")])
            try orderedList.append([orderedItem])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "top-before-paragraph":
                try root.append([heading, trailing])
            case "after-paragraph":
                try root.append([intro, heading])
            case "between-paragraphs":
                try root.append([intro, heading, trailing])
            case "after-unordered-list":
                try root.append([unorderedList, heading])
            case "after-ordered-list":
                try root.append([orderedList, heading])
            case "between-lists":
                try root.append([unorderedList, heading, listAfter])
            case "after-quote":
                try root.append([quote, heading])
            case "after-code":
                try root.append([code, heading])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: headingText.key, offset: 0, type: .text)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        editor.dispatchCommand(type: .updatePlaceholderVisibility)
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func loadEmptyBlockFixture(
        blockCase: CanonicalBlockCase,
        context: String,
        anchorMode: EmptyBlockAnchorMode
    ) throws {
        try editor.update {
            guard let root = getRoot() else {
                XCTFail("Missing root")
                return
            }

            for child in root.getChildren() {
                try child.remove()
            }

            let target = try makeEmptyElement(for: blockCase.block)
            switch anchorMode {
            case .noChildren:
                break
            case .invisibleTextAnchor:
                try target.append([createTextNode(text: "\u{200B}")])
            }

            let trailing = createParagraphNode()
            try trailing.append([createTextNode(text: "Trailing paragraph")])
            let intro = createParagraphNode()
            try intro.append([createTextNode(text: "Intro paragraph")])
            let listBefore = createListNode(listType: .bullet)
            let itemBefore = ListItemNode()
            try itemBefore.append([createTextNode(text: "before")])
            try listBefore.append([itemBefore])
            let listAfter = createListNode(listType: .bullet)
            let itemAfter = ListItemNode()
            try itemAfter.append([createTextNode(text: "after")])
            try listAfter.append([itemAfter])

            switch context {
            case "after-paragraph":
                try root.append([intro, target])
            case "after-unordered-list":
                try root.append([listBefore, target])
            case "between-paragraphs":
                try root.append([intro, target, trailing])
            case "between-lists":
                try root.append([listBefore, target, listAfter])
            default:
                XCTFail("Unknown fixture context \(context)")
            }

            let point = Point(key: target.key, offset: 0, type: .element)
            try setSelection(RangeSelection(anchor: point, focus: point, format: TextFormat()))
        }
        syncNativeSelectionFromLexical()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func makeEmptyElement(for blockType: MarkdownBlockType) throws -> ElementNode {
        switch blockType {
        case .paragraph:
            return createParagraphNode()
        case .heading(let level):
            return createHeadingNode(headingTag: level.lexicalType)
        case .quote:
            return createQuoteNode()
        case .codeBlock:
            return createCodeNode()
        case .unorderedList, .orderedList:
            throw XCTSkip("List roots are not empty text blocks in this fixture")
        }
    }

    private func assertCanonicalSignature(
        _ signature: EmptyLineRenderSignature,
        matches expected: ExpectedCaretContract,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(signature.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(signature.selectionType, .text, context, file: file, line: line)
        XCTAssertEqual(signature.textContent, "", context, file: file, line: line)
        XCTAssertEqual(signature.caretHeight, expected.font.lineHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(signature.firstLineHeadIndent, expected.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.headIndent, expected.headIndent, accuracy: 0.5, context, file: file, line: line)
        if expected.allowsListAttribute {
            XCTAssertNotNil(signature.listItemAttribute, context, file: file, line: line)
        } else {
            XCTAssertNil(signature.listItemAttribute, context, file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(signature.caretX, -1, context, file: file, line: line)
    }

    private func assertCanonicalVisualSnapshot(
        _ snapshot: ActiveLineVisualSnapshot,
        matches expected: ExpectedCaretContract,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, .text, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectedBlockText, "", context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine.blockType, expected.type, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine.visibleText, "", context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, rounded(expected.font.lineHeight), accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, 0, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
        if let extraLineFragment = snapshot.extraLineFragment {
            XCTAssertEqual(extraLineFragment.pointSize, rounded(expected.font.pointSize), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.firstLineHeadIndent, rounded(expected.firstLineHeadIndent), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.headIndent, rounded(expected.headIndent), accuracy: 0.5, context, file: file, line: line)
            XCTAssertEqual(extraLineFragment.hasListItemAttribute, expected.allowsListAttribute, context, file: file, line: line)
        }
    }

    private func assertActiveLineSnapshot(
        _ snapshot: ActiveLineVisualSnapshot,
        matches reference: ActiveLineVisualSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectedBlockText, reference.selectedBlockText, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine, reference.renderedLine, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretX, reference.caretX, accuracy: 1.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, reference.caretHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, reference.caretMidDeltaFromRenderedLine, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, reference.typingPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, reference.typingFirstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, reference.typingHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, reference.typingHasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, reference.textViewPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.extraLineFragment, reference.extraLineFragment, context, file: file, line: line)
    }

    private func assertActiveLineRendering(
        _ snapshot: ActiveLineVisualSnapshot,
        matches reference: ActiveLineVisualSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(snapshot.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(snapshot.renderedLine, reference.renderedLine, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretX, reference.caretX, accuracy: 1.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretHeight, reference.caretHeight, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.caretMidDeltaFromRenderedLine, reference.caretMidDeltaFromRenderedLine, accuracy: 1.0, context, file: file, line: line)
        XCTAssertEqual(snapshot.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingPointSize, reference.typingPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingFirstLineHeadIndent, reference.typingFirstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHeadIndent, reference.typingHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.typingHasListItemAttribute, reference.typingHasListItemAttribute, context, file: file, line: line)
        XCTAssertEqual(snapshot.textViewPointSize, reference.textViewPointSize, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(snapshot.extraLineFragment, reference.extraLineFragment, context, file: file, line: line)
        XCTAssertEqual(snapshot.placeholderVisible, reference.placeholderVisible, context, file: file, line: line)
    }

    private func assertActiveListItemStructurallyMatchesReference(
        _ signature: ActiveLineStructuralSignature,
        _ reference: ActiveLineStructuralSignature,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(signature.blockType, reference.blockType, context, file: file, line: line)
        XCTAssertEqual(signature.listType, reference.listType, context, file: file, line: line)
        XCTAssertEqual(signature.textLeafContents.last, reference.textLeafContents.last, context, file: file, line: line)
        XCTAssertEqual(signature.selectionType, reference.selectionType, context, file: file, line: line)
        XCTAssertEqual(signature.selectionOffset, reference.selectionOffset, context, file: file, line: line)
        XCTAssertEqual(signature.anchorNodeType, reference.anchorNodeType, context, file: file, line: line)
        XCTAssertEqual(signature.anchorParentType, reference.anchorParentType, context, file: file, line: line)
        XCTAssertEqual(signature.firstLineHeadIndent, reference.firstLineHeadIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.headIndent, reference.headIndent, accuracy: 0.5, context, file: file, line: line)
        XCTAssertEqual(signature.hasListItemAttribute, reference.hasListItemAttribute, context, file: file, line: line)
    }

    private func assertCaretIsVerticallyBalancedInRenderedLine(
        expectedFont: UIFont,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let caret = currentCaretRect()
        let textView = markdownEditor.textView
        let attributedText = textView.attributedText ?? NSAttributedString()
        if attributedText.length > 0 {
            let location = caretAttributeLocation(
                in: attributedText.string as NSString,
                selectedLocation: textView.selectedRange.location
            )
            let actualFont = attributedText.attribute(.font, at: location, effectiveRange: nil) as? UIFont
            XCTAssertEqual(actualFont?.pointSize ?? 0, expectedFont.pointSize, accuracy: 0.5, context, file: file, line: line)
        }

        let expectedMidY = renderedLineMidYAtCaret(file: file, line: line)
        XCTAssertEqual(caret.height, expectedFont.lineHeight, accuracy: 1.0, context, file: file, line: line)
        if let oracle = validSystemCaretRectOracle(),
           abs(oracle.midY - expectedMidY) <= 1,
           oracle.height <= expectedFont.lineHeight + 3 {
            XCTAssertEqual(caret.midY, oracle.midY, accuracy: 0.5, context, file: file, line: line)
        } else {
            XCTAssertEqual(caret.midY, expectedMidY, accuracy: 1.0, context, file: file, line: line)
        }
    }

    private func validSystemCaretRectOracle(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGRect? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText else {
            XCTFail("Missing attributed text", file: file, line: line)
            return nil
        }

        let oracle = UITextView(frame: textView.frame)
        oracle.isScrollEnabled = textView.isScrollEnabled
        oracle.textContainerInset = textView.textContainerInset
        oracle.textContainer.lineFragmentPadding = textView.textContainer.lineFragmentPadding
        oracle.attributedText = attributedText
        oracle.selectedRange = textView.selectedRange
        oracle.layoutIfNeeded()

        guard let selectedTextRange = oracle.selectedTextRange else {
            XCTFail("Missing oracle selected text range", file: file, line: line)
            return nil
        }

        let caret = oracle.caretRect(for: selectedTextRange.start)
        guard caret.height > 4,
              caret.midY >= textView.textContainerInset.top - 1,
              caret.maxY <= textView.bounds.height
        else {
            return nil
        }
        return caret
    }

    private func renderedLineMidYAtCaret(file: StaticString = #filePath, line: UInt = #line) -> CGFloat {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else {
            XCTFail("Missing attributed text", file: file, line: line)
            return 0
        }

        let text = attributedText.string as NSString
        let selectedLocation = textView.selectedRange.location
        let characterLocation: Int
        if selectedLocation < text.length {
            let location = max(selectedLocation, 0)
            if selectedLocation > 0, isLineBoundary(text.character(at: location)) {
                characterLocation = selectedLocation - 1
            } else {
                characterLocation = location
            }
        } else {
            characterLocation = text.length - 1
        }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: characterLocation)
        guard glyphIndex < textView.layoutManager.numberOfGlyphs else {
            XCTFail("Missing glyph at caret", file: file, line: line)
            return 0
        }

        let usedRect = textView.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        if !usedRect.isEmpty {
            // Centre on the visual glyph line (top of used rect + half the
            // font's lineHeight). TextKit extends the used rect downward by
            // lineSpacing as bottom padding, so usedRect.midY sits below the
            // rendered cap-height centre — keep the oracle aligned with the
            // engine's caret formula.
            let font = attributedText.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont
            let lineHeight = font?.lineHeight ?? usedRect.height
            return textView.textContainerInset.top + usedRect.minY + lineHeight / 2
        }

        return textView.textContainerInset.top + logicalLineMidY(
            at: textView.selectedRange.location,
            characterLocation: characterLocation,
            attributedText: attributedText
        )
    }

    private func logicalLineMidY(
        at selectedLocation: Int,
        characterLocation: Int,
        attributedText: NSAttributedString
    ) -> CGFloat {
        let text = attributedText.string as NSString
        let targetLineStart = lineStartLocation(containing: selectedLocation, text: text)
        var lineStart = 0
        var y: CGFloat = 0

        while lineStart < targetLineStart {
            let lineEnd = nextLineBoundary(startingAt: lineStart, text: text)
            y += lineAdvance(at: max(lineStart, min(lineEnd, text.length - 1)), attributedText: attributedText)
            lineStart = min(lineEnd + 1, text.length)
        }

        if targetLineStart > 0 {
            let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
            y += paragraphStyle?.paragraphSpacingBefore ?? 0
        }

        return y + lineHeight(at: characterLocation, attributedText: attributedText) / 2
    }

    private func lineStartLocation(containing selectedLocation: Int, text: NSString) -> Int {
        guard selectedLocation > 0 else { return 0 }
        var location = min(selectedLocation, text.length)
        while location > 0 {
            if isLineBoundary(text.character(at: location - 1)) {
                return location
            }
            location -= 1
        }
        return 0
    }

    private func nextLineBoundary(startingAt startLocation: Int, text: NSString) -> Int {
        var location = max(startLocation, 0)
        while location < text.length {
            if isLineBoundary(text.character(at: location)) {
                return location
            }
            location += 1
        }
        return text.length
    }

    private func lineAdvance(at characterLocation: Int, attributedText: NSAttributedString) -> CGFloat {
        let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
        return lineHeight(at: characterLocation, attributedText: attributedText)
            + (paragraphStyle?.lineSpacing ?? 0)
            + (paragraphStyle?.paragraphSpacing ?? 0)
    }

    private func lineHeight(at characterLocation: Int, attributedText: NSAttributedString) -> CGFloat {
        let font = attributedText.attribute(.font, at: characterLocation, effectiveRange: nil) as? UIFont
        let paragraphStyle = attributedText.attribute(.paragraphStyle, at: characterLocation, effectiveRange: nil) as? NSParagraphStyle
        return max(font?.lineHeight ?? 0, paragraphStyle?.minimumLineHeight ?? 0)
    }

    private func renderedVisualLineCountForSelectedParagraph() -> Int {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return 0 }

        let text = attributedText.string as NSString
        let location = min(max(textView.selectedRange.location, 0), max(text.length - 1, 0))
        let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: 0))
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: paragraphRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return 0 }

        var lineCount = 0
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }
            lineCount += 1
            glyphIndex = effectiveRange.upperBound
        }

        return lineCount
    }

    private func renderedVisualLineCount(forText targetText: String) -> Int {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return 0 }

        let text = attributedText.string as NSString
        let targetRange = text.range(of: targetText)
        guard targetRange.location != NSNotFound else { return 0 }

        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: targetRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return 0 }

        var lineCount = 0
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }
            lineCount += 1
            glyphIndex = min(effectiveRange.upperBound, maxGlyph)
        }

        return lineCount
    }

    private func visualLineBoundaryOffsets(forText targetText: String) -> [Int] {
        let textView = markdownEditor.textView
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else {
            XCTFail("Missing attributed text")
            return []
        }

        let text = attributedText.string as NSString
        let targetRange = text.range(of: targetText)
        guard targetRange.location != NSNotFound else {
            XCTFail("Missing target text \(targetText)")
            return []
        }

        let paragraphRange = text.paragraphRange(for: NSRange(location: targetRange.location, length: 0))
        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: paragraphRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return [] }

        var offsets = Set<Int>()
        var glyphIndex = glyphRange.location
        let maxGlyph = glyphRange.upperBound
        while glyphIndex < maxGlyph {
            var effectiveRange = NSRange(location: 0, length: 0)
            _ = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            guard effectiveRange.length > 0 else { break }

            let characterRange = textView.layoutManager.characterRange(
                forGlyphRange: effectiveRange,
                actualGlyphRange: nil
            )
            let start = max(characterRange.location, targetRange.location)
            let end = min(characterRange.upperBound, targetRange.upperBound)
            if start <= end {
                offsets.insert(min(max(start - targetRange.location, 0), targetRange.length))
                offsets.insert(min(max(end - targetRange.location, 0), targetRange.length))
            }

            glyphIndex = effectiveRange.upperBound
        }

        return offsets.sorted()
    }

    private func isLineBoundary(_ character: unichar) -> Bool {
        character == 0x000A || character == 0x2028 || character == 0x2029
    }

    private func currentCaretRect() -> CGRect {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: selectedTextRange.start)
    }

    private func rawCaretRect() -> CGRect {
        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: selectedTextRange.start)
    }

    private func placeholderLabel() -> UILabel? {
        markdownEditor.textView.subviews.compactMap { $0 as? UILabel }.first
    }

    private func assertVisiblePlaceholderFont(
        _ font: UIFont,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = placeholderLabel()
        XCTAssertEqual(label?.text, "Write something", context, file: file, line: line)
        XCTAssertEqual(label?.isHidden, false, context, file: file, line: line)
        XCTAssertEqual(label?.font.pointSize ?? 0, font.pointSize, accuracy: 0.5, context, file: file, line: line)
    }

    private func caretListItemAttribute() -> Any? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return nil }
        let location = min(max(0, textView.selectedRange.location), attributedText.length - 1)
        return attributedText.attribute(.listItem, at: location, effectiveRange: nil)
    }

    private func caretParagraphStyle() -> NSParagraphStyle? {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return nil }
        let location = min(max(0, textView.selectedRange.location), attributedText.length - 1)
        return attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private func caretAttributeLocation(in text: NSString, selectedLocation: Int) -> Int {
        guard text.length > 0 else { return 0 }
        if selectedLocation < text.length {
            let location = max(selectedLocation, 0)
            if selectedLocation > 0, isLineBoundary(text.character(at: location)) {
                return selectedLocation - 1
            }
            return location
        }
        return text.length - 1
    }

    private func visibleDocumentText() -> String {
        var result = ""
        try? editor.read {
            result = getRoot()?.getTextContent()
                .replacingOccurrences(of: "\u{200B}", with: "") ?? ""
        }
        return result
    }

    private func activeSelectionType() -> SelectionType? {
        var result: SelectionType?
        try? editor.read {
            result = (try? getSelection() as? RangeSelection)?.anchor.type
        }
        return result
    }

    private func debugSelectionState() -> String {
        var result = ""
        try? editor.read {
            let rootChildren = getRoot()?.getChildren().map { type(of: $0).getType().rawValue } ?? []
            guard let selection = try? getSelection() as? RangeSelection,
                  let node = try? selection.anchor.getNode() else {
                result = "root=\(rootChildren) selection=nil"
                return
            }
            let parentType = node.getParent().map { type(of: $0).getType().rawValue } ?? "nil"
            let nodeType = type(of: node).getType().rawValue
            let childrenSize = (node as? ElementNode)?.getChildrenSize() ?? -1
            let text = node.getTextContent().debugDescription
            result = "root=\(rootChildren) anchor=(type:\(selection.anchor.type), offset:\(selection.anchor.offset), node:\(nodeType), parent:\(parentType), children:\(childrenSize), text:\(text)) native=\(markdownEditor.textView.selectedRange)"
        }
        return result
    }

    private func activeRootChild() -> Node? {
        guard let selection = try? getSelection() as? RangeSelection,
              let anchorNode = try? selection.anchor.getNode() else {
            return getRoot()?.getFirstChild()
        }

        if anchorNode is RootNode {
            return getRoot()?.getChildAtIndex(index: selection.anchor.offset)
        }

        return findMatchingParent(startingNode: anchorNode) { candidate in
            candidate.getParent() is RootNode
        } ?? anchorNode
    }

    private func inspectDocument() -> (topLevelTypes: Set<NodeType>, inlineTraits: Set<String>) {
        var topLevelTypes = Set<NodeType>()
        var inlineTraits = Set<String>()

        try? editor.read {
            guard let root = getRoot() else { return }
            topLevelTypes = Set(root.getChildren().map { type(of: $0).getType() })

            func visit(_ node: Node) {
                if let text = node as? TextNode {
                    if text.getFormat().bold { inlineTraits.insert("bold") }
                    if text.getFormat().italic { inlineTraits.insert("italic") }
                    if text.getFormat().code { inlineTraits.insert("code") }
                    if text.getFormat().strikethrough { inlineTraits.insert("strike") }
                }
                if node is LinkNode {
                    inlineTraits.insert("link")
                }
                if let element = node as? ElementNode {
                    element.getChildren().forEach(visit)
                }
            }
            visit(root)
        }

        return (topLevelTypes, inlineTraits)
    }

    private func assertSelectionAndCaretAreHealthy(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        var hasCollapsedSelection = false
        try? editor.read {
            if let selection = try? getSelection() as? RangeSelection {
                hasCollapsedSelection = selection.isCollapsed()
            }
        }
        XCTAssertTrue(hasCollapsedSelection, "Lexical selection should stay collapsed: \(context)", file: file, line: line)

        XCTAssertEqual(markdownEditor.textView.selectedRange.length, 0, "Native selection should stay collapsed: \(context)", file: file, line: line)

        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else {
            return XCTFail("Missing native selectedTextRange: \(context)", file: file, line: line)
        }

        let caret = markdownEditor.textView.caretRect(for: selectedTextRange.start)
        XCTAssertFalse(caret.isNull, "Caret should not be null: \(context)", file: file, line: line)
        XCTAssertTrue(caret.origin.x.isFinite, "Caret x should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.origin.y.isFinite, "Caret y should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.size.width.isFinite, "Caret width should be finite: \(context)", file: file, line: line)
        XCTAssertTrue(caret.size.height.isFinite, "Caret height should be finite: \(context)", file: file, line: line)
        XCTAssertGreaterThan(caret.height, 4, "Caret should have visible height: \(context)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minX, -1, "Caret should stay inside left editor bounds: \(context)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(caret.minY, -1, "Caret should stay inside top editor bounds: \(context)", file: file, line: line)
        assertTypingAttributesMatchCaretAttributes(context, file: file, line: line)
    }

    private func assertTypingAttributesMatchCaretAttributes(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return }

        let location = caretAttributeLocation(
            in: attributedText.string as NSString,
            selectedLocation: textView.selectedRange.location
        )
        let caretAttributes = attributedText.attributes(at: location, effectiveRange: nil)
        let typingAttributes = textView.typingAttributes

        let caretFont = caretAttributes[.font] as? UIFont
        let typingFont = typingAttributes[.font] as? UIFont
        XCTAssertEqual(typingFont?.pointSize ?? 0, caretFont?.pointSize ?? 0, accuracy: 0.5, "Typing font should match caret font: \(context)", file: file, line: line)

        let caretStyle = caretAttributes[.paragraphStyle] as? NSParagraphStyle
        let typingStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(typingStyle?.firstLineHeadIndent ?? 0, caretStyle?.firstLineHeadIndent ?? 0, accuracy: 0.5, "Typing firstLineHeadIndent should match caret: \(context)", file: file, line: line)
        XCTAssertEqual(typingStyle?.headIndent ?? 0, caretStyle?.headIndent ?? 0, accuracy: 0.5, "Typing headIndent should match caret: \(context)", file: file, line: line)
        XCTAssertEqual(typingAttributes[.listItem] != nil, caretAttributes[.listItem] != nil, "Typing list item attribute should match caret: \(context)", file: file, line: line)
    }
}

private final class LayoutCaretSampler: NSObject, NSLayoutManagerDelegate {
    struct Sample: CustomStringConvertible {
        let selectedRange: NSRange
        let caret: CGRect
        let textContainsNewLine: Bool

        var description: String {
            "range=\(NSStringFromRange(selectedRange)) caret=\(caret) hasNewline=\(textContainsNewLine)"
        }
    }

    private weak var textView: UITextView?
    private(set) var samples: [Sample] = []

    init(textView: UITextView) {
        self.textView = textView
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinishedFlag: Bool
    ) {
        guard let textView,
              let selectedTextRange = textView.selectedTextRange else { return }

        samples.append(Sample(
            selectedRange: textView.selectedRange,
            caret: textView.caretRect(for: selectedTextRange.start),
            textContainsNewLine: textView.text.contains("\n")
        ))
    }
}

private final class TextStorageCaretSampler: NSObject, NSTextStorageDelegate {
    struct Sample: CustomStringConvertible {
        let selectedRange: NSRange
        let caret: CGRect
        let textContainsInsertedNewline: Bool
        let editedRange: NSRange
        let changeInLength: Int

        var description: String {
            "range=\(NSStringFromRange(selectedRange)) caret=\(caret) edited=\(NSStringFromRange(editedRange)) delta=\(changeInLength) hasInsertedNewline=\(textContainsInsertedNewline)"
        }
    }

    private weak var textView: UITextView?
    private(set) var samples: [Sample] = []

    init(textView: UITextView, previousLineMaxY: CGFloat) {
        self.textView = textView
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters),
              let textView,
              let selectedTextRange = textView.selectedTextRange
        else { return }

        let text = textStorage.string as NSString
        let insertedNewlineRange = NSRange(location: max(0, editedRange.location), length: max(0, delta))
        let textContainsInsertedNewline = insertedNewlineRange.length > 0
            && insertedNewlineRange.upperBound <= text.length
            && text.substring(with: insertedNewlineRange).contains("\n")

        let caret = textView.caretRect(for: selectedTextRange.start)
        samples.append(Sample(
            selectedRange: textView.selectedRange,
            caret: caret,
            textContainsInsertedNewline: textContainsInsertedNewline,
            editedRange: editedRange,
            changeInLength: delta
        ))
    }
}
