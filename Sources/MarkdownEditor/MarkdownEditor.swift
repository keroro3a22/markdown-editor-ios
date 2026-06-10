import UIKit
import Lexical
import LexicalMarkdown
import LexicalListPlugin
import LexicalLinkPlugin

// MARK: - Extensions

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
}

private extension HeadingTagType {
    var intValue: Int {
        switch self {
        case .h1: return 1
        case .h2: return 2
        case .h3: return 3
        case .h4: return 4
        case .h5: return 5
        }
    }
}

// MARK: - Content Editor (No Scroll Management)

public final class MarkdownEditorContentView: UIView {
    
    // MARK: - Public Properties
    
    public weak var delegate: MarkdownEditorDelegate?
    
    public var isEditable: Bool = true {
        didSet { applyEffectiveEditability() }
    }
    
    public var placeholderText: String? {
        didSet { updatePlaceholder() }
    }
    
    /// Access to the underlying text view for setting inputAccessoryView
    public var textView: UITextView {
        return lexicalView.textView
    }

    // Test hook for driving editor commands deterministically in unit tests.
    internal var editorForTesting: Editor { lexicalView.editor }
    
    /// Input accessory view for this editor
    public override var inputAccessoryView: UIView? {
        get { return textView.inputAccessoryView }
        set { textView.inputAccessoryView = newValue }
    }
    
    // MARK: - Private Properties
    
    private let lexicalView: LexicalView
    private let configuration: MarkdownEditorConfiguration
    private let logger: MarkdownCommandLogger
    private weak var controller: AnyObject?
    private var cursorDelegate: MarkdownCursorDelegate?
    
    // Domain layer bridge
    private let domainBridge: MarkdownDomainBridge
    
    // Command handlers for cleanup
    private var commandHandlers: [Editor.RemovalHandler] = []
    
    // Editing state tracking
    private var isEditing = false

    // Streaming replacement session (single active session)
    private var replacementSessionState: ReplacementSessionState?
    // Streaming append session (single active session)
    private var appendSessionState: AppendSessionState?

    // Unified undo/redo history. We snapshot Lexical EditorState so we can restore without re-importing markdown.
    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    private var lastHistoryMarkdown: String?
    private var lastHistoryChangeAt: Date?
    private static let maxHistoryEntries = 200
    private static let historyMergeDelay: TimeInterval = 0.75
    private var cachedExportDocument: MarkdownDocument?
    private var cachedExportIsDirty = true
    private var pendingDeferredUpdateWork = false

    private var isProgrammaticLoad = false
    private var isApplyingUndoRedo = false
    private var isApplyingPasteTransaction = false
    private var isCanonicalizingSelectionAnchor = false
    
    // Pending keystroke log for completion in update listener
    private var pendingKeystrokeLog: PendingKeystrokeLog?
    
    // Content size tracking
    private var lastContentSize: CGSize = .zero
    
    // MARK: - Initialization
    
