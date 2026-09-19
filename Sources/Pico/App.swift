import AppKit
import ApplicationServices
import OSLog
import SwiftUI
@preconcurrency import Translation

@main struct PicoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        MenuBarExtra("Pico", image: "MenuBarIcon") {
            MenuBarMenu(state: appDelegate.state)
        }.menuBarExtraStyle(.menu)
        Settings { SettingsView(state: appDelegate.state) }
        Window("Welcome to Pico", id: "welcome") { WelcomeView(state: appDelegate.state) }.defaultSize(
            width: 520, height: 360)
    }
}

struct MenuBarMenu: View {
    @ObservedObject var state: AppState
    @ObservedObject private var settings: SettingsStore

    init(state: AppState) {
        self.state = state
        self._settings = ObservedObject(wrappedValue: state.settings)
    }

    var body: some View {
        let lang = settings.uiLanguage
        Button(state.enabled ? L10n.pause(lang) : L10n.resume(lang)) { state.toggle() }
        Divider()
        Button(L10n.menuSettings(lang)) { state.presentSettings() }
        Button(L10n.quit(lang)) { NSApp.terminate(nil) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    override init() {
        state = AppState()
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        state.startTranslationHost()
    }
    /// Clicking the Dock icon with no visible windows opens settings, so the
    /// app is always configurable even when the menu bar item is hard to spot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { state.presentSettings() }
        return true
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let lang = state.settings.uiLanguage
        let menu = NSMenu()
        let settings = NSMenuItem(title: L10n.menuSettings(lang), action: #selector(openSettingsFromDock), keyEquivalent: "")
        let toggle = NSMenuItem(
            title: state.enabled ? L10n.pause(lang) : L10n.resume(lang),
            action: #selector(toggleFromDock), keyEquivalent: "")
        let quit = NSMenuItem(title: L10n.quit(lang), action: #selector(quitFromDock), keyEquivalent: "")
        [settings, toggle, quit].forEach {
            $0.target = self
            menu.addItem($0)
        }
        return menu
    }
    @objc private func openSettingsFromDock() { state.presentSettings() }
    @objc private func toggleFromDock() { state.toggle() }
    @objc private func quitFromDock() { NSApp.terminate(nil) }
}

@MainActor final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "app.pico", category: "runtime")
    @Published var enabled: Bool
    private var menuBarWatchdog: Timer?
    private var menuBarHealAttempts = 0
    @Published var translation = ""
    @Published var permissionGranted: Bool
    @Published var showWelcome: Bool
    var settings: SettingsStore
    let permission = AccessibilityPermissionManager()
    let monitor = AccessibilityMonitor()
    let input = InputCoordinator()
    let llmRouter: LLMModelRouter
    let translationService: TranslationService
    let coordinator: TranslationCoordinator
    let translationHolder: TranslationSessionHolder
    let history: TranslationHistoryController
    let overlay = OverlayCoordinator()
    let speech: SpeechPerforming
    let pasteboardWatcher = PasteboardWatcher()
    let autoUpdater: AutoUpdateController
    private let speechPolicy = SpeechPolicyEvaluator()
    private let hotKey = GlobalHotKey.shared
    private var currentSession: InputSessionID?
    private var pendingAction: PendingTranslationAction?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var installHealWindow: NSWindow?
    private var reauthWindow: NSWindow?
    private var reauthDismissedThisSession = false
    private let permissionWatchdog = AccessibilityPermissionWatchdog()
    private var translationHostWindow: TranslationHostWindowController?
    init() {
        let store = SettingsStore()
        let enabledValue = store.enabled
        let trustedValue = AXIsProcessTrusted()
        let welcomeValue = !UserDefaults.standard.bool(forKey: "onboardingComplete")
        let holder = TranslationSessionHolder()
        let router = LLMModelRouter(models: store.llmModels, timeoutSeconds: store.llmFallbackTimeout)
        let service = TranslationService(
            localEngine: HostedTranslationEngine(holder: holder),
            llmRouter: router,
            backend: store.translationBackend,
            models: store.llmModels,
            timeoutSeconds: store.llmFallbackTimeout)
        let historyController = TranslationHistoryController()
        settings = store
        autoUpdater = AutoUpdateController(settings: store)
        enabled = enabledValue
        permissionGranted = trustedValue
        showWelcome = welcomeValue
        translationHolder = holder
        llmRouter = router
        translationService = service
        coordinator = TranslationCoordinator(
            engine: service, sourceLanguage: store.sourceLanguage, targetLanguage: store.targetLanguage)
        history = historyController
        speech = SpeechService()
        NSLog("Pico startup trusted=%@ enabled=%@", String(trustedValue), String(enabledValue))
        DiagnosticLog.write("startup trusted=\(trustedValue) enabled=\(enabledValue)")
        logger.info("startup trusted=\(trustedValue, privacy: .public) enabled=\(enabledValue, privacy: .public)")
        input.isEnabled = enabled
        input.delayMilliseconds = settings.translationSpeed
        input.sourceLanguage = settings.sourceLanguage
        input.timing = settings.translationTiming
        overlay.hideAfter = settings.hideAfter
        overlay.neverHide = settings.neverHide
        overlay.textSize = settings.textSize
        overlay.position = settings.overlayPosition
        overlay.edgeDistance = settings.overlayEdgeDistance
        overlay.behavior = settings.overlayBehavior
        overlay.cardOpacity = settings.overlayOpacity
        overlay.theme = settings.overlayTheme
        overlay.surface = settings.overlaySurface
        monitor.onSnapshot = { [weak self] snapshot, session, screen in
            self?.input.handle(snapshot, session: session, screen: screen)
        }
        monitor.onFocusChanged = { [weak self] in self?.input.reset() }
        input.excludedBundleIDs = settings.excludedBundleIDs
        monitor.excludedBundleIDs = settings.excludedBundleIDs
        monitor.sourceLanguage = settings.sourceLanguage
        settings.onTranslationSettingsChanged = { [weak self] in self?.applyTranslationSettings() }
        settings.onClipboardSettingsChanged = { [weak self] in self?.applyClipboardSettings() }
        settings.onAutoUpdateChanged = { [weak self] in self?.autoUpdater.startMonitoring() }
        overlay.onCopyToPasteboard = { [weak self] _ in self?.pasteboardWatcher.resyncBaseline() }
        pasteboardWatcher.onCopy = { [weak self] text in self?.translateCopiedText(text, autoTriggered: true) }
        settings.onHistoryRetentionChanged = { [weak self] in
            guard let self else { return }
            self.history.reload(retention: self.settings.historyRetention)
        }
        input.onSentence = { [weak self] text, sentenceKey, session, screen, snapshot in
            self?.translate(text, sentenceKey: sentenceKey, session: session, screen: screen, snapshot: snapshot)
        }
        input.onEmpty = { [weak self] in
            self?.clearPendingAction()
            self?.overlay.hide()
            self?.speech.stop()
            Task { await self?.coordinator.cancel() }
        }
        if permissionGranted && enabled {
            monitor.start()
            DiagnosticLog.write("accessibility monitor started")
            logger.info("accessibility monitor started")
        } else {
            DiagnosticLog.write("accessibility monitor skipped")
            logger.info("accessibility monitor skipped")
        }
        // 常驻授权观察器：状态跃迁时回调。restored=更新状态、收起提醒窗、
        // 拉起监控；lost=只更新状态（会话中不弹窗，下次启动或打开主开关
        // 才提醒）。会话中授权再死（系统设置里被手动关掉、策略重置）也能
        // 在重勾后自动恢复——老版轮询恢复后即退出，存在这个缺口。
        permissionWatchdog.onRestored = { [weak self] in
            guard let self else { return }
            permissionGranted = true
            reauthWindow?.orderOut(nil)
            reauthWindow = nil
            monitor.start()
            DiagnosticLog.write("accessibility permission restored, starting monitor")
            logger.info("accessibility permission restored, starting monitor")
        }
        permissionWatchdog.onLost = { [weak self] in
            guard let self else { return }
            permissionGranted = false
            DiagnosticLog.write("accessibility permission lost")
            logger.info("accessibility permission lost")
        }
        permissionWatchdog.start()
        hotKey.onAction = { [weak self] action in
            switch action {
            case .replace: self?.handleReplaceHotKey()
            case .copy: self?.handleCopyHotKey()
            case .translate: self?.handleTranslateHotKey()
            case .clipboard: self?.handleClipboardHotKey()
            }
        }
        refreshHotKeys()
        applyTranslationSettings()
        applyClipboardSettings()
        autoUpdater.startMonitoring()
        history.reload(retention: settings.historyRetention)
        DiagnosticLog.write("init showWelcome=\(showWelcome) onboarded=\(UserDefaults.standard.bool(forKey: "onboardingComplete"))")
        if showWelcome {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                DiagnosticLog.write("welcome task firing")
                self?.presentWelcome()
            }
        }
        // 从磁盘映像/下载文件夹运行时提示一键搬到「应用程序」，避免授权反复失效
        if InstallHealer.shouldPrompt() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4.5))
                self?.presentInstallHeal()
            }
        }
        // 授权失效提醒：曾授权过、现在掉了的用户会在启动几秒后看到提示窗
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5.5))
            self?.maybePresentReauth()
        }
    }
    func startTranslationHost() {
        guard translationHostWindow == nil else { return }
        translationHostWindow = TranslationHostWindowController(holder: translationHolder, settings: settings)
        startMenuBarWatchdog()
    }

    /// 系统在菜单栏拥挤或创建时机不巧时，会把状态项停到屏幕外（负坐标）。
    /// 看门狗检测到后移除并重建状态项，让系统重新分配一个可见位置。
    func startMenuBarWatchdog() {
        menuBarWatchdog?.invalidate()
        menuBarWatchdog = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.healMenuBarExtraIfNeeded() }
        }
    }

    private func healMenuBarExtraIfNeeded() {
        guard enabled else { return }
        guard let screen = NSScreen.main else { return }
        // 菜单栏条带：屏幕顶部 24pt
        let barFrame = NSRect(x: 0, y: screen.frame.maxY - 24, width: screen.frame.width, height: 24)
        let statusWindows = NSApp.windows.filter { $0.level == .statusBar }
        guard !statusWindows.isEmpty else { return }
        let misplaced = statusWindows.contains { !barFrame.intersects($0.frame) }
        if misplaced {
            // 把状态项放回条带内、时钟左侧
            var x = screen.frame.maxX - 24 - 8
            for window in statusWindows.reversed() {
                let w = window.frame.width
                window.setFrame(NSRect(x: x - w, y: barFrame.minY, width: w, height: 24), display: true)
                x -= w + 8
            }
            menuBarHealAttempts += 1
        } else {
            menuBarHealAttempts = 0
        }
    }

    /// Applies a settings edit to the running pipeline. Direction, engine,
    /// prompt/model order, and timeout all take effect on the next request;
    /// existing work is invalidated so stale output cannot overwrite it.
    func applyTranslationSettings() {
        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        let backend = settings.translationBackend
        let timeout = settings.llmFallbackTimeout
        let models = settings.llmModels
        input.setSourceLanguage(source)
        monitor.sourceLanguage = source
        translationHolder.configure(source: source, target: target)
        currentSession = nil
        clearPendingAction()
        overlay.hide()
        speech.stop()
        let coordinator = coordinator
        let service = translationService
        Task {
            await coordinator.cancel()
            await coordinator.setDirection(from: source, to: target)
            await service.configure(backend: backend, models: models, timeoutSeconds: timeout)
            await coordinator.clearCache()
        }
    }
    func toggle() {
        enabled.toggle()
        settings.enabled = enabled
        input.isEnabled = enabled
        if enabled {
            permissionGranted = AXIsProcessTrusted()
            monitor.start()
            refreshHotKeys()
            maybePresentReauth()
        } else {
            input.reset()
            monitor.stop()
            clearPendingAction()
            refreshHotKeys()
            Task { await coordinator.cancel() }
            speech.stop()
            overlay.hide()
        }
        applyClipboardSettings()
    }
    func requestPermission() {
        permission.request()
        permissionGranted = AXIsProcessTrusted()
        if permissionGranted { monitor.start() }
    }
    func showOverlayTest() { overlay.show("This is a position preview.", on: NSScreen.main) }

    /// 「报告问题」：一键在本机生成脱敏诊断文件（桌面），并在访达中显示。
    /// 不做任何网络上传，文件由用户亲手发给作者。
    func generateDiagnosticsReport() {
        let snapshot = DiagnosticsSnapshot(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            installPath: Bundle.main.bundlePath,
            installNeedsHealing: InstallHealer.needsHealing(bundlePath: Bundle.main.bundlePath),
            osVersion: DiagnosticsReport.osVersion(),
            hardwareModel: DiagnosticsReport.hardwareModel(),
            machine: DiagnosticsReport.machine(),
            accessibilityTrusted: AXIsProcessTrusted(),
            monitorRunning: monitor.isRunning,
            probeLine: monitor.diagnosticProbe(),
            weChatVersion: DiagnosticsReport.weChatVersion(),
            enabled: enabled,
            timingRaw: settings.translationTiming.rawValue,
            speedMilliseconds: settings.translationSpeed,
            sourceLanguage: settings.sourceLanguage.rawValue,
            targetLanguage: settings.targetLanguage.rawValue,
            backendRaw: settings.translationBackend.rawValue,
            llmModelCount: settings.llmModels.count,
            uiLanguage: settings.uiLanguage.rawValue,
            clipboardEnabled: settings.clipboardTranslationEnabled,
            clipboardTriggerRaw: settings.clipboardTriggerMode.rawValue,
            excludedBundleIDs: settings.excludedBundleIDs.sorted(),
            generatedAt: Date())
        let content = DiagnosticsReport.render(
            snapshot: snapshot, recentLog: DiagnosticLog.recentLines(),
            debugLogExists: DiagnosticLog.debugFileExists(),
            debugLogTail: DiagnosticLog.debugFileTail())
        guard let url = DiagnosticsReport.write(content) else {
            DiagnosticLog.write("diagnostics report write failed")
            return
        }
        DiagnosticLog.write("diagnostics report written \(url.lastPathComponent)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        showWelcome = false
        welcomeWindow?.close()
        welcomeWindow = nil
    }
    func presentSettings() {
        if let settingsWindow {
            updateSettingsWindowTitle()
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.settingsWindowTitle(settings.uiLanguage)
        let hosting = NSHostingView(rootView: SettingsView(state: self))
        hosting.sizingOptions = .minSize
        window.contentView = hosting
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.setContentSize(NSSize(width: 840, height: 700))
        centerOnMainScreen(window)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
    /// macOS 26: center() can land a window off-screen (seen on the overlay
    /// prompt); pin the window to the main screen center explicitly.
    private func centerOnMainScreen(_ window: NSWindow) {
        window.center()
        guard let screen = NSScreen.main else { return }
        var frame = window.frame
        frame.origin.x = screen.frame.midX - frame.width / 2
        frame.origin.y = screen.frame.midY - frame.height / 2
        window.setFrameOrigin(frame.origin)
    }

    func updateSettingsWindowTitle() {
        settingsWindow?.title = L10n.settingsWindowTitle(settings.uiLanguage)
    }
    private func presentWelcome() {
        DiagnosticLog.write("presentWelcome called")
        guard welcomeWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Welcome to Pico"
        window.contentView = NSHostingView(rootView: WelcomeView(state: self))
        centerOnMainScreen(window)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }

    /// 非阻塞安装位置提示窗。只用 orderFrontRegardless 展示、不抢键盘
    /// 焦点（窗口曾被误按键触发默认按钮），并按主屏显式居中（macOS 26
    /// 上 center() 会把窗放去屏外）。
    private func presentInstallHeal() {
        guard installHealWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 210), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L10n.installHealTitle(settings.uiLanguage)
        let controller = InstallHealController()
        controller.onDismiss = { [weak self] in
            self?.installHealWindow?.orderOut(nil)
            self?.installHealWindow = nil
        }
        window.contentView = NSHostingView(
            rootView: InstallHealView(controller: controller, lang: settings.uiLanguage)
                .frame(width: 400, height: 182))
        window.center()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            var frame = window.frame
            frame.origin.x = screen.frame.midX - frame.width / 2
            frame.origin.y = screen.frame.midY - frame.height / 2
            window.setFrameOrigin(frame.origin)
        }
        window.isReleasedWhenClosed = false
        // 浮在普通窗口之上但不抢键盘焦点；orderFrontRegardless 的默认 z 序
        // 会被前台应用的窗口整个挡住
        window.level = .floating
        window.orderFrontRegardless()
        installHealWindow = window
    }
    private func translate(
        _ text: String, sentenceKey: String, session: InputSessionID, screen: NSScreen?, snapshot: TextSnapshot
    ) {
        let sourceLanguage = settings.sourceLanguage
        let targetLanguage = settings.targetLanguage
        currentSession = session
        let previous = pendingAction
        let sameSentence = previous?.sentenceKey == sentenceKey && previous?.session == session
        var sourceWithTerminator: String?
        if settings.replaceOriginal {
            sourceWithTerminator = FieldReplacement.evaluate(fieldText: snapshot.text, source: text)?
                .sourceWithTerminator
        }
        pendingAction = PendingTranslationAction(
            text: nil,
            sourceWithTerminator: sourceWithTerminator,
            session: session,
            sentenceKey: sentenceKey,
            applyReplaceWhenReady: sameSentence && previous?.applyReplaceWhenReady == true,
            applyCopyWhenReady: sameSentence && previous?.applyCopyWhenReady == true)
        DiagnosticLog.write("translation requested length=\(text.count)")
        logger.info("translation requested length=\(text.count, privacy: .public)")
        let coordinator = coordinator
        Task { [weak self, coordinator] in
            guard let result = await coordinator.translate(text) else {
                await MainActor.run {
                    DiagnosticLog.write("translation returned no result")
                    self?.logger.info("translation returned no result")
                }
                return
            }
            await MainActor.run {
                self?.acceptTranslationResult(
                    result,
                    sourceText: text,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    key: sentenceKey,
                    session: session,
                    screen: screen,
                    avoid: snapshot.fieldFrame)
            }
        }
    }
    private func acceptTranslationResult(
        _ result: String,
        sourceText: String,
        sourceLanguage: Language,
        targetLanguage: Language,
        key sentenceKey: String,
        session: InputSessionID,
        screen: NSScreen?,
        avoid: NSRect?,
        speak: Bool = true
    ) {
        guard currentSession == session, enabled else {
            DiagnosticLog.write("translation discarded stale session")
            logger.info("translation discarded stale session")
            return
        }
        translation = result
        if pendingAction?.session == session, pendingAction?.sentenceKey == sentenceKey {
            pendingAction?.text = result
        } else {
            pendingAction = PendingTranslationAction(
                text: result, sourceWithTerminator: nil, session: session, sentenceKey: sentenceKey)
        }
        history.record(
            sourceText: sourceText,
            translatedText: result,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            retention: settings.historyRetention)
        DiagnosticLog.write("translation result accepted length=\(result.count)")
        logger.info("translation result accepted length=\(result.count, privacy: .public)")
        overlay.show(result, key: sentenceKey, on: screen, avoid: avoid)
        if speak { speakIfAllowed(result) }
        if pendingAction?.applyReplaceWhenReady == true { applyPendingReplace() }
        if pendingAction?.applyCopyWhenReady == true { applyPendingCopy() }
    }
    private func speakIfAllowed(_ text: String) {
        guard speechPolicy.shouldSpeak(
            speechEnabled: settings.speechEnabled,
            speechTriggers: settings.speechTriggers,
            translationTiming: settings.translationTiming)
        else {
            DiagnosticLog.write("speech skipped")
            return
        }
        DiagnosticLog.write("speech speaking length=\(text.count)")
        speech.speak(text, language: settings.targetLanguage)
    }
    /// 授权失效提醒：走过引导的老用户如果当前没有辅助功能授权（系统更新、
    /// 重装或换签名都可能吊销），启动几秒后主动弹窗指路，避免打字翻译静默
    /// 失效没人发现。纯新用户走欢迎窗，不弹这个。
    func maybePresentReauth() {
        let trusted = AXIsProcessTrusted()
        let onboarded = UserDefaults.standard.bool(forKey: "onboardingComplete")
        let status = "reauth check enabled=\(enabled) onboarded=\(onboarded) trusted=\(trusted) dismissed=\(reauthDismissedThisSession)"
        DiagnosticLog.write(status)
        logger.info("\(status, privacy: .public)")
        guard ReauthGate.shouldPrompt(
            masterEnabled: enabled, onboardingComplete: onboarded,
            dismissedThisSession: reauthDismissedThisSession, currentlyTrusted: trusted)
        else { return }
        // TCC 在启动初期偶发抖动：3 秒后复核仍失败才弹，防止已授权用户被误打扰
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            if AXIsProcessTrusted() {
                DiagnosticLog.write("reauth check: trust recovered during confirmation")
                logger.info("reauth check: trust recovered during confirmation")
                return
            }
            self.presentReauth()
        }
    }

    private func presentReauth() {
        guard reauthWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 258), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L10n.reauthTitle(settings.uiLanguage)
        let controller = ReauthController()
        controller.onDismiss = { [weak self] in
            self?.reauthDismissedThisSession = true
            self?.reauthWindow?.orderOut(nil)
            self?.reauthWindow = nil
            DiagnosticLog.write("reauth prompt dismissed")
        }
        window.contentView = NSHostingView(
            rootView: ReauthView(controller: controller, lang: settings.uiLanguage)
                .frame(width: 400, height: 230))
        centerOnMainScreen(window)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.orderFrontRegardless()
        reauthWindow = window
        DiagnosticLog.write("reauth prompt presented")
        NSLog("Pico reauth prompt presented")
    }

    func setReplaceOriginal(_ enabled: Bool) {
        settings.replaceOriginal = enabled
        refreshHotKeys()
    }

    func setCopyTranslation(_ enabled: Bool) {
        settings.copyTranslation = enabled
        refreshHotKeys()
    }

    func setReplaceShortcut(_ shortcut: ReplaceShortcut) {
        settings.replaceShortcut = shortcut
        refreshHotKeys()
    }

    func setCopyShortcut(_ shortcut: ReplaceShortcut) {
        settings.copyShortcut = shortcut
        refreshHotKeys()
    }

    func setTranslationTiming(_ timing: TranslationTiming) {
        settings.translationTiming = timing
        input.timing = timing
        refreshHotKeys()
    }

    func setTranslateShortcut(_ shortcut: ReplaceShortcut) {
        settings.translateShortcut = shortcut
        refreshHotKeys()
    }

    private func refreshHotKeys() {
        hotKey.set(.replace, shortcut: enabled && settings.replaceOriginal ? settings.replaceShortcut : nil)
        hotKey.set(.copy, shortcut: enabled && settings.copyTranslation ? settings.copyShortcut : nil)
        hotKey.set(
            .translate,
            shortcut: enabled && settings.translationTiming == .shortcut ? settings.translateShortcut : nil)
        hotKey.set(
            .clipboard,
            shortcut: enabled && settings.clipboardTranslationEnabled ? settings.clipboardShortcut : nil)
    }

    /// Keeps the pasteboard watcher and the clipboard hotkey in sync with the
    /// clipboard settings and the app's master switch.
    func applyClipboardSettings() {
        let active = enabled && settings.clipboardTranslationEnabled
        if active && settings.clipboardTriggerMode == .autoWatch {
            pasteboardWatcher.start()
        } else {
            pasteboardWatcher.stop()
        }
        refreshHotKeys()
    }

    private func handleClipboardHotKey() {
        translateCopiedText(autoTriggered: false)
    }

    /// Translates the current clipboard content (hotkey) or the freshly
    /// copied text (auto watch). Auto mode only fires for text in the
    /// configured source language so code and links stay quiet.
    func translateCopiedText(_ rawText: String? = nil, autoTriggered: Bool) {
        guard enabled, settings.clipboardTranslationEnabled else { return }
        guard var text = (rawText ?? NSPasteboard.general.string(forType: .string))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return }
        if text.count > 2000 { text = String(text.prefix(2000)) }
        if autoTriggered {
            // 黑名单应用保持完全静音：前台是排除应用时不触发剪贴板翻译
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                settings.excludedBundleIDs.contains(front) {
                return
            }
            guard LanguageTextDetector().contains(text, language: settings.sourceLanguage) else { return }
        }
        // 微信读书等阅读器复制出来的选区没有换行，先按句子重建段落，
        // 译文才能保持分段可读。
        text = TextParagraphing.restoreParagraphBreaks(text)
        let session = InputSessionID(pid: ProcessInfo.processInfo.processIdentifier)
        let sentenceKey = "clipboard:\(text)"
        currentSession = session
        pendingAction = PendingTranslationAction(
            text: nil, sourceWithTerminator: nil, session: session, sentenceKey: sentenceKey)
        DiagnosticLog.write("clipboard translation requested length=\(text.count)")
        logger.info("clipboard translation requested length=\(text.count, privacy: .public)")
        let coordinator = coordinator
        Task { [weak self, coordinator] in
            guard let result = await coordinator.translate(text) else { return }
            await MainActor.run {
                guard let self else { return }
                self.acceptTranslationResult(
                    result,
                    sourceText: text,
                    sourceLanguage: self.settings.sourceLanguage,
                    targetLanguage: self.settings.targetLanguage,
                    key: sentenceKey,
                    session: session,
                    screen: NSScreen.main,
                    avoid: nil,
                    speak: false)
            }
        }
    }

    private func handleTranslateHotKey() {
        guard enabled, settings.translationTiming == .shortcut else { return }
        guard let captured = monitor.snapshotNow() else { return }
        input.translateNow(captured.snapshot, session: captured.session, screen: captured.screen)
    }

    private func handleReplaceHotKey() {
        guard enabled, settings.replaceOriginal else { return }
        if pendingAction?.text != nil, pendingAction?.sourceWithTerminator != nil {
            applyPendingReplace()
        } else if pendingAction != nil {
            pendingAction?.applyReplaceWhenReady = true
        }
    }

    private func handleCopyHotKey() {
        guard enabled, settings.copyTranslation else { return }
        if pendingAction?.text != nil {
            applyPendingCopy()
        } else if pendingAction != nil {
            pendingAction?.applyCopyWhenReady = true
        }
    }

    private func applyPendingReplace() {
        guard enabled, settings.replaceOriginal else { return }
        guard var pending = pendingAction, let translation = pending.text,
            let source = pending.sourceWithTerminator
        else { return }
        if monitor.replace(sourceWithTerminator: source, translation: translation) {
            pending.sourceWithTerminator = nil
            pending.applyReplaceWhenReady = false
            pendingAction = pending
        }
    }

    private func applyPendingCopy() {
        guard enabled, settings.copyTranslation else { return }
        _ = TranslationClipboard.copy(pendingAction?.text)
        pasteboardWatcher.resyncBaseline()
        pendingAction?.applyCopyWhenReady = false
    }

    private func clearPendingAction() {
        pendingAction = nil
        translation = ""
    }

    deinit {
        // 授权观察器的 Task 持弱引用，应用退出时随 self 释放自行结束
        let watcher = pasteboardWatcher
        Task { @MainActor in watcher.stop() }
    }
}

