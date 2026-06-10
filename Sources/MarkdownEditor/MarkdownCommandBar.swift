import UIKit
import SwiftUI

// MARK: - Command Bar Content API

/// A single button in the command bar.
public enum CommandBarItem {
    // Built-in items
    case undo, redo
    case bold, italic, strikethrough
    case unorderedList, orderedList
    case heading(MarkdownBlockType.HeadingLevel)

    // Host-defined items
    case iconButton(systemName: String, label: String, action: @MainActor (any MarkdownEditorInterface) -> Void)
    case textButton(title: String, action: @MainActor (any MarkdownEditorInterface) -> Void)
}

/// A visual group rendered as a glass capsule containing one or more items.
public struct CommandBarGroup {
    public let items: [CommandBarItem]

    public init(_ items: [CommandBarItem]) {
        self.items = items
    }

    public init(@CommandBarItemBuilder items: () -> [CommandBarItem]) {
        self.items = items()
    }
}

/// The full command bar layout, composed of groups.
public struct CommandBarContent {
    public let groups: [CommandBarGroup]

    public init(_ groups: [CommandBarGroup]) {
        self.groups = groups
    }

    public init(@CommandBarContentBuilder groups: () -> [CommandBarGroup]) {
        self.groups = groups()
    }
}

// MARK: Presets

public extension CommandBarContent {
    /// The default command bar matching the built-in layout.
    static let `default` = CommandBarContent {
        undoRedoGroup
        formattingGroup
        listsGroup
        headingsGroup
    }

    /// An empty command bar — the accessory view is not shown.
    static let hidden = CommandBarContent([])

    // Individual groups for cherry-picking

    static let undoRedoGroup = CommandBarGroup([.undo, .redo])
    static let formattingGroup = CommandBarGroup([.bold, .italic, .strikethrough])
    static let listsGroup = CommandBarGroup([.unorderedList, .orderedList])
    static let headingsGroup = CommandBarGroup([.heading(.h1), .heading(.h2)])
}

// MARK: Result Builders

@resultBuilder
public struct CommandBarItemBuilder {
    public static func buildBlock(_ components: [CommandBarItem]...) -> [CommandBarItem] { components.flatMap { $0 } }
    public static func buildOptional(_ items: [CommandBarItem]?) -> [CommandBarItem] { items ?? [] }
    public static func buildEither(first items: [CommandBarItem]) -> [CommandBarItem] { items }
    public static func buildEither(second items: [CommandBarItem]) -> [CommandBarItem] { items }
    public static func buildArray(_ components: [[CommandBarItem]]) -> [CommandBarItem] { components.flatMap { $0 } }
    public static func buildExpression(_ item: CommandBarItem) -> [CommandBarItem] { [item] }
}

@resultBuilder
public struct CommandBarContentBuilder {
    public static func buildBlock(_ components: [CommandBarGroup]...) -> [CommandBarGroup] { components.flatMap { $0 } }
    public static func buildOptional(_ groups: [CommandBarGroup]?) -> [CommandBarGroup] { groups ?? [] }
    public static func buildEither(first groups: [CommandBarGroup]) -> [CommandBarGroup] { groups }
    public static func buildEither(second groups: [CommandBarGroup]) -> [CommandBarGroup] { groups }
    public static func buildArray(_ components: [[CommandBarGroup]]) -> [CommandBarGroup] { components.flatMap { $0 } }
    public static func buildExpression(_ group: CommandBarGroup) -> [CommandBarGroup] { [group] }
}

// MARK: - Layout Constants

private enum CommandBarLayout {
    static let barHeight: CGFloat = 55
    static let controlHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 15
    static let menuHeight: CGFloat = 45
    static let menuCornerRadius: CGFloat = 22.5
    static let collapsedLabelWidth: CGFloat = 220
}

// MARK: - Bridge

@Observable
@MainActor
final class CommandBarActions {
    weak var editor: (any MarkdownEditorInterface)?

    func undo() { editor?.undo() }
    func redo() { editor?.redo() }
    func toggleBold() { editor?.applyFormatting(.bold) }
    func toggleItalic() { editor?.applyFormatting(.italic) }
    func toggleStrikethrough() { editor?.applyFormatting(.strikethrough) }
    func setUnorderedList() { editor?.setBlockType(.unorderedList) }
    func setOrderedList() { editor?.setBlockType(.orderedList) }

    func setHeading(_ level: MarkdownBlockType.HeadingLevel) {
        editor?.setBlockType(.heading(level: level))
    }

    func performCustom(_ action: @MainActor (any MarkdownEditorInterface) -> Void) {
        guard let editor else { return }
        action(editor)
    }
}

// MARK: - SwiftUI Content

