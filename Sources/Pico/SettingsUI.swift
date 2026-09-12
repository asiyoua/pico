import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Translation

// MARK: - Layout primitives

/// A settings row: leading title (with optional subtitle) and a trailing
/// control. Draws a hairline separator under itself unless suppressed for
/// the last row of a group.
struct SettingsRow<Control: View>: View {
    let label: String
    var subtitle: String? = nil
    var divider: Bool = true
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if divider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

/// A titled group card: section header above a rounded, hairline-stroked
/// container whose rows sit on the control background.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

/// Small helper for picker-style trailing controls with a fixed width.
struct TrailingPicker<Selection: Hashable, Options: View>: View {
    var width: CGFloat = 180
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Options

    var body: some View {
        Picker("", selection: $selection) {
            content()
        }
        .labelsHidden()
        .controlSize(.regular)
        .frame(width: width)
    }
}

struct ExcludedAppRow: View {
    let bundleID: String
    let language: UILanguage
    let remove: () -> Void
    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    var body: some View {
        HStack(spacing: 10) {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
            Text(appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? L10n.unknownApp(language))
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.secondary.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ShortcutRecorderButton: View {
    let language: UILanguage
    let shortcut: ReplaceShortcut
    let onCommit: (ReplaceShortcut) -> Void
    @State private var recording = false

    var body: some View {
        Button(recording ? L10n.shortcutRecording(language) : shortcut.displayString) {
            recording = true
        }
        .controlSize(.regular)
        .background {
            ShortcutKeyMonitor(isActive: $recording) { event in
                if UInt32(event.keyCode) == ReplaceShortcut.escapeKeyCode {
                    recording = false
                    return
                }
                if let recorded = ReplaceShortcut.from(event: event) {
                    onCommit(recorded)
                    recording = false
                }
            }
        }
    }
}

private struct ShortcutKeyMonitor: NSViewRepresentable {
    @Binding var isActive: Bool
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isActive = false
        var onKeyDown: ((NSEvent) -> Void)?
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive else { return event }
                self.onKeyDown?(event)
                return nil
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct ModelOrderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var models: [LLMModelConfiguration]
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
            let from = models.firstIndex(where: { $0.id == draggedID }),
            let to = models.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation(.snappy) {
            models.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

/// Editable row for one provider in the user-defined fail-over order.
struct LLMModelEditor: View {
    @State private var draft: LLMModelConfiguration
    @State private var isExpanded = false
    let language: UILanguage
    let save: (LLMModelConfiguration) -> Void
    let remove: () -> Void

    init(
        model: LLMModelConfiguration,
        language: UILanguage,
        save: @escaping (LLMModelConfiguration) -> Void,
        remove: @escaping () -> Void
    ) {
        var initialDraft = model
        if initialDraft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialDraft.systemPrompt = LLMTranslationPrompt.defaultSystemPrompt
        }
        _draft = State(initialValue: initialDraft)
        self.language = language
        self.save = save
        self.remove = remove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name.isEmpty ? L10n.modelPlaceholder(language) : draft.name)
                            .font(.subheadline.weight(.semibold))
                        if !draft.model.isEmpty {
                            Text(draft.model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(draft.enabled ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.name.isEmpty ? L10n.modelPlaceholder(language) : draft.name)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: L10n.modelName(language)) {
                        TextField(L10n.modelPlaceholder(language), text: $draft.name).textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: L10n.provider(language)) {
                        Picker("", selection: $draft.provider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(L10n.providerName(provider, language)).tag(provider)
                            }
                        }
                        .onChange(of: draft.provider) { _, provider in
                            if draft.baseURL.isEmpty || draft.baseURL == LLMProvider.openAICompatible.defaultBaseURL {
                                draft.baseURL = provider.defaultBaseURL
                            }
                            if draft.model.isEmpty { draft.model = provider.defaultModel }
                        }
                    }
                    LabeledField(label: L10n.endpointURL(language)) {
                        TextField(L10n.urlPlaceholder(language), text: $draft.baseURL).textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: L10n.apiKey(language)) {
                        SecureField("", text: $draft.apiKey).textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: L10n.modelID(language)) {
                        TextField(L10n.modelIDPlaceholder(language), text: $draft.model).textFieldStyle(.roundedBorder)
                    }
                    LabeledField(label: L10n.thinkingMode(language)) {
                        Picker("", selection: $draft.thinking) {
                            ForEach(LLMThinkingMode.allCases) { mode in
                                Text(thinkingName(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    LabeledField(label: L10n.prompt(language)) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $draft.systemPrompt)
                                .frame(minHeight: 110)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                            HStack {
                                Text(L10n.promptHint(language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(L10n.restoreDefaultPrompt(language)) {
                                    draft.systemPrompt = LLMTranslationPrompt.defaultSystemPrompt
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    HStack {
                        Toggle(L10n.modelEnabled(language), isOn: $draft.enabled).toggleStyle(.checkbox)
                        Spacer()
                        Button(L10n.removeModel(language), role: .destructive, action: remove)
                    }
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: draft) { _, updated in save(updated) }
    }

    private func thinkingName(_ mode: LLMThinkingMode) -> String {
        switch mode {
        case .automatic: return L10n.thinkingAutomatic(language)
        case .nonThinking: return L10n.thinkingOff(language)
        case .thinking: return L10n.thinkingOn(language)
        }
    }
}

/// Label-over-field stack used inside expanded model editors.
struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            field()
        }
    }
}

struct LanguageResourceRow: View {
    let language: UILanguage
    let sourceLanguage: Language
    let targetLanguage: Language

    private enum PackState {
        case checking, installed, unsupported, available, downloading, failed
    }

    @State private var packState: PackState = .checking
    @State private var progressText = ""
    @State private var configuration: TranslationSession.Configuration
    @State private var requested = false

    init(language: UILanguage, sourceLanguage: Language, targetLanguage: Language) {
        self.language = language
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        _configuration = State(
            initialValue: TranslationSession.Configuration(source: sourceLanguage.locale, target: targetLanguage.locale))
    }

    var body: some View {
        Group {
            switch packState {
            case .checking:
                Text(L10n.languagesChecking(language))
                    .foregroundStyle(.secondary)
            case .installed:
                Text(L10n.languagesReady(sourceLanguage, targetLanguage, language))
                    .foregroundStyle(.secondary)
            case .unsupported:
                Text(L10n.languagesUnsupported(sourceLanguage, targetLanguage, language))
                    .foregroundStyle(.secondary)
            case .available:
                Button(L10n.downloadLanguage(language)) {
                    startDownload()
                }
            case .downloading:
                Text(progressText)
                    .foregroundStyle(.secondary)
            case .failed:
                VStack(alignment: .leading, spacing: 6) {
                    Text(progressText)
                        .foregroundStyle(.secondary)
                    Button(L10n.downloadLanguage(language)) { startDownload() }
                }
            }
        }
        .task(id: "\(sourceLanguage.rawValue)-\(targetLanguage.rawValue)") {
            requested = false
            configuration = TranslationSession.Configuration(source: sourceLanguage.locale, target: targetLanguage.locale)
            await refreshAvailability()
        }
        .translationTask(configuration) { session in
            guard requested else { return }
            do {
                try await session.prepareTranslation()
                progressText = L10n.languagesDownloading(language)
                let availability = LanguageAvailability()
                for _ in 0..<120 {
                    let state = await availability.status(from: sourceLanguage.locale, to: targetLanguage.locale)
                    if state == .installed {
                        packState = .installed
                        return
                    }
                    if state == .unsupported {
                        packState = .unsupported
                        return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                progressText = L10n.languagesStillDownloading(sourceLanguage, targetLanguage, language)
                packState = .failed
            } catch {
                progressText = L10n.languagesDownloadFailed(language)
                packState = .failed
            }
        }
    }

    private func startDownload() {
        requested = true
        packState = .downloading
        progressText = L10n.languagesPreparing(language)
        configuration.invalidate()
    }

    private func refreshAvailability() async {
        let state = await LanguageAvailability().status(from: sourceLanguage.locale, to: targetLanguage.locale)
        switch state {
        case .installed: packState = .installed
        case .unsupported: packState = .unsupported
        default: packState = .available
        }
    }
}

struct OverlayPositionPicker: View {
    @Binding var selection: OverlayPosition
    let language: UILanguage

    var body: some View {
        HStack(spacing: 12) {
            ForEach(OverlayPosition.allCases, id: \.self) { position in
                Button {
                    selection = position
                } label: {
                    VStack(spacing: 6) {
                        OverlayPositionThumbnail(position: position, isSelected: selection == position)
                        Text(position.displayName(for: language))
                            .font(.caption)
                            .foregroundStyle(selection == position ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OverlayPositionThumbnail: View {
    let position: OverlayPosition
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.45), lineWidth: isSelected ? 2 : 1)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.55))
                    .frame(width: geo.size.width * 0.36, height: 5)
                    .position(indicatorCenter(in: geo.size))
            }
            .padding(1)
        }
        .frame(width: 64, height: 40)
    }

    private func indicatorCenter(in size: CGSize) -> CGPoint {
        let inset: CGFloat = 8
        switch position {
        case .topRight:
            return CGPoint(x: size.width - inset - size.width * 0.18, y: inset + 2.5)
        case .bottomCenter:
            return CGPoint(x: size.width / 2, y: size.height - inset - 2.5)
        case .bottomRight:
            return CGPoint(x: size.width - inset - size.width * 0.18, y: size.height - inset - 2.5)
        }
    }
}

// MARK: - Settings view

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, translation, overlay, history, privacy, about

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .translation: return "character.bubble"
            case .overlay: return "photo.on.rectangle"
            case .history: return "clock"
            case .privacy: return "lock"
            case .about: return "info.circle"
            }
        }

        // Morandi palette: muted but colorful — dusty blue, sage, mauve,
        // mustard, dusty rose and terracotta.
        // Chip gradient in the style of macOS System Settings icons.
        var chipColors: [Color] {
            switch self {
            case .general: return [Color(red: 0.64, green: 0.66, blue: 0.69), Color(red: 0.42, green: 0.45, blue: 0.49)]
            case .translation: return [Color(red: 0.36, green: 0.66, blue: 0.96), Color(red: 0.12, green: 0.44, blue: 0.89)]
            case .overlay: return [Color(red: 0.67, green: 0.56, blue: 0.95), Color(red: 0.45, green: 0.31, blue: 0.81)]
            case .history: return [Color(red: 0.97, green: 0.70, blue: 0.30), Color(red: 0.89, green: 0.52, blue: 0.11)]
            case .privacy: return [Color(red: 0.96, green: 0.45, blue: 0.48), Color(red: 0.85, green: 0.26, blue: 0.30)]
            case .about: return [Color(red: 0.39, green: 0.78, blue: 0.47), Color(red: 0.18, green: 0.62, blue: 0.32)]
            }
        }

        func title(_ lang: UILanguage) -> String {
            switch self {
            case .general: return L10n.tabGeneral(lang)
            case .translation: return L10n.tabTranslation(lang)
            case .overlay: return L10n.tabOverlay(lang)
            case .history: return L10n.tabHistory(lang)
            case .privacy: return L10n.tabPrivacy(lang)
            case .about: return L10n.tabAbout(lang)
            }
        }
    }

    @ObservedObject var state: AppState
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var history: TranslationHistoryController
    @ObservedObject private var autoUpdater: AutoUpdateController
    @State private var selectedPage: Page = .general
    @State private var draggedModelID: UUID?
    @State private var historyExportMessage: String?
    @State private var showingClearHistoryConfirmation = false

    init(state: AppState) {
        self.state = state
        self._settings = ObservedObject(wrappedValue: state.settings)
        self._history = ObservedObject(wrappedValue: state.history)
        self._autoUpdater = ObservedObject(wrappedValue: state.autoUpdater)
    }

    private var lang: UILanguage { settings.uiLanguage }

    private var autoUpdateStatusText: String {
        switch autoUpdater.phase {
        case .idle:
            return "—"
        case .checking:
            return L10n.autoUpdateChecking(lang)
        case .upToDate:
            return L10n.autoUpdateUpToDate(lang)
        case .downloading(let progress):
            return "\(L10n.autoUpdateDownloading(lang)) \(Int(progress * 100))%"
        case .installing:
            return L10n.autoUpdateInstalling(lang)
        case .failed(let message):
            return "\(L10n.autoUpdateFailed(lang))：\(message)"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .onAppear { state.updateSettingsWindowTitle() }
        .onChange(of: settings.uiLanguage) { _, _ in state.updateSettingsWindowTitle() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases) { page in
                sidebarButton(page)
            }
            Spacer()
            Text("Pico v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarButton(_ page: Page) -> some View {
        let selected = selectedPage == page
        let chip = LinearGradient(
            colors: page.chipColors,
            startPoint: .topLeading, endPoint: .bottomTrailing)
        return Button {
            selectedPage = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(page.title(lang))
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            // 整行都可点击（否则透明背景区域点击会穿透）
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedPage.title(lang))
                    .font(.title2.bold())
                pageContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .general: generalPage
        case .translation: translationPage
        case .overlay: overlayPage
        case .history: historyPage
        case .privacy: privacyPage
        case .about: aboutPage
        }
    }

    private func smallToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    // MARK: General

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.groupLaunchTitle(lang)) {
                SettingsRow(label: L10n.enableLiveTranslation(lang)) {
                    smallToggle(Binding(
                        get: { state.enabled },
                        set: { _ in state.toggle() }))
                }
                SettingsRow(label: L10n.launchAtLogin(lang), divider: false) {
                    smallToggle($state.settings.launchAtLogin)
                }
            }
            SettingsGroup(title: L10n.autoUpdateGroupTitle(lang)) {
                SettingsRow(label: L10n.autoUpdateToggle(lang)) {
                    smallToggle($state.settings.autoUpdateEnabled)
                }
                SettingsRow(label: L10n.autoUpdateStatus(lang), divider: false) {
                    Text(autoUpdateStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            SettingsGroup(title: L10n.groupLanguageTitle(lang)) {
                SettingsRow(label: L10n.interfaceLanguage(lang)) {
                    TrailingPicker(width: 160, selection: $settings.uiLanguage) {
                        ForEach(UILanguage.allCases) { language in
                            Text(language.pickerLabel).tag(language)
                        }
                    }
                }
                SettingsRow(label: L10n.accessibility(lang), divider: false) {
                    if state.permissionGranted {
                        Text(L10n.permissionGranted(lang))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(L10n.openSystemSettings(lang)) { state.requestPermission() }
                    }
                }
            }
        }
    }

    // MARK: Translation

    private var translationPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.groupEngineTitle(lang)) {
                SettingsRow(label: L10n.translationBackend(lang)) {
                    TrailingPicker(width: 200, selection: $settings.translationBackend) {
                        ForEach(TranslationBackend.allCases) { backend in
                            Text(backend.displayName(for: lang)).tag(backend)
                        }
                    }
                }
                if settings.translationBackend == .local {
                    SettingsRow(label: L10n.languageResources(lang), divider: false) {
                        LanguageResourceRow(
                            language: lang,
                            sourceLanguage: settings.sourceLanguage,
                            targetLanguage: settings.targetLanguage)
                    }
                }
            }
            SettingsGroup(title: L10n.groupLanguagesTitle(lang)) {
                SettingsRow(label: L10n.sourceLanguage(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.sourceLanguage },
                        set: { source in
                            settings.sourceLanguage = source
                            if settings.targetLanguage == source {
                                settings.targetLanguage = source == .english ? .chinese : .english
                            }
                        })) {
                        ForEach(Language.allCases) { language in
                            Text(languageName(language)).tag(language)
                        }
                    }
                }
                SettingsRow(label: L10n.targetLanguage(lang)) {
                    TrailingPicker(width: 160, selection: $settings.targetLanguage) {
                        ForEach(Language.allCases.filter { $0 != settings.sourceLanguage }) { language in
                            Text(languageName(language)).tag(language)
                        }
                    }
                }
            }
            SettingsGroup(title: L10n.groupLiveInputTitle(lang)) {
                SettingsRow(label: L10n.translationSpeed(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { state.settings.translationSpeed },
                        set: {
                            state.settings.translationSpeed = $0
                            state.input.delayMilliseconds = $0
                        })) {
                        Text(L10n.speedFast(lang)).tag(300)
                        Text(L10n.speedBalanced(lang)).tag(450)
                        Text(L10n.speedRelaxed(lang)).tag(700)
                    }
                }
                SettingsRow(label: L10n.translationTiming(lang), divider: settings.translationTiming == .shortcut) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.translationTiming },
                        set: { state.setTranslationTiming($0) })) {
                        ForEach(TranslationTiming.allCases, id: \.self) { mode in
                            Text(mode.displayName(for: lang)).tag(mode)
                        }
                    }
                }
                if settings.translationTiming == .shortcut {
                    SettingsRow(label: L10n.translateShortcut(lang), divider: false) {
                        ShortcutRecorderButton(
                            language: lang,
                            shortcut: settings.translateShortcut,
                            onCommit: { state.setTranslateShortcut($0) })
                    }
                }
            }
            if settings.translationBackend != .local {
                modelSettingsSection
            }
            SettingsGroup(title: L10n.groupActions(lang)) {
                SettingsRow(label: L10n.replaceOriginal(lang)) {
                    smallToggle(Binding(
                        get: { settings.replaceOriginal },
                        set: { state.setReplaceOriginal($0) }))
                }
                if settings.replaceOriginal {
                    SettingsRow(label: L10n.replaceShortcut(lang)) {
                        ShortcutRecorderButton(
                            language: lang,
                            shortcut: settings.replaceShortcut,
                            onCommit: { state.setReplaceShortcut($0) })
                    }
                }
                SettingsRow(label: L10n.copyTranslation(lang)) {
                    smallToggle(Binding(
                        get: { settings.copyTranslation },
                        set: { state.setCopyTranslation($0) }))
                }
                if settings.copyTranslation {
                    SettingsRow(label: L10n.copyShortcut(lang), divider: false) {
                        ShortcutRecorderButton(
                            language: lang,
                            shortcut: settings.copyShortcut,
                            onCommit: { state.setCopyShortcut($0) })
                    }
                }
            }
            SettingsGroup(title: L10n.groupSpeech(lang)) {
                SettingsRow(label: L10n.readTranslationsAloud(lang), divider: false) {
                    Menu {
                        Toggle(L10n.speechTimingAll(lang), isOn: allSpeechTriggersBinding)
                        Divider()
                        ForEach(SpeechTrigger.allCases) { trigger in
                            Toggle(speechTriggerName(trigger), isOn: speechTriggerBinding(trigger))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(L10n.speechTimingSummary(settings.speechTriggers, lang))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize()
                }
            }
            Text(L10n.speechVoiceHint(settings.targetLanguage, lang))
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsGroup(title: L10n.clipboardGroup(lang)) {
                SettingsRow(label: L10n.clipboardTranslate(lang), divider: settings.clipboardTriggerMode == .hotkey) {
                    smallToggle($settings.clipboardTranslationEnabled)
                }
                if settings.clipboardTranslationEnabled {
                    if settings.clipboardTriggerMode == .hotkey {
                        SettingsRow(label: L10n.clipboardShortcut(lang), divider: false) {
                            ShortcutRecorderButton(
                                language: lang,
                                shortcut: settings.clipboardShortcut,
                                onCommit: { settings.clipboardShortcut = $0 })
                        }
                    } else {
                        SettingsRow(label: L10n.clipboardTrigger(lang), divider: false) {
                            TrailingPicker(width: 160, selection: $settings.clipboardTriggerMode) {
                                ForEach(ClipboardTriggerMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName(for: lang)).tag(mode)
                                }
                            }
                        }
                    }
                }
            }
            if settings.clipboardTranslationEnabled {
                Text(L10n.clipboardHint(lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allSpeechTriggersBinding: Binding<Bool> {
        Binding(
            get: { settings.speechTriggers == .all },
            set: { setSpeechTriggers($0 ? .all : []) })
    }

    private func speechTriggerBinding(_ trigger: SpeechTrigger) -> Binding<Bool> {
        let selection = SpeechTriggerSelection(rawValue: trigger.rawValue)
        return Binding(
            get: { settings.speechTriggers.contains(selection) },
            set: { enabled in
                var updated = settings.speechTriggers
                if enabled {
                    updated.insert(selection)
                } else {
                    updated.remove(selection)
                }
                setSpeechTriggers(updated)
            })
    }

    private func setSpeechTriggers(_ triggers: SpeechTriggerSelection) {
        settings.speechTriggers = triggers
        if triggers.isEmpty { state.speech.stop() }
    }

    private func speechTriggerName(_ trigger: SpeechTrigger) -> String {
        switch trigger {
        case .pause: return L10n.speechTimingPause(lang)
        case .completeSentence: return L10n.speechTimingCompleteSentence(lang)
        case .shortcut: return L10n.speechTimingShortcut(lang)
        }
    }

    private var languageName: (Language) -> String {
        { lang == .chinese ? $0.chineseName : $0.englishName }
    }

    @ViewBuilder
    private var modelSettingsSection: some View {
        SettingsGroup(title: L10n.modelSettings(lang)) {
            SettingsRow(label: L10n.failoverTimeout(lang), divider: settings.llmModels.isEmpty) {
                HStack(spacing: 8) {
                    Slider(value: $settings.llmFallbackTimeout, in: 1...120, step: 1)
                        .frame(width: 130)
                    Text(L10n.timeoutSeconds(lang, Int(settings.llmFallbackTimeout)))
                        .monospacedDigit()
                        .frame(width: 96, alignment: .trailing)
                }
            }
        }
        Text(L10n.apiKeyKeychainHint(lang))
            .font(.caption)
            .foregroundStyle(.secondary)
        if settings.llmModels.isEmpty {
            Group {
                Button(L10n.addModel(lang)) { settings.addLLMModel(defaultModel()) }
                    .buttonStyle(.bordered)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(settings.llmModels) { model in
                    LLMModelEditor(
                        model: model,
                        language: lang,
                        save: { settings.updateLLMModel($0) },
                        remove: { settings.removeLLMModel(id: model.id) })
                        .padding(12)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                        .onDrag {
                            draggedModelID = model.id
                            return NSItemProvider(object: model.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: ModelOrderDropDelegate(
                                targetID: model.id,
                                models: $settings.llmModels,
                                draggedID: $draggedModelID))
                }
            }
        }
        Text(L10n.llmTranslationPrivacy(lang))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func defaultModel() -> LLMModelConfiguration {
        LLMModelConfiguration(
            name: lang == .chinese ? "新的 API 模型" : "New API Model",
            provider: .openAICompatible,
            baseURL: LLMProvider.openAICompatible.defaultBaseURL,
            model: LLMProvider.openAICompatible.defaultModel,
            timeoutSeconds: 0)
    }

    // MARK: Overlay

    private var overlayPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.groupPosition(lang)) {
                SettingsRow(label: L10n.displayPosition(lang), divider: false) {
                    OverlayPositionPicker(
                        selection: Binding(
                            get: { settings.overlayPosition },
                            set: {
                                settings.overlayPosition = $0
                                state.overlay.position = $0
                            }),
                        language: lang)
                }
            }
            SettingsGroup(title: L10n.groupAppearance(lang)) {
                SettingsRow(label: L10n.textSize(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.textSize },
                        set: {
                            settings.textSize = $0
                            state.overlay.textSize = $0
                        })) {
                        ForEach(OverlayTextSize.allCases, id: \.self) { Text($0.displayName(for: lang)).tag($0) }
                    }
                }
                SettingsRow(label: L10n.edgeDistance(lang)) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.overlayEdgeDistance },
                                set: {
                                    settings.overlayEdgeDistance = $0
                                    state.overlay.edgeDistance = $0
                                }), in: 0...300, step: 4)
                            .frame(width: 130)
                        Text("\(Int(settings.overlayEdgeDistance))")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                SettingsRow(label: L10n.overlayOpacity(lang)) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.overlayOpacity },
                                set: {
                                    settings.overlayOpacity = $0
                                    state.overlay.cardOpacity = $0
                                }), in: 0.3...1, step: 0.05)
                            .frame(width: 130)
                        Text("\(Int((settings.overlayOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsRow(label: L10n.overlayTheme(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.overlayTheme },
                        set: {
                            settings.overlayTheme = $0
                            state.overlay.theme = $0
                        })) {
                        ForEach(OverlayTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName(for: lang)).tag(theme)
                        }
                    }
                }
                SettingsRow(label: L10n.overlaySurface(lang), divider: false) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.overlaySurface },
                        set: {
                            settings.overlaySurface = $0
                            state.overlay.surface = $0
                        })) {
                        ForEach(OverlaySurfaceEffect.allCases, id: \.self) { effect in
                            Text(effect.displayName(for: lang)).tag(effect)
                        }
                    }
                }
            }
            SettingsGroup(title: L10n.groupBehavior(lang)) {
                SettingsRow(label: L10n.newTranslationBehavior(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.overlayBehavior },
                        set: {
                            settings.overlayBehavior = $0
                            state.overlay.behavior = $0
                        })) {
                        ForEach(OverlayBehavior.allCases, id: \.self) { Text($0.displayName(for: lang)).tag($0) }
                    }
                }
                SettingsRow(label: L10n.hideAfter(lang)) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.hideAfter },
                                set: {
                                    settings.hideAfter = $0
                                    state.overlay.hideAfter = $0
                                }), in: 5...60, step: 1)
                            .frame(width: 130)
                            .disabled(settings.neverHide)
                        Text(L10n.seconds(lang, Int(settings.hideAfter)))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                SettingsRow(label: L10n.neverHide(lang), divider: false) {
                    smallToggle(Binding(
                        get: { settings.neverHide },
                        set: {
                            settings.neverHide = $0
                            state.overlay.neverHide = $0
                        }))
                }
            }
            Group {
                Button(L10n.previewOverlay(lang)) { state.showOverlayTest() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: History

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: L10n.groupHistoryTitle(lang)) {
                SettingsRow(label: L10n.historyRetention(lang)) {
                    TrailingPicker(width: 160, selection: Binding(
                        get: { settings.historyRetention },
                        set: { settings.historyRetention = $0 })) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(L10n.historyRetentionName(retention, lang)).tag(retention)
                        }
                    }
                }
                SettingsRow(label: L10n.historyExport(lang), divider: false) {
                    HStack(spacing: 8) {
                        Button(L10n.historyClear(lang), role: .destructive) {
                            showingClearHistoryConfirmation = true
                        }
                        .controlSize(.small)
                        .disabled(history.entries.isEmpty)
                        Menu {
                            Button(L10n.historyExportMarkdown(lang)) { exportHistory(.markdown) }
                            Button(L10n.historyExportExcel(lang)) { exportHistory(.excel) }
                        } label: {
                            Label(L10n.historyExport(lang), systemImage: "square.and.arrow.up")
                        }
                    }
                    .confirmationDialog(
                        L10n.historyClearConfirm(lang),
                        isPresented: $showingClearHistoryConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(L10n.historyClearAction(lang), role: .destructive) {
                            history.clearAll()
                            historyExportMessage = nil
                        }
                        Button(L10n.cancelAction(lang), role: .cancel) {}
                    }
                }
            }
            if let historyExportMessage {
                Text(historyExportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = history.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if history.entries.isEmpty {
                Text(L10n.historyEmpty(lang))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                historyTable
            }
        }
        .task { history.reload(retention: settings.historyRetention) }
    }

    private var historyTable: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(historyDayGroups) { group in
                Text(historyDayString(group.day))
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                HStack(alignment: .top, spacing: 12) {
                    Text(L10n.historyIndex(lang)).frame(width: 42, alignment: .trailing)
                    Text(L10n.historyOriginal(lang)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.historyTranslation(lang)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                        Text(entry.sourceText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.translatedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    Divider()
                }
            }
        }
    }

    private var historyDayGroups: [HistoryDayGroup] {
        let calendar = Calendar.current
        var groups: [HistoryDayGroup] = []
        for entry in history.entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if let last = groups.indices.last, calendar.isDate(groups[last].day, inSameDayAs: day) {
                groups[last].entries.append(entry)
            } else {
                groups.append(HistoryDayGroup(day: day, entries: [entry]))
            }
        }
        return groups
    }

    private func historyDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func exportHistory(_ format: HistoryExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Pico-history.\(format.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try TranslationHistoryExporter.export(history.entries, format: format, language: lang, to: url)
                historyExportMessage = url.lastPathComponent
            } catch {
                historyExportMessage = error.localizedDescription
            }
        }
    }

    // MARK: Privacy

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.privacyExplanation(lang))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsGroup(title: L10n.groupExcludedAppsTitle(lang)) {
                ForEach(Array(state.settings.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID, language: lang) {
                        state.settings.excludedBundleIDs.remove(bundleID)
                        state.input.excludedBundleIDs = state.settings.excludedBundleIDs
                        state.monitor.excludedBundleIDs = state.settings.excludedBundleIDs
                    }
                }
                SettingsRow(label: "", divider: false) {
                    Button(L10n.addApplication(lang)) { AddExcludedAppView.openPanel(state: state) }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: About

    private var aboutPage: some View {
        AboutView(language: lang)
            .frame(maxWidth: .infinity)
    }
}

private struct HistoryDayGroup: Identifiable {
    let day: Date
    var entries: [TranslationHistoryEntry]
    var id: Date { day }
}