    public init(configuration: MarkdownEditorConfiguration = .init()) {
        self.configuration = configuration
        
        // Initialize logger with configuration
        self.logger = MarkdownCommandLogger(loggingConfig: configuration.logging)
        
        // Initialize Domain Bridge
        self.domainBridge = MarkdownDomainBridge(logger: logger)
        
        // Initialize Lexical components
        let theme = Self.createLexicalTheme(from: configuration.theme)
        let plugins = Self.createPlugins(for: configuration.features)
        
        let editorConfig = EditorConfig(theme: theme, plugins: plugins)
        self.lexicalView = LexicalView(
            editorConfig: editorConfig,
            featureFlags: FeatureFlags()
        )
        
        super.init(frame: .zero)
        setupContentView()
        
        // Connect domain bridge to Lexical editor
        domainBridge.connect(to: lexicalView.editor)
        canonicalizeSingleEmptyRootBlockIfNeeded()
        syncNativeSelectionToLexicalSelection()
        lastHistoryMarkdown = exportMarkdownForHistory()
        
        // Set up cursor customization
        setupCursorCustomization()
        
        setupCommandBar()
        setupEditorListeners()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // Clean up command handlers
        for handler in commandHandlers {
            handler()
        }
        commandHandlers.removeAll()
        
        // Remove keyboard notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Layout Override
    
    public override var intrinsicContentSize: CGSize {
        // When scrolling is disabled, we need to calculate the actual text size
        let textView = lexicalView.textView
        
        // Get the size that fits the text content
        let width = bounds.width > 0 ? bounds.width : UIView.noIntrinsicMetric
        let sizeThatFits = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        
        // Ensure minimum height for interaction
        return CGSize(width: width, height: max(sizeThatFits.height, 100))
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Calculate the actual size needed for the text
        let textView = lexicalView.textView
        let sizeThatFits = textView.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        
        // Check if size changed and notify parent for intrinsic size updates
        if sizeThatFits.height != lastContentSize.height {
            lastContentSize = sizeThatFits
            invalidateIntrinsicContentSize()
            
            // Force the superview to re-layout
            superview?.setNeedsLayout()
        }
    }
    
    // MARK: - Public API
    
    public func loadMarkdown(_ document: MarkdownDocument) -> MarkdownEditorResult<Void> {
        return loadMarkdownInternal(document, resetHistory: true)
    }

    private func loadMarkdownInternal(
        _ document: MarkdownDocument,
        resetHistory: Bool
    ) -> MarkdownEditorResult<Void> {
        let wasProgrammaticLoad = isProgrammaticLoad
        isProgrammaticLoad = true
        defer { isProgrammaticLoad = wasProgrammaticLoad }

        do {
            try MarkdownImporter.importMarkdown(document.content, into: lexicalView.editor)
            domainBridge.syncFromLexical()
        } catch {
            return .failure(.invalidMarkdown(error.localizedDescription))
        }

        // If document is empty and startWithTitle is enabled, apply H1 formatting
        if document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && configuration.behavior.startWithTitle {
            do {
                try lexicalView.editor.update {
                    // Ensure there is a selection; create one at the start of the first block if missing
                    var selection = try getSelection() as? RangeSelection
                    if selection == nil,
                       let root = getRoot(),
                       let first = root.getFirstChild() as? ElementNode {
                        let point = Point(key: first.key, offset: 0, type: .element)
                        let newSelection = RangeSelection(anchor: point, focus: point, format: TextFormat())
                        getActiveEditorState()?.selection = newSelection
                        selection = newSelection
                    }
                    if let selection = selection {
                        setBlocksType(selection: selection) { createHeadingNode(headingTag: .h1) }
                    }
                }

                // Sync domain bridge state after applying the formatting
                domainBridge.syncFromLexical()
            } catch {
                // Silently handle the error for now - startWithTitle is a nice-to-have feature
            }
        }

        canonicalizeSingleEmptyRootBlockIfNeeded()
        syncNativeSelectionToLexicalSelection()

        // Refresh placeholder visibility after content load to prevent overlap when content is non-empty
        lexicalView.showPlaceholderText()

        if resetHistory {
            undoStack.removeAll()
            redoStack.removeAll()
            lastHistoryChangeAt = nil
        }
        markExportDirty()
        lastHistoryMarkdown = exportMarkdownForHistory()

        delegate?.markdownEditor(self, didLoadDocument: document)
        return .success(())
    }
    
    public func exportMarkdown() -> MarkdownEditorResult<MarkdownDocument> {
        if !cachedExportIsDirty, let cachedExportDocument {
            return .success(cachedExportDocument)
        }

        // Export through domain bridge
        let result = domainBridge.exportDocument()
        
        switch result {
        case .success(let document):
            cachedExportDocument = document
            cachedExportIsDirty = false
            return .success(document)
        case .failure(let error):
            // Map domain error to editor error
            switch error {
            case .serializationFailed:
                return .failure(.serializationFailed)
            default:
                return .failure(.editorStateCorrupted)
            }
        }
    }
    
    public func applyFormatting(_ formatting: InlineFormatting) {
        // Sync current state from Lexical
        domainBridge.syncFromLexical()
        
        // Create domain command
        let command = domainBridge.createFormattingCommand(formatting)
        
        // Execute through domain bridge (validates and applies)
        let result = domainBridge.execute(command)
        
        switch result {
        case .success:
            // Success - state is already updated in Lexical
            break
        case .failure(let error):
            // Map domain error to editor error
            let editorError: MarkdownEditorError
            switch error {
            case .unsupportedOperation(let reason):
                editorError = .unsupportedFeature(reason)
            default:
                editorError = .editorStateCorrupted
            }
            delegate?.markdownEditor(self, didEncounterError: editorError)
        }
    }
    
    public func setBlockType(_ blockType: MarkdownBlockType) {
        // Sync current state from Lexical
        domainBridge.syncFromLexical()

        if transformSelectedEmptyBlock(to: blockType) {
            updatePlaceholder()
            syncNativeSelectionToLexicalSelection()
            return
        }
        
        // Capture caret before toggling for safety in UI-layer as well
        var preservedPoint: (key: NodeKey, offset: Int, type: SelectionType)? = nil
        try? lexicalView.editor.read {
            if let selection = try? getSelection() as? RangeSelection {
                preservedPoint = (selection.anchor.key, selection.anchor.offset, selection.anchor.type)
            }
        }
        
        // Create domain command with smart list toggle logic
        let command = domainBridge.createBlockTypeCommand(blockType)
        
        // Execute through domain bridge
        let result = domainBridge.execute(command)
        
        switch result {
        case .success:
            updatePlaceholder()

            // Force layout update for list items to trigger bullet rendering
            if blockType == .unorderedList || blockType == .orderedList {
                DispatchQueue.main.async { [weak self] in
                    self?.lexicalView.setNeedsLayout()
                }
            }
            
            // Best-effort selection restoration if anchor was forced to start
            if let preservedPoint, preservedPoint.type == .text {
                try? lexicalView.editor.update {
                    if let _: TextNode = getNodeByKey(key: preservedPoint.key) {
                        let clampedOffset: Int = {
                            if let node: TextNode = getNodeByKey(key: preservedPoint.key) {
                                return max(0, min(preservedPoint.offset, node.getTextContentSize()))
                            }
                            return preservedPoint.offset
                        }()
                        let p = Point(key: preservedPoint.key, offset: clampedOffset, type: .text)
                        let newSel = RangeSelection(anchor: p, focus: p, format: TextFormat())
                        getActiveEditorState()?.selection = newSel
                    }
                }
            }
            syncNativeSelectionToLexicalSelection()
        case .failure(let error):
            logger.logSimpleEvent("ERROR", details: "Block type command failed: \(error.localizedDescription)")
            // Map domain error to editor error
            let editorError: MarkdownEditorError
            switch error {
            case .unsupportedOperation(let reason):
                editorError = .unsupportedFeature(reason)
            default:
                editorError = .editorStateCorrupted
            }
            delegate?.markdownEditor(self, didEncounterError: editorError)
        }
    }
    
    public func getCurrentFormatting() -> InlineFormatting {
        // Sync current state from Lexical
        domainBridge.syncFromLexical()
        
        // Get formatting from domain state
        let state = domainBridge.getCurrentState()
        return state.currentFormatting
    }
    
    public func getCurrentBlockType() -> MarkdownBlockType {
        // Sync current state from Lexical
        domainBridge.syncFromLexical()
        
        // Get block type from domain state
        let state = domainBridge.getCurrentState()
        return state.currentBlockType
    }

    private func transformSelectedEmptyBlock(to blockType: MarkdownBlockType) -> Bool {
        var didTransform = false

        try? lexicalView.editor.update {
            guard let selection = try? getSelection() as? RangeSelection,
                  selection.isCollapsed(),
                  let selectedNode = try? selection.anchor.getNode() else { return }

            let block = (selectedNode as? ElementNode) ?? findMatchingParent(startingNode: selectedNode) { candidate in
                candidate.getParent() is RootNode
            } as? ElementNode

            guard let block,
                  block.getParent() is RootNode,
                  isTextContentEmptyIgnoringEmptyInvisibles(block.getTextContent()) else { return }

            let targetBlockType: MarkdownBlockType = if blockTypeMatches(markdownBlockType(for: block), blockType) {
                .paragraph
            } else {
                blockType
            }

            let replacement: ElementNode
            switch targetBlockType {
            case .paragraph:
                replacement = createParagraphNode()
            case .heading(let level):
                replacement = createHeadingNode(headingTag: level.lexicalType)
            case .codeBlock:
                replacement = createCodeNode()
            case .quote:
                replacement = createQuoteNode()
            case .unorderedList, .orderedList:
                return
            }

            _ = try? block.replace(replaceWith: replacement)
            let anchor = createTextNode(text: emptyTextCaretAnchor)
            try? replacement.append([anchor])
            let point = Point(key: anchor.key, offset: 0, type: .text)
            try? setSelection(RangeSelection(anchor: point, focus: point, format: selection.format))
            didTransform = true
        }

        return didTransform
    }

    private func markdownBlockType(for block: ElementNode) -> MarkdownBlockType? {
        if let heading = block as? HeadingNode {
            switch heading.getTag() {
            case .h1: return .heading(level: .h1)
            case .h2: return .heading(level: .h2)
            case .h3: return .heading(level: .h3)
            case .h4: return .heading(level: .h4)
            case .h5: return .heading(level: .h5)
            }
        }
        if block is ParagraphNode { return .paragraph }
        if block is CodeNode { return .codeBlock }
        if block is QuoteNode { return .quote }
        return nil
    }

    private func blockTypeMatches(_ current: MarkdownBlockType?, _ requested: MarkdownBlockType) -> Bool {
        guard let current else { return false }
        switch (current, requested) {
        case (.heading(let currentLevel), .heading(let requestedLevel)):
            return currentLevel.lexicalType == requestedLevel.lexicalType
        default:
            return current == requested
        }
    }

    // MARK: - Undo/Redo

    public func undo() {
        preserveEnclosingScrollPosition { [weak self] in
            guard let self else { return }
            let handled = self.performUndo()
            MarkdownLogger.editor("Undo handled=\(handled)", level: .debug, config: configuration.logging)
        }
    }

    public func redo() {
        preserveEnclosingScrollPosition { [weak self] in
            guard let self else { return }
            let handled = self.performRedo()
            MarkdownLogger.editor("Redo handled=\(handled)", level: .debug, config: configuration.logging)
        }
    }

    @discardableResult
    private func performUndo() -> Bool {
        guard let target = undoStack.popLast() else { return false }

        let current = lexicalView.editor.getEditorState().clone(selection: nil)
        redoStack.append(current)

        isApplyingUndoRedo = true
        defer { isApplyingUndoRedo = false }

        do {
            try lexicalView.editor.setEditorState(target.clone(selection: nil))
            lastHistoryChangeAt = nil
            return true
        } catch {
            _ = redoStack.popLast()
            undoStack.append(target)
            return false
        }
    }

    @discardableResult
    private func performRedo() -> Bool {
        guard let target = redoStack.popLast() else { return false }

        let current = lexicalView.editor.getEditorState().clone(selection: nil)
        undoStack.append(current)

        isApplyingUndoRedo = true
        defer { isApplyingUndoRedo = false }

        do {
            try lexicalView.editor.setEditorState(target.clone(selection: nil))
            lastHistoryChangeAt = nil
            return true
        } catch {
            _ = undoStack.popLast()
            redoStack.append(target)
            return false
        }
    }

    private func enclosingScrollView() -> UIScrollView? {
        var node: UIView? = superview
        while let view = node {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            node = view.superview
        }
        return nil
    }

    private func preserveEnclosingScrollPosition(_ action: @escaping () -> Void) {
        guard let scrollView = enclosingScrollView() else {
            action()
            return
        }

        let originalOffset = scrollView.contentOffset
        action()

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            scrollView.layoutIfNeeded()

            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )

            let clampedY = min(max(originalOffset.y, minY), maxY)
            let clampedOffset = CGPoint(x: originalOffset.x, y: clampedY)
            if clampedOffset != scrollView.contentOffset {
                scrollView.setContentOffset(clampedOffset, animated: false)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupContentView() {
        // Disable text view scrolling - parent will handle scrolling
        lexicalView.textView.isScrollEnabled = false
        
        addSubview(lexicalView)
        lexicalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lexicalView.topAnchor.constraint(equalTo: topAnchor),
            lexicalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lexicalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            lexicalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Apply background color from theme
        let backgroundColor = configuration.theme.colors.backgroundColor
        self.backgroundColor = backgroundColor
        lexicalView.backgroundColor = backgroundColor
        lexicalView.textView.backgroundColor = backgroundColor
    }
    
    private func setupCursorCustomization() {
        let textView = lexicalView.textView as TextView
        textView.cursorDelegate = nil
        cursorDelegate = nil
    }
    
    private func setupEditorListeners() {
        let updateHandler = lexicalView.editor.registerUpdateListener { [weak self] activeEditorState, previousEditorState, dirtyNodes in
            guard let self = self else { return }
            let wasCanonicalizingSelectionAnchor = self.isCanonicalizingSelectionAnchor
            defer {
                if wasCanonicalizingSelectionAnchor {
                    self.isCanonicalizingSelectionAnchor = false
                }
            }

            let contentChanged = self.didContentChange(
                activeEditorState: activeEditorState,
                previousEditorState: previousEditorState,
                dirtyNodes: dirtyNodes
            )
            self.markExportDirty()
            
            // Complete any pending keystroke logging first (before syncing domain state)
            if self.pendingKeystrokeLog != nil {
                self.completeKeystrokeLog()
            }
            
            if contentChanged {
                // Sync domain state with Lexical state only for meaningful content edits.
                self.domainBridge.syncFromLexical()
            }

            // Record coarse undo/redo snapshots (best-effort).
            self.recordHistoryIfNeeded(
                activeEditorState: activeEditorState,
                previousEditorState: previousEditorState,
                dirtyNodes: dirtyNodes,
                contentChanged: contentChanged
            )
            
            if contentChanged {
                self.scheduleDeferredUpdateWork()
            }
        }
        commandHandlers.append(updateHandler)
        
        // Register domain command handlers for keyboard events
        registerDomainCommandHandlers()
        
        // Set up keyboard notification observers
        setupKeyboardNotifications()
    }

    private func recordHistoryIfNeeded(
        activeEditorState: EditorState,
        previousEditorState: EditorState,
        dirtyNodes: DirtyNodeMap,
        contentChanged: Bool
    ) {
        guard contentChanged else { return }
        guard let currentMarkdown = exportMarkdownForHistory() else { return }

        // During programmatic loads or while applying undo/redo we only advance the baseline.
        if isProgrammaticLoad || isApplyingUndoRedo || isApplyingPasteTransaction || isCanonicalizingSelectionAnchor {
            lastHistoryMarkdown = currentMarkdown
            return
        }

        // During streaming sessions, do not create per-update history entries.
        // A single entry will be committed on finish().
        if replacementSessionState != nil || appendSessionState != nil {
            lastHistoryMarkdown = currentMarkdown
            return
        }

        guard let previousMarkdown = lastHistoryMarkdown else {
            lastHistoryMarkdown = currentMarkdown
            lastHistoryChangeAt = nil
            return
        }

        let hasDirtyNodes = !dirtyNodes.isEmpty
        let markdownChanged = (previousMarkdown != currentMarkdown)
        let nodeMapCountChanged = (previousEditorState.getNodeMap().count != activeEditorState.getNodeMap().count)

        // If the markdown string did not change but Lexical reports dirty nodes,
        // we still want undo to work (e.g. inserting an empty paragraph / line break at end).
        // Additionally, some structural edits might not mark dirty nodes but will still change the nodeMap.
        guard markdownChanged || hasDirtyNodes || nodeMapCountChanged else { return }

        let now = Date()
        let forceNewGroup = (!markdownChanged && (hasDirtyNodes || nodeMapCountChanged))
        let shouldStartNewGroup: Bool = {
            if forceNewGroup { return true }
            guard let lastHistoryChangeAt else { return true }
            return now.timeIntervalSince(lastHistoryChangeAt) > Self.historyMergeDelay
        }()

        if shouldStartNewGroup {
            undoStack.append(previousEditorState.clone(selection: nil))
            if undoStack.count > Self.maxHistoryEntries {
                undoStack.removeFirst(undoStack.count - Self.maxHistoryEntries)
            }
            redoStack.removeAll()
        }

        lastHistoryChangeAt = now
        lastHistoryMarkdown = currentMarkdown
    }

    private func markExportDirty() {
        cachedExportIsDirty = true
        cachedExportDocument = nil
    }

    private func didContentChange(
        activeEditorState: EditorState,
        previousEditorState: EditorState,
        dirtyNodes: DirtyNodeMap
    ) -> Bool {
        !dirtyNodes.isEmpty || activeEditorState.getNodeMap().count != previousEditorState.getNodeMap().count || activeEditorState !== previousEditorState
    }

    private func scheduleDeferredUpdateWork() {
        guard !pendingDeferredUpdateWork else { return }
        pendingDeferredUpdateWork = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDeferredUpdateWork = false

            self.delegate?.markdownEditorDidChange(self)

            if self.configuration.behavior.autoSave, let document = self.exportMarkdown().value {
                self.delegate?.markdownEditor(self, didAutoSave: document)
            }

            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
            self.superview?.setNeedsLayout()
        }
    }
    
    private func registerDomainCommandHandlers() {
        // Register smart Enter handler by intercepting insertText command
        let enterHandler = lexicalView.editor.registerCommand(
            type: .insertText,
            listener: { [weak self] payload in
                guard let self = self,
                      let text = payload as? String else { return false }
                
                // Capture before state for logging
                let beforeSnapshot = logger.createSnapshot(from: self.lexicalView.editor)

                if self.handleMarkdownPasteIfNeeded(text, beforeSnapshot: beforeSnapshot) {
                    return true
                }

                // Internal placeholder cleanup:
                // We use ZWSP (\u{200B}) as a caret anchor in empty blocks (esp. list items).
                // Some Lexical transitions (e.g. exiting a list) can leave that ZWSP behind in a paragraph.
                // If we don't strip it before normal typing, marker shortcuts like "- " become "-\u{200B} "
                // and fail to trigger.
                if text != "\n" {
                    self.stripZeroWidthSpacesInActiveTextNodeIfNeeded()
                }

                // Markdown shortcuts (space-triggered): block markers at the start of a paragraph.
                if text == " ", self.handleMarkdownShortcutsIfNeeded(beforeSnapshot: beforeSnapshot) {
                    return true
                }
                
                // Check if this is an Enter key
                if text == "\n" {
                    logger.logSimpleEvent("ENTER_DETECTED", details: "Enter key pressed via insertText")
                    
                    // Sync current state
                    self.domainBridge.syncFromLexical()
                    
                    // Check if domain should handle this
                    let state = self.domainBridge.currentDomainState
                    let isInList = self.isSelectionInListItem()
                    let isLineEmpty = self.isCurrentLineEmpty()
                    
                    if isInList {
                        self.logKeystroke(
                            "Enter",
                            beforeSnapshot: beforeSnapshot,
                            action: "Enter in list (Lexical paragraph insertion; isLineEmpty=\(isLineEmpty))"
                        )
                        self.insertParagraphAndAnchorEmptyBlock()
                        return true
                    } else {
                        // Non-list handling based on returnKeyBehavior and block context
                        switch self.configuration.behavior.returnKeyBehavior {
                        case .insertParagraph:
                            self.logKeystroke("Enter", beforeSnapshot: beforeSnapshot, action: "Insert paragraph")
                            self.insertParagraphAndAnchorEmptyBlock()
                            return true
                        case .insertLineBreak:
                            self.logKeystroke("Enter", beforeSnapshot: beforeSnapshot, action: "Insert line break")
                            self.lexicalView.editor.dispatchCommand(type: .insertLineBreak)
                            return true
                        case .smart:
                            let isHeading: Bool = {
                                if case .heading = state.currentBlockType { return true }
                                return false
                            }()
                            if isHeading {
                                self.logKeystroke("Enter", beforeSnapshot: beforeSnapshot, action: "Heading: insert paragraph (exit heading)")
                                self.insertParagraphAndAnchorEmptyBlock()
                                return true
                            }
                            self.logKeystroke("Enter", beforeSnapshot: beforeSnapshot, action: "Smart paragraph insertion")
                            self.insertParagraphAndAnchorEmptyBlock()
                            return true
                        }
                    }
                } else {
                    // Log regular character insertion
                    let displayText = text.count == 1 ? "'\(text)'" : "text: \"\(text)\""
                    self.logKeystroke("Character: \(displayText)", beforeSnapshot: beforeSnapshot, action: "Insert text")
                }
                
                // Let Lexical handle normal text insertion
                return false
            },
            priority: .High
        )

        let pasteHandler = lexicalView.editor.registerCommand(
            type: .paste,
            listener: { [weak self] payload in
                guard let self,
                      let pasteboard = payload as? UIPasteboard,
                      let text = pasteboard.string else { return false }

                let beforeSnapshot = logger.createSnapshot(from: self.lexicalView.editor)
                return self.handleMarkdownPasteIfNeeded(text, beforeSnapshot: beforeSnapshot)
            },
            priority: .High
        )
        
        // Register smart Backspace handler by intercepting deleteCharacter command
        let backspaceHandler = lexicalView.editor.registerCommand(
            type: .deleteCharacter,
            listener: { [weak self] payload in
                guard let self = self,
                      let isBackwards = payload as? Bool,
                      isBackwards else { return false }
                
                logger.logSimpleEvent("BACKSPACE_DETECTED", details: "Backspace key pressed via deleteCharacter")
                
                // Capture before state for logging
                let beforeSnapshot = logger.createSnapshot(from: self.lexicalView.editor)
                
                // Sync current state
                self.domainBridge.syncFromLexical()
                
                // Check if domain should handle this
                let state = self.domainBridge.currentDomainState
                
                // If in a list and at start of empty line
                let isInList = (state.currentBlockType == .unorderedList || state.currentBlockType == .orderedList)
                let isLineEmpty = self.isCurrentLineEmpty()
                let isAtLineStart = self.isCursorAtLineStart()
                
                if isInList && isLineEmpty && isAtLineStart {
                    logger.logSimpleEvent("BACKSPACE", details: "List context: handling empty item backspace via smart command")

                    let command = self.domainBridge.createSmartBackspaceCommand()
                    if case .success = self.domainBridge.execute(command) {
                        return true
                    }

                    logger.logSimpleEvent("BACKSPACE", details: "Smart backspace command failed in list context; falling back to Lexical")
                    return false
                } else {
                    // Log this as a regular keystroke that Lexical will handle
                    self.logKeystroke("Backspace", beforeSnapshot: beforeSnapshot, action: "Delete character backward")
                }

                guard let selection = try? getSelection() as? RangeSelection else { return false }
                try? selection.deleteCharacter(isBackwards: true)
                self.anchorSelectedEmptyBlockIfNeededWithinCurrentUpdate()
                return true
            },
            priority: .High
        )

        let selectionChangeHandler = lexicalView.editor.registerCommand(
            type: .selectionChange,
            listener: { [weak self] _ in
                guard let self else { return false }

                if self.anchorSelectedEmptyBlockIfNeededWithinCurrentUpdate() {
                    self.isCanonicalizingSelectionAnchor = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.syncNativeSelectionToLexicalSelection()
                        self.updatePlaceholder()
                    }
                }

                return false
            },
            priority: .Low
        )
        
        // Store handlers for cleanup
        commandHandlers.append(enterHandler)
        commandHandlers.append(pasteHandler)
        commandHandlers.append(backspaceHandler)
        commandHandlers.append(selectionChangeHandler)
    }

