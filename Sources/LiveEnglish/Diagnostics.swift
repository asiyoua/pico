import Foundation

/// Lightweight file log used while diagnosing Accessibility issues.
///
/// Writing is opt-in: it is enabled by the `FLOATTRANS_DEBUG=1` environment
/// variable or the `debugLogEnabled` user default. This keeps the release
/// build from growing an unbounded log file for every poll tick. The file is
/// truncated once it exceeds ``maxBytes`` so long sessions stay bounded.
enum DiagnosticLog {
    private static let url = URL(fileURLWithPath: "/tmp/liveenglish-debug.log")
    private static let maxBytes = 1_048_576
    /// Fractional seconds keep the stage-by-stage latency measurable.
    /// ISO8601DateFormatter is thread-safe for formatting; the unsafe marker
    /// only satisfies shared-state checking.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func write(_ message: String) {
        guard isEnabled() else { return }
        let line = "\(formatter.string(from: .now)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
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

    private static func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["FLOATTRANS_DEBUG"] == "1"
            || UserDefaults.standard.bool(forKey: "debugLogEnabled")
    }

    private static func shouldTruncate() -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            return false
        }
        return size > maxBytes
    }
}