private struct PendingTranslationAction {
    var text: String?
    var sourceWithTerminator: String?
    var session: InputSessionID
    var sentenceKey: String
    var applyReplaceWhenReady = false
    var applyCopyWhenReady = false
}

struct AboutView: View {
    var language: UILanguage = .chinese
    @ObservedObject var autoUpdater: AutoUpdateController

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(
                width: 96, height: 96)
            Text(L10n.productName(language)).font(.largeTitle.bold())
            Text(L10n.version(language)).foregroundStyle(.secondary)
            Text(L10n.aboutBody(language)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(L10n.checkForUpdates(language)) {
                autoUpdater.checkManually()
            }
            .disabled(autoUpdater.isBusy)
            if let statusText = autoUpdater.statusText(for: language) {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Divider()
            aboutLinkRow(
                label: L10n.aboutProjectRepo(language),
                title: "github.com/asiyoua/pico",
                urlString: "https://github.com/asiyoua/pico")
            aboutLinkRow(
                label: L10n.aboutContactAuthor(language),
                title: "xinzhu400@gmail.com",
                urlString: "mailto:xinzhu400@gmail.com")
        }
        .padding(28)
        .frame(maxWidth: 420)
    }

    private func aboutLinkRow(label: String, title: String, urlString: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let url = URL(string: urlString) {
                Link(title, destination: url).font(.caption)
            }
        }
    }
}

