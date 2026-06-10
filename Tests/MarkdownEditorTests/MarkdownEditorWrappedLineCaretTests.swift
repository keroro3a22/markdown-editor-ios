import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

/// Repro for two reported caret bugs that survive after the Enter-polish fix:
///
///   1. **Wrapped-line caret x-offset**: when a paragraph or heading wraps to
///      a second visual line, the caret on the second line lands far to the
///      right of where the cursor character actually sits — sometimes a full
///      line-width off, pushing the caret off-screen. The user sees a missing
///      caret on the wrapped continuation of any long block.
///   2. **Vertical centering regression**: the caret was visually centered
///      against the rendered glyph baseline before the recent caret-math
///      change, and now sits slightly below the visual centre of the line.
final class MarkdownEditorWrappedLineCaretTests: MarkdownTestCase {

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

    // MARK: - 1. Wrapped-line caret x must respect the soft line break

    /// A body paragraph long enough to wrap. The caret at the start of the
    /// second visual line must land near the left inset, NOT at the prefix
    /// width of the entire paragraph.
    func testCaretAtStartOfWrappedSecondLineLandsAtLeftInset() throws {
        let longParagraph = "This demo showcases the MarkdownEditor with the following features that are described in detail throughout the document."
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: longParagraph))
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        // Find the offset of "following" — the user reported caret jumps when
        // positioned right before this word on the wrapped line.
        let text = markdownEditor.textView.text as NSString
        let target = text.range(of: "following")
        XCTAssertNotEqual(target.location, NSNotFound, "Setup: 'following' must be present")

        moveNativeCaret(toLocation: target.location)
        flushLayout()

        let caret = rawCaretRect()
        let expectedX = glyphOriginX(forCharacterAt: target.location)
        XCTAssertEqual(
            caret.minX,
            expectedX,
            accuracy: 1.5,
            "Caret on wrapped second line should agree with TextKit's glyph position (\(expectedX)pt). Actual minX=\(caret.minX) — looks like the second-line caret is being offset by the first-line width."
        )
        XCTAssertLessThanOrEqual(caret.maxX, markdownEditor.textView.bounds.width, "Caret should stay inside the visible width")
    }

    /// Same invariant at the END of the second wrapped line (the user-reported
    /// case where the caret goes completely off-screen).
    func testCaretAtEndOfWrappedParagraphStaysInsideVisibleWidth() throws {
        let longParagraph = "This demo showcases the MarkdownEditor with the following features that are described in detail throughout the document."
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: longParagraph))
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        let text = markdownEditor.textView.text as NSString
        moveNativeCaret(toLocation: text.length)
        flushLayout()

        let caret = rawCaretRect()
        XCTAssertGreaterThanOrEqual(caret.minX, 0, "Caret should not go off the left")
        XCTAssertLessThanOrEqual(
            caret.maxX,
            markdownEditor.textView.bounds.width,
            "Caret at end of wrapped paragraph went off-screen at minX=\(caret.minX) (visible width=\(markdownEditor.textView.bounds.width))."
        )
    }

    /// Same invariant for a wrapped HEADING — the user reported this affects
    /// titles too. We find the actual character index of the start of the
    /// second visual line and place the caret there.
    func testCaretAtStartOfWrappedSecondLineInHeadingLandsAtLeftInset() throws {
        let longHeading = "# Welcome to the Markdown Editor that demonstrates rich text editing"
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: longHeading))
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        let secondLineStart = try characterIndexOfSecondVisualLineStart()
        moveNativeCaret(toLocation: secondLineStart)
        flushLayout()

        let caret = rawCaretRect()
        let expectedX = glyphOriginX(forCharacterAt: secondLineStart)
        XCTAssertEqual(
            caret.minX,
            expectedX,
            accuracy: 1.5,
            "Heading caret on wrapped second line (char \(secondLineStart)) should agree with TextKit's glyph position (\(expectedX)pt). Actual minX=\(caret.minX)."
        )
    }

    /// Caret on the wrapped second line must agree with where TextKit actually
    /// drew the glyph at that character — the gold-standard "rendered position"
    /// oracle.
    func testCaretXAgreesWithTextKitGlyphPositionOnWrappedSecondLine() throws {
        let longParagraph = "This demo showcases the MarkdownEditor with the following features that are described in detail throughout the document."
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: longParagraph))
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()

        let text = markdownEditor.textView.text as NSString
        let target = text.range(of: "following")
        moveNativeCaret(toLocation: target.location)
        flushLayout()

        let tv = markdownEditor.textView
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        let glyphIndex = tv.layoutManager.glyphIndexForCharacter(at: target.location)
        let glyphLocation = tv.layoutManager.location(forGlyphAt: glyphIndex)
        let lineFragment = tv.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let expectedX = tv.textContainerInset.left + lineFragment.origin.x + glyphLocation.x

        let caret = rawCaretRect()
        XCTAssertEqual(
            caret.minX,
            expectedX,
            accuracy: 1.5,
            "Caret minX should agree with TextKit glyph position (\(expectedX)pt). Actual: \(caret.minX)pt."
        )
    }

    // MARK: - 2. Caret must be vertically centered in its rendered line

    /// On a body paragraph, the caret should sit visually centered on the
    /// glyph line — either right on the lineHeight midpoint or slightly
    /// above it (toward the cap-height centre). It must NOT sit below.
    func testBodyCaretIsVerticallyCenteredInRenderedLine() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "Hello World"))
        try moveNativeCaretToText("Hello World", offset: 5)
        flushLayout()

        let caret = rawCaretRect()
        let glyphMid = glyphLineMidY(forCharacterAt: 0)
        let drift = caret.midY - glyphMid
        XCTAssertLessThanOrEqual(drift, 0.5, "Body caret should not sit below glyph centre. Drift: \(drift)pt.")
        XCTAssertGreaterThanOrEqual(drift, -2.0, "Body caret should not ride more than ~2pt above. Drift: \(drift)pt.")
    }

    /// On a heading, same vertical-centring invariant.
    func testHeadingCaretIsVerticallyCenteredInRenderedLine() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title"))
        try moveNativeCaretToText("Title", offset: 3)
        flushLayout()

        let caret = rawCaretRect()
        let glyphMid = glyphLineMidY(forCharacterAt: 2) // skip "# "; first heading glyph
        let drift = caret.midY - glyphMid
        XCTAssertLessThanOrEqual(drift, 0.5, "Heading caret should not sit below glyph centre. Drift: \(drift)pt.")
        XCTAssertGreaterThanOrEqual(drift, -2.0, "Heading caret should not ride more than ~2pt above. Drift: \(drift)pt.")
    }

    /// After Enter the caret should sit visually centered on the new empty
    /// paragraph's rendered glyph line — within a small band of the line
    /// fragment midpoint (TextKit's lineHeight midpoint is slightly below
    /// the perceived cap-height centre, so the caret is allowed to ride
    /// up to ~1.5pt above it).
    func testCaretAfterEnterIsVerticallyCenteredOnEmptyParagraphLine() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "Anchor"))
        try moveNativeCaretToText("Anchor", offset: ("Anchor" as NSString).length)
        flushLayout()

        markdownEditor.textView.insertText("\n")
        flushLayout()

        let caret = rawCaretRect()
        let tv = markdownEditor.textView
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        guard let selectedRange = tv.selectedTextRange else { return XCTFail("no selection") }
        let caretLocation = tv.offset(from: tv.beginningOfDocument, to: selectedRange.start)
        let characterLocation = max(0, min(caretLocation, (tv.attributedText?.length ?? 1) - 1))
        let glyphIndex = tv.layoutManager.glyphIndexForCharacter(at: characterLocation)
        let lineFragment = tv.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let expectedMidY = tv.textContainerInset.top + lineFragment.midY

        let drift = caret.midY - expectedMidY
        XCTAssertLessThanOrEqual(drift, 0.5, "Caret on new empty paragraph should not sit below the line fragment centre. Drift: \(drift)pt.")
        XCTAssertGreaterThanOrEqual(drift, -2.0, "Caret on new empty paragraph should not ride more than ~2pt above centre. Drift: \(drift)pt.")
    }

    /// Caret on the second paragraph of an existing two-paragraph document
    /// must sit visually centered on its rendered glyph line.
    func testCaretOnSecondParagraphIsVerticallyCenteredOnGlyphLine() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "First\nSecond"))
        try moveNativeCaretToText("Second", offset: 3)
        flushLayout()

        let caret = rawCaretRect()
        let tv = markdownEditor.textView
        let secondText = (tv.text as NSString).range(of: "Second")
        let glyphIndex = tv.layoutManager.glyphIndexForCharacter(at: secondText.location)
        let used = tv.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let expectedMidY = tv.textContainerInset.top + used.midY

        let drift = caret.midY - expectedMidY
        XCTAssertLessThanOrEqual(drift, 0.5, "Caret on second paragraph should not sit below glyph centre. Drift: \(drift)pt.")
        XCTAssertGreaterThanOrEqual(drift, -2.0, "Caret on second paragraph should not ride more than ~2pt above. Drift: \(drift)pt.")
    }

    // MARK: - Helpers

    private func rawCaretRect() -> CGRect {
        guard let range = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: range.start)
    }

    private func flushLayout() {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func moveNativeCaret(toLocation location: Int) {
        flushLayout()
        let clamped = max(0, min(location, (markdownEditor.textView.text as NSString).length))
        markdownEditor.textView.selectedRange = NSRange(location: clamped, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        flushLayout()
    }

    private func moveNativeCaretToText(_ search: String, offset: Int) throws {
        flushLayout()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: search)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(search)")
        let clampedOffset = min(max(offset, 0), visibleRange.length)
        moveNativeCaret(toLocation: visibleRange.location + clampedOffset)
    }

    /// TextKit's rendered glyph X for the character at `location` — the
    /// gold-standard caret position oracle.
    private func glyphOriginX(forCharacterAt location: Int) -> CGFloat {
        let tv = markdownEditor.textView
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        let glyphIndex = tv.layoutManager.glyphIndexForCharacter(at: location)
        let glyphLocation = tv.layoutManager.location(forGlyphAt: glyphIndex)
        let lineFragment = tv.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return tv.textContainerInset.left + lineFragment.origin.x + glyphLocation.x
    }

    private func characterIndexOfSecondVisualLineStart() throws -> Int {
        let tv = markdownEditor.textView
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        var glyphIndex = 0
        let totalGlyphs = tv.layoutManager.numberOfGlyphs
        var firstLineRange = NSRange(location: 0, length: 0)
        guard totalGlyphs > 0 else {
            XCTFail("Fixture rendered no glyphs — the wrapped-line fixture is broken, not skippable")
            throw LexicalError.invariantViolation("no glyphs")
        }
        _ = tv.layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &firstLineRange)
        let secondLineGlyphStart = firstLineRange.upperBound
        guard secondLineGlyphStart < totalGlyphs else {
            XCTFail("Fixture did not wrap into a second visual line — lengthen the fixture, do not skip")
            throw LexicalError.invariantViolation("fixture did not wrap")
        }
        let charRange = tv.layoutManager.characterRange(
            forGlyphRange: NSRange(location: secondLineGlyphStart, length: 1),
            actualGlyphRange: nil
        )
        return charRange.location
    }

    private func glyphLineMidY(forCharacterAt characterLocation: Int) -> CGFloat {
        let tv = markdownEditor.textView
        guard let attributedText = tv.attributedText, attributedText.length > 0 else { return 0 }
        let clamped = min(max(0, characterLocation), attributedText.length - 1)
        tv.layoutManager.ensureLayout(for: tv.textContainer)
        let glyphIndex = tv.layoutManager.glyphIndexForCharacter(at: clamped)
        let used = tv.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return tv.textContainerInset.top + used.midY
    }
}
