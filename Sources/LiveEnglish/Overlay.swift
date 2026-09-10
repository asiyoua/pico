import AppKit
import SwiftUI

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

struct TranslationOverlayView: View {
    let text: String
    let fontSize: CGFloat
    let theme: OverlayTheme
    let surface: OverlaySurfaceEffect
    let onClose: () -> Void
    let onCopy: () -> Void
    let dragOrigin: () -> CGPoint
    let onDrag: (CGPoint) -> Void

    @State private var dragStartOrigin: CGPoint?
    @State private var closeHovered = false
    @State private var copyHovered = false
    @State private var copied = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.accentColor.opacity(0.85))
                .frame(width: 3)
                .padding(.leading, 14)
                .padding(.vertical, 15)
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 14)
            HStack(spacing: 6) {
                Button(action: copyTapped) {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            copied ? theme.accentColor : (copyHovered ? Color.primary : Color.secondary))
                }
                .buttonStyle(.plain)
                .onHover { copyHovered = $0 }
                .accessibilityLabel(Text("Copy"))
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(closeHovered ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .accessibilityLabel(Text("Close"))
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .frame(minWidth: 340, maxWidth: 600)
        .background {
            surfaceShape
                .overlay {
                    if theme != .system {
                        shape.fill(theme.accentColor.opacity(0.10))
                    }
                }
                .overlay { shape.stroke(Color.primary.opacity(0.12), lineWidth: 1) }
        }
        // The whole card is a move handle; the buttons above still win for
        // plain clicks because a click never starts a drag.
        .contentShape(shape)
        .gesture(moveGesture)
    }

    @ViewBuilder private var surfaceShape: some View {
        switch surface {
        case .frost: shape.fill(.regularMaterial)
        case .glass: shape.fill(.ultraThinMaterial)
        case .thick: shape.fill(.thickMaterial)
        case .solid: shape.fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartOrigin == nil { dragStartOrigin = dragOrigin() }
                let origin = dragStartOrigin ?? .zero
                onDrag(
                    CGPoint(
                        x: origin.x + value.translation.width,
                        y: origin.y - value.translation.height))
            }
            .onEnded { _ in dragStartOrigin = nil }
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
        weak var screen: NSScreen?
        var avoid: NSRect?
        var slot: OverlayPosition?
        var isPinned = false
        var usesAnchor = false
        var hideTask: Task<Void, Never>?
        init(id: UUID, key: String, panel: NSPanel, screen: NSScreen?, avoid: NSRect?, text: String) {
            self.id = id
            self.key = key
            self.panel = panel
            self.screen = screen
            self.avoid = avoid
            self.text = text
        }
    }

    private var entries: [Entry] = []
    /// Top-left corner the next fresh overlay should use. Set when the user
    /// drags a panel; cleared when the configured position changes.
    private var anchor: CGPoint?
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
            entry.panel.contentView = NSHostingView(
                rootView: makeView(text: entry.text, id: entry.id, panel: entry.panel))
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
            existing.panel.contentView = NSHostingView(
                rootView: makeView(text: text, id: existing.id, panel: existing.panel))
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
        panel.alphaValue = CGFloat(min(max(cardOpacity, 0.3), 1))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: makeView(text: text, id: id, panel: panel))
        let entry = Entry(id: id, key: key, panel: panel, screen: target, avoid: avoid, text: text)
        entries.append(entry)
        relayout()
        panel.orderFrontRegardless()
        scheduleHide(for: entry)
    }

    private func makeView(text: String, id: UUID, panel: NSPanel) -> TranslationOverlayView {
        TranslationOverlayView(
            text: text,
            fontSize: textSize.points,
            theme: theme,
            surface: surface,
            onClose: { [weak self] in self?.remove(id) },
            onCopy: { [weak self] in
                TranslationClipboard.copy(text)
                self?.onCopyToPasteboard?(text)
            },
            dragOrigin: { [weak panel] in panel?.frame.origin ?? .zero },
            onDrag: { [weak self, weak panel] newOrigin in
                guard let panel else { return }
                panel.setFrameOrigin(newOrigin)
                self?.pin(id, topLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
            })
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
            entry.panel.orderOut(nil)
        }
        entries.removeAll()
    }
    private func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.hideTask?.cancel()
        entry.panel.orderOut(nil)
        // Relayout each remaining panel on its own screen so closing one
        // overlay on a secondary display does not move the others to the main
        // screen.
        relayout()
    }
    private func relayout() {
        var stackIndex = 0
        for entry in entries {
            entry.panel.contentView?.layoutSubtreeIfNeeded()
            let size = entry.panel.contentView?.fittingSize ?? entry.panel.frame.size
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
