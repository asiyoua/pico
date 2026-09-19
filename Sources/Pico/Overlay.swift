import AppKit
import SwiftUI

/// Maps the persisted theme choice to concrete colors used by the overlay.
/// 全卡覆盖的透明拖拽层：手动逐事件驱动窗口移动（setFrameOrigin，无系统
/// 边界栏），四向都允许推出屏幕外——卡片拖到哪儿就停在哪儿。头部按钮区
/// 与底边缩放把手在 hitTest 里穿透给下层 SwiftUI 控件；滚轮显式转发给
/// 正文滚动区（否则事件会死在本层）；悬停经 NSTrackingArea 上报，用于
/// 悬停暂停自动隐藏与钉住按钮的浮现。
private struct WindowDragCatcherRepresentable: NSViewRepresentable {
    var onHoverChange: (Bool) -> Void
    var excludesHandle: Bool
    /// 钉住按钮当前是否可见（悬停或已钉住）：可见时头部命中区让位三键
    var pinChipVisible: Bool

    func makeNSView(context: Context) -> WindowDragCatcherView {
        let view = WindowDragCatcherView()
        view.onHoverChange = onHoverChange
        view.excludesHandle = excludesHandle
        view.pinChipVisible = pinChipVisible
        return view
    }

    func updateNSView(_ nsView: WindowDragCatcherView, context: Context) {
        nsView.onHoverChange = onHoverChange
        nsView.excludesHandle = excludesHandle
        nsView.pinChipVisible = pinChipVisible
    }
}

