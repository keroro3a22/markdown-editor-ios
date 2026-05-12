import XCTest
@testable import Lexical
import LexicalListPlugin
import LexicalLinkPlugin
@testable import MarkdownEditor

/// Regression coverage for two reported polish bugs around the Enter key:
///
///   1. **Cursor jumps**: pressing Enter sometimes causes the caret to take a
///      visibly jittery path (wrong x, wrong height, brief flash to an unrelated
///      line, etc.) before settling on the newly-inserted line.
///   2. **Content shifts down**: under "weird circumstances" the rendered
///      content above the insertion point appears to slide downward when a new
///      line is created — i.e. the previous block changes its on-screen y.
///
/// These tests do not attempt to fix anything. They encode measurable
/// invariants that a user would perceive as smooth/glitch-free Enter, and are
/// expected to fail (or be brittle) until the underlying behavior is hardened.
final class MarkdownEditorEnterPolishRegressionTests: MarkdownTestCase {

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

    // MARK: - 1. Content above insertion settles predictably

    /// TextKit applies the paragraph's `paragraphSpacing` by extending the
    /// previous paragraph's last-line usedRect downward when that paragraph
    /// stops being last. As a result, the rendered glyph midY of the first
    /// line drifts down by exactly `paragraphSpacing / 2` the first time a
    /// new block is appended. This is the documented steady-state behavior
    /// of the current theme — guarding it ensures a future theme/engine
    /// change doesn't accidentally introduce *larger* or *non-deterministic*
    /// drift on Enter.
    func testFirstLineGlyphYDriftsDeterministicallyWhenAppendingParagraph() throws {
        try resetToEmptyParagraph()
        typeText("Hello")
        flushLayout()

        let beforeFirstLineY = glyphMidY(forCharacterAt: 0)

        typeText("\n")
        flushLayout()

        let afterFirstLineY = glyphMidY(forCharacterAt: 0)
        let expectedDrift = MarkdownEditorConfiguration.default.theme.spacing.paragraphSpacing / 2
        XCTAssertEqual(
            afterFirstLineY - beforeFirstLineY,
            expectedDrift,
            accuracy: 0.5,
            "Expected the first-line midY to drift by \(expectedDrift)pt (paragraphSpacing/2). Actual: \(afterFirstLineY - beforeFirstLineY)pt."
        )
    }

    /// Same documented drift for a heading: when Enter exits a heading the
    /// heading's last-line usedRect now extends downward by `headingSpacing`,
    /// so its glyph midY drifts by `headingSpacing / 2`.
    func testHeadingGlyphYDriftsDeterministicallyWhenAppendingParagraph() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title"))
        try moveNativeCaret(toText: "Title", offset: ("Title" as NSString).length)
        flushLayout()

        let beforeHeadingY = glyphMidY(forCharacterAt: 0)

        typeText("\n")
        flushLayout()

