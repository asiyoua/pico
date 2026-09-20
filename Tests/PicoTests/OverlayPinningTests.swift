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

    /// 数量上限只管未钉住的临时卡：堆叠模式第 4 条未钉复制顶掉最老的未钉卡。
    func testUnpinnedCapEvictsOldestUnpinned() {
        let coordinator = OverlayCoordinator()
        coordinator.neverHide = true
        coordinator.show("甲", key: "a", on: NSScreen.main)
        coordinator.show("乙", key: "b", on: NSScreen.main)
        coordinator.show("丙", key: "c", on: NSScreen.main)
        let oldestID = coordinator.shownEntryIDs.first
        coordinator.show("丁", key: "d", on: NSScreen.main)

        XCTAssertEqual(coordinator.shownEntryIDs.count, 3)
        XCTAssertFalse(coordinator.shownEntryIDs.contains(oldestID!), "最老的未钉卡被顶掉")
    }

    /// 钉住的卡不设数量上限、永不自动移除：全钉之后继续复制，
    /// 既不挤钉住卡（旧逻辑在全部钉住时会挤最老钉住卡），新卡照常出现。
    func testPinnedCardsHaveNoCountCap() {
        let coordinator = OverlayCoordinator()
        coordinator.neverHide = true
        coordinator.show("甲", key: "a", on: NSScreen.main)
        coordinator.show("乙", key: "b", on: NSScreen.main)
        coordinator.show("丙", key: "c", on: NSScreen.main)
        let pinnedIDs = coordinator.shownEntryIDs
        for id in pinnedIDs { coordinator.togglePin(of: id) }

        coordinator.show("丁", key: "d", on: NSScreen.main)
        coordinator.show("戊", key: "e", on: NSScreen.main)

        for id in pinnedIDs {
            XCTAssertTrue(coordinator.shownEntryIDs.contains(id), "钉住的卡片不得被自动移除")
        }
        XCTAssertEqual(coordinator.shownEntryIDs.count, 5, "钉住不设上限，新卡照常并存")
    }

    /// 钉住卡不计入未钉上限：1 张钉住 + 4 条复制 = 1 钉 + 3 未钉在屏，
    /// 顶掉的只是最老的未钉卡。
    func testPinnedCardNotCountedTowardUnpinnedCap() {
        let coordinator = OverlayCoordinator()
        coordinator.neverHide = true
        coordinator.show("钉住", key: "p", on: NSScreen.main)
        let pinnedID = coordinator.shownEntryIDs[0]
        coordinator.togglePin(of: pinnedID)
        coordinator.show("乙", key: "b", on: NSScreen.main)
        coordinator.show("丙", key: "c", on: NSScreen.main)
        let oldestUnpinned = coordinator.shownEntryIDs[1]
        coordinator.show("丁", key: "d", on: NSScreen.main)
        coordinator.show("戊", key: "e", on: NSScreen.main)

        XCTAssertTrue(coordinator.shownEntryIDs.contains(pinnedID), "钉住的卡片必须豁免挤占")
        XCTAssertFalse(coordinator.shownEntryIDs.contains(oldestUnpinned), "最老的未钉卡被顶掉")
        XCTAssertEqual(coordinator.shownEntryIDs.count, 4)
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