final class WindowDragCatcherView: NSView {
    var onHoverChange: (Bool) -> Void = { _ in }
    var excludesHandle = false
    var pinChipVisible = false
    private var startMouse: CGPoint?
    private var startOrigin: CGPoint?
    private var scrollTarget: NSScrollView?
    private var trackingArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse, let startOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        // 无边界栏：跟随光标增量移动，四向都允许推出屏幕外
        window.setFrameOrigin(
            CGPoint(x: startOrigin.x + (now.x - startMouse.x),
                    y: startOrigin.y + (now.y - startMouse.y)))
    }

    override func mouseUp(with event: NSEvent) {
        startMouse = nil
        startOrigin = nil
    }

    // 面板的 isMovableByWindowBackground 会让窗口服务器接管拖拽并在屏幕
    // 顶缘设栏，拖拽改由本层驱动后必须关闭
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 头部按钮区（复制/关闭/钉住）与底边缩放把手穿透给下层控件
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let width = bounds.width, height = bounds.height
        // 三键（钉住/复制/关闭）都在右上：悬停浮现钉住键后让位 104pt，
        // 平时只让位复制/关闭的 70pt
        let chipsWidth: CGFloat = pinChipVisible ? 104 : 70
        if local.x >= width - chipsWidth, local.y >= height - 36 { return nil }
        if excludesHandle,
            local.x >= width / 2 - 40, local.x <= width / 2 + 40,
            local.y <= 26 {
            return nil
        }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
        DiagnosticLog.write("catcher hover enter")
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
        DiagnosticLog.write("catcher hover exit")
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

    /// Width of the longest line when nothing wraps. Together with the card
    /// width clamp (min 340, max 600) this mirrors how SwiftUI sizes the
    /// card, so wrap counts below match the rendered layout.
    static func textWidth(text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        _ = manager.glyphRange(for: container)
        return ceil(manager.usedRect(for: container).width)
    }

    /// Body-text width the card will actually offer: the card is clamped to
    /// 340...600 and pads 16pt leading + 12pt trailing (keep in sync with the
    /// paddings in `TranslationOverlayView.body`).
    static func measuredContentWidth(text: String, fontSize: CGFloat) -> CGFloat {
        let ideal = textWidth(text: text, fontSize: fontSize)
        let card = min(600, max(340, ideal + 28))
        return card - 28
    }

    /// Pulls a frame fully inside `bounds` (used for auto-placed cards so a
    /// fresh card never spawns partially off-screen, whatever the display).
    /// Pure so the clamp math is unit-testable. User-dragged cards are NOT
    /// clamped — 拖到哪儿就停在哪儿，允许故意推出屏幕外。
    static func clampedIntoVisible(_ frame: NSRect, in bounds: NSRect, margin: CGFloat = 8) -> NSRect {
        let x = min(
            max(frame.minX, bounds.minX + margin),
            max(bounds.minX + margin, bounds.maxX - frame.width - margin))
        let y = min(
            max(frame.minY, bounds.minY + margin),
            max(bounds.minY + margin, bounds.maxY - frame.height - margin))
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

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
    /// 钉住的卡片不自动隐藏，关闭才消失；状态由协调器持有（跨刷新保留）。
    let contentPinned: Bool
    /// Resize bounds for scrollable cards; the coordinator derives them from
    /// the screen so a dragged-out handle stays on display.
    var minBodyHeight: CGFloat = 90
    var maxBodyHeight: CGFloat = .infinity
    let onClose: () -> Void
    let onCopy: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }
    /// Live body-height updates while the user drags the bottom handle.
    var onResize: (CGFloat) -> Void = { _ in }
    /// Called when the handle is released so the coordinator can settle the
    /// panel frame (top edge fixed) after SwiftUI has resized the content.
    var onResizeEnd: (CGFloat) -> Void = { _ in }
    /// 钉住/解除钉住当前卡片。
    var onTogglePin: () -> Void = {}

    @State private var closeHovered = false
    @State private var copyHovered = false
    @State private var copied = false
    @State private var pinHovered = false
    @State private var handleHovered = false
    @State private var handlePressed = false
    /// 卡片是否被鼠标悬停：驱动钉住按钮的浮现
    @State private var cardHovered = false
    /// Body height while the handle is being dragged; nil falls back to the
    /// installed limit (also how double-click restores the default).
    @State private var liveLimit: CGFloat?

    private var effectiveLimit: CGFloat? { liveLimit ?? textHeightLimit }

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PICO")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.accentColor)
                Spacer(minLength: 8)
                Button(action: onTogglePin) {
                    Image(systemName: contentPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            contentPinned ? Color.primary : (pinHovered ? Color.primary : Color.secondary))
                        .frame(width: 22, height: 22)
                        .background(chipBackground(highlighted: pinHovered))
                }
                .buttonStyle(.plain)
                .opacity(cardHovered || contentPinned ? 1 : 0)
                .onHover { pinHovered = $0 }
                .accessibilityLabel(Text("Pin"))
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
        .overlay { WindowDragCatcherRepresentable(
            onHoverChange: { cardHovered = $0 },
            excludesHandle: textHeightLimit != nil,
            pinChipVisible: cardHovered || contentPinned) }
        .overlay(alignment: .bottom) {
            if textHeightLimit != nil { resizeHandle }
        }
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
        let bodyText = MarkdownCardBodyView(
            text: text,
            fontSize: fontSize,
            accentColor: theme.accentColor)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let limit = effectiveLimit {
            ScrollView(.vertical) { bodyText }
                .frame(height: limit)
        } else {
            bodyText
        }
    }

    /// Bottom-edge grabber for scrollable cards: drag to grow/shrink the card
    /// (top edge stays put), double-click to restore the default height.
    private var resizeHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(handleHovered || handlePressed ? 0.75 : 0.35))
            .frame(width: 44, height: 5)
            .padding(.bottom, 3)
            .frame(height: 18)
            .contentShape(Rectangle())
            .onHover { hovering in
                handleHovered = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = liveLimit ?? textHeightLimit ?? 0
                        handlePressed = true
                        let newHeight = min(
                            max(base + value.translation.height, minBodyHeight), maxBodyHeight)
                        if newHeight != liveLimit {
                            liveLimit = newHeight
                            onResize(newHeight)
                        }
                    }
                    .onEnded { _ in
                        handlePressed = false
                        if let liveLimit { onResizeEnd(liveLimit) }
                    }
            )
            .onTapGesture(count: 2) {
                liveLimit = nil
                if let limit = textHeightLimit { onResize(limit) }
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

/// 自由浮窗面板：关闭 AppKit 默认的窗口框架约束——默认实现会把窗口
/// 顶边压回菜单栏/屏幕上缘之下，导致「把卡片往顶上抽出去」永远做不到
/// （左右下三向系统本就不设栏）。四向自由全靠这个覆写。
final class OverlayPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
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
        /// 钉住（不自动隐藏，关闭才消失）；与 isPinned（位置保持）语义不同
        var contentPinned = false
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
    var textSize: OverlayTextSize = .medium {
        didSet {
            // Re-measure: font size changes both the rendered cards and the
            // scroll threshold computed in installContent.
            guard oldValue != textSize else { return }
            for entry in entries { installContent(for: entry) }
            relayout()
        }
    }
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
            entry.panel.contentView = NSHostingView(
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
        if entries.count >= 3 {
            // 挤掉最老的一张；钉住的卡片豁免——全部钉住时才挤最老的钉住卡
            let victim = entries.first(where: { !$0.contentPinned }) ?? entries[0]
            remove(victim.id)
        }
        let target = screen ?? NSScreen.main
        let id = UUID()
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 64), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = false
        // 拖拽由卡片上的 WindowDragCatcher 逐事件驱动（setFrameOrigin，无
        // 系统边界栏，四向都允许推出屏幕外），不用窗口服务器背景拖拽
        panel.isMovableByWindowBackground = false
        // 显式关闭「应用失活即隐藏」（NSPanel 默认依赖平台行为）
        panel.hidesOnDeactivate = false
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
            text: entry.text, fontSize: textSize.points,
            width: OverlaySizing.measuredContentWidth(text: entry.text, fontSize: textSize.points))
        let plan = OverlaySizing.plan(
            naturalCardHeight: naturalText + chrome,
            maxCardHeight: cardHeightLimit(on: entry.screen),
            chromeHeight: chrome)
        entry.textHeightLimit = plan.textHeightLimit
        entry.plannedCardHeight = plan.scrolls ? plan.cardHeight : nil
        entry.panel.contentView = NSHostingView(
            rootView: makeView(text: entry.text, textHeightLimit: entry.textHeightLimit, id: entry.id))
    }

    /// Card height ceiling: roughly 60% of the visible screen so long
    /// translations stay readable instead of spilling past the display edge.
    /// 小屏（13 寸 Air 可视高 ~750pt）按 0.55 阅读区太小，提到 0.6；
    /// 大屏仍受 460 上限约束不受影响。
    private func cardHeightLimit(on screen: NSScreen?) -> CGFloat {
        let visible = screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        return min(460, max(240, visible * 0.6))
    }

    /// Header row + outer padding height, measured once with a zero-height
    /// text area (layout constants, so it never needs invalidation).
    private func chromeHeight() -> CGFloat {
        if let cached = measuredChromeHeight { return cached }
        let host = NSHostingView(
            rootView: TranslationOverlayView(
                text: "Xg", fontSize: 10, theme: theme, surface: surface, textHeightLimit: 0,
                contentPinned: false,
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
        let entry = entries.first(where: { $0.id == id })
        return TranslationOverlayView(
            text: text,
            fontSize: textSize.points,
            theme: theme,
            surface: surface,
            textHeightLimit: textHeightLimit,
            contentPinned: entry?.contentPinned ?? false,
            minBodyHeight: 90,
            maxBodyHeight: max(
                90, (screenForEntry(id)?.visibleFrame.height ?? 900) - 120),
            onClose: { [weak self] in self?.remove(id) },
            onCopy: { [weak self] in
                TranslationClipboard.copy(text)
                self?.onCopyToPasteboard?(text)
            },
            onHoverChange: { [weak self] hovering in
                self?.setHovering(id, hovering)
            },
            onResize: { [weak self] bodyHeight in
                self?.recordResize(of: id, to: bodyHeight)
            },
            onResizeEnd: { [weak self] bodyHeight in
                self?.settleResize(of: id, to: bodyHeight)
            },
            onTogglePin: { [weak self] in
                self?.togglePin(of: id)
            })
    }

    private func screenForEntry(_ id: UUID) -> NSScreen? {
        entries.first(where: { $0.id == id })?.screen ?? NSScreen.main
    }

    /// Bottom-edge resize: grows/shrinks the card with the top edge fixed.
    /// While dragging, SwiftUI grows the hosting view and the window along
    /// with it (the cursor's physical screen limit naturally bounds the
    /// drag), so the coordinator only records state; on release
    /// `settleResize` pins the final frame with the top edge fixed and
    /// marks the card user-placed.
    private func recordResize(of id: UUID, to bodyHeight: CGFloat) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let chrome = chromeHeight()
        entry.textHeightLimit = bodyHeight
        entry.plannedCardHeight = bodyHeight + chrome
        entry.isPinned = true
    }

    /// Pins the final frame with the top edge fixed. The view already clamps
    /// the drag to sane bounds (the cursor physically cannot leave the screen
    /// mid-drag, so the bottom edge stays reachable); settling with the same
    /// value avoids fighting the hosting view's content sizing.
    func settleResize(of id: UUID, to bodyHeight: CGFloat) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let chrome = chromeHeight()
        let clamped = min(max(bodyHeight, 90), 4000)
        entry.textHeightLimit = clamped
        entry.plannedCardHeight = clamped + chrome
        var frame = entry.panel.frame
        frame.origin.y = frame.maxY - (clamped + chrome)
        frame.size.height = clamped + chrome
        isApplyingProgrammaticFrame = true
        entry.panel.setFrame(frame, display: true)
        isApplyingProgrammaticFrame = false
    }

    /// 钉住/解除钉住：钉住的卡片不参与自动隐藏，关闭时才消失。
    /// 切换后重建内容视图，让钉住图标的状态立即反映（否则视图停留在
    /// 创建时的快照，点击无视觉反馈）。
    func togglePin(of id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.contentPinned.toggle()
        if entry.contentPinned {
            entry.hideTask?.cancel()
            DiagnosticLog.write("overlay pinned id=\(id.uuidString.prefix(6))")
        } else {
            scheduleHide(for: entry)
            DiagnosticLog.write("overlay unpinned id=\(id.uuidString.prefix(6))")
        }
        installContent(for: entry)
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

    /// 判定光标是否压在卡片上（scheduleHide 的豁免条件）；测试可注入固定值。
    var cursorOverCard: (NSRect) -> Bool = { frame in frame.contains(NSEvent.mouseLocation) }

    private func scheduleHide(for entry: Entry) {
        // 钉住的卡片不参与自动隐藏，关闭时才消失
        guard !entry.contentPinned else { return }
        // 光标正压在卡片上时不启动隐藏计时——卡片弹出时光标可能本来就在
        // 卡片位置，此时没有 mouseEntered 边界事件，悬停暂停只能靠这里兜住
        if cursorOverCard(entry.panel.frame) {
            DiagnosticLog.write("auto-hide skipped: cursor over card")
            return
        }
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