enum AddExcludedAppView {
    @MainActor static func openPanel(state: AppState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.begin { response in
            guard response == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else {
                return
            }
            state.settings.excludedBundleIDs.insert(bundleID)
            state.input.excludedBundleIDs = state.settings.excludedBundleIDs
            state.monitor.excludedBundleIDs = state.settings.excludedBundleIDs
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var state: AppState
    @State private var step = 0
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "character.bubble").font(.system(size: 42)).foregroundStyle(.blue)
            Text(
                step == 0
                    ? "Write in Chinese.\nSee it in English." : step == 1 ? "Accessibility Permission" : "Try it now"
            ).font(.title).multilineTextAlignment(.center)
            Text(
                step == 0
                        ? "Pico translates what you're typing without interrupting your workflow."
                        : step == 1
                            ? "Permission lets Pico read only the editable text field. Password fields are always skipped."
                            : "Type something in Chinese in any supported text field."
            ).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if step == 1 && !state.permissionGranted {
                Button("Allow Permission") { state.requestPermission() }.buttonStyle(.borderedProminent)
            }
            if step == 1 {
                LanguageResourceRow(
                    language: state.settings.uiLanguage,
                    sourceLanguage: state.settings.sourceLanguage,
                    targetLanguage: state.settings.targetLanguage)
            }
            Spacer()
            Button(step == 2 ? "Done" : "Continue") { if step < 2 { step += 1 } else { state.finishOnboarding() } }
                .buttonStyle(.borderedProminent)
        }.padding(36)
    }
}

