import AppKit

// MARK: - GitHub release metadata

struct PicoReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    var dmgAsset: Asset? {
        assets.first { $0.name.hasSuffix(".dmg") }
    }
}

enum AutoUpdateError: LocalizedError {
    case badResponse
    case sizeMismatch
    case noInstallerAsset

    var errorDescription: String? {
        switch self {
        case .badResponse: return "更新服务器响应异常"
        case .sizeMismatch: return "下载的更新包大小不符"
        case .noInstallerAsset: return "更新中缺少安装包"
        }
    }
}

// MARK: - Auto update controller

/// Checks GitHub Releases and, when 自动检查更新 is enabled, asks the user
/// before updating: a non-blocking alert offers 立即更新 / 暂不更新. On
/// consent the release is downloaded, the app quits itself and a detached
/// helper replaces /Applications/Pico.app and relaunches. The replacement
/// carries the same bundle id and signing certificate, so the accessibility
/// grant and every setting survive each update.
@MainActor
final class AutoUpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double)
        case installing
        case failed(String)
    }

    @Published var phase: Phase = .idle

    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let downloadSizeCap = 64 * 1024 * 1024

    private let settings: SettingsStore
    private var timer: Timer?
    private var scheduledCheck: Task<Void, Never>?
    private var pendingRelease: PicoReleaseInfo?
    private var skippedVersion: String?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = nil
        guard settings.autoUpdateEnabled else {
            phase = .idle
            return
        }
        scheduleCheck(after: 10)
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkAndInstallIfNeeded() }
        }
    }

    func checkNow() {
        scheduleCheck(after: 0)
    }

    private func scheduleCheck(after seconds: TimeInterval) {
        scheduledCheck?.cancel()
        scheduledCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.checkAndInstallIfNeeded()
        }
    }

    func checkAndInstallIfNeeded() async {
        guard settings.autoUpdateEnabled else {
            phase = .idle
            return
        }
        phase = .checking
        do {
            let release = try await fetchLatestRelease()
            let local = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard UpdateChecker.compare(local: local, remoteTag: release.tagName) == .remoteNewer else {
                phase = .upToDate
                return
            }
            guard release.dmgAsset != nil else {
                throw AutoUpdateError.noInstallerAsset
            }
            // 本会话内用户已对同一版本点过「暂不」，静默视为最新，不再打扰
            guard release.tagName != skippedVersion else {
                phase = .upToDate
                return
            }
            pendingRelease = release
            phase = .available(version: release.tagName)
            presentUpdatePrompt(version: release.tagName)
        } catch is CancellationError {
            // a newer check superseded this one
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Update prompt

    /// 非阻塞弹窗：借 NSAlert 自带的窗口作宿主挂 sheet，不跑嵌套 runloop，
    /// 等待期间翻译等主线程功能照常工作。
    private func presentUpdatePrompt(version: String) {
        let lang = settings.uiLanguage
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(lang)
        alert.informativeText = L10n.updateAvailableBody(lang, version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.updateNowButton(lang))
        alert.addButton(withTitle: L10n.updateLaterButton(lang))
        let hostWindow = alert.window
        alert.beginSheetModal(for: hostWindow) { [weak self] response in
            hostWindow.orderOut(nil)
            if response == .alertFirstButtonReturn {
                self?.confirmUpdate()
            } else {
                self?.postponeUpdate()
            }
        }
        hostWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func confirmUpdate() {
        guard let release = pendingRelease, case .available = phase else { return }
        guard let dmg = release.dmgAsset, let url = URL(string: dmg.browserDownloadURL) else {
            phase = .failed(AutoUpdateError.noInstallerAsset.localizedDescription)
            return
        }
        Task { [weak self] in
            await self?.downloadAndInstall(release: release, assetURL: url, expectedSize: dmg.size)
        }
    }

    func postponeUpdate() {
        if let release = pendingRelease {
            skippedVersion = release.tagName
        }
        pendingRelease = nil
        phase = .upToDate
    }

    private func downloadAndInstall(release: PicoReleaseInfo, assetURL: URL, expectedSize: Int) async {
        do {
            phase = .downloading(progress: 0)
            let data = try await download(from: assetURL, expectedSize: expectedSize) { [weak self] fraction in
                self?.phase = .downloading(progress: fraction)
            }
            phase = .installing
            let staged = try stageDownloadedUpdate(data: data, version: release.tagName)
            applyStagedUpdateAndRelaunch(dmgFile: staged)
            // helper 会等进程退出再换装；这里给 spawn 留半拍后优雅退出
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps

    private func fetchLatestRelease() async throws -> PicoReleaseInfo {
        var request = URLRequest(url: UpdateChecker.latestReleaseURL)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AutoUpdateError.badResponse
        }
        return try JSONDecoder().decode(PicoReleaseInfo.self, from: data)
    }

    private func download(
        from url: URL, expectedSize: Int, progress: @escaping (Double) -> Void
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AutoUpdateError.badResponse
        }
        var data = Data()
        data.reserveCapacity(expectedSize > 0 ? expectedSize : 0)
        var lastReport = Date.distantPast
        for try await byte in asyncBytes {
            data.append(byte)
            if Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                let fraction = expectedSize > 0 ? Double(data.count) / Double(expectedSize) : 0
                progress(min(max(fraction, 0), 1))
            }
        }
        guard expectedSize <= 0 || data.count == expectedSize else {
            throw AutoUpdateError.sizeMismatch
        }
        return data
    }

    private func stageDownloadedUpdate(data: Data, version: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pico-update", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Pico-\(version).dmg")
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Spawns a detached helper that waits for this app to exit, swaps the
    /// installed bundle with the staged DMG contents and relaunches. The
    /// helper survives the app quitting because it is orphaned to launchd.
    private func applyStagedUpdateAndRelaunch(dmgFile: URL) {
        let mountPoint = "/tmp/pico-update-mount"
        let script = """
        set -e
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            pgrep -f "Pico.app/Contents/MacOS/Pico" >/dev/null 2>&1 || break
            sleep 0.5
        done
        mkdir -p "\(mountPoint)"
        hdiutil attach "\(dmgFile.path)" -nobrowse -readonly -mountpoint "\(mountPoint)" >/dev/null
        rm -rf /Applications/Pico.app
        cp -R "\(mountPoint)/Pico.app" /Applications/
        hdiutil detach "\(mountPoint)" >/dev/null 2>&1 || true
        rm -f "\(dmgFile.path)"
        rmdir "\(mountPoint)" 2>/dev/null || true
        open /Applications/Pico.app
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
