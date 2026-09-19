import AppKit

/// 一份脱敏的诊断快照。字段是刻意挑过的：足以定位「打字翻译没反应」类
/// 问题，又绝不携带 API 密钥、模型配置、翻译文本等隐私面。
struct DiagnosticsSnapshot {
    var appVersion: String
    var appBuild: String
    var bundleID: String
    var installPath: String
    var installNeedsHealing: Bool
    var osVersion: String
    var hardwareModel: String
    var machine: String
    var accessibilityTrusted: Bool
    var monitorRunning: Bool
    var probeLine: String
    var weChatVersion: String?
    var enabled: Bool
    var timingRaw: String
    var speedMilliseconds: Int
    var sourceLanguage: String
    var targetLanguage: String
    var backendRaw: String
    /// 只报模型数量；模型名、服务地址、密钥一律不进报告
    var llmModelCount: Int
    var uiLanguage: String
    var clipboardEnabled: Bool
    var clipboardTriggerRaw: String
    var excludedBundleIDs: [String]
    var generatedAt: Date
}

/// 「报告问题」诊断报告：全部信息只在本机组装、写入用户桌面文件，由用户
/// 亲手发给作者，不做任何网络上传。键名用英文便于定位，正文人类可读。
enum DiagnosticsReport {
    static func fileName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Pico-Diagnostics-\(formatter.string(from: date)).txt"
    }

    static func render(
        snapshot: DiagnosticsSnapshot, recentLog: [String], debugLogExists: Bool,
        debugLogTail: [String]
    ) -> String {
        let time = ISO8601DateFormatter().string(from: snapshot.generatedAt)
        var lines: [String] = [
            "Pico 诊断报告 / Pico Diagnostics Report",
            "generated_at: \(time)",
            "说明：本文件由 Pico 在本机生成，未经过网络发送；不含翻译内容与 API 密钥。",
            String(repeating: "=", count: 60),
            "[app]",
            "version: \(snapshot.appVersion) (build \(snapshot.appBuild))",
            "bundle_id: \(snapshot.bundleID)",
            "install_path: \(snapshot.installPath)",
            "install_needs_healing: \(snapshot.installNeedsHealing)",
            "[system]",
            "macos: \(snapshot.osVersion)",
            "hardware: \(snapshot.hardwareModel)",
            "machine: \(snapshot.machine)",
            "[permission]",
            "accessibility_trusted: \(snapshot.accessibilityTrusted)",
            "monitor_running: \(snapshot.monitorRunning)",
            "[probe]",
            snapshot.probeLine,
            "wechat_version: \(snapshot.weChatVersion ?? "not_installed")",
            "[settings]",
            "master_enabled: \(snapshot.enabled)",
            "timing: \(snapshot.timingRaw)",
            "speed_ms: \(snapshot.speedMilliseconds)",
            "direction: \(snapshot.sourceLanguage) -> \(snapshot.targetLanguage)",
            "backend: \(snapshot.backendRaw)",
            "llm_model_count: \(snapshot.llmModelCount)",
            "ui_language: \(snapshot.uiLanguage)",
            "clipboard_translation_enabled: \(snapshot.clipboardEnabled)",
            "clipboard_trigger: \(snapshot.clipboardTriggerRaw)",
            "excluded_apps: \(snapshot.excludedBundleIDs.isEmpty ? "(none)" : snapshot.excludedBundleIDs.joined(separator: ", "))",
        ]
        lines.append(String(repeating: "=", count: 60))
        lines.append("[recent_log] (最近 \(recentLog.count) 条，仅含长度与标识)")
        lines.append(contentsOf: recentLog)
        lines.append(String(repeating: "=", count: 60))
        lines.append("[debug_file] /tmp/pico-debug.log exists=\(debugLogExists)")
        if debugLogExists { lines.append(contentsOf: debugLogTail) }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 写入目录（默认桌面，失败回退下载文件夹），返回落盘位置。
    static func write(_ content: String, at date: Date = Date(), in directory: URL? = nil) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base =
            directory ?? home.appendingPathComponent("Desktop", isDirectory: true)
        let target = base.appendingPathComponent(fileName(at: date))
        do {
            try content.write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            let fallback = home.appendingPathComponent("Downloads", isDirectory: true)
                .appendingPathComponent(fileName(at: date))
            return (try? content.write(to: fallback, atomically: true, encoding: .utf8)) != nil
                ? fallback : nil
        }
    }

    /// 微信版本是「打字翻译突然失效」的已知变量（4.1.5 起无障碍树按需构建）。
    static func weChatVersion(
        searchDirectories: [URL]? = nil
    ) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories =
            searchDirectories ?? [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
            ]
        let names = ["WeChat.app", "微信.app"]
        for directory in directories {
            for name in names {
                let bundleURL = directory.appendingPathComponent(name)
                guard
                    let info = CFBundleCopyInfoDictionaryForURL(bundleURL as CFURL)
                        as? [String: Any],
                    let version = info["CFBundleShortVersionString"] as? String
                else { continue }
                return version
            }
        }
        return nil
    }

    static func hardwareModel() -> String { sysctlString("hw.model") ?? "unknown" }
    static func machine() -> String { sysctlString("hw.machine") ?? "unknown" }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
