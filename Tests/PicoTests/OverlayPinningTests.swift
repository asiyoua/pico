import XCTest

@testable import Pico

@MainActor
final class OverlayPinningTests: XCTestCase {
    func testPinnedCardSurvivesAutoHide() throws {
        let coordinator = OverlayCoordinator()
        coordinator.neverHide = false
        coordinator.hideAfter = 0.1
        coordinator.show("钉住的长文本", key: "pin-a", on: NSScreen.main)
        let id = try XCTUnwrap(coordinator.shownEntryIDs.first)
        coordinator.togglePin(of: id)

        let waited = expectation(description: "wait past auto-hide")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waited.fulfill() }
        wait(for: [waited], timeout: 2)

        XCTAssertEqual(coordinator.shownEntryIDs, [id], "钉住的卡片不得自动隐藏")
    }

    func testUnpinnedCardAutoHides() async throws {
        let coordinator = OverlayCoordinator()
        coordinator.neverHide = false
        coordinator.hideAfter = 0.1
        coordinator.show("未钉住的卡片", key: "pin-b", on: NSScreen.main)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(coordinator.shownEntryIDs.isEmpty, "未钉住的卡片按隐藏时长消失")
    }

    func testEvictionPrefersNonPinnedCards() {
        let coordinator = OverlayCoordinator()
        coordinator.show("甲", key: "a", on: NSScreen.main)
        coordinator.show("乙", key: "b", on: NSScreen.main)
        let pinnedID = coordinator.shownEntryIDs[0]
        coordinator.togglePin(of: pinnedID)
        coordinator.show("丙", key: "c", on: NSScreen.main)
        coordinator.show("丁", key: "d", on: NSScreen.main)

        // 第 4 张挤掉未钉住的「乙」，钉住的「甲」豁免
        XCTAssertEqual(coordinator.shownEntryIDs.count, 3)
        XCTAssertFalse(coordinator.shownEntryIDs.isEmpty)
        XCTAssertTrue(coordinator.shownEntryIDs.contains(pinnedID), "钉住的卡片必须豁免挤占")
    }

    /// 钉住语义=只随显式关闭消失：会话清空（切窗口触发 reset→onEmpty）、
    /// replace 换卡、空文本 show 等「非用户点名关闭」都必须豁免钉住卡。
    /// 回归背景：切窗口曾把钉住的卡一起 hide() 干掉（用户 2026-09-20 报）。
    func testHideUnpinnedSparesPinnedCards() {
        let coordinator = OverlayCoordinator()
        coordinator.show("甲", key: "a", on: NSScreen.main)
        coordinator.show("乙", key: "b", on: NSScreen.main)
        let pinnedID = coordinator.shownEntryIDs[0]
        coordinator.togglePin(of: pinnedID)

        coordinator.hideUnpinned()

        XCTAssertEqual(coordinator.shownEntryIDs, [pinnedID], "hideUnpinned 必须保留钉住的卡片")
    }

    func testReplaceModeSparesPinnedCards() throws {
        let coordinator = OverlayCoordinator()
        coordinator.behavior = .replace
        coordinator.neverHide = true
        coordinator.show("钉住的旧卡", key: "pinned", on: NSScreen.main)
        let pinnedID = try XCTUnwrap(coordinator.shownEntryIDs.first)
        coordinator.togglePin(of: pinnedID)

        coordinator.show("新卡", key: "new", on: NSScreen.main)

        XCTAssertTrue(coordinator.shownEntryIDs.contains(pinnedID), "replace 不得顶掉钉住的卡片")
        XCTAssertEqual(coordinator.shownEntryIDs.count, 2, "replace 模式下新卡与钉住卡并存")
    }
}
