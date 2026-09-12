import Foundation

enum UILanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum L10n {
    // MARK: - Menu bar

    static func pause(_ lang: UILanguage) -> String {
        lang == .chinese ? "暂停" : "Pause"
    }
    static func resume(_ lang: UILanguage) -> String {
        lang == .chinese ? "继续" : "Resume"
    }
    static func menuSettings(_ lang: UILanguage) -> String {
        lang == .chinese ? "设置…" : "Settings…"
    }
    static func quit(_ lang: UILanguage) -> String {
        lang == .chinese ? "退出" : "Quit"
    }

    // MARK: - Settings chrome

    static func settingsWindowTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "Pico 设置" : "Pico Settings"
    }
    static func tabGeneral(_ lang: UILanguage) -> String {
        lang == .chinese ? "通用" : "General"
    }
    static func tabTranslation(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译" : "Translation"
    }
    static func tabOverlay(_ lang: UILanguage) -> String {
        lang == .chinese ? "悬浮窗" : "Overlay"
    }
    static func tabHistory(_ lang: UILanguage) -> String {
        lang == .chinese ? "历史记录" : "History"
    }
    static func tabPrivacy(_ lang: UILanguage) -> String {
        lang == .chinese ? "隐私" : "Privacy"
    }
    static func tabAbout(_ lang: UILanguage) -> String {
        lang == .chinese ? "关于" : "About"
    }

    static func enableLiveTranslation(_ lang: UILanguage) -> String {
        lang == .chinese ? "启用实时翻译" : "Enable Live Translation"
    }
    static func launchAtLogin(_ lang: UILanguage) -> String {
        lang == .chinese ? "登录时启动" : "Launch at Login"
    }
    static func interfaceLanguage(_ lang: UILanguage) -> String {
        lang == .chinese ? "界面语言" : "Interface Language"
    }
    static func accessibility(_ lang: UILanguage) -> String {
        lang == .chinese ? "辅助功能" : "Accessibility"
    }
    static func permissionGranted(_ lang: UILanguage) -> String {
        lang == .chinese ? "✓ 已授权" : "✓ Authorized"
    }
    static func permissionHint(_ lang: UILanguage) -> String {
        lang == .chinese ? "需要辅助功能权限才能读取输入内容" : "Accessibility permission is required to read typed text"
    }
    static func openSystemSettings(_ lang: UILanguage) -> String {
        lang == .chinese ? "打开系统设置" : "Open System Settings"
    }

    static func translationBackend(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译方式" : "Translation Engine"
    }
    static func backendLocal(_ lang: UILanguage) -> String {
        lang == .chinese ? "macOS 本地翻译" : "macOS On-device"
    }
    static func backendLanguageModel(_ lang: UILanguage) -> String {
        lang == .chinese ? "大语言模型 API" : "Language Model API"
    }
    static func sourceLanguage(_ lang: UILanguage) -> String {
        lang == .chinese ? "源语言" : "Source Language"
    }
    static func targetLanguage(_ lang: UILanguage) -> String {
        lang == .chinese ? "目标语言" : "Target Language"
    }
    static func languagePair(_ source: Language, _ target: Language, _ lang: UILanguage) -> String {
        let sourceName = lang == .chinese ? source.chineseName : source.englishName
        let targetName = lang == .chinese ? target.chineseName : target.englishName
        return "\(sourceName) → \(targetName)"
    }
    static func modelSettings(_ lang: UILanguage) -> String {
        lang == .chinese ? "大语言模型" : "Language Models"
    }
    static func modelSettingsHint(_ lang: UILanguage) -> String {
        lang == .chinese ? "已启用模型会按顺序尝试；超时或失败时自动切换到下一项。" : "Enabled models are tried in order; a timeout or failure advances to the next model."
    }
    static func addModel(_ lang: UILanguage) -> String { lang == .chinese ? "添加模型" : "Add Model" }
    static func removeModel(_ lang: UILanguage) -> String { lang == .chinese ? "删除模型" : "Remove Model" }
    static func modelName(_ lang: UILanguage) -> String { lang == .chinese ? "名称" : "Name" }
    static func provider(_ lang: UILanguage) -> String { lang == .chinese ? "服务商" : "Provider" }
    static func providerName(_ provider: LLMProvider, _ lang: UILanguage) -> String {
        switch provider {
        case .openAICompatible: return lang == .chinese ? "OpenAI 兼容" : "OpenAI compatible"
        case .anthropic: return lang == .chinese ? "Claude（Anthropic）" : "Claude (Anthropic)"
        case .deepSeek: return "DeepSeek"
        case .glm: return lang == .chinese ? "GLM（智谱）" : "GLM (Zhipu)"
        case .custom: return lang == .chinese ? "自定义" : "Custom"
        }
    }
    static func endpointURL(_ lang: UILanguage) -> String { "API URL" }
    static func apiKey(_ lang: UILanguage) -> String { lang == .chinese ? "API 密钥" : "API Key" }
    static func modelID(_ lang: UILanguage) -> String { lang == .chinese ? "模型名称" : "Model ID" }
    static func prompt(_ lang: UILanguage) -> String { lang == .chinese ? "提示词" : "Prompt" }
    static func promptHint(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "已填入默认系统提示词；每次请求会自动附加当前源语言、目标语言和待翻译文本。"
            : "The default system prompt is filled in. Each request also includes the selected languages and source text."
    }
    static func restoreDefaultPrompt(_ lang: UILanguage) -> String {
        lang == .chinese ? "恢复默认提示词" : "Restore Default Prompt"
    }
    static func thinkingMode(_ lang: UILanguage) -> String { lang == .chinese ? "思考模式" : "Reasoning Mode" }
    static func thinkingAutomatic(_ lang: UILanguage) -> String { lang == .chinese ? "自动" : "Automatic" }
    static func thinkingOff(_ lang: UILanguage) -> String { lang == .chinese ? "非思考" : "Non-thinking" }
    static func thinkingOn(_ lang: UILanguage) -> String { lang == .chinese ? "思考" : "Thinking" }
    static func failoverTimeout(_ lang: UILanguage) -> String { lang == .chinese ? "切换超时" : "Fail-over Timeout" }
    static func timeoutSeconds(_ lang: UILanguage, _ value: Int) -> String {
        lang == .chinese ? "超过 \(value) 秒切换" : "Switch after \(value) sec"
    }
    static func apiKeyKeychainHint(_ lang: UILanguage) -> String {
        lang == .chinese ? "API 密钥仅保存于此 Mac 的钥匙串。" : "API keys are stored only in this Mac's Keychain."
    }
    static func modelPlaceholder(_ lang: UILanguage) -> String { lang == .chinese ? "例如：DeepSeek 主模型" : "For example: Primary DeepSeek" }
    static func urlPlaceholder(_ lang: UILanguage) -> String { "https://api.example.com/v1" }
    static func modelIDPlaceholder(_ lang: UILanguage) -> String { lang == .chinese ? "例如：deepseek-chat" : "For example: deepseek-chat" }
    static func promptPlaceholder(_ lang: UILanguage) -> String { lang == .chinese ? "留空使用默认翻译提示词" : "Leave empty to use the default translation prompt" }
    static func noModels(_ lang: UILanguage) -> String { lang == .chinese ? "还没有配置模型。" : "No models configured." }
    static func modelEnabled(_ lang: UILanguage) -> String { lang == .chinese ? "启用" : "Enabled" }
    static func localTranslationPrivacy(_ lang: UILanguage) -> String {
        lang == .chinese ? "本地翻译不会把输入内容发送到网络。" : "On-device translation does not send typed text over the network."
    }
    static func llmTranslationPrivacy(_ lang: UILanguage) -> String {
        lang == .chinese ? "大模型模式会把输入内容发送到所选 API 服务商。" : "Language-model mode sends typed text to the selected API provider."
    }

    static func translationDirection(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译方向" : "Direction"
    }
    static func translationDirectionValue(_ lang: UILanguage) -> String {
        lang == .chinese ? "中文 → 英文" : "Chinese → English"
    }
    static func translationDirectionValue(_ source: Language, _ target: Language, _ lang: UILanguage) -> String {
        languagePair(source, target, lang)
    }
    static func translationSpeed(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译速度" : "Translation Speed"
    }
    static func translationTiming(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译时机" : "Translation Timing"
    }
    static func timingPause(_ lang: UILanguage) -> String {
        lang == .chinese ? "超时翻译" : "On Pause"
    }
    static func timingCompleteSentence(_ lang: UILanguage) -> String {
        lang == .chinese ? "完整句子翻译" : "Complete Sentence"
    }
    static func timingShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "快捷键触发翻译" : "On Shortcut"
    }
    static func historyRetention(_ lang: UILanguage) -> String {
        lang == .chinese ? "保存期限" : "Retention"
    }
    static func historyRetentionName(_ value: HistoryRetention, _ lang: UILanguage) -> String {
        switch value {
        case .oneDay: return lang == .chinese ? "1 天" : "1 Day"
        case .sevenDays: return lang == .chinese ? "7 天" : "7 Days"
        case .thirtyDays: return lang == .chinese ? "30 天" : "30 Days"
        case .sixMonths: return lang == .chinese ? "6 个月" : "6 Months"
        case .forever: return lang == .chinese ? "永久" : "Forever"
        }
    }
    static func historyOriginal(_ lang: UILanguage) -> String { lang == .chinese ? "原文" : "Original" }
    static func historyTranslation(_ lang: UILanguage) -> String { lang == .chinese ? "译文" : "Translation" }
    static func historyIndex(_ lang: UILanguage) -> String { lang == .chinese ? "序号" : "No." }
    static func historyExport(_ lang: UILanguage) -> String { lang == .chinese ? "导出历史记录" : "Export History" }
    static func historyExportMarkdown(_ lang: UILanguage) -> String { lang == .chinese ? "导出 Markdown" : "Export Markdown" }
    static func historyExportExcel(_ lang: UILanguage) -> String { lang == .chinese ? "导出 Excel" : "Export Excel" }
    static func historyExportTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "Pico 历史记录" : "Pico Translation History"
    }
    static func historyEmpty(_ lang: UILanguage) -> String {
        lang == .chinese ? "暂时没有已完成的翻译记录。" : "No completed translations yet."
    }
    static func historyStorageHint(_ lang: UILanguage) -> String {
        lang == .chinese ? "历史记录仅保存在这台 Mac 上。" : "History is stored only on this Mac."
    }
    static func translateShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译快捷键" : "Translate Shortcut"
    }
    static func speedFast(_ lang: UILanguage) -> String {
        lang == .chinese ? "快速" : "Fast"
    }
    static func speedBalanced(_ lang: UILanguage) -> String {
        lang == .chinese ? "均衡" : "Balanced"
    }
    static func speedRelaxed(_ lang: UILanguage) -> String {
        lang == .chinese ? "舒缓" : "Relaxed"
    }
    static func languageResources(_ lang: UILanguage) -> String {
        lang == .chinese ? "语言资源" : "Language Pack"
    }
    static func languagesReady(_ lang: UILanguage) -> String {
        lang == .chinese ? "中文 → 英文 · 已就绪 ✓" : "Chinese → English · Ready ✓"
    }
    static func languagesReady(_ source: Language, _ target: Language, _ lang: UILanguage) -> String {
        lang == .chinese ? "\(languagePair(source, target, lang)) · 已就绪 ✓" : "\(languagePair(source, target, lang)) · Ready ✓"
    }
    static func languagesUnsupported(_ lang: UILanguage) -> String {
        lang == .chinese ? "此 Mac 不支持中文 → 英文" : "Chinese → English is not supported on this Mac"
    }
    static func languagesUnsupported(_ source: Language, _ target: Language, _ lang: UILanguage) -> String {
        lang == .chinese ? "此 Mac 不支持 \(languagePair(source, target, lang))" : "\(languagePair(source, target, lang)) is not supported on this Mac"
    }
    static func downloadLanguage(_ lang: UILanguage) -> String {
        lang == .chinese ? "下载语言" : "Download Languages"
    }
    static func languagesChecking(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在检查…" : "Checking…"
    }
    static func languagesPreparing(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在准备下载…" : "Preparing download…"
    }
    static func languagesDownloading(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在下载语言…" : "Downloading languages…"
    }
    static func languagesStillDownloading(_ lang: UILanguage) -> String {
        lang == .chinese ? "下载仍在进行，请稍后在系统设置中查看。" : "Download still in progress. Check Language & Region."
    }
    static func languagesStillDownloading(_ source: Language, _ target: Language, _ lang: UILanguage) -> String {
        lang == .chinese ? "\(languagePair(source, target, lang)) 仍在下载，请稍后查看系统设置。" : "\(languagePair(source, target, lang)) is still downloading. Check System Settings later."
    }
    static func languagesDownloadFailed(_ lang: UILanguage) -> String {
        lang == .chinese ? "语言下载未完成。" : "Language download was not completed."
    }
    static func groupActions(_ lang: UILanguage) -> String {
        lang == .chinese ? "快捷操作" : "Actions"
    }
    static func replaceOriginal(_ lang: UILanguage) -> String {
        lang == .chinese ? "替换原文" : "Replace Original"
    }
    static func replaceShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "替换快捷键" : "Replace Shortcut"
    }
    static func copyTranslation(_ lang: UILanguage) -> String {
        lang == .chinese ? "复制译文" : "Copy Translation"
    }
    static func copyShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "复制快捷键" : "Copy Shortcut"
    }
    static func shortcutRecording(_ lang: UILanguage) -> String {
        lang == .chinese ? "按下快捷键…" : "Press a shortcut…"
    }
    static func replaceOriginalHint(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "按下快捷键，把当前译文写回输入框。"
            : "Press the shortcut to replace the field with the current translation."
    }
    static func copyTranslationHint(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "按下快捷键把当前英文译文复制到剪贴板。"
            : "Press the shortcut to copy the current English translation."
    }
    static func groupSpeech(_ lang: UILanguage) -> String {
        lang == .chinese ? "朗读" : "Speech"
    }
    static func readTranslationsAloud(_ lang: UILanguage) -> String {
        lang == .chinese ? "朗读翻译结果" : "Read Translations Aloud"
    }
    static func speechTimingAll(_ lang: UILanguage) -> String {
        lang == .chinese ? "全部时机" : "All Translation Events"
    }
    static func speechTimingNone(_ lang: UILanguage) -> String {
        lang == .chinese ? "不朗读" : "Never"
    }
    static func speechTimingPause(_ lang: UILanguage) -> String {
        lang == .chinese ? "超时翻译" : "On Pause"
    }
    static func speechTimingCompleteSentence(_ lang: UILanguage) -> String {
        lang == .chinese ? "完整句子翻译" : "Complete Sentence"
    }
    static func speechTimingShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "快捷键触发翻译" : "On Shortcut"
    }
    static func speechTimingSummary(_ selection: SpeechTriggerSelection, _ lang: UILanguage) -> String {
        if selection.isEmpty { return speechTimingNone(lang) }
        if selection == .all { return speechTimingAll(lang) }
        return SpeechTrigger.allCases.compactMap { trigger in
            let triggerSelection = SpeechTriggerSelection(rawValue: trigger.rawValue)
            guard selection.contains(triggerSelection) else { return nil }
            switch trigger {
            case .pause: return speechTimingPause(lang)
            case .completeSentence: return speechTimingCompleteSentence(lang)
            case .shortcut: return speechTimingShortcut(lang)
            }
        }
        .joined(separator: lang == .chinese ? "、" : ", ")
    }
    static func speechVoiceHint(_ target: Language, _ lang: UILanguage) -> String {
        let languageName = lang == .chinese ? target.chineseName : target.englishName
        return lang == .chinese
            ? "朗读会使用此 Mac 上\(languageName)的默认系统语音。"
            : "Speech uses this Mac’s default \(languageName) system voice."
    }

    static func groupPosition(_ lang: UILanguage) -> String {
        lang == .chinese ? "位置" : "Position"
    }
    static func groupAppearance(_ lang: UILanguage) -> String {
        lang == .chinese ? "外观" : "Appearance"
    }
    static func groupBehavior(_ lang: UILanguage) -> String {
        lang == .chinese ? "行为" : "Behavior"
    }
    static func displayPosition(_ lang: UILanguage) -> String {
        lang == .chinese ? "显示位置" : "Placement"
    }
    static func textSize(_ lang: UILanguage) -> String {
        lang == .chinese ? "文字大小" : "Text Size"
    }
    static func edgeDistance(_ lang: UILanguage) -> String {
        lang == .chinese ? "距顶部距离" : "Edge Distance"
    }
    static func newTranslationBehavior(_ lang: UILanguage) -> String {
        lang == .chinese ? "新翻译出现时" : "When a new translation appears"
    }
    static func hideAfter(_ lang: UILanguage) -> String {
        lang == .chinese ? "隐藏时间" : "Hide After"
    }
    static func seconds(_ lang: UILanguage, _ value: Int) -> String {
        lang == .chinese ? "\(value) 秒" : "\(value) sec"
    }
    static func neverHide(_ lang: UILanguage) -> String {
        lang == .chinese ? "永不隐藏" : "Never hide"
    }
    static func previewOverlay(_ lang: UILanguage) -> String {
        lang == .chinese ? "预览悬浮窗" : "Preview Overlay"
    }

    static func positionTopRight(_ lang: UILanguage) -> String {
        lang == .chinese ? "右上" : "Top Right"
    }
    static func positionBottomCenter(_ lang: UILanguage) -> String {
        lang == .chinese ? "底部居中" : "Bottom Center"
    }
    static func positionBottomRight(_ lang: UILanguage) -> String {
        lang == .chinese ? "右下" : "Bottom Right"
    }
    static func sizeSmall(_ lang: UILanguage) -> String {
        lang == .chinese ? "小" : "Small"
    }
    static func sizeMedium(_ lang: UILanguage) -> String {
        lang == .chinese ? "中" : "Medium"
    }
    static func sizeLarge(_ lang: UILanguage) -> String {
        lang == .chinese ? "大" : "Large"
    }
    static func behaviorReplace(_ lang: UILanguage) -> String {
        lang == .chinese ? "替换上一条" : "Replace Previous"
    }
    static func behaviorStack(_ lang: UILanguage) -> String {
        lang == .chinese ? "向下堆叠" : "Stack Below"
    }

    static func privacyExplanation(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "Pico 不会读取或翻译以下应用内的文本。"
            : "Pico will not read or translate text inside these apps."
    }
    static func addApplication(_ lang: UILanguage) -> String {
        lang == .chinese ? "＋ 添加应用…" : "+ Add Application…"
    }
    static func unknownApp(_ lang: UILanguage) -> String {
        lang == .chinese ? "未知应用" : "Unknown App"
    }

    // MARK: - Overlay appearance

    static func overlayOpacity(_ lang: UILanguage) -> String {
        lang == .chinese ? "悬浮窗透明度" : "Overlay Opacity"
    }
    static func overlayTheme(_ lang: UILanguage) -> String {
        lang == .chinese ? "主题色" : "Accent Color"
    }
    static func overlaySurface(_ lang: UILanguage) -> String {
        lang == .chinese ? "背景效果" : "Background"
    }
    static func themeSystem(_ lang: UILanguage) -> String {
        lang == .chinese ? "跟随系统" : "System"
    }
    static func themeBlue(_ lang: UILanguage) -> String {
        lang == .chinese ? "蓝色" : "Blue"
    }
    static func themeGreen(_ lang: UILanguage) -> String {
        lang == .chinese ? "绿色" : "Green"
    }
    static func themePurple(_ lang: UILanguage) -> String {
        lang == .chinese ? "紫色" : "Purple"
    }
    static func themeOrange(_ lang: UILanguage) -> String {
        lang == .chinese ? "橙色" : "Orange"
    }
    static func themePink(_ lang: UILanguage) -> String {
        lang == .chinese ? "粉色" : "Pink"
    }
    static func surfaceFrost(_ lang: UILanguage) -> String {
        lang == .chinese ? "毛玻璃" : "Frosted"
    }
    static func surfaceGlass(_ lang: UILanguage) -> String {
        lang == .chinese ? "轻透玻璃" : "Thin Glass"
    }
    static func surfaceThick(_ lang: UILanguage) -> String {
        lang == .chinese ? "厚实" : "Thick"
    }
    static func surfaceSolid(_ lang: UILanguage) -> String {
        lang == .chinese ? "纯色" : "Solid"
    }

    // MARK: - Clipboard translation

    static func clipboardGroup(_ lang: UILanguage) -> String {
        lang == .chinese ? "剪贴板翻译" : "Clipboard Translation"
    }
    static func clipboardTranslate(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译复制的文字" : "Translate Copied Text"
    }
    static func clipboardTrigger(_ lang: UILanguage) -> String {
        lang == .chinese ? "触发方式" : "Trigger"
    }
    static func triggerHotkey(_ lang: UILanguage) -> String {
        lang == .chinese ? "快捷键" : "Hotkey"
    }
    static func triggerAuto(_ lang: UILanguage) -> String {
        lang == .chinese ? "自动监听" : "Auto Watch"
    }
    static func clipboardShortcut(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译快捷键" : "Hotkey"
    }
    static func clipboardHint(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "在任意应用按快捷键翻译剪贴板内容；自动监听模式下，复制包含源语言的内容即弹出译文。"
            : "Press the hotkey in any app to translate the clipboard. In auto-watch mode, copying text in the source language shows the translation."
    }

    // MARK: - Settings groups

    static func groupLaunchTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "启动" : "Launch"
    }
    static func groupLanguageTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "语言与权限" : "Language & Permission"
    }
    static func groupEngineTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "翻译引擎" : "Engine"
    }
    static func groupLanguagesTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "语言方向" : "Languages"
    }
    static func groupLiveInputTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "输入翻译" : "Live Input"
    }
    static func groupHistoryTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "保留与导出" : "Retention & Export"
    }
    static func groupExcludedAppsTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "排除的应用" : "Excluded Apps"
    }

    // MARK: - Auto update

    static func autoUpdateGroupTitle(_ lang: UILanguage) -> String {
        lang == .chinese ? "自动更新" : "Software Update"
    }
    static func autoUpdateToggle(_ lang: UILanguage) -> String {
        lang == .chinese ? "自动安装更新" : "Install Updates Automatically"
    }
    static func autoUpdateStatus(_ lang: UILanguage) -> String {
        lang == .chinese ? "状态" : "Status"
    }
    static func autoUpdateChecking(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在检查更新…" : "Checking for updates…"
    }
    static func autoUpdateUpToDate(_ lang: UILanguage) -> String {
        lang == .chinese ? "已是最新版本" : "Up to date"
    }
    static func autoUpdateDownloading(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在下载更新" : "Downloading update"
    }
    static func autoUpdateInstalling(_ lang: UILanguage) -> String {
        lang == .chinese ? "准备完成，即将自动重启安装…" : "Ready — restarting to install…"
    }
    static func autoUpdateFailed(_ lang: UILanguage) -> String {
        lang == .chinese ? "更新失败" : "Update failed"
    }

    // MARK: - History safety

    static func historyClear(_ lang: UILanguage) -> String {
        lang == .chinese ? "清空历史" : "Clear History"
    }
    static func historyClearConfirm(_ lang: UILanguage) -> String {
        lang == .chinese ? "确定要删除全部翻译历史吗？此操作不可恢复。" : "Delete all translation history? This cannot be undone."
    }
    static func historyClearAction(_ lang: UILanguage) -> String {
        lang == .chinese ? "全部删除" : "Delete All"
    }
    static func cancelAction(_ lang: UILanguage) -> String {
        lang == .chinese ? "取消" : "Cancel"
    }

    // MARK: - About

    static func productName(_ lang: UILanguage) -> String {
        "Pico"
    }
    static func version(
        _ lang: UILanguage,
        marketing: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) -> String {
        let value = marketing ?? ""
        return lang == .chinese ? "版本 \(value)" : "Version \(value)"
    }
    static func checkForUpdates(_ lang: UILanguage) -> String {
        lang == .chinese ? "检查更新" : "Check for Updates"
    }
    static func checkForUpdatesChecking(_ lang: UILanguage) -> String {
        lang == .chinese ? "正在检查…" : "Checking…"
    }
    static func checkForUpdatesUpToDate(_ lang: UILanguage) -> String {
        lang == .chinese ? "已是最新版本" : "You’re up to date"
    }
    static func checkForUpdatesFailed(_ lang: UILanguage) -> String {
        lang == .chinese ? "检查更新失败" : "Couldn’t check for updates"
    }
    static func aboutBody(_ lang: UILanguage) -> String {
        lang == .chinese
            ? "一款安静、实时的多语言翻译工具。\n输入框实时翻译 + 剪贴板翻译，低打扰浮窗显示。\n默认本地翻译，内容不出设备。\n\nMIT 开源许可证"
            : "A quiet, real-time translation tool.\nLive input translation plus clipboard mode in a low-profile overlay.\nLocal by default; your text stays on device.\n\nMIT License"
    }
    static func aboutProjectRepo(_ lang: UILanguage) -> String {
        lang == .chinese ? "项目仓库" : "Repository"
    }
    static func aboutContactAuthor(_ lang: UILanguage) -> String {
        lang == .chinese ? "联系作者" : "Contact the author"
    }
}
