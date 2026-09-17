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
}
