/*
 * ListEnterExitBehaviorTests
 *
 * List enter/exit/backspace behavior: exits from empty/whitespace items,
 * deletion below lists, marker variants, and the generated list-exit matrix.
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class ListEnterExitBehaviorTests: MarkdownRuntimeTestCase {
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

    func testGeneratedEmptyListExitCaretMatrix() throws {
        // Marker, entry path, and follow-up are independent axes (each fault
        // class — marker parsing, exit caret X, follow-up typing, ZWSP leak —
        // is at most two-axis), so instead of the full cartesian product this
        // runs every marker x entry path against representative follow-ups,
        // plus every follow-up once on a fixed marker/path.
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
        let representativeFollowUps = ["word", "emoji 👩🏽‍💻", "zero\u{200B}width"]

        func exerciseListExit(marker: String, entryPath: EntryPath, followUp: String) throws {
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
        }

        for marker in markers {
            for entryPath in EntryPath.allCases {
                for followUp in representativeFollowUps {
                    try exerciseListExit(marker: marker, entryPath: entryPath, followUp: followUp)
                }
            }
        }
        for followUp in followUps {
            try exerciseListExit(marker: "-", entryPath: EntryPath.allCases[0], followUp: followUp)
        }
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
}