    private func insertParagraphAndAnchorEmptyBlock() {
        try? lexicalView.editor.update {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            try? selection.insertParagraph()
            self.anchorSelectedEmptyBlockIfNeededWithinCurrentUpdate()
        }
        lexicalView.editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionToLexicalSelection()
    }

    @discardableResult
    private func anchorSelectedEmptyBlockIfNeededWithinCurrentUpdate() -> Bool {
        guard let selection = try? getSelection() as? RangeSelection,
              selection.isCollapsed(),
              selection.anchor.type == .element,
              let element = try? selection.anchor.getNode() as? ElementNode,
              element.getParent() is RootNode,
              isTextContentEmptyIgnoringEmptyInvisibles(element.getTextContent()) else { return false }

        let anchor: TextNode
        if let existingAnchor = element.getChildren().compactMap({ $0 as? TextNode }).first(where: { isTextContentEmptyIgnoringEmptyInvisibles($0.getTextContent()) }) {
            _ = try? existingAnchor.setText(emptyTextCaretAnchor)
            anchor = existingAnchor
        } else if element.getChildrenSize() == 0 {
            let newAnchor = createTextNode(text: emptyTextCaretAnchor)
            try? element.append([newAnchor])
            anchor = newAnchor
        } else {
            return false
        }

        let point = Point(key: anchor.key, offset: 0, type: .text)
        try? setSelection(RangeSelection(anchor: point, focus: point, format: selection.format))
        return true
    }

