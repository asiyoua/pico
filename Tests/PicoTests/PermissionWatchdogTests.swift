import XCTest

@testable import Pico

@MainActor
final class AccessibilityPermissionWatchdogTests: XCTestCase {
    private final class ProbeBox {
        var trusted = false
    }

    private final class Counter {
        var restored = 0
        var lost = 0
    }

    func testTransitionsFireCallbacksOncePerFlip() async throws {
        let box = ProbeBox()
        box.trusted = false
        let counter = Counter()
        let watchdog = AccessibilityPermissionWatchdog(
            probe: { box.trusted }, interval: .milliseconds(20))
        watchdog.onRestored = { counter.restored += 1 }
        watchdog.onLost = { counter.lost += 1 }

        watchdog.start()
        box.trusted = true
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.restored, 1, "授权恢复必须恰好回调一次")
        XCTAssertEqual(counter.lost, 0)

        box.trusted = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.lost, 1, "授权丢失必须回调一次")
        XCTAssertEqual(counter.restored, 1)

        watchdog.stop()
    }

    func testStopSilencesFurtherCallbacks() async throws {
        let box = ProbeBox()
        let counter = Counter()
        let watchdog = AccessibilityPermissionWatchdog(
            probe: { box.trusted }, interval: .milliseconds(20))
        watchdog.onRestored = { counter.restored += 1 }
        watchdog.onLost = { counter.lost += 1 }

        watchdog.start()
        watchdog.stop()
        box.trusted = true
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(counter.restored, 0, "stop 后不得再回调")
    }
}
