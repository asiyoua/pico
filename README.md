# 闪译 FloatTrans（二创版）

> 基于 [krisir/floattrans](https://github.com/krisir/floattrans)（MIT 许可）增强的二创版本。
> **[下载最新版](https://github.com/asiyoua/floattrans/releases)** · 原项目主页：[krisir.github.io/floattrans](https://krisir.github.io/floattrans/)

一款 macOS 实时翻译工具：读取支持无障碍（Accessibility）的文本输入框，按设定的语言方向翻译，以低打扰浮窗显示译文。默认使用 macOS 系统本地翻译，**内容不出设备**。

---

## 二创版特色（相对上游 v0.2.0）

### 剪贴板翻译——微信等应用也能用

- 任何应用里复制文字后按 **⌥⇧V**（可改），译文浮窗立即弹出
- 可选「自动监听」模式：复制包含源语言的内容即自动翻译；纯代码、纯链接不干扰
- 微信 Mac 版不向系统暴露无障碍接口，实时输入翻译无法支持；剪贴板模式是该场景的标准替代方案

### 悬浮窗全面重做

- **整卡拖动**移动，位置自动记忆，后续译文跟随你拖到的位置
- 右上角**一键复制译文**（绿勾反馈），复制不会反向触发翻译
- **自动避开当前输入框**，不再遮挡正在打的字

### 外观自定义

- 透明度 **30%–100%** 实时调节，遮挡内容时可直接透视
- 六种主题色：跟随系统 / 蓝 / 绿 / 紫 / 橙 / 粉
- 四种背景效果：毛玻璃 / 轻透玻璃 / 厚实 / 纯色

### 窗口化与工程加固

- Dock 图标常驻：点击图标直接打开设置窗口，右键菜单可暂停 / 退出
- 固定自签名证书构建：本机重装、升级后**无需反复授权辅助功能**
- 关于页标明原仓库、二创仓库与联系方式，并致谢原开发者

### 隐私与安全

- 默认本地翻译，内容不出设备；**零第三方依赖**，无遥测、无统计、无崩溃上报
- 诊断日志默认关闭，仅记录文本「长度」不记录内容，文件权限 600，超过 1MB 自动清空
- 历史记录支持**一键清空**（VACUUM，无残留），默认 7 天自动过期
- API 密钥仅存本机钥匙串，**禁止 iCloud 同步**，不写入偏好设置
- 密码输入框（安全文本框）永不读取

### 全新品牌

- 全新图标：靛蓝渐变对话气泡 + 「译」 + 闪电徽标（由 `Scripts/make-icon.swift` 纯代码绘制）
- 中文名更新为「**闪译**」——闪一般快的翻译；应用标识与数据位置不变，老用户无缝升级

### 稳定性修复

- 无障碍命中测试坐标换算修正、输入框位置按焦点缓存（对慢无障碍应用更快）
- 翻译缓存加上限（防长期内存增长）、历史记录坏行容错
- 本地调试日志按需开启并限制大小

---

## 基础功能（继承上游）

- 翻译引擎可选 macOS 本地翻译或大语言模型 API
- 源语言与目标语言独立选择：中文、英语、日语、俄语、韩语、法语、德语、西班牙语
- 本地翻译检查当前语言对；缺少系统语言包时可在应用内发起下载
- 支持 OpenAI 兼容接口、Claude、DeepSeek、GLM 和自定义 API URL；可配置模型名、密钥、提示词和思考模式
- 多个 API 模型可拖动排序，超时或失败自动按顺序切换，阈值可配置
- API 密钥保存于 macOS 钥匙串，不写入应用偏好设置
- 翻译历史本机保存：按 1 天 / 7 天 / 30 天 / 6 个月 / 永久保留，导出 Markdown 或 Excel
- 三种翻译时机：停止输入后翻译（默认）、整句翻译、快捷键翻译（默认 ⌃⇧T）
- 写回原文（⌥⇧[）、复制译文（⌥⇧]），快捷键均可改
- 朗读译文：时机多选，语音随目标语言自动切换
- 浮窗最多同时 3 个，替换或堆叠显示，支持右上 / 底部居中 / 右下位置
- 边距、字号、自动隐藏时间（5–60 秒或永不）可调
- 中英双语界面；支持排除指定应用

## 系统要求

- macOS 15 或更高版本
- Swift 6 / Xcode 16 或更高版本（构建）
- 辅助功能权限
- 本地翻译需要对应语言对的系统 Translation 语言包

## 安装（普通用户）

1. 从 [Releases](https://github.com/asiyoua/floattrans/releases) 下载 DMG，把闪译拖入「应用程序」
2. 首次打开：右键点击 → 「打开」（本地签名未公证，Gatekeeper 会询问一次）
3. 「系统设置 → 隐私与安全性 → 辅助功能」中开启闪译
4. 在设置 → 翻译中选择语言方向；微信里翻译用「复制 + ⌥⇧V」

## 构建和运行

```sh
swift test
zsh Scripts/build-app.sh
open FloatTrans.app
```

磁盘上的应用包和可执行文件名为 `FloatTrans`；用户看到的显示名是「闪译」。

## 打 DMG

```sh
zsh Scripts/build-dmg.sh
```

产物在 `dist/FloatTrans-<version>.dmg`。本机构建优先使用名为 `FloatTrans Dev` 的自签名代码签名证书（没有则回退 ad-hoc）：同一证书签名的更新不会再触发辅助功能重新授权。对外公开分发建议配置 Developer ID 并公证：

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="notary"
zsh Scripts/build-dmg.sh
```

## 首次使用

1. 启动闪译，按引导开启辅助功能权限
2. 在设置 → 翻译中选择本地翻译与源语言、目标语言；缺语言包时点击下载并等待完成
3. 在支持无障碍的文本框（浏览器、TextEdit、办公软件等）输入所选源语言，停止输入片刻即出译文
4. 微信等不暴露无障碍的应用：复制文字后按 ⌥⇧V，或在设置 → 翻译 → 剪贴板翻译中开启「自动监听」
5. 如需 API 翻译，切换到「大语言模型 API」并添加模型

## 设置

- 通用：启用翻译、登录时启动、界面语言、辅助功能状态
- 翻译：引擎、语言方向、速度、翻译时机、替换原文、复制译文、朗读、剪贴板翻译（快捷键 / 自动监听）
- API 模型：多模型排序、提供商 / URL / 密钥 / 提示词 / 思考模式、自动切换超时
- 悬浮窗：位置、字号、边距、**透明度**、**主题色**、**背景效果**、隐藏行为、预览
- 历史记录：按日期查看、保留期限、导出、**一键清空**
- 隐私：排除翻译的应用
- 关于：版本、原仓库与二创仓库、检查更新

## 调试日志

默认关闭。需要排查时开启（仅记录文本长度与无障碍元素状态，不记录文本内容，权限 600，超 1MB 自动清空）：

```sh
defaults write cc.kristar.floattrans debugLogEnabled -bool YES
tail -f /tmp/liveenglish-debug.log
defaults write cc.kristar.floattrans debugLogEnabled -bool NO   # 用完关闭
```

## 翻译实现

macOS 本地翻译使用系统 `Translation` Framework 和本地语言包；语言包缺失时应用会引导下载。大语言模型模式仅在用户主动配置后使用，输入内容发往用户指定的服务商。剪贴板翻译复用同一翻译管线。

## 项目结构

```text
Sources/LiveEnglish/
├── App.swift            应用入口、菜单栏、设置/欢迎窗口、关于页、剪贴板管线
├── SettingsUI.swift     设置窗口
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

不同应用对 macOS 无障碍 API 的支持程度不同：TextEdit、浏览器和多数原生应用可正常读取；微信等自绘界面应用不暴露文本元素，请使用剪贴板翻译；密码框永远跳过。

## 致谢与许可

- 原项目：[krisir/floattrans](https://github.com/krisir/floattrans)（MIT），感谢原作者的出色工作
- 本仓库为二创增强版，同样以 MIT 许可发布
- 问题与建议请提 [Issues](https://github.com/asiyoua/floattrans/issues)
