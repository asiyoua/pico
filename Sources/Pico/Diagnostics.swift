import Foundation

/// Lightweight file log used while diagnosing Accessibility issues.
///
/// Writing is opt-in: it is enabled by the `PICO_DEBUG=1` environment
/// variable or the `debugLogEnabled` user default. This keeps the release
/// build from growing an unbounded log file for every poll tick. The file is
/// truncated once it exceeds ``maxBytes`` so long sessions stay bounded.
enum DiagnosticLog {
    private static let url = URL(fileURLWithPath: "/tmp/pico-debug.log")
    private static let maxBytes = 1_048_576
    /// 内存日志环：无论调试开关与否都记录，供「生成诊断报告」一键导出。
    /// 只待在本机内存里，用户主动导出报告时才随文件离开机器。
    private static let bufferLock = NSLock()
    private static let bufferCapacity = 400
    nonisolated(unsafe) private static var buffer: [String] = []
    /// Fractional seconds keep the stage-by-stage latency measurable.
    /// ISO8601DateFormatter is thread-safe for formatting; the unsafe marker
    /// only satisfies shared-state checking.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: .now)) \(message)\n"
        remember(line)
        guard isEnabled() else { return }
        let data = Data(line.utf8)
        if shouldTruncate(), (try? FileManager.default.removeItem(at: url)) == nil {
            return
        }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
        // /tmp is shared; keep the log readable by the current user only.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func recentLines() -> [String] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    /// 调试文件是否存在（存在说明用户开过 PICO_DEBUG/debugLogEnabled）。
    static func debugFileExists() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 调试文件尾部若干行，供诊断报告附带；读不到就给空数组。
    static func debugFileTail(maxLines: Int = 150) -> [String] {
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).suffix(maxLines))
    }

    private static func remember(_ line: String) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        buffer.append(line)
        if buffer.count > bufferCapacity {
            buffer.removeFirst(buffer.count - bufferCapacity)
        }
    }

    private static func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["PICO_DEBUG"] == "1"
            || UserDefaults.standard.bool(forKey: "debugLogEnabled")
    }

    private static func shouldTruncate() -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            return false
        }
        return size > maxBytes
    }
}
