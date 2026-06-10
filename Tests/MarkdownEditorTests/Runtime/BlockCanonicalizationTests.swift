/*
 * BlockCanonicalizationTests
 *
 * Equivalent histories must converge to identical canonical block state:
 * convergence matrices, transition fuzzers, and export/import + undo/redo
 * round-trips (the live-vs-fresh-import oracle lives here).
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class BlockCanonicalizationTests: MarkdownRuntimeTestCase {
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
}
