import AppKit
import SwiftUI

/// 「辅助功能授权失效」弹窗的判定，纯函数便于单测。走过引导
/// （onboardingComplete）是老用户的判据：授权可能在升级或换签名时被系统
/// 吊销，门槛不能用「本版本见过授权」之类的缓存——那会让吊销发生在老版本
/// 时代的目标用户永远凑不齐条件，弹窗对真正需要的人失明。
enum ReauthGate {
    static func shouldPrompt(
        masterEnabled: Bool, onboardingComplete: Bool, dismissedThisSession: Bool,
        currentlyTrusted: Bool
    ) -> Bool {
        guard masterEnabled, onboardingComplete, !dismissedThisSession else { return false }
        return !currentlyTrusted
    }
}

/// 自动移除本应用已失效的辅助功能授权记录——等价于在系统设置里点「−」，
/// 但用户不需要会找那个按钮。tccutil 对指定 Bundle ID 的 reset 免认证。
enum AccessibilityGrantResetter {
    enum Outcome { case removed, alreadyClear, failed }
    static func resetOwnGrant(bundleID: String) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return .failed }
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: return .removed
        case 64: return .alreadyClear  // tccutil 对无授权记录的 Bundle ID 报 No such bundle identifier
        default: return .failed
        }
    }
}

@MainActor final class ReauthController: ObservableObject {
    enum Step { case start, removed, failed }
    @Published var step: Step = .start
    var onDismiss: (() -> Void)?

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        onDismiss?()
    }

    func later() {
        onDismiss?()
    }

    /// 弹窗期间用户可能已在系统设置里重勾（观察器随后会收起本窗），此时
    /// 不动授权直接收工；tccutil 放后台线程跑，不阻塞界面。
    func removeStaleGrant() {
        guard !AXIsProcessTrusted() else { onDismiss?(); return }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                AccessibilityGrantResetter.resetOwnGrant(
                    bundleID: Bundle.main.bundleIdentifier ?? "com.asiyoua.pico")
            }.value
            let ok = outcome != .failed
            DiagnosticLog.write("reauth stale grant reset outcome=\(String(describing: outcome))")
            step = ok ? .removed : .failed
        }
    }
}

struct ReauthView: View {
    @ObservedObject var controller: ReauthController
    let lang: UILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.reauthTitle(lang)).font(.headline)
            switch controller.step {
            case .start:
                Text(L10n.reauthWizardIntro(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L10n.reauthLater(lang)) { controller.later() }
                    Button(L10n.reauthWizardRemove(lang)) { controller.removeStaleGrant() }
                        .buttonStyle(.borderedProminent)
                }
            case .removed:
                Text(L10n.reauthWizardSteps(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L10n.reauthLater(lang)) { controller.later() }
                    Button(L10n.reauthWizardOpenSettings(lang)) { controller.openSettings() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed:
                Text(L10n.reauthWizardRemoveFailed(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L10n.reauthLater(lang)) { controller.later() }
                    Button(L10n.reauthOpenSettings(lang)) { controller.openSettings() }
                }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
