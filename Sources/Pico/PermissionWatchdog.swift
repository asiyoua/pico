import AppKit
import ApplicationServices

/// 系统辅助功能授权的主动请求（弹系统授权对话框）。
@MainActor final class AccessibilityPermissionManager {
    var isGranted: Bool { AXIsProcessTrusted() }

    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// 常驻辅助功能授权观察器：每秒核对一次系统授权状态，状态跃迁时回调。
/// - onRestored：授权从无到有（更新状态、收起提醒窗、拉起监控）
/// - onLost：授权从有到无（只更新状态；会话中不弹窗，下次启动或打开
///   主开关才提醒）
/// 老版轮询在授权恢复后即退出，会话中授权再死（系统设置里被手动关掉、
/// 策略重置）就无人盯梢，重勾后监控不会重启——本类型修复该缺口。
/// 探测函数与轮询间隔可注入，便于单测。
@MainActor final class AccessibilityPermissionWatchdog {
    var onRestored: () -> Void = {}
    var onLost: () -> Void = {}

    private let probe: () -> Bool
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var lastKnown: Bool

    init(probe: @escaping () -> Bool = AXIsProcessTrusted, interval: Duration = .seconds(1)) {
        self.probe = probe
        self.interval = interval
        self.lastKnown = probe()
    }

    func start() {
        guard task == nil else { return }
        let probe = probe
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                let trusted = probe()
                guard trusted != lastKnown else { continue }
                lastKnown = trusted
                if trusted { onRestored() } else { onLost() }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