struct TranslationHostView: View {
    let holder: TranslationSessionHolder
    @ObservedObject var settings: SettingsStore
    @State private var configuration: TranslationSession.Configuration

    init(holder: TranslationSessionHolder, settings: SettingsStore) {
        self.holder = holder
        self.settings = settings
        _configuration = State(
            initialValue: TranslationSession.Configuration(
                source: settings.sourceLanguage.locale, target: settings.targetLanguage.locale))
    }

    var body: some View {
        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        Color.clear
            .frame(width: 1, height: 1)
            .onChange(of: settings.sourceLanguage) { _, _ in resetConfiguration() }
            .onChange(of: settings.targetLanguage) { _, _ in resetConfiguration() }
            .translationTask(configuration) { session in
                holder.attach(session, source: source, target: target)
            }
    }

    private func resetConfiguration() {
        holder.configure(source: settings.sourceLanguage, target: settings.targetLanguage)
        configuration = TranslationSession.Configuration(
            source: settings.sourceLanguage.locale, target: settings.targetLanguage.locale)
    }
}

@MainActor final class TranslationHostWindowController {
    private let window: NSWindow

    init(holder: TranslationSessionHolder, settings: SettingsStore) {
        let panel = NSPanel(
            contentRect: NSRect(x: -2000, y: -2000, width: 8, height: 8),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.01
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: TranslationHostView(holder: holder, settings: settings))
        panel.orderFrontRegardless()
        window = panel
    }
}
