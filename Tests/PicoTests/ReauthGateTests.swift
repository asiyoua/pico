import XCTest

@testable import Pico

final class ReauthGateTests: XCTestCase {
    func testPromptFiresForRevokedUpgradedUser() {
        // 目标人群：换签名/重装时授权被吊销的老用户。走过引导、当前未授权、
        // 本版本从未见过授权（旧版没有缓存）也必须弹——这是修复的 bug 本体
        XCTAssertTrue(ReauthGate.shouldPrompt(
            masterEnabled: true, onboardingComplete: true, dismissedThisSession: false,
            currentlyTrusted: false))
    }

    func testStaysQuietForFreshUserStillInOnboarding() {
        // 纯新用户没走过引导，欢迎窗负责授权，不弹提醒
        XCTAssertFalse(ReauthGate.shouldPrompt(
            masterEnabled: true, onboardingComplete: false, dismissedThisSession: false,
            currentlyTrusted: false))
    }

    func testStaysQuietWhenPermissionIsHealthy() {
        XCTAssertFalse(ReauthGate.shouldPrompt(
            masterEnabled: true, onboardingComplete: true, dismissedThisSession: false,
            currentlyTrusted: true))
    }

    func testStaysQuietWhenMasterSwitchIsOff() {
        XCTAssertFalse(ReauthGate.shouldPrompt(
            masterEnabled: false, onboardingComplete: true, dismissedThisSession: false,
            currentlyTrusted: false))
    }

    func testStaysQuietAfterUserDismissedThisSession() {
        XCTAssertFalse(ReauthGate.shouldPrompt(
            masterEnabled: true, onboardingComplete: true, dismissedThisSession: true,
            currentlyTrusted: false))
    }
}