    private func canonicalizeSingleEmptyRootBlockIfNeeded() {
        try? lexicalView.editor.update {
            guard let root = getRoot(),
                  root.getChildrenSize() == 1,
                  let block = root.getFirstChild() as? ElementNode,
                  isTextContentEmptyIgnoringEmptyInvisibles(block.getTextContent()) else { return }

            let existingAnchor = block.getChildren().compactMap { $0 as? TextNode }.first { textNode in
                isTextContentEmptyIgnoringEmptyInvisibles(textNode.getTextContent())
            }

            let anchor: TextNode
            if let existingAnchor {
                _ = try? existingAnchor.setText(emptyTextCaretAnchor)
                anchor = existingAnchor
            } else {
                for child in block.getChildren() {
                    try? child.remove()
                }
                anchor = createTextNode(text: emptyTextCaretAnchor)
                try? block.append([anchor])
            }

            let point = Point(key: anchor.key, offset: 0, type: .text)
            let format = (try? getSelection() as? RangeSelection)?.format ?? TextFormat()
            try? setSelection(RangeSelection(anchor: point, focus: point, format: format))
        }
    }

    private func syncNativeSelectionToLexicalSelection() {
        var nativeRange: NSRange?
        try? lexicalView.editor.read {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            nativeRange = try? createNativeSelection(from: selection, editor: lexicalView.editor).range
        }

        if let nativeRange {
            lexicalView.textView.selectedRange = nativeRange
            syncUIKitTypingAttributesFromCaret()
        }
    }

    private func syncUIKitTypingAttributesFromCaret() {
        let textView = lexicalView.textView
        guard let attributedText = textView.attributedText,
              attributedText.length > 0 else { return }

        let location = caretAttributeLocation(for: textView.selectedRange.location, text: attributedText.string as NSString)
        let attributes = attributedText.attributes(at: location, effectiveRange: nil)
        textView.typingAttributes = attributes
    }

    private func caretAttributeLocation(for cursorLocation: Int, text: NSString) -> Int {
        let textLength = text.length
        guard textLength > 0 else { return 0 }
        if cursorLocation < textLength {
            let characterLocation = max(cursorLocation, 0)
            if cursorLocation > 0, isLineBoundary(text.character(at: characterLocation)) {
                return cursorLocation - 1
            }
            return characterLocation
        }
        return textLength - 1
    }

    private func isLineBoundary(_ character: unichar) -> Bool {
        character == 0x000A || character == 0x2028 || character == 0x2029
    }

    private func isSelectionInListItem() -> Bool {
        guard let selection = try? getSelection() as? RangeSelection,
              let anchorNode = try? selection.anchor.getNode() else {
            return false
        }

        return findParentListItem(anchorNode) != nil
    }

    private func handleMarkdownPasteIfNeeded(_ text: String, beforeSnapshot: MarkdownStateSnapshot?) -> Bool {
        guard shouldParseAsMarkdownPaste(text) else { return false }

        let nodes = MarkdownImporter.makeNodes(from: text)
        guard !nodes.isEmpty else { return false }

        let beforeEditorState = lexicalView.editor.getEditorState().clone(selection: nil)
        var didInsert = false

        isApplyingPasteTransaction = true
        defer { isApplyingPasteTransaction = false }

        do {
            try lexicalView.editor.update {
                guard let selection = try? getSelection() as? RangeSelection else { return }
                if selection.isCollapsed(), self.shouldInsertMarkdownPasteAsBlocks(text) {
                    didInsert = self.insertMarkdownPasteBlocks(nodes, at: selection)
                } else {
                    didInsert = (try? selection.insertNodes(nodes: nodes, selectStart: false)) == true
                }
            }
        } catch {
            return false
        }

        guard didInsert else { return false }

        lexicalView.showPlaceholderText()
        undoStack.append(beforeEditorState.clone(selection: nil))
        if undoStack.count > Self.maxHistoryEntries {
            undoStack.removeFirst(undoStack.count - Self.maxHistoryEntries)
        }
        redoStack.removeAll()
        lastHistoryChangeAt = nil
        markExportDirty()
        domainBridge.syncFromLexical()
        lastHistoryMarkdown = exportMarkdownForHistory()

        logKeystroke("Paste Markdown", beforeSnapshot: beforeSnapshot, action: "Parse markdown paste and insert nodes")
        lexicalView.editor.dispatchCommand(type: .selectionChange)
        return true
    }

    private func shouldParseAsMarkdownPaste(_ text: String) -> Bool {
        guard text.count > 1 else { return false }
        if text.contains("\n") || text.contains("\r") { return true }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let blockPrefixes = ["# ", "## ", "### ", "#### ", "##### ", "###### ", "> ", "- ", "* ", "+ ", "```", "~~~"]
        if blockPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return true }

        return trimmed.contains("**")
            || trimmed.contains("__")
            || trimmed.contains("~~")
            || trimmed.contains("`")
            || trimmed.range(of: #"\[[^\]]+\]\([^\)]*\)"#, options: .regularExpression) != nil
    }

    private func shouldInsertMarkdownPasteAsBlocks(_ text: String) -> Bool {
        if text.contains("\n") || text.contains("\r") { return true }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let blockPrefixes = ["# ", "## ", "### ", "#### ", "##### ", "###### ", "> ", "- ", "* ", "+ ", "```", "~~~"]
        if blockPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        return trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil
    }

    private func insertMarkdownPasteBlocks(_ nodes: [Node], at selection: RangeSelection) -> Bool {
        guard !nodes.isEmpty,
              let anchorNode = try? selection.anchor.getNode(),
              let topLevel = try? anchorNode.getTopLevelElementOrThrow() else {
            return false
        }

        do {
            var insertionTarget: Node
            if topLevel.isEmpty(), let first = nodes.first {
                _ = try topLevel.replace(replaceWith: first)
                insertionTarget = first
                for node in nodes.dropFirst() {
                    insertionTarget = try insertionTarget.insertAfter(nodeToInsert: node)
                }
            } else {
                insertionTarget = topLevel
                for node in nodes {
                    insertionTarget = try insertionTarget.insertAfter(nodeToInsert: node)
                }
            }

            if let element = insertionTarget as? ElementNode {
                _ = try? element.selectEnd()
            } else {
                _ = try? insertionTarget.selectNext(anchorOffset: nil, focusOffset: nil)
            }
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Keystroke Event Logging
    
    private func logKeystroke(_ keyName: String, beforeSnapshot: MarkdownStateSnapshot?, action: String) {
        guard configuration.logging.isEnabled && configuration.logging.level >= .verbose else { return }
        guard let beforeSnapshot = beforeSnapshot else { return }
        
        // Log the start of keystroke (before state and action)
        let separator = String(repeating: "=", count: 42)
        MarkdownLogger.editor("\n\(separator) KEYSTROKE: \(keyName) \(separator)", level: .verbose, config: configuration.logging)
        MarkdownLogger.editor(beforeSnapshot.detailedDescription, level: .verbose, config: configuration.logging)
        if configuration.logging.includeDetailedState, let uiAttrs = captureUIKitTextAttributesSnapshot() {
            MarkdownLogger.editor("UI_TYPING_ATTRS: \(uiAttrs.typing)", level: .verbose, config: configuration.logging)
            MarkdownLogger.editor("UI_CARET_ATTRS:  \(uiAttrs.caret)", level: .verbose, config: configuration.logging)
        }
        MarkdownLogger.editor("ACTION: \(action)", level: .verbose, config: configuration.logging)
        
        // Store pending log to complete in update listener
        pendingKeystrokeLog = PendingKeystrokeLog(
            keyName: keyName,
            action: action,
            beforeSnapshot: beforeSnapshot
        )
    }
    
    private func completeKeystrokeLog() {
        guard configuration.logging.isEnabled && configuration.logging.level >= .verbose else {
            pendingKeystrokeLog = nil
            return
        }
        guard pendingKeystrokeLog != nil else { return }
        
        // Capture after state
        let afterSnapshot = logger.createSnapshot(from: lexicalView.editor)
        
        // Complete the log with after state
            if let afterSnapshot = afterSnapshot {
                MarkdownLogger.editor("AFTER STATE:", level: .verbose, config: configuration.logging)
                MarkdownLogger.editor(afterSnapshot.detailedDescription, level: .verbose, config: configuration.logging)
            if configuration.logging.includeDetailedState, let uiAttrs = captureUIKitTextAttributesSnapshot() {
                    MarkdownLogger.editor("UI_TYPING_ATTRS: \(uiAttrs.typing)", level: .verbose, config: configuration.logging)
                    MarkdownLogger.editor("UI_CARET_ATTRS:  \(uiAttrs.caret)", level: .verbose, config: configuration.logging)
            }
            } else {
                MarkdownLogger.editor("AFTER STATE: Unable to capture", level: .error, config: configuration.logging)
            }
        
            let endSeparator = String(repeating: "=", count: 100)
            MarkdownLogger.editor(endSeparator, level: .verbose, config: configuration.logging)
        
        // Clear the pending log
        pendingKeystrokeLog = nil
    }

    private func captureUIKitTextAttributesSnapshot() -> (typing: String, caret: String)? {
        guard configuration.logging.isEnabled && configuration.logging.level >= .verbose else { return nil }

        let typing = describeAttributes(textView.typingAttributes)

        let attributedText = textView.attributedText ?? NSAttributedString(string: "")
        guard attributedText.length > 0 else {
            return (typing: typing, caret: "<empty>")
        }

        let caretLocation = min(max(0, textView.selectedRange.location), attributedText.length - 1)
        let caretAttrs = attributedText.attributes(at: caretLocation, effectiveRange: nil)
        return (typing: typing, caret: describeAttributes(caretAttrs))
    }

    private func describeAttributes(_ attrs: [NSAttributedString.Key: Any]) -> String {
        var parts: [String] = []

        if let font = attrs[.font] as? UIFont {
            var flags: [String] = []
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) { flags.append("bold") }
            if traits.contains(.traitItalic) { flags.append("italic") }
            parts.append("font=\(font.fontName) \(String(format: "%.1f", font.pointSize))\(flags.isEmpty ? "" : " [\(flags.joined(separator: ","))]")")
        }

        if let color = attrs[.foregroundColor] as? UIColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            parts.append(String(format: "fg=rgba(%.3f,%.3f,%.3f,%.3f)", r, g, b, a))
        }

        if let style = attrs[.paragraphStyle] as? NSParagraphStyle {
            parts.append(String(format: "para(line=%.1f,before=%.1f,after=%.1f)", style.lineSpacing, style.paragraphSpacingBefore, style.paragraphSpacing))
        }

        if let listItem = attrs[.listItem] {
            parts.append("listItem=\(type(of: listItem))")
        }

        if parts.isEmpty {
            return "<none>"
        }

        return parts.joined(separator: " ")
    }
    