struct CommandBarContentView: View {
    var actions: CommandBarActions
    var content: CommandBarContent
    @State private var expansionProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - CommandBarLayout.horizontalPadding * 2)
            let labelSize = CGSize(
                width: min(CommandBarLayout.collapsedLabelWidth, availableWidth),
                height: CommandBarLayout.menuHeight
            )

            ExpandableCommandBarMenu(
                alignment: .center,
                progress: expansionProgress,
                labelSize: labelSize,
                expandedSize: CGSize(width: availableWidth, height: CommandBarLayout.menuHeight),
                cornerRadius: CommandBarLayout.menuCornerRadius
            ) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Array(content.groups.enumerated()), id: \.offset) { _, group in
                            HStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                    resolvedView(for: item)
                                }
                            }
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .frame(width: availableWidth, height: CommandBarLayout.menuHeight)
            } label: {
                HStack(spacing: 20) {
                    ForEach(Array(collapsedItems.enumerated()), id: \.offset) { _, item in
                        resolvedView(for: item)
                    }
                }
                .font(.title3)
                .foregroundStyle(Color.primary)
            }
            .commandBarScrollEffect()
            .frame(width: availableWidth, height: CommandBarLayout.menuHeight)
            .padding(.horizontal, CommandBarLayout.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .onAppear {
                withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.65)) {
                    expansionProgress = 1
                }
            }
        }
        .frame(height: CommandBarLayout.barHeight)
    }

    private var collapsedItems: [CommandBarItem] {
        content.groups.flatMap(\.items).prefix(4).map { $0 }
    }

    // MARK: - Item Resolution

    @ViewBuilder
    private func resolvedView(for item: CommandBarItem) -> some View {
        switch item {
        case .undo:
            iconButton("arrow.uturn.left", label: "Undo", action: actions.undo)
        case .redo:
            iconButton("arrow.uturn.right", label: "Redo", action: actions.redo)
        case .bold:
            iconButton("bold", label: "Bold", action: actions.toggleBold)
        case .italic:
            iconButton("italic", label: "Italic", action: actions.toggleItalic)
        case .strikethrough:
            iconButton("strikethrough", label: "Strikethrough", action: actions.toggleStrikethrough)
        case .unorderedList:
            iconButton("list.bullet", label: "Bullet List", action: actions.setUnorderedList)
        case .orderedList:
            iconButton("list.number", label: "Numbered List", action: actions.setOrderedList)
        case .heading(let level):
            textButton(level.displayTitle, action: { actions.setHeading(level) })
        case .iconButton(let systemName, let label, let action):
            iconButton(systemName, label: label, action: { actions.performCustom(action) })
        case .textButton(let title, let action):
            textButton(title, action: { actions.performCustom(action) })
        }
    }

    // MARK: - Buttons

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        UIKitCommandBarButton(
            label: label,
            content: .icon(systemName),
            action: action
        )
        .frame(width: CommandBarLayout.controlHeight, height: CommandBarLayout.controlHeight)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        UIKitCommandBarButton(
            label: title,
            content: .title(title),
            action: action
        )
        .frame(height: CommandBarLayout.controlHeight)
    }
}

private struct ExpandableCommandBarMenu<Content: View, Label: View>: View, Animatable {
    var alignment: Alignment
    var progress: CGFloat
    var labelSize: CGSize
    var expandedSize: CGSize
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let widthDiff = expandedSize.width - labelSize.width
        let heightDiff = expandedSize.height - labelSize.height
        let resolvedWidth = labelSize.width + widthDiff * contentOpacity
        let resolvedHeight = labelSize.height + heightDiff * contentOpacity

        ZStack(alignment: alignment) {
            content
                .compositingGroup()
                .scaleEffect(contentScale)
                .blur(radius: 14 * blurProgress)
                .opacity(contentOpacity)
                .frame(width: expandedSize.width, height: expandedSize.height)

            label
                .compositingGroup()
                .blur(radius: 14 * blurProgress)
                .opacity(1 - labelOpacity)
                .frame(width: labelSize.width, height: labelSize.height)
        }
        .compositingGroup()
        .frame(width: resolvedWidth, height: resolvedHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .commandBarGlass(.roundedRectangle(cornerRadius))
        .scaleEffect(
            x: 1 - blurProgress * 0.25,
            y: 1 + blurProgress * 0.25,
            anchor: scaleAnchor
        )
        .offset(y: offset * blurProgress)
    }

    private var labelOpacity: CGFloat {
        min(progress / 0.35, 1)
    }

    private var contentOpacity: CGFloat {
        max(progress - 0.35, 0) / 0.65
    }

    private var contentScale: CGFloat {
        guard expandedSize.width > 0, expandedSize.height > 0 else { return 1 }
        let minAspectScale = min(labelSize.width / expandedSize.width, labelSize.height / expandedSize.height)
        return minAspectScale + (1 - minAspectScale) * progress
    }

    private var blurProgress: CGFloat {
        progress > 0.5 ? (1 - progress) / 0.5 : progress / 0.5
    }

