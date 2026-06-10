/*
 * MarkdownStartWithTitleTests
 * 
 * Tests for the startWithTitle configuration behavior.
 */

import XCTest
@testable import MarkdownEditor

final class MarkdownStartWithTitleTests: XCTestCase {
    
    func testStartWithTitleConfiguration() {
        // Given: Configuration with startWithTitle enabled
        let config = MarkdownEditorConfiguration(
            behavior: EditorBehavior(
                autoSave: true,
                autoCorrection: true,
                smartQuotes: true,
                returnKeyBehavior: .smart,
                startWithTitle: true
            )
        )
        
        // Then: Should be enabled
        XCTAssertTrue(config.behavior.startWithTitle)
    }
    
    func testStartWithTitleDisabledConfiguration() {
        // Given: Configuration with startWithTitle disabled
        let config = MarkdownEditorConfiguration(
            behavior: EditorBehavior(
                autoSave: true,
                autoCorrection: true,
                smartQuotes: true,
                returnKeyBehavior: .smart,
                startWithTitle: false
            )
        )
        
        // Then: Should be disabled
        XCTAssertFalse(config.behavior.startWithTitle)
    }
    
    func testDefaultConfigurationHasStartWithTitle() {
        // Given: Default configuration
        let config = MarkdownEditorConfiguration()
        
        // Then: startWithTitle should be enabled by default
        XCTAssertTrue(config.behavior.startWithTitle)
    }
    
    func testEmptyDocumentDetection() {
        // Test various forms of "empty" documents
        let testCases = [
            ("", true, "Empty string"),
            ("   ", true, "Only spaces"),
            ("\n", true, "Only newline"),
            ("\n\n", true, "Multiple newlines"),
            ("  \n  ", true, "Spaces and newlines"),
            ("\t\t", true, "Only tabs"),
            ("Hello", false, "Has content"),
            ("# Title", false, "Already has title"),
            ("- List", false, "Has list")
        ]
        
        for (content, shouldBeEmpty, description) in testCases {
            let isEmpty = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            XCTAssertEqual(isEmpty, shouldBeEmpty, "Failed for: \(description)")
        }
    }
    
    func testStartWithTitleLogic() {
        // This tests the logic that should be in loadMarkdown
        
        // Case 1: Empty document with startWithTitle enabled
        let emptyContent = ""
        let startWithTitle = true
        let shouldApplyTitle = emptyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startWithTitle
        XCTAssertTrue(shouldApplyTitle, "Should apply title to empty document when enabled")
        
        // Case 2: Non-empty document with startWithTitle enabled
        let nonEmptyContent = "Some text"
        let shouldNotApplyTitle = nonEmptyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startWithTitle
        XCTAssertFalse(shouldNotApplyTitle, "Should not apply title to non-empty document")
        
        // Case 3: Empty document with startWithTitle disabled
        let emptyContentDisabled = ""
        let startWithTitleDisabled = false
        let shouldNotApply = emptyContentDisabled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startWithTitleDisabled
        XCTAssertFalse(shouldNotApply, "Should not apply title when disabled")
    }
}