    private func isCurrentLineEmpty() -> Bool {
        var isEmpty = false
        
        try? lexicalView.editor.read {
            // Get the current selection
            guard let selection = try? getSelection() as? RangeSelection else {
                return
            }
            
            // Prefer checking the nearest ListItemNode when present
            let anchor = selection.anchor
            var targetNode: Node?
            if let node = try? anchor.getNode() {
                if let li = self.findParentListItem(node) {
                    targetNode = li
                } else if let element = node as? ElementNode {
                    targetNode = element
                } else {
                    targetNode = node.getParent()
                }
            }
            guard let checkNode = targetNode else { return }
            
            // Check if the node has only whitespace/invisible caret anchors or is empty.
            let rawText = checkNode.getTextContent()
            isEmpty = isTextContentEmptyIgnoringEmptyInvisibles(rawText)
        }
        
        return isEmpty
    }

    private enum MarkdownShortcutPlan {
        case heading(level: MarkdownBlockType.HeadingLevel, markerText: String, textNodeKey: NodeKey)
        case list(kind: String, markerText: String, start: Int?, textNodeKey: NodeKey)

        var markerText: String {
            switch self {
            case .heading(_, let markerText, _), .list(_, let markerText, _, _):
                return markerText
            }
        }

        var textNodeKey: NodeKey {
            switch self {
            case .heading(_, _, let key), .list(_, _, _, let key):
                return key
            }
        }
    }

    private func handleMarkdownShortcutsIfNeeded(beforeSnapshot: MarkdownStateSnapshot?) -> Bool {
        // We only run on the exact keystroke that would complete the shortcut (space).
        // Supported:
        // - Headings: "# " through "###### "
        // - Unordered: "- " / "* " / "+ "
        // - Ordered: "1. " / "10. " etc
        var shouldTrigger = false
        var debugDetails: String? = nil
        var planned: MarkdownShortcutPlan? = nil

        try? lexicalView.editor.read {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            guard selection.isCollapsed() else { return }

            let anchor = selection.anchor
            guard anchor.type == .text else {
                debugDetails = "anchor.type=\(anchor.type) (expected .text)"
                return
            }

            guard let textNode = try? anchor.getNode() as? TextNode else { return }
            let raw = textNode.getTextContent()
            let visibleText = textContentRemovingEmptyInvisibles(raw)
            let visibleOffset: Int = {
                let prefix = self.prefix(of: raw, upToUTF16Offset: anchor.offset)
                return textContentRemovingEmptyInvisibles(prefix).count
            }()

            guard let paragraph = textNode.getParent() as? ParagraphNode else { return }
            guard (paragraph.getParent() is RootNode) else {
                debugDetails = "paragraph.parent=\(String(describing: paragraph.getParent())) (expected RootNode)"
                return
            }

            // Only trigger when the paragraph contains exactly the marker in a single text node.
            guard paragraph.getChildrenSize() == 1,
                  let onlyChild = paragraph.getFirstChild() as? TextNode,
                  onlyChild.key == textNode.key else {
                debugDetails = "paragraph.children=\(paragraph.getChildrenSize()) (expected 1 text child)"
                return
            }

            if visibleOffset == visibleText.count,
               visibleText.allSatisfy({ $0 == "#" }),
               (1...6).contains(visibleText.count) {
                let level: MarkdownBlockType.HeadingLevel
                switch visibleText.count {
                case 1: level = .h1
                case 2: level = .h2
                case 3: level = .h3
                case 4: level = .h4
                default: level = .h5
                }
                shouldTrigger = true
                planned = .heading(level: level, markerText: visibleText, textNodeKey: textNode.key)
                debugDetails = "trigger=true kind=heading marker=\(visibleText)"
                return
            }

            // Unordered list marker: "-" / "*" / "+" at visible offset 1 (ignoring internal ZWSP).
            if (visibleText == "-" || visibleText == "*" || visibleText == "+"), visibleOffset == 1 {
                shouldTrigger = true
                planned = .list(kind: "unordered", markerText: visibleText, start: nil, textNodeKey: textNode.key)
                debugDetails = "trigger=true kind=unordered marker=\(visibleText) paragraphHasNextSibling=\(paragraph.getNextSibling() != nil)"
                return
            }

            // Ordered list marker: "<digits>." at visible offset == visible length (ignoring internal ZWSP).
            if visibleText.hasSuffix("."), visibleOffset == visibleText.count {
                let digits = String(visibleText.dropLast())
                if let start = Int(digits), !digits.isEmpty {
                    shouldTrigger = true
                    planned = .list(kind: "ordered", markerText: visibleText, start: start, textNodeKey: textNode.key)
                    debugDetails = "trigger=true kind=ordered marker=\(visibleText) start=\(start) paragraphHasNextSibling=\(paragraph.getNextSibling() != nil)"
                    return
                }
            }

            debugDetails = "no trigger raw=\"\(raw)\" visible=\"\(visibleText)\" anchor.offset=\(anchor.offset) visibleOffset=\(visibleOffset)"
        }

        if configuration.logging.isEnabled && configuration.logging.level >= .verbose, let debugDetails {
            logger.logSimpleEvent("LIST_SHORTCUT_CHECK_v3", details: debugDetails)
        }

        guard shouldTrigger, let planned else { return false }

        self.logKeystroke("Space", beforeSnapshot: beforeSnapshot, action: "Markdown shortcut: convert block")

        // Perform the conversion as a single editor update to keep Lexical + native selection in sync.
        // Return true so Lexical does not insert the actual space character.
        try? lexicalView.editor.update {
            guard let selection = try? getSelection() as? RangeSelection else { return }
            guard selection.isCollapsed() else { return }

            guard let textNode: TextNode = getNodeByKey(key: planned.textNodeKey),
                  let paragraph = textNode.getParent() as? ParagraphNode,
                  paragraph.getParent() is RootNode else { return }

            // Remove the marker text so the new list item starts empty.
            // Delete backwards `markerText.count` times.
            for _ in 0..<planned.markerText.count {
                try? selection.deleteCharacter(isBackwards: true)
            }

            switch planned {
            case .heading(let level, _, _):
                _ = try? textNode.setText("")
                let heading = createHeadingNode(headingTag: level.lexicalType)
                _ = try? paragraph.replace(replaceWith: heading)
                let textAnchor = createTextNode(text: emptyTextCaretAnchor)
                try? heading.append([textAnchor])
                let anchor = Point(key: textAnchor.key, offset: 0, type: .text)
                try? setSelection(RangeSelection(anchor: anchor, focus: anchor, format: selection.format))
                return

            case .list(let kind, _, let plannedStart, _):
                let listType: ListType = kind == "ordered" ? .number : .bullet
                let start: Int = plannedStart ?? 1

                // Create an empty list item with ZWSP to ensure the bullet/number renders and the caret has a text anchor.
                let listItem = ListItemNode()
                let zwsp = createTextNode(text: emptyTextCaretAnchor)
                try? listItem.append([zwsp])

                func selectZWSP() {
                    let p = Point(key: zwsp.key, offset: 0, type: .text)
                    getActiveEditorState()?.selection = RangeSelection(anchor: p, focus: p, format: TextFormat())
                }

                // Merge with adjacent same-type lists if present; otherwise replace the paragraph with a new list.
                if let prevList = paragraph.getPreviousSibling() as? ListNode, prevList.getListType() == listType {
                    try? prevList.append([listItem])
                    try? paragraph.remove()

                    if let nextList = prevList.getNextSibling() as? ListNode, nextList.getListType() == listType {
                        try? prevList.append(nextList.getChildren())
                        try? nextList.remove()
                    }

                    try? updateChildrenListItemValue(list: prevList, children: nil)
                    selectZWSP()
                } else if let nextList = paragraph.getNextSibling() as? ListNode, nextList.getListType() == listType {
                    if let first = nextList.getFirstChild() {
                        _ = try? first.insertBefore(nodeToInsert: listItem)
                    } else {
                        try? nextList.append([listItem])
                    }
                    try? paragraph.remove()
                    try? updateChildrenListItemValue(list: nextList, children: nil)
                    selectZWSP()
                } else {
                    let list = ListNode(listType: listType, start: start)
                    try? list.append([listItem])
                    _ = try? paragraph.replace(replaceWith: list)
                    try? updateChildrenListItemValue(list: list, children: nil)
                    selectZWSP()
                }
            }
        }

        // Nudge the frontend to update selection rendering immediately.
        lexicalView.editor.dispatchCommand(type: .selectionChange)
        syncNativeSelectionToLexicalSelection()
        updatePlaceholder()
        return true
    }

    private func stripZeroWidthSpacesInActiveTextNodeIfNeeded() {
        // Keep this minimal and conservative: only touch a collapsed text selection.
        // This prevents leftover ZWSP from poisoning shortcuts and selection math.
        try? lexicalView.editor.update {
            self.stripZeroWidthSpacesInActiveTextNodeIfNeededWithinCurrentUpdate()
        }
    }

