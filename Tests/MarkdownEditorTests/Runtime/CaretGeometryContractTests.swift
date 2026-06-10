/*
 * CaretGeometryContractTests
 *
 * Caret geometry contracts with regression history (caret height/centering,
 * wrapped-line caret X, embedded/inline heading geometry, Enter timing and
 * jitter — see commits 6143c54, 4b79e79, 38a63cc).
 */

import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

final class CaretGeometryContractTests: MarkdownRuntimeTestCase {
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
}
