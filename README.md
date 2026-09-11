# Pico 皮可

[下载最新版](https://github.com/asiyoua/pico/releases) · 问题反馈：[Issues](https://github.com/asiyoua/pico/issues)

Pico（皮可）是一只住在你菜单栏里的 macOS 实时翻译小助手：在支持无障碍（Accessibility）的文本输入框中打字，译文以低打扰浮窗实时浮现；微信这类不暴露无障碍接口的应用，复制一下按 ⌥⇧V 也能翻译。
名字取自物理词头 pico-（10⁻¹²）——又小又快。

## 功能亮点

**输入实时翻译**
- 停止输入片刻即出译文（快 / 均衡 / 慢三档防抖），也可改为整句翻译或快捷键触发（默认 ⌃⇧T）
- 译文可写回输入框（⌥⇧[）或复制（⌥⇧]），快捷键均可改
- 按句子识别，同一句动态更新，最多 3 个浮窗并存

**剪贴板翻译——专为微信等应用而生**

> **为什么需要它？** 微信等部分应用的聊天窗口不向 macOS 系统开放无障碍（Accessibility）接口，系统层面任何实时翻译工具都无法读取其中正在输入的文字——这是应用自身的限制，不是 Pico 的问题。因此 Pico 专门提供了剪贴板翻译：在这类应用里正常选中文字按 ⌘C 复制，再按 ⌥⇧V 即可出译文；而支持无障碍的应用（浏览器、备忘录、办公软件等）则照常自动实时翻译，无需任何操作。

- 任意应用复制文字后按 **⌥⇧V**（可改），译文浮窗立即弹出
- 自动监听模式：复制包含源语言的内容即自动翻译，代码与链接不干扰

**悬浮窗**
- 整卡拖动 + 位置记忆，新译文跟随你拖到的位置
- 自动避开当前输入框，不遮挡正在打的字
- 透明度 30%–100% 实时调节，遮挡内容可直接透视
- 六种主题色 × 四种背景效果（毛玻璃 / 轻透玻璃 / 厚实 / 纯色）
- 右上角一键复制译文，最多同时 3 个浮窗

**翻译引擎**
- macOS 本地翻译：内容不出设备，语言方向支持中 / 英 / 日 / 俄 / 韩 / 法 / 德 / 西任意组合
- 大语言模型 API：OpenAI 兼容接口、Claude、DeepSeek、GLM 与自定义地址；多模型自动故障切换

**其它**
- 朗读译文：时机多选，语音随目标语言自动切换
- 翻译历史本机保存：1 天至永久多档保留，导出 Markdown / Excel，一键清空
- 中英双语界面；支持排除指定应用

## 隐私

- 默认使用 macOS 本地翻译，内容不出设备；选择大语言模型 API 时，文本仅发往你自行配置的服务商
- 无遥测、无统计、无崩溃上报；零第三方依赖
- API 密钥仅存本机钥匙串，禁止 iCloud 同步，不写入偏好设置
- 密码输入框（安全文本框）永不读取
- 翻译历史仅存本机，保留期限可调，支持一键清空（VACUUM 无残留）

## 系统要求

- macOS 15 或更高版本 · Apple Silicon
- 辅助功能权限；本地翻译需对应语言对的系统 Translation 语言包

## 安装

1. 从 [Releases](https://github.com/asiyoua/pico/releases) 下载 DMG，把 Pico 拖入「应用程序」
2. 首次打开：右键点击 → 「打开」（本地签名未公证，Gatekeeper 询问一次）
3. 「系统设置 → 隐私与安全性 → 辅助功能」中开启 Pico
4. 在支持无障碍的输入框打字实时翻译；微信等应用用「复制 + ⌥⇧V」

## 使用提示

- 悬浮窗可以直接拖动，拖过的位置会被记住
- 设置 → 悬浮窗可调整透明度、主题色和背景效果，改动实时生效
- 点击 Dock 图标打开设置窗口，右键 Dock 图标可暂停 / 退出

## 构建和运行

```sh
swift test
zsh Scripts/build-app.sh
open FloatTrans.app
```

应用包、可执行文件与显示名统一为 Pico（Bundle ID 为 `com.asiyoua.pico`）。打包 DMG：

```sh
zsh Scripts/build-dmg.sh
```

对外公开分发建议配置 Developer ID 并公证（`CODESIGN_IDENTITY` / `NOTARY_PROFILE`）。本机构建优先使用名为 `FloatTrans Dev` 的自签名证书，同一证书签名的更新不会触发辅助功能重新授权。

## 图标生成

应用图标与菜单栏图标均为代码生成：

```sh
swift Scripts/make-icon-from-logo.swift pico-logo.png   # 应用图标（icns）
swift Scripts/make-menubar-icon.swift                   # 菜单栏闪电模板图标
```

## 翻译实现

本地翻译使用系统 `Translation` Framework 和本地语言包；语言包缺失时应用会引导下载。大语言模型模式使用用户指定的 API，输入内容仅发往该服务商。剪贴板翻译复用同一翻译管线。

## 项目结构

```text
Sources/Pico/
├── App.swift            应用入口、菜单栏、设置/欢迎窗口、关于页、剪贴板管线
├── SettingsUI.swift     设置窗口（侧边栏导航 + 卡片分组）
├── HotKey.swift         替换 / 复制 / 翻译 / 剪贴板快捷键
├── Input.swift          无障碍监听、文本读取、防抖、剪贴板监听
├── Models.swift         句子提取、翻译协议和协调器
├── Overlay.swift        悬浮窗：拖动、避让、主题、透明度
├── Settings.swift       设置模型和持久化
├── Speech.swift         朗读策略
├── L10n.swift           中英界面文案
├── LLMTranslation.swift 多模型 API 请求与故障切换
├── KeychainStore.swift  API 密钥钥匙串存储
├── UpdateChecker.swift  GitHub 检查更新
├── TranslationHistory.swift 历史存储、清理与导出
└── Diagnostics.swift    本地调试日志
```

## 注意事项

不同应用对 macOS 无障碍 API 的支持程度不同：浏览器、TextEdit 和多数原生应用可以实时翻译；微信等自绘界面应用不向系统暴露文本元素，实时翻译无法支持，请使用剪贴板翻译（复制 + ⌥⇧V）；密码输入框永远跳过，不会被读取。

## 致谢

Pico 的无障碍实时翻译架构基于 [krisir/floattrans](https://github.com/krisir/floattrans) v0.2.0（MIT）演化而来，感谢原作者的出色工作。

## 许可

[MIT](LICENSE)