    private func stripZeroWidthSpacesInActiveTextNodeIfNeededWithinCurrentUpdate() {
        guard let selection = try? getSelection() as? RangeSelection else { return }
        guard selection.isCollapsed(), selection.anchor.type == .text else { return }
        guard let textNode = try? selection.anchor.getNode() as? TextNode else { return }

        let raw = textNode.getTextContent()
        guard isTextContentEmptyIgnoringEmptyInvisibles(raw) else { return }

        let cleaned = textContentRemovingEmptyInvisibles(raw)

        guard cleaned != raw else { return }

        // Preserve the caret position relative to visible text.
        let prefix = prefix(of: raw, upToUTF16Offset: selection.anchor.offset)
        let invisiblesBefore = emptyTextInvisibleScalarCount(in: prefix)
        let newOffset = max(0, selection.anchor.offset - invisiblesBefore)
        let clampedOffset = min(newOffset, (cleaned as NSString).length)

        _ = try? textNode.setText(cleaned)

        let p = Point(key: textNode.key, offset: clampedOffset, type: .text)
        try? setSelection(RangeSelection(anchor: p, focus: p, format: TextFormat()))
    }

    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        updateEditingState(true)
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        updateEditingState(false)
    }
    
    private func updateEditingState(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
        delegate?.markdownEditor(self, didChangeEditingState: isEditing)
    }
    
    private func isCursorAtLineStart() -> Bool {
        var isAtStart = false
        
        try? lexicalView.editor.read {
            // Get the current selection
            guard let selection = try? getSelection() as? RangeSelection else {
                return
            }
            
            guard selection.isCollapsed() else { return }
            let anchor = selection.anchor
            
            if anchor.type == .element {
                // Element-anchored selection: offset 0 means at start
                isAtStart = anchor.offset == 0
                return
            }
            
            // Text-anchored selection: consider ZWSP/whitespace before caret as "at start"
            if anchor.type == .text,
               let textNode = try? anchor.getNode() as? TextNode {
                let fullText = textNode.getTextContent()
                let prefix = self.prefix(of: fullText, upToUTF16Offset: anchor.offset)
                let sanitized = textContentRemovingEmptyInvisibles(prefix)
                isAtStart = sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        
        return isAtStart
    }
    
    // MARK: - Helpers
    private func prefix(of text: String, upToUTF16Offset offset: Int) -> String {
        let nsText = text as NSString
        let length = min(max(offset, 0), nsText.length)
        return nsText.substring(to: length)
    }

    private func findParentListItem(_ node: Node) -> ListItemNode? {
        var current: Node? = node
        while let n = current {
            if let li = n as? ListItemNode { return li }
            current = n.getParent()
        }
        return nil
    }
    
    // MARK: - Controller Binding
    
    @available(iOS 17.0, *)
    internal func bindController(_ controller: Any) {
        self.controller = controller as AnyObject
    }
    
    private static func createLexicalTheme(from markdownTheme: MarkdownTheme) -> Theme {
        let theme = Theme()
        
        // Configure list styling from MarkdownTheme
        theme.indentSize = markdownTheme.spacing.indentSize
        theme.listBulletMargin = markdownTheme.spacing.listBulletMargin
        theme.listBulletTextSpacing = markdownTheme.spacing.listBulletTextSpacing
        
        // Note: Cursor height adjustment is now handled automatically per-block 
        // in TextView.caretRect(for:) based on actual line spacing at cursor position
        
        // Configure typography with line spacing and paragraph spacing (BEFORE and AFTER blocks)
        theme.paragraph = [
            .font: markdownTheme.typography.body,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.paragraphSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.paragraphSpacingBefore
        ]
        
        theme.setValue(.heading, forSubtype: "h1", value: [
            .font: markdownTheme.typography.h1,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.headingSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.headingSpacingBefore
        ])
        
        theme.setValue(.heading, forSubtype: "h2", value: [
            .font: markdownTheme.typography.h2,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.headingSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.headingSpacingBefore
        ])
        
        theme.setValue(.heading, forSubtype: "h3", value: [
            .font: markdownTheme.typography.h3,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.headingSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.headingSpacingBefore
        ])
        
        theme.setValue(.heading, forSubtype: "h4", value: [
            .font: markdownTheme.typography.h4,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.headingSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.headingSpacingBefore
        ])
        
        theme.setValue(.heading, forSubtype: "h5", value: [
            .font: markdownTheme.typography.h5,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.headingSpacing,
            .paragraphSpacingBefore: markdownTheme.spacing.headingSpacingBefore
        ])
        
        let codeBlockDrawing = CodeBlockCustomDrawingAttributes(
            background: markdownTheme.colors.codeBackground,
            border: markdownTheme.colors.codeBorder,
            borderWidth: markdownTheme.colors.codeBorder == .clear ? 0 : 1
        )

        theme.code = [
            .font: markdownTheme.typography.code,
            .foregroundColor: markdownTheme.colors.code,
            .paddingHead: 16.0,
            .paddingTail: -16.0,
            .lineSpacing: 3.0,
            .codeBlockCustomDrawing: codeBlockDrawing
        ]

        theme.setBlockLevelAttributes(.code, value: BlockLevelAttributes(
            marginTop: 14,
            marginBottom: 14,
            paddingTop: 10,
            paddingBottom: 10
        ))

        theme.setValue(.text, forSubtype: TextNodeThemeSubtype.code, value: [
            .font: markdownTheme.typography.code,
            .foregroundColor: markdownTheme.colors.code,
            .inlineCodeBackgroundColor: markdownTheme.colors.codeBackground
        ])

        theme.quote = [
            .font: markdownTheme.typography.body,
            .foregroundColor: markdownTheme.colors.quote
        ]
        
        // Configure list item spacing and bullet styling
        theme.listItem = [
            .font: markdownTheme.typography.body,
            .foregroundColor: markdownTheme.colors.text,
            .lineSpacing: markdownTheme.spacing.lineSpacing,
            .paragraphSpacing: markdownTheme.spacing.listItemSpacing,  // Space between list items
            .listSpacing: markdownTheme.spacing.listSpacing,  // Space after entire list
            .bulletSizeIncrease: markdownTheme.spacing.bulletSizeIncrease,  // Bullet size increase
            .bulletWeight: markdownTheme.spacing.bulletWeight.rawValue,  // Bullet font weight
            .bulletVerticalOffset: markdownTheme.spacing.bulletVerticalOffset  // Bullet vertical positioning
        ]
        
        return theme
    }
    
    private static func createPlugins(for features: MarkdownFeatureSet) -> [Plugin] {
        var plugins: [Plugin] = []
        
        // Always include markdown support
        plugins.append(LexicalMarkdown())
        
        if features.contains(.lists) {
            plugins.append(ListPlugin())
        }
        
        if features.contains(.links) {
            plugins.append(LinkPlugin())
        }
        
        // Always add the zero-width space fix plugin for better list item deletion behavior
        plugins.append(ZeroWidthSpaceFixPlugin())
        
        return plugins
    }
    
    private func setupCommandBar() {
        guard !configuration.commandBar.groups.isEmpty else {
            textView.inputAccessoryView = nil
            return
        }
        let commandBar = MarkdownCommandBarInputView(content: configuration.commandBar)
        commandBar.editor = self
        textView.inputAccessoryView = commandBar
    }

    internal func configureAccessoryTracking(scrollView: UIScrollView?) {
        guard let commandBar = textView.inputAccessoryView as? MarkdownCommandBarInputView else { return }
        commandBar.trackedScrollView = scrollView
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }

    internal var commandBarAccessoryView: MarkdownCommandBarInputView? {
        textView.inputAccessoryView as? MarkdownCommandBarInputView
    }
    
    private func updatePlaceholder() {
        // Apply placeholder to Lexical if available
        guard let placeholderText, !placeholderText.isEmpty else {
            // Clear by setting empty placeholder to avoid stale label
            lexicalView.placeholderText = nil
            return
        }
        
        // Choose font based on the active empty block so toolbar changes are visible
        // before the user types.
        let emptyBlockType: MarkdownBlockType? = {
            var blockType: MarkdownBlockType?
            try? lexicalView.editor.read {
                guard let root = getRoot(),
                      isTextContentEmptyIgnoringEmptyInvisibles(root.getTextContent()) else { return }
                guard let selection = try? getSelection() as? RangeSelection,
                      let node = try? selection.anchor.getNode() else { return }

                let block = (node as? ElementNode) ?? findMatchingParent(startingNode: node) { candidate in
                    candidate.getParent() is RootNode
                } as? ElementNode

                if let heading = block as? HeadingNode {
                    switch heading.getTag() {
                    case .h1: blockType = .heading(level: .h1)
                    case .h2: blockType = .heading(level: .h2)
                    case .h3: blockType = .heading(level: .h3)
                    case .h4: blockType = .heading(level: .h4)
                    case .h5: blockType = .heading(level: .h5)
                    }
                } else if block is ParagraphNode {
                    blockType = .paragraph
                }
            }
            return blockType
        }()

        let isEmpty: Bool = {
            let result = domainBridge.exportDocument()
            if case .success(let doc) = result {
                return doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }()
        
        let font: UIFont
        if case .heading(let level) = emptyBlockType {
            switch level {
            case .h1: font = configuration.theme.typography.h1
            case .h2: font = configuration.theme.typography.h2
            case .h3: font = configuration.theme.typography.h3
            case .h4: font = configuration.theme.typography.h4
            case .h5, .h6: font = configuration.theme.typography.h5
            }
        } else if configuration.behavior.startWithTitle && isEmpty {
            font = configuration.theme.typography.h1
        } else {
            font = configuration.theme.typography.body
        }
        
        let color = configuration.theme.colors.text.withAlphaComponent(0.35)
        let placeholder = LexicalPlaceholderText(text: placeholderText, font: font, color: color)
        lexicalView.placeholderText = placeholder
        // Let Lexical manage placeholder visibility based on content state
    }

    // MARK: - Streaming Replacement Editing

    private struct ReplacementSessionState {
        let token: UUID
        let anchorKey: NodeKey
        let startedAt: Date
        let beforeEditorState: EditorState
        let originalRawText: String
        let matchStartUtf16: Int
        let originalMatchText: String
        let originalMatchLengthUtf16: Int
        var replacementText: String
        var replacementLengthUtf16: Int
    }

    private struct AppendSessionState {
        let token: UUID
        let startedAt: Date
        let beforeEditorState: EditorState
        var appendedMarkdown: String
        var appendedRootNodeKeys: [NodeKey]
    }

    private func exportMarkdownForHistory() -> String? {
        switch domainBridge.exportDocument() {
        case .success(let doc):
            return doc.content
        case .failure:
            return nil
        }
    }

    private func applyEffectiveEditability() {
        let locked = (replacementSessionState != nil || appendSessionState != nil)
        lexicalView.textView.isEditable = isEditable && !locked
    }

    private func clearMarkedTextIfNeeded() {
        // Lexical reconciliation can crash if UIKit has an active IME composition ("marked text")
        // while we apply programmatic streaming edits. Clear it best-effort before mutations.
        let tv = lexicalView.textView
        if tv.markedTextRange != nil {
            tv.unmarkText()
        }
    }

    private func replaceTextRangeInEditor(
        anchorKey: NodeKey,
        startUtf16: Int,
        lengthUtf16: Int,
        replacementText: String
    ) {
        clearMarkedTextIfNeeded()
        do {
            try lexicalView.editor.update {
                guard let node = getNodeByKey(key: anchorKey) as? ElementNode else { return }

                // Collect leaf text nodes so we can target a precise selection range.
                func collectTextNodes(from node: Node) -> [TextNode] {
                    if let text = node as? TextNode { return [text] }
                    guard let element = node as? ElementNode else { return [] }
                    return element.getChildren().flatMap(collectTextNodes(from:))
                }

                var textNodes = collectTextNodes(from: node)
                if textNodes.isEmpty {
                    // Ensure a text node exists so we can create a text selection.
                    let seedText: String = (node is ListItemNode || node is CodeNode) ? emptyTextCaretAnchor : ""
                    let textNode = TextNode(text: seedText)
                    try? node.append([textNode])
                    textNodes = [textNode]
                }

                guard let lastTextNode = textNodes.last else { return }

                func locate(offsetUtf16: Int) -> (node: TextNode, localOffset: Int) {
                    let clamped = max(0, offsetUtf16)
                    var remaining = clamped
                    for tn in textNodes {
                        let len = tn.getTextContentSize()
                        if remaining <= len {
                            return (tn, remaining)
                        }
                        remaining -= len
                    }
                    return (lastTextNode, lastTextNode.getTextContentSize())
                }

                let start = max(0, startUtf16)
                let end = max(start, start + max(0, lengthUtf16))

                let startPos = locate(offsetUtf16: start)
                let endPos = locate(offsetUtf16: end)

                let anchor = Point(key: startPos.node.key, offset: startPos.localOffset, type: .text)
                let focus = Point(key: endPos.node.key, offset: endPos.localOffset, type: .text)
                let selection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
                getActiveEditorState()?.selection = selection
                try selection.insertRawText(text: replacementText)

                // Preserve Lexical's invariants for “empty” blocks that must remain selectable/editable.
                if (node is ListItemNode || node is CodeNode), node.getTextContent().isEmpty {
                    for child in node.getChildren() {
                        try? child.remove()
                    }
                    let zwsp = TextNode(text: emptyTextCaretAnchor)
                    try? node.append([zwsp])
                    let p = Point(key: zwsp.key, offset: zwsp.getTextContentSize(), type: .text)
                    getActiveEditorState()?.selection = RangeSelection(anchor: p, focus: p, format: TextFormat())
                }
            }
        } catch {
            // Best-effort; failures should not crash.
        }
    }

    private func setAppendMarkdownInEditor(_ markdown: String) {
        clearMarkedTextIfNeeded()
        do {
            try lexicalView.editor.update {
                guard let root = getRoot() else { return }
                guard var state = appendSessionState else { return }

                // Remove any previously appended top-level nodes.
                for key in state.appendedRootNodeKeys {
                    if let node = getNodeByKey(key: key) {
                        try? node.remove()
                    }
                }

                let nodesToAppend = MarkdownImporter.makeNodes(from: markdown)
                if !nodesToAppend.isEmpty {
                    try? root.append(nodesToAppend)
                }

                state.appendedMarkdown = markdown
                state.appendedRootNodeKeys = nodesToAppend.map(\.key)
                appendSessionState = state

                // Move caret to end of appended content (best-effort).
                if let last = nodesToAppend.last {
                    if let list = last as? ListNode, let lastItem = list.getLastChild() as? ListItemNode {
                        let point = Point(key: lastItem.key, offset: 0, type: .element)
                        getActiveEditorState()?.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
                    } else if let element = last as? ElementNode {
                        let point = Point(key: element.key, offset: element.getChildrenSize(), type: .element)
                        getActiveEditorState()?.selection = RangeSelection(anchor: point, focus: point, format: TextFormat())
                    }
                }
            }
        } catch {
            // Best-effort; failures should not crash.
        }
    }
}

// MARK: - MarkdownEditorContentView Protocol Conformance

extension MarkdownEditorContentView: MarkdownEditorInterface {}

// MARK: - Streaming Editing Conformance

@MainActor
extension MarkdownEditorContentView: MarkdownStreamingEditing, MarkdownStreamingEditingInternal, MarkdownStreamingAppending, MarkdownStreamingAppendingInternal {
    public func startReplacement(
        findText: String,
        beforeContext: String?,
        afterContext: String?
    ) throws -> ReplacementSession {
        guard replacementSessionState == nil, appendSessionState == nil else {
            throw StreamingReplacementError.sessionAlreadyActive
        }

        let trimmed = findText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StreamingReplacementError.emptyFindText
        }

        let match: StreamingReplacementMatchResult? = {
            do {
                var candidates: [StreamingReplacementMatchCandidate] = []
                try lexicalView.editor.read {
                    guard let root = getRoot() else { return }
                    var ordinal = 0

                    for child in root.getChildren() {
                        if let list = child as? ListNode {
                            for item in list.getChildren().compactMap({ $0 as? ListItemNode }) {
                                let raw = item.getTextContent()
                                let normalized = StreamingReplacementMatching.normalizeForMatchingWithMapping(raw)
                                candidates.append(.init(
                                    nodeKey: item.key,
                                    rawText: raw,
                                    normalizedText: normalized.normalized,
                                    normalizedMapping: normalized.mapping,
                                    ordinal: ordinal
                                ))
                                ordinal += 1
                            }
                            continue
                        }

                        if let element = child as? ElementNode {
                            let raw = element.getTextContent()
                            let normalized = StreamingReplacementMatching.normalizeForMatchingWithMapping(raw)
                            candidates.append(.init(
                                nodeKey: element.key,
                                rawText: raw,
                                normalizedText: normalized.normalized,
                                normalizedMapping: normalized.mapping,
                                ordinal: ordinal
                            ))
                            ordinal += 1
                        }
                    }
                }

                return StreamingReplacementMatching.bestMatch(
                    candidates: candidates,
                    findText: trimmed,
                    beforeContext: beforeContext,
                    afterContext: afterContext
                )
            } catch {
                return nil
            }
        }()

        guard let match else {
            throw StreamingReplacementError.matchNotFound
        }

        let rawLength = (match.rawText as NSString).length
        guard match.matchStartUtf16 >= 0,
              match.matchLengthUtf16 >= 0,
              (match.matchStartUtf16 + match.matchLengthUtf16) <= rawLength else {
            throw StreamingReplacementError.invalidMatchRange
        }

        let originalMatchText = (match.rawText as NSString).substring(
            with: NSRange(location: match.matchStartUtf16, length: match.matchLengthUtf16)
        )

        let token = UUID()
        let startedAt = Date()
        let beforeEditorState = lexicalView.editor.getEditorState().clone(selection: nil)
        replacementSessionState = ReplacementSessionState(
            token: token,
            anchorKey: match.nodeKey,
            startedAt: startedAt,
            beforeEditorState: beforeEditorState,
            originalRawText: match.rawText,
            matchStartUtf16: match.matchStartUtf16,
            originalMatchText: originalMatchText,
            originalMatchLengthUtf16: match.matchLengthUtf16,
            replacementText: "",
            replacementLengthUtf16: 0
        )

        applyEffectiveEditability()
        // Remove the matched range immediately so the user sees “editing in progress”.
        replaceTextRangeInEditor(
            anchorKey: match.nodeKey,
            startUtf16: match.matchStartUtf16,
            lengthUtf16: match.matchLengthUtf16,
            replacementText: ""
        )

        return ReplacementSession(owner: self, token: token)
    }

    public func startAppend() throws -> AppendSession {
        guard replacementSessionState == nil, appendSessionState == nil else {
            throw StreamingReplacementError.sessionAlreadyActive
        }

        let token = UUID()
        let startedAt = Date()
        let beforeEditorState = lexicalView.editor.getEditorState().clone(selection: nil)
        appendSessionState = AppendSessionState(
            token: token,
            startedAt: startedAt,
            beforeEditorState: beforeEditorState,
            appendedMarkdown: "",
            appendedRootNodeKeys: []
        )
        applyEffectiveEditability()

        return AppendSession(owner: self, token: token)
    }

    internal func isReplacementSessionActive(token: UUID) -> Bool {
        replacementSessionState?.token == token
    }

    internal func appendReplacementDelta(token: UUID, delta: String) {
        guard var state = replacementSessionState, state.token == token else { return }
        guard !delta.isEmpty else { return }
        let oldLength = state.replacementLengthUtf16
        state.replacementText += delta
        state.replacementLengthUtf16 = (state.replacementText as NSString).length
        replacementSessionState = state
        replaceTextRangeInEditor(
            anchorKey: state.anchorKey,
            startUtf16: state.matchStartUtf16,
            lengthUtf16: oldLength,
            replacementText: state.replacementText
        )
    }

    internal func setReplacementText(token: UUID, fullText: String) {
        guard var state = replacementSessionState, state.token == token else { return }
        let oldLength = state.replacementLengthUtf16
        state.replacementText = fullText
        state.replacementLengthUtf16 = (state.replacementText as NSString).length
        replacementSessionState = state
        replaceTextRangeInEditor(
            anchorKey: state.anchorKey,
            startUtf16: state.matchStartUtf16,
            lengthUtf16: oldLength,
            replacementText: state.replacementText
        )
    }

    internal func finishReplacement(token: UUID) {
        guard let state = replacementSessionState, state.token == token else { return }

        // Commit a single undo step for the whole streaming session.
        undoStack.append(state.beforeEditorState.clone(selection: nil))
        if undoStack.count > Self.maxHistoryEntries {
            undoStack.removeFirst(undoStack.count - Self.maxHistoryEntries)
        }
        redoStack.removeAll()
        lastHistoryChangeAt = nil
        lastHistoryMarkdown = exportMarkdownForHistory()

        replacementSessionState = nil
        applyEffectiveEditability()
    }

    internal func cancelReplacement(token: UUID) {
        guard let state = replacementSessionState, state.token == token else { return }

        // Cancel means "restore original document state". Since we lock editing during a session,
        // reverting the full EditorState is the most robust way to roll back.
        replacementSessionState = nil
        applyEffectiveEditability()

        isApplyingUndoRedo = true
        defer { isApplyingUndoRedo = false }
        do {
            try lexicalView.editor.setEditorState(state.beforeEditorState.clone(selection: nil))
        } catch {
            // Best-effort; failures should not crash.
        }
        lastHistoryChangeAt = nil
        lastHistoryMarkdown = exportMarkdownForHistory()
    }

    // MARK: - Append Streaming Internal

    internal func isAppendSessionActive(token: UUID) -> Bool {
        appendSessionState?.token == token
    }

    internal func appendAppendDelta(token: UUID, delta: String) {
        guard var state = appendSessionState, state.token == token else { return }
        guard !delta.isEmpty else { return }
        state.appendedMarkdown += delta
        appendSessionState = state
        setAppendMarkdownInEditor(state.appendedMarkdown)
    }

    internal func setAppendText(token: UUID, fullText: String) {
        guard var state = appendSessionState, state.token == token else { return }
        state.appendedMarkdown = fullText
        appendSessionState = state
        setAppendMarkdownInEditor(state.appendedMarkdown)
    }

    internal func finishAppend(token: UUID) {
        guard let state = appendSessionState, state.token == token else { return }
        if !state.appendedMarkdown.isEmpty {
            // Commit a single undo step for the whole streaming session.
            undoStack.append(state.beforeEditorState.clone(selection: nil))
            if undoStack.count > Self.maxHistoryEntries {
                undoStack.removeFirst(undoStack.count - Self.maxHistoryEntries)
            }
            redoStack.removeAll()
            lastHistoryChangeAt = nil
            lastHistoryMarkdown = exportMarkdownForHistory()
        }
        appendSessionState = nil
        applyEffectiveEditability()
    }

    internal func cancelAppend(token: UUID) {
        guard let state = appendSessionState, state.token == token else { return }

        // Cancel means "restore original document state".
        appendSessionState = nil
        applyEffectiveEditability()

        isApplyingUndoRedo = true
        defer { isApplyingUndoRedo = false }
        do {
            try lexicalView.editor.setEditorState(state.beforeEditorState.clone(selection: nil))
        } catch {
            // Best-effort; failures should not crash.
        }
        lastHistoryChangeAt = nil
        lastHistoryMarkdown = exportMarkdownForHistory()
    }
}

// MARK: - Primary Editor Interface

public final class MarkdownEditorView: UIView {
    
    // MARK: - Public Properties
    
    public weak var delegate: MarkdownEditorDelegate? {
        didSet { contentView.delegate = delegate }
    }
    
    public var isEditable: Bool = true {
        didSet { contentView.isEditable = isEditable }
    }
    
    public var placeholderText: String? {
        didSet { contentView.placeholderText = placeholderText }
    }
    
    /// Access to the underlying text view for setting inputAccessoryView
    public var textView: UITextView {
        return contentView.textView
    }
    
    /// Input accessory view for this editor
    public override var inputAccessoryView: UIView? {
        get { return contentView.inputAccessoryView }
        set { contentView.inputAccessoryView = newValue }
    }
    
    // MARK: - Private Properties
    
    private let contentView: MarkdownEditorContentView
    private let scrollView: UIScrollView
    private let configuration: MarkdownEditorConfiguration
    private var accessoryCoordinator: MarkdownAccessoryCoordinator?
    private var hasNormalizedInitialContentOffset = false
    
    // MARK: - Initialization
    
    public init(configuration: MarkdownEditorConfiguration = .init()) {
        self.configuration = configuration
        self.contentView = MarkdownEditorContentView(configuration: configuration)
        self.scrollView = UIScrollView()
        
        super.init(frame: .zero)
        setupScrollView()
        contentView.configureAccessoryTracking(scrollView: scrollView)
        if let commandBarAccessoryView = contentView.commandBarAccessoryView {
            accessoryCoordinator = MarkdownAccessoryCoordinator(
                hostView: self,
                scrollView: scrollView,
                textView: contentView.textView,
                accessoryView: commandBarAccessoryView
            )
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public API
    
    public func loadMarkdown(_ document: MarkdownDocument) -> MarkdownEditorResult<Void> {
        return contentView.loadMarkdown(document)
    }
    
    public func exportMarkdown() -> MarkdownEditorResult<MarkdownDocument> {
        return contentView.exportMarkdown()
    }
    
    public func applyFormatting(_ formatting: InlineFormatting) {
        contentView.applyFormatting(formatting)
    }
    
    public func setBlockType(_ blockType: MarkdownBlockType) {
        contentView.setBlockType(blockType)
    }
    
    public func getCurrentFormatting() -> InlineFormatting {
        return contentView.getCurrentFormatting()
    }
    
    public func getCurrentBlockType() -> MarkdownBlockType {
        return contentView.getCurrentBlockType()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        accessoryCoordinator?.refreshInsets()
        normalizeInitialContentOffsetIfNeeded()
    }

    // MARK: - Undo/Redo

    public func undo() {
        contentView.undo()
    }

    public func redo() {
        contentView.redo()
    }
    
    // MARK: - Private Methods
    
    private func setupScrollView() {
        // Configure scroll view
        scrollView.backgroundColor = configuration.theme.colors.backgroundColor
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false

        // Add scroll view to main view
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Add content view to scroll view
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            // Content view width should match the visible scroll frame.
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        // Apply background color from theme
        let backgroundColor = configuration.theme.colors.backgroundColor
        self.backgroundColor = backgroundColor
        scrollView.backgroundColor = backgroundColor
    }

    private func normalizeInitialContentOffsetIfNeeded() {
        guard !hasNormalizedInitialContentOffset, window != nil else { return }

        let minY = -scrollView.adjustedContentInset.top
        guard minY < 0 else {
            hasNormalizedInitialContentOffset = true
            return
        }

        guard scrollView.contentOffset.y == 0 else {
            hasNormalizedInitialContentOffset = true
            return
        }

        scrollView.setContentOffset(CGPoint(x: 0, y: minY), animated: false)
        hasNormalizedInitialContentOffset = true
    }
    
    // MARK: - Controller Binding
    
    @available(iOS 17.0, *)
    internal func bindController(_ controller: Any) {
        contentView.bindController(controller)
    }
}

// MARK: - MarkdownEditorView Protocol Conformance

extension MarkdownEditorView: MarkdownEditorInterface {}

@MainActor
extension MarkdownEditorView: MarkdownStreamingEditing {
    public func startReplacement(
        findText: String,
        beforeContext: String?,
        afterContext: String?
    ) throws -> ReplacementSession {
        try contentView.startReplacement(findText: findText, beforeContext: beforeContext, afterContext: afterContext)
    }
}

@MainActor
extension MarkdownEditorView: MarkdownStreamingAppending {
    public func startAppend() throws -> AppendSession {
        try contentView.startAppend()
    }
}

// MARK: - Editor Interface Protocol

public protocol MarkdownEditorInterface: AnyObject {
    var textView: UITextView { get }
    func loadMarkdown(_ document: MarkdownDocument) -> MarkdownEditorResult<Void>
    func exportMarkdown() -> MarkdownEditorResult<MarkdownDocument>
    func applyFormatting(_ formatting: InlineFormatting)
    func setBlockType(_ blockType: MarkdownBlockType)
    func getCurrentFormatting() -> InlineFormatting
    func getCurrentBlockType() -> MarkdownBlockType
    func undo()
    func redo()
}

// MARK: - Delegate Protocol

public protocol MarkdownEditorDelegate: AnyObject {
    func markdownEditorDidChange(_ editor: any MarkdownEditorInterface)
    func markdownEditor(_ editor: any MarkdownEditorInterface, didLoadDocument document: MarkdownDocument)
    func markdownEditor(_ editor: any MarkdownEditorInterface, didAutoSave document: MarkdownDocument)
    func markdownEditor(_ editor: any MarkdownEditorInterface, didEncounterError error: MarkdownEditorError)
    func markdownEditor(_ editor: any MarkdownEditorInterface, didChangeEditingState isEditing: Bool)
}

// Provide default implementations
public extension MarkdownEditorDelegate {
    func markdownEditorDidChange(_ editor: any MarkdownEditorInterface) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didLoadDocument document: MarkdownDocument) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didAutoSave document: MarkdownDocument) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didEncounterError error: MarkdownEditorError) {}
    func markdownEditor(_ editor: any MarkdownEditorInterface, didChangeEditingState isEditing: Bool) {}
}

// MARK: - Keystroke Logging Support

private struct PendingKeystrokeLog {
    let keyName: String
    let action: String
    let beforeSnapshot: MarkdownStateSnapshot
}
