import AppKit
import SwiftUI

/// Hosting view that keeps window-server background dragging alive even when
/// the hit test lands on interactive SwiftUI bridges (a scroll view's bridge
/// opts out and would otherwise swallow the drag).
final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Transparent layer over the scrollable text: pressing it starts a native
/// window drag (`performDrag` rides the same window-server path as
/// isMovableByWindowBackground, so the drag stays 1:1). Scroll-wheel events
/// are routed explicitly to the enclosing NSScrollView (SwiftUI's ScrollView
/// bridge) because they would otherwise die in this layer. The card's buttons
/// live outside the scroll area so they behave as before.
private struct WindowDragCatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> DragCatcherView { DragCatcherView() }
    func updateNSView(_ nsView: DragCatcherView, context: Context) {}

    final class DragCatcherView: NSView {
        private var scrollTarget: NSScrollView?

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scrollTarget = nil
        }

        override func scrollWheel(with event: NSEvent) {
            if scrollTarget == nil {
                // SwiftUI hoists .overlay views beside the scroll view under
                // the hosting view, so the NSScrollView bridge is a sibling
                // subtree, never an ancestor — search the whole tree.
                var root: NSView? = superview
                while let parent = root?.superview { root = parent }
                var queue: [NSView] = root.map { [$0] } ?? []
                while !queue.isEmpty, scrollTarget == nil {
                    let view = queue.removeFirst()
                    if let scroll = view as? NSScrollView {
                        scrollTarget = scroll
                    } else {
                        queue.append(contentsOf: view.subviews)
                    }
                }
            }
            if let scrollTarget {
                scrollTarget.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}

/// Maps the persisted theme choice to concrete colors used by the overlay.
extension OverlayTheme {
    var accentColor: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return Color(red: 0.05, green: 0.45, blue: 0.95)
        case .green: return Color(red: 0.10, green: 0.65, blue: 0.35)
        case .purple: return Color(red: 0.55, green: 0.35, blue: 0.90)
        case .orange: return Color(red: 0.95, green: 0.50, blue: 0.15)
        case .pink: return Color(red: 0.90, green: 0.30, blue: 0.55)
        }
    }
}

/// Decides whether a translation card fits on screen or needs to scroll.
/// Pure so the threshold policy is unit-testable.
enum OverlaySizing {
    struct Plan: Equatable {
        let scrolls: Bool
        let textHeightLimit: CGFloat?
        let cardHeight: CGFloat
    }

    /// Roughly the widest wrap width a card offers its body text: 600pt card
    /// minus leading/trailing padding and a scrollbar allowance.
    static let measuredTextWidth: CGFloat = 560

