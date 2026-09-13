import AppKit
import SwiftUI

/// 安装位置自检：Pico 从磁盘映像、下载文件夹（或其触发的 App
/// Translocation 随机路径）运行时，Gatekeeper 每次启动都拦、辅助功能
/// 授权反复失效。检测到就提示用户一键搬到「应用程序」，搬完重启新实例。
enum InstallHealer {
    static let dismissedDefaultsKey = "installHealerDismissedVersion"

    static func needsHealing(bundlePath: String = Bundle.main.bundlePath) -> Bool {
        let home = NSHomeDirectory()
        return bundlePath.contains("AppTranslocation")
            || bundlePath.contains("/Volumes/")
            || bundlePath.hasPrefix(home + "/Downloads/")
    }

    /// 用户点过「暂不」就同版本不再打扰，下个版本再问一次
    static func shouldPrompt(
        dismissedVersion: String? = UserDefaults.standard.string(forKey: dismissedDefaultsKey),
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "",
        bundlePath: String = Bundle.main.bundlePath
    ) -> Bool {
        needsHealing(bundlePath: bundlePath) && dismissedVersion != currentVersion
    }

    static func rememberDismissal(
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    ) {
        UserDefaults.standard.set(version, forKey: dismissedDefaultsKey)
    }

    /// 复制到 /Applications（不可写则回退 ~/Applications），剥掉 quarantine
    /// 并返回目标路径；已有同名 app 时替换。
    static func relocate(appPath: String = Bundle.main.bundlePath) throws -> String {
        let fm = FileManager.default
        let destinations = ["/Applications", NSHomeDirectory() + "/Applications"]
        for base in destinations {
            let dir = URL(fileURLWithPath: base, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            guard fm.isWritableFile(atPath: dir.path) else { continue }
            let dest = dir.appendingPathComponent("Pico.app", isDirectory: true)
            if dest.path == appPath { return dest.path }
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(atPath: appPath, toPath: dest.path)
            stripQuarantine(at: dest.path)
            return dest.path
        }
        throw CocoaError(.fileWriteNoPermission)
    }

    /// 剥 quarantine 后 Gatekeeper 不再拦（浏览器下载的副本带着这个标记）
    private static func stripQuarantine(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// 退出所有实例（含本进程与可能存在的重复实例）后启动搬好位置的副本
    static func spawnRelaunch(dest: String) {
        let script = """
        sleep 0.5
        pkill -x Pico 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x Pico >/dev/null 2>&1 || break
            sleep 0.5
        done
        open "\(dest)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

@MainActor
final class InstallHealController: ObservableObject {
    enum Phase: Equatable {
        case prompt
        case moving
        case failed(String)
    }

    @Published var phase: Phase = .prompt
    var onDismiss: (() -> Void)?

    func later() {
        InstallHealer.rememberDismissal()
        onDismiss?()
    }

    func moveNow() {
        phase = .moving
        do {
            let dest = try InstallHealer.relocate()
            InstallHealer.spawnRelaunch(dest: dest)
            onDismiss?()
            // 给 spawn 留半拍再优雅退出；脚本里还有 pkill 兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct InstallHealView: View {
    @ObservedObject var controller: InstallHealController
    let lang: UILanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch controller.phase {
            case .prompt:
                Text(L10n.installHealBody(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L10n.installHealLaterButton(lang)) { controller.later() }
                    Button(L10n.installHealMoveButton(lang)) { controller.moveNow() }
                }
            case .moving:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.installHealMoving(lang))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text("\(L10n.installHealFailed(lang))：\(message)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L10n.installHealLaterButton(lang)) { controller.later() }
                    Button(L10n.updateRetryButton(lang)) { controller.moveNow() }
                }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
