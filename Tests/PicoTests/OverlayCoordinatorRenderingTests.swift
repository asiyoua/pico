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

    func testAutoHideStillFiresWithoutHover() async throws {
        coordinator.hideAfter = 0.5
        coordinator.show(Self.longChineseText(), key: "plain-key", on: NSScreen.main)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(coordinator.shownEntryIDs.isEmpty)
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