    /// Exact wrapped text height via TextKit — deterministic regardless of
    /// window state (NSHostingView.fittingSize collapses for scrollable or
    /// unattached content). A few points of drift against SwiftUI's line
    /// layout only matters at the scroll threshold, where either choice is
    /// acceptable.
    static func textHeight(text: String, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        _ = manager.glyphRange(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    static func plan(naturalCardHeight: CGFloat, maxCardHeight: CGFloat, chromeHeight: CGFloat) -> Plan {
        guard naturalCardHeight > maxCardHeight, maxCardHeight > chromeHeight + 60 else {
            return Plan(scrolls: false, textHeightLimit: nil, cardHeight: naturalCardHeight)
        }
        return Plan(
            scrolls: true, textHeightLimit: maxCardHeight - chromeHeight, cardHeight: maxCardHeight)
    }
}

struct TranslationOverlayView: View {
    let text: String
    let fontSize: CGFloat
    let theme: OverlayTheme
    let surface: OverlaySurfaceEffect
    /// When set, body text scrolls inside this fixed height instead of growing
    /// the card without bound (long clipboard translations).
    let textHeightLimit: CGFloat?
    let onClose: () -> Void
    let onCopy: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var closeHovered = false
    @State private var copyHovered = false
    @State private var copied = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PICO")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.accentColor)
                Spacer(minLength: 8)
                Button(action: copyTapped) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            copied ? theme.accentColor : (copyHovered ? Color.primary : Color.secondary))
                        .frame(width: 22, height: 22)
                        .background(chipBackground(highlighted: copyHovered || copied))
                }
                .buttonStyle(.plain)
                .onHover { copyHovered = $0 }
                .accessibilityLabel(Text("Copy"))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(closeHovered ? Color.primary : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(chipBackground(highlighted: closeHovered))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .accessibilityLabel(Text("Close"))
            }
            textBody
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .padding(.bottom, 13)
        .frame(minWidth: 340, maxWidth: 600)
        .onHover { onHoverChange($0) }
        .background { WindowDragCatcher() }
        .background {
            surfaceShape
                .overlay {
                    if theme != .system {
                        shape.fill(theme.accentColor.opacity(0.10))
                    }
                }
                .overlay { shape.stroke(theme.accentColor.opacity(0.35), lineWidth: 1) }
        }
        // The whole card is a move handle; window dragging is driven by the
        // window server via isMovableByWindowBackground (set on the panel), so
        // buttons above still win for plain clicks.
    }

    @ViewBuilder private var textBody: some View {
        let bodyText = Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let limit = textHeightLimit {
            ScrollView(.vertical) { bodyText }
                .overlay { WindowDragCatcher() }
                .frame(height: limit)
        } else {
            bodyText
                .overlay { WindowDragCatcher() }
        }
    }

    private func chipBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(highlighted ? 0.09 : 0.05))
    }

    @ViewBuilder private var surfaceShape: some View {
        switch surface {
        case .frost: shape.fill(.regularMaterial)
        case .glass: shape.fill(.ultraThinMaterial)
        case .thick: shape.fill(.thickMaterial)
        case .solid: shape.fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func copyTapped() {
        onCopy()
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

@MainActor final class OverlayCoordinator {
    private final class Entry {
        let id: UUID
        let key: String
        let panel: NSPanel
        var text: String
        var textHeightLimit: CGFloat?
        /// Set when the card scrolls: the panel height is a fixed budget
        /// instead of the (collapsed) fitting size of a scroll view.
        var plannedCardHeight: CGFloat?
        weak var screen: NSScreen?
        var avoid: NSRect?
        var slot: OverlayPosition?
        var isPinned = false
        var usesAnchor = false
        var hideTask: Task<Void, Never>?
        /// Lets us detach the didMove observer when the entry goes away.
        var moveObserver: NSObjectProtocol?
        init(id: UUID, key: String, panel: NSPanel, screen: NSScreen?, avoid: NSRect?, text: String) {
            self.id = id
            self.key = key
            self.panel = panel
            self.screen = screen
            self.avoid = avoid
            self.text = text
        }
    }

    /// Debug/diagnostic hook: frames of the panels currently on screen.
    var visiblePanelFrames: [NSRect] { entries.map { $0.panel.frame } }
    /// Debug/diagnostic hook: ids of the entries currently on screen.
    var shownEntryIDs: [UUID] { entries.map(\.id) }

    private var entries: [Entry] = []
    /// Top-left corner the next fresh overlay should use. Set when the user
    /// drags a panel; cleared when the configured position changes.
    private var anchor: CGPoint?
    /// True while we move panels ourselves (placement/relayout); didMove
    /// notifications arriving outside these windows are user drags.
    private var isApplyingProgrammaticFrame = false
    var hideAfter: Double = 4
    var neverHide = false
    var textSize: OverlayTextSize = .medium
    /// Whole-window transparency applied via panel alpha so slider changes
    /// update live panels without rebuilding views.
    var cardOpacity: Double = 1 {
        didSet {
            let value = CGFloat(min(max(cardOpacity, 0.3), 1))
            entries.forEach { $0.panel.alphaValue = value }
        }
    }
    var theme: OverlayTheme = .system {
        didSet {
            if oldValue != theme { refreshAppearance() }
        }
    }
    var surface: OverlaySurfaceEffect = .frost {
        didSet {
            if oldValue != surface { refreshAppearance() }
        }
    }
    var position: OverlayPosition = .bottomCenter {
        didSet {
            if oldValue != position { anchor = nil }
        }
    }
    var edgeDistance: Double = 48
    var behavior: OverlayBehavior = .stack
    /// Invoked after the overlay's copy button writes text to the pasteboard,
    /// so the owner can resync its clipboard watcher and avoid a feedback loop.
    var onCopyToPasteboard: ((String) -> Void)?
    /// Recreates every panel's content so theme/surface changes apply to
    /// overlays that are already on screen.
    func refreshAppearance() {
        for entry in entries {
            entry.panel.contentView = MovableHostingView(
                rootView: makeView(text: entry.text, textHeightLimit: entry.textHeightLimit, id: entry.id))
        }
        relayout()
    }
    func show(_ text: String, on screen: NSScreen?) { show(text, key: UUID().uuidString, on: screen) }
    func show(_ text: String, key: String, on screen: NSScreen?, avoid: NSRect? = nil) {
        guard !text.isEmpty else {
            hide()
            return
        }
        if let existing = entries.first(where: { $0.key == key }) {
            existing.text = text
            existing.screen = screen ?? existing.screen ?? NSScreen.main
            existing.avoid = avoid
            installContent(for: existing)
            // Restart the auto-hide timer so a refreshed sentence gets the
            // full display duration instead of vanishing on the old schedule.
            scheduleHide(for: existing)
            relayout()
            return
        }
        if behavior == .replace { hide() }
        if entries.count >= 3 { remove(entries[0].id) }
        let target = screen ?? NSScreen.main
        let id = UUID()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 64), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = false
        // Window-server-driven dragging: the move tracks the cursor 1:1
        // without a per-event round trip through the main thread.
        panel.isMovableByWindowBackground = true
        panel.alphaValue = CGFloat(min(max(cardOpacity, 0.3), 1))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let entry = Entry(id: id, key: key, panel: panel, screen: target, avoid: avoid, text: text)
        entry.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let self, let panel, !self.isApplyingProgrammaticFrame else { return }
            self.pin(id, topLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
        }
        entries.append(entry)
        installContent(for: entry)
        relayout()
        isApplyingProgrammaticFrame = true
        panel.orderFrontRegardless()
        isApplyingProgrammaticFrame = false
        scheduleHide(for: entry)
    }

    /// Sizes the card for the current text (scrolling when it would exceed the
    /// screen budget) and installs it as the panel's content.
    private func installContent(for entry: Entry) {
        let chrome = chromeHeight()
        let naturalText = OverlaySizing.textHeight(
            text: entry.text, fontSize: textSize.points, width: OverlaySizing.measuredTextWidth)
        let plan = OverlaySizing.plan(
            naturalCardHeight: naturalText + chrome,
            maxCardHeight: cardHeightLimit(on: entry.screen),
            chromeHeight: chrome)
        entry.textHeightLimit = plan.textHeightLimit
        entry.plannedCardHeight = plan.scrolls ? plan.cardHeight : nil
        entry.panel.contentView = MovableHostingView(
            rootView: makeView(text: entry.text, textHeightLimit: entry.textHeightLimit, id: entry.id))
    }

    /// Card height ceiling: roughly half the screen so long translations stay
    /// readable instead of spilling past the display edge.
    private func cardHeightLimit(on screen: NSScreen?) -> CGFloat {
        let visible = screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        return min(460, max(240, visible * 0.55))
    }

    /// Header row + outer padding height, measured once with a zero-height
    /// text area (layout constants, so it never needs invalidation).
    private func chromeHeight() -> CGFloat {
        if let cached = measuredChromeHeight { return cached }
        let host = MovableHostingView(
            rootView: TranslationOverlayView(
                text: "Xg", fontSize: 10, theme: theme, surface: surface, textHeightLimit: 0,
                onClose: {}, onCopy: {}, onHoverChange: { _ in }))
        measurePanel.contentView = host
        host.layoutSubtreeIfNeeded()
        measuredChromeHeight = host.fittingSize.height
        measurePanel.contentView = nil
        return measuredChromeHeight ?? 64
    }
    private var measuredChromeHeight: CGFloat?

    private var measurePanel: NSPanel {
        if let panel = measurePanelStorage { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: -20000, y: -20000, width: 600, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
        measurePanelStorage = panel
        return panel
    }
    private var measurePanelStorage: NSPanel?

    private func makeView(text: String, textHeightLimit: CGFloat?, id: UUID) -> TranslationOverlayView {
        TranslationOverlayView(
            text: text,
            fontSize: textSize.points,
            theme: theme,
            surface: surface,
            textHeightLimit: textHeightLimit,
            onClose: { [weak self] in self?.remove(id) },
            onCopy: { [weak self] in
                TranslationClipboard.copy(text)
                self?.onCopyToPasteboard?(text)
            },
            onHoverChange: { [weak self] hovering in
                self?.setHovering(id, hovering)
            })
    }

    /// Pauses auto-hide while the cursor rests on the card so long
    /// translations can be read (and scrolled) at leisure.
    func setHovering(_ id: UUID, _ hovering: Bool) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        if hovering {
            entry.hideTask?.cancel()
        } else {
            scheduleHide(for: entry)
        }
    }

    /// Remembers a user-dragged panel and adopts its position as the spot for
    /// future overlays, so moving one out of the way keeps later ones clear.
    private func pin(_ id: UUID, topLeft: CGPoint) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.isPinned = true
        anchor = topLeft
    }

    private func scheduleHide(for entry: Entry) {
        entry.hideTask?.cancel()
        guard !neverHide else { return }
        let seconds = hideAfter
        entry.hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.remove(entry.id)
        }
    }
    func hide() {
        for entry in entries {
            entry.hideTask?.cancel()
            if let observer = entry.moveObserver { NotificationCenter.default.removeObserver(observer) }
            entry.panel.orderOut(nil)
        }
        entries.removeAll()
    }
    private func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.hideTask?.cancel()
        if let observer = entry.moveObserver { NotificationCenter.default.removeObserver(observer) }
        entry.panel.orderOut(nil)
        // Relayout each remaining panel on its own screen so closing one
        // overlay on a secondary display does not move the others to the main
        // screen.
        relayout()
    }
    private func relayout() {
        isApplyingProgrammaticFrame = true
        defer { isApplyingProgrammaticFrame = false }
        var stackIndex = 0
        for entry in entries {
            entry.panel.contentView?.layoutSubtreeIfNeeded()
            let fitting = entry.panel.contentView?.fittingSize ?? entry.panel.frame.size
            // A scrolling card's fitting height collapses to the scroll view's
            // ideal; the planned budget is the real panel height there.
            let size = NSSize(
                width: fitting.width,
                height: entry.plannedCardHeight ?? fitting.height)
            if entry.isPinned {
                // Keep the user-chosen top-left corner; only grow downward if
                // the refreshed text needs a different height.
                let old = entry.panel.frame
                entry.panel.setFrame(
                    NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height),
                    display: true)
                continue
            }
            if let anchor, entry.usesAnchor || (entry.slot == nil && stackIndex == 0) {
                entry.usesAnchor = true
                entry.panel.setFrame(
                    Self.anchoredFrame(size: size, topLeft: anchor, on: entry.screen), display: true)
                stackIndex += 1
                continue
            }
            if entry.slot == nil {
                entry.slot = resolveSlot(size: size, avoid: entry.avoid, screen: entry.screen, stackIndex: stackIndex)
            }
            entry.panel.setFrame(
                position(for: size, on: entry.screen, slot: entry.slot ?? position, stackIndex: stackIndex),
                display: true)
            stackIndex += 1
        }
    }

    /// Picks the first placement that does not cover the focused text field,
    /// preferring the user's configured position.
    private func resolveSlot(size: NSSize, avoid: NSRect?, screen: NSScreen?, stackIndex: Int) -> OverlayPosition {
        guard let avoid, avoid != .zero else { return position }
        let keepOut = avoid.insetBy(dx: -6, dy: -6)
        var candidates: [OverlayPosition] = [position]
        candidates.append(contentsOf: OverlayPosition.allCases.filter { $0 != position })
        for candidate in candidates {
            let frame = position(for: size, on: screen, slot: candidate, stackIndex: stackIndex)
            if !frame.intersects(keepOut) { return candidate }
        }
        return position
    }

    private static func anchoredFrame(size: NSSize, topLeft: CGPoint, on screen: NSScreen?) -> NSRect {
        let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let x = min(max(topLeft.x, bounds.minX + margin), max(bounds.minX + margin, bounds.maxX - size.width - margin))
        let y = min(
            max(topLeft.y - size.height, bounds.minY + margin),
            max(bounds.minY + margin, bounds.maxY - size.height - margin))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
    private func position(for size: NSSize, on screen: NSScreen?, slot: OverlayPosition, stackIndex: Int) -> NSRect {
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let distance = CGFloat(max(0, edgeDistance))
        let offset = CGFloat(stackIndex) * (size.height + 10)
        switch slot {
        case .topRight:
            return NSRect(
                x: frame.maxX - size.width - distance, y: frame.maxY - size.height - distance - offset,
                width: size.width, height: size.height)
        case .bottomRight:
            return NSRect(
                x: frame.maxX - size.width - distance, y: frame.minY + distance + offset, width: size.width,
                height: size.height)
        case .bottomCenter:
            return NSRect(
                x: frame.midX - size.width / 2, y: frame.minY + distance + offset, width: size.width,
                height: size.height)
        }
    }
}