        let afterHeadingY = glyphMidY(forCharacterAt: 0)
        let expectedDrift = MarkdownEditorConfiguration.default.theme.spacing.headingSpacing / 2
        XCTAssertEqual(
            afterHeadingY - beforeHeadingY,
            expectedDrift,
            accuracy: 0.5,
            "Expected heading midY to drift by \(expectedDrift)pt (headingSpacing/2). Actual: \(afterHeadingY - beforeHeadingY)pt."
        )
    }

    /// When the user has multiple blocks and presses Enter at the end of the
    /// last one, no earlier block should change y. We capture each preceding
    /// line's midY and assert it is unchanged after the insert.
    func testAllPriorLinesStayPutWhenAppendingNewLinesAtDocumentEnd() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title\n## Subtitle\nBody one"))
        try moveNativeCaret(toText: "Body one", offset: ("Body one" as NSString).length)
        flushLayout()

        let baseline = capturePerLineMidYs()
        XCTAssertGreaterThanOrEqual(baseline.count, 2, "Setup should produce at least two line fragments")

        for press in 1...3 {
            typeText("\n")
            flushLayout()
            let after = capturePerLineMidYs()
            let comparable = min(baseline.count, after.count)

            for index in 0..<comparable {
                XCTAssertEqual(
                    baseline[index],
                    after[index],
                    accuracy: 0.5,
                    "Press \(press): line \(index) drifted from \(baseline[index]) to \(after[index]) — prior content shifted vertically."
                )
            }
        }
    }

    /// The textView's rendered content height should grow by a *uniform*
    /// amount per Enter. The absolute value depends on theme spacing
    /// (lineHeight + lineSpacing + paragraphSpacing); the invariant we
    /// guard is uniformity across successive presses.
    func testRenderedContentHeightGrowsUniformlyPerEnter() throws {
        try resetToEmptyParagraph()
        typeText("Anchor")
        flushLayout()

        let textView = markdownEditor.textView
        var previous = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        var deltas: [CGFloat] = []

        for _ in 1...4 {
            typeText("\n")
            flushLayout()
            let current = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
            deltas.append(current - previous)
            previous = current
        }

        guard let first = deltas.first else { return XCTFail("no samples") }
        for (index, delta) in deltas.enumerated() {
            XCTAssertEqual(
                delta,
                first,
                accuracy: 1.0,
                "Press \(index + 1) grew the document by \(delta)pt while press 1 grew it by \(first)pt — non-uniform layout growth."
            )
        }
    }

    // MARK: - 2. Caret must not jump around

    /// After Enter, the caret should land at a stable x equal to the body
    /// inset. Across several consecutive Enters the x should not wander.
    func testCaretMinXIsConstantAcrossConsecutiveEnters() throws {
        try resetToEmptyParagraph()
        typeText("Start")
        flushLayout()

        var xs: [CGFloat] = []
        for _ in 0..<5 {
            typeText("\n")
            flushLayout()
            xs.append(rawCaretRect().minX)
        }

        guard let first = xs.first else { return XCTFail("No samples") }
        for (index, value) in xs.enumerated() {
            XCTAssertEqual(
                value,
                first,
                accuracy: 0.5,
                "Press \(index + 1): caret x drifted from \(first) to \(value) — horizontal jump."
            )
        }
    }

    /// Successive Enters should advance the caret midY by the *same* amount
    /// each time. The user perceives a glitchy cursor when the per-press
    /// delta varies — even if the cumulative position eventually settles to
    /// the right place.
    func testEachEnterAdvancesCaretByAUniformAmount() throws {
        try resetToEmptyParagraph()
        typeText("Anchor")
        flushLayout()

        var deltas: [CGFloat] = []
        var lastMidY = rawCaretRect().midY

        for _ in 1...4 {
            typeText("\n")
            flushLayout()
            let midY = rawCaretRect().midY
            deltas.append(midY - lastMidY)
            lastMidY = midY
        }

        guard let first = deltas.first else { return XCTFail("no samples") }
        for (index, delta) in deltas.enumerated() {
            XCTAssertEqual(
                delta,
                first,
                accuracy: 0.5,
                "Press \(index + 1) advanced \(delta)pt while press 1 advanced \(first)pt — non-uniform cursor jump."
            )
        }
    }

    /// Immediately after Enter, the caret height should match the body font's
    /// line height. A caret that briefly renders too short or too tall is the
    /// "glitchy" symptom the user reported.
    func testCaretHeightSettlesToBodyLineHeightImmediatelyAfterEnter() throws {
        try resetToEmptyParagraph()
        typeText("Hello")
        flushLayout()

        let bodyLineHeight = MarkdownEditorConfiguration.default.theme.typography.body.lineHeight
        markdownEditor.textView.insertText("\n")
        let immediate = rawCaretRect()

        XCTAssertEqual(
            immediate.height,
            bodyLineHeight,
            accuracy: 1.5,
            "Caret height immediately after Enter was \(immediate.height)pt; expected ≈\(bodyLineHeight)pt."
        )
    }

    /// Pressing Enter at the end of a heading should land the caret on a body
    /// paragraph with body-sized caret height.
    func testEnterAtEndOfHeadingLandsCaretWithBodyHeight() throws {
        _ = markdownEditor.loadMarkdown(MarkdownDocument(content: "# Title"))
        try moveNativeCaret(toText: "Title", offset: ("Title" as NSString).length)
        flushLayout()

        let bodyLineHeight = MarkdownEditorConfiguration.default.theme.typography.body.lineHeight

        typeText("\n")
        flushLayout()
        let after = rawCaretRect()

        XCTAssertEqual(
            after.height,
            bodyLineHeight,
            accuracy: 1.5,
            "Caret on the new line after a heading should have body height, got \(after.height)pt."
        )
    }

    /// Splitting a word with Enter produces the same deterministic drift on
    /// the first line as appending to the end of a paragraph. The caret on
    /// the new line should land at the body inset.
    func testEnterInMiddleOfWordSplitsLineWithDeterministicDrift() throws {
        try resetToEmptyParagraph()
        typeText("Hello World")
        flushLayout()
        try moveNativeCaret(toText: "Hello World", offset: 5)
        flushLayout()

        let beforeFirstLineY = glyphMidY(forCharacterAt: 0)

        typeText("\n")
        flushLayout()

        let afterFirstLineY = glyphMidY(forCharacterAt: 0)
        let expectedDrift = MarkdownEditorConfiguration.default.theme.spacing.paragraphSpacing / 2
        XCTAssertEqual(
            afterFirstLineY - beforeFirstLineY,
            expectedDrift,
            accuracy: 0.5,
            "Expected first-line midY to drift by \(expectedDrift)pt (paragraphSpacing/2). Actual: \(afterFirstLineY - beforeFirstLineY)pt."
        )

        let caret = rawCaretRect()
        XCTAssertLessThanOrEqual(caret.minX, 20, "Caret should land near the body inset after mid-word split, got minX=\(caret.minX).")
    }

    // MARK: - 3. Transient caret samples during the Enter operation

    /// Sample the caret rect at every layout pass during the Enter operation
    /// and assert no intermediate rect publishes a vertical position above the
    /// resting before-Enter line nor below the resting after-Enter line.
    /// This catches a visible flash even if the final settled rect is correct.
    func testNoTransientCaretRectFlashesAboveOrBelowTheRestingLines() throws {
        try resetToEmptyParagraph()
        typeText("Anchor")
        flushLayout()

        let restingBeforeMidY = rawCaretRect().midY

        let textView = markdownEditor.textView
        let sampler = EnterCaretSampler(textView: textView)
        let previousDelegate = textView.layoutManager.delegate
        textView.layoutManager.delegate = sampler
        defer { textView.layoutManager.delegate = previousDelegate }

        textView.insertText("\n")
        flushLayout()

        let restingAfterMidY = rawCaretRect().midY
        let tolerance: CGFloat = 1.0

        for (index, sample) in sampler.samples.enumerated() {
            XCTAssertGreaterThanOrEqual(
                sample.caret.midY,
                restingBeforeMidY - tolerance,
                "Sample \(index) flashed upward to midY=\(sample.caret.midY) (resting before=\(restingBeforeMidY))."
            )
            XCTAssertLessThanOrEqual(
                sample.caret.midY,
                restingAfterMidY + tolerance,
                "Sample \(index) overshot the destination to midY=\(sample.caret.midY) (resting after=\(restingAfterMidY))."
            )
        }
    }

    // MARK: - Helpers

    private func resetToEmptyParagraph() throws {
        let result = markdownEditor.loadMarkdown(MarkdownDocument(content: ""))
        if case .failure(let error) = result {
            XCTFail("Failed to reset editor: \(error)")
        }
        flushLayout()
        syncNativeSelectionFromLexicalForTests()
        flushLayout()
    }

    private func typeText(_ text: String) {
        for character in text {
            markdownEditor.textView.insertText(String(character))
        }
    }

    private func flushLayout() {
        markdownEditor.layoutIfNeeded()
        markdownEditor.textView.layoutIfNeeded()
    }

    private func rawCaretRect() -> CGRect {
        guard let selectedTextRange = markdownEditor.textView.selectedTextRange else { return .null }
        return markdownEditor.textView.caretRect(for: selectedTextRange.start)
    }

    /// midY (in textView coordinates) of the line fragment that contains the
    /// glyph at the given character location. Used to detect when content
    /// shifts vertically.
    private func glyphMidY(forCharacterAt location: Int) -> CGFloat {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return 0 }
        let clamped = min(max(0, location), attributedText.length - 1)
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: clamped)
        guard glyphIndex < textView.layoutManager.numberOfGlyphs else { return 0 }
        let used = textView.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return textView.textContainerInset.top + used.midY
    }

    /// For each visual line in the text view, the midY of its line fragment.
    private func capturePerLineMidYs() -> [CGFloat] {
        let textView = markdownEditor.textView
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return [] }
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        var midYs: [CGFloat] = []
        var glyphIndex = 0
        let totalGlyphs = textView.layoutManager.numberOfGlyphs
        while glyphIndex < totalGlyphs {
            var effectiveRange = NSRange(location: 0, length: 0)
            let used = textView.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            midYs.append(textView.textContainerInset.top + used.midY)
            guard effectiveRange.length > 0 else { break }
            glyphIndex = effectiveRange.upperBound
        }
        return midYs
    }

    private func moveNativeCaret(toText text: String, offset: Int) throws {
        flushLayout()
        let visibleRange = (markdownEditor.textView.text as NSString).range(of: text)
        XCTAssertNotEqual(visibleRange.location, NSNotFound, "Missing visible text \(text)")
        let clampedOffset = min(max(offset, 0), visibleRange.length)
        markdownEditor.textView.selectedRange = NSRange(location: visibleRange.location + clampedOffset, length: 0)
        markdownEditor.textView.delegate?.textViewDidChangeSelection?(markdownEditor.textView)
        editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionFromLexicalForTests()
        flushLayout()
    }

    /// Push the Lexical selection out to the UIKit textView. Mirrors what the
    /// runtime matrix tests call `syncNativeSelectionFromLexical`.
    private func syncNativeSelectionFromLexicalForTests() {
        try? editor.read {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            let nativeSelection = try? createNativeSelection(from: selection, editor: editor)
            if let range = nativeSelection?.range {
                DispatchQueue.main.async {}
                markdownEditor.textView.selectedRange = range
            }
        }
    }
}

private final class EnterCaretSampler: NSObject, NSLayoutManagerDelegate {
    struct Sample {
        let caret: CGRect
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
        guard let textView, let range = textView.selectedTextRange else { return }
        samples.append(Sample(caret: textView.caretRect(for: range.start)))
    }
}
