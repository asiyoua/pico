import AppKit
import XCTest
@testable import Pico

/// Drives the real overlay panels through AppKit layout so the height cap and
/// the hover-pause behavior are verified against actual fitting sizes, not
/// just the pure planning function.
@MainActor
final class OverlayCoordinatorRenderingTests: XCTestCase {
    private var coordinator: OverlayCoordinator!

    override func setUp() async throws {
        _ = NSApplication.shared
        coordinator = OverlayCoordinator()
        coordinator.textSize = .medium
    }

    override func tearDown() async throws {
        coordinator.hide()
    }

    private static func longChineseText(lines: Int = 120) -> String {
        (1...lines).map { "第\($0)句，这是一段用于验证浮窗高度上限的中文长文本，翻译后应当变成一段更长的英文并且只在卡片内部滚动。" }
            .joined(separator: " ")
    }

    func testShortCardKeepsNaturalHeight() {
        coordinator.neverHide = true
        coordinator.show("Hello world, this is fine.", on: NSScreen.main)
        let frames = coordinator.visiblePanelFrames
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        XCTAssertLessThanOrEqual(frame.width, 600)
        XCTAssertGreaterThanOrEqual(frame.width, 340)
        XCTAssertLessThan(frame.height, 200)
    }

    func testLongCardClampsToBudgetAndFitsOnScreen() throws {
        coordinator.neverHide = true
        let screen = try XCTUnwrap(NSScreen.main)
        coordinator.show(Self.longChineseText(), on: screen)
        let frames = coordinator.visiblePanelFrames
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        let expected = min(460, max(240, screen.visibleFrame.height * 0.55))
        XCTAssertEqual(frame.height, expected, accuracy: 2)
        XCTAssertLessThanOrEqual(frame.width, 600)
        // The card must sit fully inside the visible screen.
        XCTAssertTrue(screen.visibleFrame.contains(frame), "\(frame) vs \(screen.visibleFrame)")
    }

    func testRefreshedLongCardStaysClamped() throws {
        coordinator.neverHide = true
        let key = "test-key"
        coordinator.show(Self.longChineseText(lines: 40), key: key, on: NSScreen.main)
        coordinator.show(Self.longChineseText(lines: 200), key: key, on: NSScreen.main)
        let frames = coordinator.visiblePanelFrames
        XCTAssertEqual(frames.count, 1)
        let screen = try XCTUnwrap(NSScreen.main)
        let expected = min(460, max(240, screen.visibleFrame.height * 0.55))
        XCTAssertEqual(frames[0].height, expected, accuracy: 2)
    }

    func testHoverPausesAutoHideUntilCursorLeaves() async throws {
        // 不依赖真实光标位置
        coordinator.cursorOverCard = { _ in false }
        coordinator.hideAfter = 0.5
        coordinator.show(Self.longChineseText(), key: "hover-key", on: NSScreen.main)
        let id = try XCTUnwrap(coordinator.shownEntryIDs.first)
        try await Task.sleep(for: .milliseconds(250))
        coordinator.setHovering(id, true)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(coordinator.shownEntryIDs.count, 1, "hovering must pause the hide timer")
        coordinator.setHovering(id, false)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(coordinator.shownEntryIDs.isEmpty, "leaving the card should resume auto-hide")
    }

    /// 鼠标悬停必须「经视图接线」才到得了协调器（tracking area → catcher →
    /// 视图 onHoverChange → setHovering）。直接调 setHovering 的测试测不到
    /// 断线：2026-09-20 拖拽层重构丢失转发后单测全绿、真机卡片照样消失，
    /// 本用例从 catcher 回调入口驱动，把接线本身钉进测试。
    func testCatcherHoverForwardingPausesAutoHide() async throws {
        coordinator.cursorOverCard = { _ in false }
        coordinator.hideAfter = 0.4
        coordinator.show(Self.longChineseText(), key: "wire-key", on: NSScreen.main)
        let catcher = try XCTUnwrap(findCatcher(), "卡片内容里必须找得到 WindowDragCatcherView")

        catcher.onHoverChange(true)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(coordinator.shownEntryIDs.count, 1, "catcher 悬停事件必须经视图转发暂停自动隐藏")

        catcher.onHoverChange(false)
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertTrue(coordinator.shownEntryIDs.isEmpty, "catcher 移开事件必须经视图转发恢复自动隐藏")
    }

    private func findCatcher() -> WindowDragCatcherView? {
        var queue: [NSView] = coordinator.panelContentViews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let catcher = view as? WindowDragCatcherView { return catcher }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    func testAutoHideStillFiresWithoutHover() async throws {
        // 不依赖真实光标位置
        coordinator.cursorOverCard = { _ in false }
        coordinator.hideAfter = 0.5
        coordinator.show(Self.longChineseText(), key: "plain-key", on: NSScreen.main)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(coordinator.shownEntryIDs.isEmpty)
    }

    func testCursorOverCardAtBirthSuppressesAutoHide() async throws {
        // 光标压在卡片上时（卡片可能正好弹出在光标位置），隐藏计时豁免
        coordinator.cursorOverCard = { _ in true }
        coordinator.hideAfter = 0.3
        coordinator.show(Self.longChineseText(), key: "under-cursor", on: NSScreen.main)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.shownEntryIDs.count, 1, "光标压卡时不得自动隐藏")
    }

    func testResizeGrowsCardWithTopEdgeFixed() throws {
        coordinator.neverHide = true
        let screen = try XCTUnwrap(NSScreen.main)
        coordinator.show(Self.longChineseText(), key: "rz", on: screen)
        let id = try XCTUnwrap(coordinator.shownEntryIDs.first)
        let before = try XCTUnwrap(coordinator.visiblePanelFrames.first)
        coordinator.settleResize(of: id, to: 620)
        let after = try XCTUnwrap(coordinator.visiblePanelFrames.first)
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertEqual(after.maxY, before.maxY, accuracy: 2, "top edge must stay fixed")
    }

    func testResizeShrinksAndClampsToMinimum() throws {
        coordinator.neverHide = true
        coordinator.show(Self.longChineseText(), key: "rz2", on: NSScreen.main)
        let id = try XCTUnwrap(coordinator.shownEntryIDs.first)
        coordinator.settleResize(of: id, to: 10)
        let after = try XCTUnwrap(coordinator.visiblePanelFrames.first)
        XCTAssertGreaterThanOrEqual(after.height, 90)
        // Sanity cap for non-UI callers; the drag handle clamps earlier.
        coordinator.settleResize(of: id, to: 99_999)
        let maxed = try XCTUnwrap(coordinator.visiblePanelFrames.first)
        XCTAssertLessThanOrEqual(maxed.height, 4000 + 51 + 2)
    }
}
