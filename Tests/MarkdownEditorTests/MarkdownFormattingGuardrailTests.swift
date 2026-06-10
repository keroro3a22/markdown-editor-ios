/*
 * MarkdownFormattingGuardrailTests
 *
 * Live-editor coverage for the formatting business rules enforced by
 * MarkdownLexicalBridge.applyFormatting:
 *  1. No inline formatting inside code blocks.
 *  2. No formatting across a multi-block selection.
 *  3. Code is incompatible with bold/italic/strikethrough — both within a
 *     single request and against the formatting already at the selection.
 * Each rejection surfaces as a .unsupportedFeature delegate error and leaves
 * the document unchanged.
 */

import XCTest
@testable import MarkdownEditor
import Lexical

final class MarkdownFormattingGuardrailTests: XCTestCase {

    private final class DelegateRecorder: MarkdownEditorDelegate {
        var errors: [MarkdownEditorError] = []
        func markdownEditor(_ editor: any MarkdownEditorInterface, didEncounterError error: MarkdownEditorError) {
            errors.append(error)
        }
    }

    private var editorView: MarkdownEditorContentView!
    private var recorder: DelegateRecorder!

    override func setUp() {
        super.setUp()
        editorView = MarkdownEditorContentView()
        editorView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        recorder = DelegateRecorder()
        editorView.delegate = recorder
    }

    override func tearDown() {
        editorView = nil
        recorder = nil
        super.tearDown()
    }

    private func loadAndExport(_ markdown: String) -> String {
        if case .failure(let error) = editorView.loadMarkdown(MarkdownDocument(content: markdown)) {
            XCTFail("Failed to load fixture markdown: \(error)")
        }
        return exportContent()
    }

    private func exportContent() -> String {
        switch editorView.exportMarkdown() {
        case .success(let doc): return doc.content
        case .failure: XCTFail("Export failed"); return ""
        }
    }

    private func selectAll(of nodeMatch: @escaping (Node) -> Bool) throws {
        try editorView.editorForTesting.update {
            guard let root = getRoot() else { return XCTFail("No root") }

            func findTextNodes(_ node: Node) -> [TextNode] {
                if let text = node as? TextNode { return [text] }
                guard let element = node as? ElementNode else { return [] }
                return element.getChildren().flatMap(findTextNodes)
            }

            guard let block = root.getChildren().first(where: nodeMatch),
                  let firstText = findTextNodes(block).first,
                  let lastText = findTextNodes(block).last else {
                return XCTFail("Fixture block or text node not found")
            }

            let anchor = Point(key: firstText.key, offset: 0, type: .text)
            let focus = Point(key: lastText.key, offset: lastText.getTextContentSize(), type: .text)
            // Mirror Lexical's user-selection behavior: the selection's format
            // field reflects the formatting of the selected text.
            try setSelection(RangeSelection(anchor: anchor, focus: focus, format: firstText.getFormat()))
        }
    }

    private func assertRejected(_ before: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(recorder.errors.count, 1, "Expected exactly one delegate error", file: file, line: line)
        if case .unsupportedFeature = recorder.errors.first {
        } else {
            XCTFail("Expected .unsupportedFeature, got \(String(describing: recorder.errors.first))", file: file, line: line)
        }
        XCTAssertEqual(exportContent(), before, "Rejected formatting must not change the document", file: file, line: line)
    }

    // MARK: - Rule 1: code blocks reject inline formatting

    func testBoldInsideCodeBlockIsRejected() throws {
        let before = loadAndExport("```\nlet x = 1\n```")
        try selectAll(of: { $0 is CodeNode })

        editorView.applyFormatting([.bold])

        assertRejected(before)
    }

    // MARK: - Rule 2: multi-block selections reject formatting

    func testBoldAcrossTwoParagraphsIsRejected() throws {
        let before = loadAndExport("Hello world\n\nSecond paragraph")
        try editorView.editorForTesting.update {
            guard let root = getRoot(),
                  let first = root.getChildren().first as? ElementNode,
                  let last = root.getChildren().last as? ElementNode,
                  first.key != last.key,
                  let firstText = first.getFirstChild() as? TextNode,
                  let lastText = last.getFirstChild() as? TextNode else {
                return XCTFail("Fixture should produce two paragraphs with text")
            }
            let anchor = Point(key: firstText.key, offset: 2, type: .text)
            let focus = Point(key: lastText.key, offset: 3, type: .text)
            try setSelection(RangeSelection(anchor: anchor, focus: focus, format: TextFormat()))
        }

        editorView.applyFormatting([.bold])

        assertRejected(before)
    }

    // MARK: - Rule 3: code is incompatible with bold/italic/strikethrough

    func testCodePlusBoldInOneRequestIsRejected() throws {
        let before = loadAndExport("Plain paragraph text")
        try selectAll(of: { $0 is ParagraphNode })

        editorView.applyFormatting([.code, .bold])

        assertRejected(before)
    }

    func testCodeToggleOnBoldTextIsRejected() throws {
        let before = loadAndExport("**already bold**")
        try selectAll(of: { $0 is ParagraphNode })
        XCTAssertTrue(editorView.getCurrentFormatting().contains(.bold), "Fixture selection should be bold")

        editorView.applyFormatting([.code])

        assertRejected(before)
    }

    func testBoldToggleOnInlineCodeIsRejected() throws {
        let before = loadAndExport("`inline code`")
        try selectAll(of: { $0 is ParagraphNode })
        XCTAssertTrue(editorView.getCurrentFormatting().contains(.code), "Fixture selection should be inline code")

        editorView.applyFormatting([.bold])

        assertRejected(before)
    }

    // MARK: - Control: allowed formatting still applies

    func testBoldOnPlainParagraphApplies() throws {
        _ = loadAndExport("Plain paragraph text")
        try selectAll(of: { $0 is ParagraphNode })

        editorView.applyFormatting([.bold])

        XCTAssertTrue(recorder.errors.isEmpty, "No delegate error expected, got \(recorder.errors)")
        XCTAssertTrue(exportContent().contains("**"), "Bold should serialize as ** markers")
    }
}