    private var offset: CGFloat {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: return -40
        case .top, .topLeading, .topTrailing: return 40
        default: return 0
        }
    }

    private var scaleAnchor: UnitPoint {
        switch alignment {
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}

private enum CommandBarGlassShape {
    case capsule
    case circle
    case roundedRectangle(CGFloat)
}

private extension View {
    @ViewBuilder
    func commandBarGlass(_ shape: CommandBarGlassShape) -> some View {
        if #available(iOS 26.0, *) {
            let glass = Glass.regular
                .tint(Color(.systemBackground).opacity(0.3))
                .interactive()
            switch shape {
            case .capsule:
                self.glassEffect(glass, in: .capsule)
            case .circle:
                self.glassEffect(glass, in: .circle)
            case .roundedRectangle(let cornerRadius):
                self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            switch shape {
            case .capsule:
                self
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                    }
            case .circle:
                self
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                    }
            case .roundedRectangle(let cornerRadius):
                self
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                    }
            }
        }
    }

    @ViewBuilder
    func commandBarScrollEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }

}

private enum CommandBarButtonContent {
    case icon(String)
    case title(String)
}

private struct UIKitCommandBarButton: UIViewRepresentable {
    let label: String
    let content: CommandBarButtonContent
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.tintColor = .label
        button.accessibilityLabel = label
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)

        switch content {
        case .icon(let systemName):
            let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            button.setImage(UIImage(systemName: systemName, withConfiguration: configuration), for: .normal)
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center

        case .title(let title):
            var configuration = UIButton.Configuration.plain()
            configuration.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)])
            )
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
            button.configuration = configuration
        }

        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.accessibilityLabel = label
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleTap() {
            action()
        }
    }
}

// MARK: - Non-stealing hosting controller

/// Prevents the hosting controller from stealing first responder from the text editor.
/// Without this, tapping SwiftUI buttons in the inputAccessoryView causes the UITextView
/// to resign first responder, which corrupts the Lexical editor state.
private class NonStealingHostingController<Content: View>: UIHostingController<Content> {
    override var canBecomeFirstResponder: Bool { false }
    override var canResignFirstResponder: Bool { false }
}

// MARK: - UIView Wrapper

public class MarkdownCommandBar: UIView {
    public weak var editor: (any MarkdownEditorInterface)? {
        didSet { actions.editor = editor }
    }

    private let actions = CommandBarActions()
    private let content: CommandBarContent
    private var _hostingController: NonStealingHostingController<CommandBarContentView>?

    public init(content: CommandBarContent = .default) {
        self.content = content
        super.init(frame: .zero)
        setupContent()
    }

    public override init(frame: CGRect) {
        self.content = .default
        super.init(frame: frame)
        setupContent()
    }

    public required init?(coder: NSCoder) {
        self.content = .default
        super.init(coder: coder)
        setupContent()
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: CommandBarLayout.barHeight)
    }

    private func setupContent() {
        backgroundColor = .clear

        let hc = NonStealingHostingController(rootView: CommandBarContentView(actions: actions, content: content))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        hc.sizingOptions = .intrinsicContentSize

        addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hc.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        _hostingController = hc
    }
}

final class MarkdownCommandBarInputView: UIInputView {
    private static let preferredHeight = MarkdownCommandBar().intrinsicContentSize.height

    weak var editor: (any MarkdownEditorInterface)? {
        didSet { commandBar.editor = editor }
    }

    weak var trackedScrollView: UIScrollView? {
        didSet { updateScrollEdgeInteraction() }
    }

    private let commandBar: MarkdownCommandBar

    init(content: CommandBarContent = .default) {
        self.commandBar = MarkdownCommandBar(content: content)
        // UIKit sizes input accessory views to the keyboard width; the initial
        // frame width is irrelevant (and UIScreen.main is deprecated for it).
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: Self.preferredHeight),
            inputViewStyle: .keyboard
        )
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        commandBar.intrinsicContentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width > 0 ? size.width : bounds.width,
            height: Self.preferredHeight
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollEdgeInteraction()
    }

    private func setupContent() {
        allowsSelfSizing = true
        backgroundColor = .clear
        autoresizesSubviews = true
        autoresizingMask = [.flexibleWidth]

        commandBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(commandBar)
        NSLayoutConstraint.activate([
            commandBar.topAnchor.constraint(equalTo: topAnchor),
            commandBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            commandBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            commandBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            commandBar.heightAnchor.constraint(equalToConstant: commandBar.intrinsicContentSize.height)
        ])
    }

    private func updateScrollEdgeInteraction() {
        guard #available(iOS 26.0, *) else { return }

        for interaction in interactions where interaction is UIScrollEdgeElementContainerInteraction {
            removeInteraction(interaction)
        }

        guard let trackedScrollView else {
            return
        }

        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.edge = .bottom
        interaction.scrollView = trackedScrollView
        addInteraction(interaction)
    }
}
