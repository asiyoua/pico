import XCTest
@testable import Pico

final class OverlaySizingTests: XCTestCase {
    private let chrome: CGFloat = 51

    func testShortTextKeepsNaturalHeightWithoutScrolling() {
        let plan = OverlaySizing.plan(naturalCardHeight: 120, maxCardHeight: 460, chromeHeight: chrome)
        XCTAssertFalse(plan.scrolls)
        XCTAssertNil(plan.textHeightLimit)
        XCTAssertEqual(plan.cardHeight, 120)
    }

    func testNaturalHeightExactlyAtLimitDoesNotScroll() {
        let plan = OverlaySizing.plan(naturalCardHeight: 460, maxCardHeight: 460, chromeHeight: chrome)
        XCTAssertFalse(plan.scrolls)
        XCTAssertEqual(plan.cardHeight, 460)
    }

    func testLongTextScrollsWithinBudget() {
        let plan = OverlaySizing.plan(naturalCardHeight: 1400, maxCardHeight: 460, chromeHeight: chrome)
        XCTAssertTrue(plan.scrolls)
        XCTAssertEqual(plan.textHeightLimit, 460 - chrome)
        XCTAssertEqual(plan.cardHeight, 460)
    }

    func testSmallScreensScaleTheBudget() {
        let plan = OverlaySizing.plan(naturalCardHeight: 900, maxCardHeight: 300, chromeHeight: chrome)
        XCTAssertTrue(plan.scrolls)
        XCTAssertEqual(plan.textHeightLimit, 300 - chrome)
        XCTAssertEqual(plan.cardHeight, 300)
    }

    func testDegenerateTinyBudgetFallsBackToNatural() {
        // A budget too small to leave room for text must not produce a
        // negative/absurd scroll area.
        let plan = OverlaySizing.plan(naturalCardHeight: 900, maxCardHeight: 60, chromeHeight: chrome)
        XCTAssertFalse(plan.scrolls)
        XCTAssertNil(plan.textHeightLimit)
        XCTAssertEqual(plan.cardHeight, 900)
    }

    func testMeasuredContentWidthClampsLikeTheCard() {
        // Wide text: card clamps to 600, body gets 600 - 28 padding.
        let wide = OverlaySizing.measuredContentWidth(
            text: String(repeating: "word ", count: 300), fontSize: 13)
        XCTAssertEqual(wide, 572)
        // Tiny text: card sits at minWidth 340, body gets 340 - 28.
        let short = OverlaySizing.measuredContentWidth(text: "hi", fontSize: 13)
        XCTAssertEqual(short, 312)
    }

    func testTextWidthFollowsLongestLine() {
        // Hard line breaks: the longest line sets the width, not the total.
        let mixed = OverlaySizing.textWidth(text: "a\naaaaaaa\naa", fontSize: 13)
        let single = OverlaySizing.textWidth(text: "aaaaaaa", fontSize: 13)
        XCTAssertEqual(mixed, single, accuracy: 2)
    }

    func testClampedIntoVisiblePullsTopOverflowBackUnderTheMenuBar() {
        // 长卡被拖得顶出屏幕：松手后顶边贴齐上缘内 8pt，尺寸不变
        let bounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let dragged = NSRect(x: 300, y: 830, width: 500, height: 460)
        let settled = OverlaySizing.clampedIntoVisible(dragged, in: bounds)
        XCTAssertEqual(settled, NSRect(x: 300, y: 432, width: 500, height: 460))
    }

    func testClampedIntoVisibleAlsoFixesHorizontalAndBottomOverflow() {
        let bounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let dragged = NSRect(x: 1200, y: -40, width: 500, height: 460)
        let settled = OverlaySizing.clampedIntoVisible(dragged, in: bounds)
        XCTAssertEqual(settled.minX, 1440 - 500 - 8)
        XCTAssertEqual(settled.minY, 8)
    }

    func testClampedIntoVisibleKeepsFramesThatAreAlreadyInside() {
        let bounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let inside = NSRect(x: 300, y: 300, width: 500, height: 200)
        XCTAssertEqual(OverlaySizing.clampedIntoVisible(inside, in: bounds), inside)
    }
}
