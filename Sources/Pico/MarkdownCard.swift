import SwiftUI

/// 翻译卡片的轻量 Markdown 渲染。路线：纯本地行级解析＋系统
/// AttributedString 行内样式，零第三方依赖、零网络（Markdown 里的远程
/// 图片一律不加载）。任何解析不确定的内容都按纯文本原样显示——最坏
/// 情况就是「和今天一样」，绝不会更糟。
enum MarkdownCard {
    struct ListItem: Equatable {
        let indent: Int
        let text: String
    }

    struct OrderedItem: Equatable {
        let number: Int
        let text: String
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(items: [ListItem])
        /// 有序列表保留源文本里的真实序号——引擎/原文写几就是几，
        /// 不按渲染下标重编（否则 2/3/4 条目会被重置成 1）。
        case ordered(items: [OrderedItem])
        case code(String)
        case quote(String)
        case divider
    }

    struct Document: Equatable {
        /// 是否检测到 Markdown 强特征（标题/围栏/列表/引用/分隔线）。
        /// 没有强特征的文本按纯文本原样渲染，避免 `2*3*4` 这类误判。
        let isMarkdown: Bool
        let blocks: [Block]
    }

    private static let cjkRange: ClosedRange<UInt32> = 0x4E00...0x9FFF

    /// 行级解析。规则刻意保守：只有行首的强特征才算 Markdown 结构。
    static func parse(_ text: String) -> Document {
        var isMarkdown = false
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [(Int, String)] = []
        var ordered: [OrderedItem] = []
        var quote: [String] = []
        var code: [String]?
        /// 空行延迟处理：列表项之间的空行（引擎输出段落分隔）不断开列表，
        /// 只有空行后接了别的块才真正分段——否则 1/2/3/4 会被拆成四个
        /// 单条列表、每个都从 1 数起（2026-09-20 用户报「全是一」）。
        var pendingBlank = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.reduce("") { acc, line in
                guard !acc.isEmpty else { return line }
                if let last = acc.last, let scalar = last.unicodeScalars.first, cjkRange.contains(scalar.value) {
                    return acc + line
                }
                return acc + " " + line
            }
            blocks.append(.paragraph(joined))
            paragraph = []
        }
        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bullet(items: bullets.map { ListItem(indent: $0, text: $1) }))
            bullets = []
        }
        func flushOrdered() {
            guard !ordered.isEmpty else { return }
            blocks.append(.ordered(items: ordered))
            ordered = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushOrdered()
            flushQuote()
            pendingBlank = false
        }

        for line in text.components(separatedBy: .newlines) {
            if code != nil {
                // 围栏代码块：内容原样保留，直到闭合围栏
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(line)
                }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushAll()
                isMarkdown = true
                code = []
                continue
            }
            if line.isEmpty || line.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingBlank = true
                continue
            }
            if let match = headingMatch(line) {
                flushAll()
                isMarkdown = true
                blocks.append(.heading(level: match.level, text: match.content))
                continue
            }
            if isDivider(line) {
                flushAll()
                isMarkdown = true
                blocks.append(.divider)
                continue
            }
            if let match = bulletMatch(line) {
                if pendingBlank && bullets.isEmpty { flushAll() }
                flushParagraph()
                flushOrdered()
                flushQuote()
                isMarkdown = true
                pendingBlank = false
                bullets.append((match.indent, match.content))
                continue
            }
            if let match = orderedMatch(line) {
                if pendingBlank && ordered.isEmpty { flushAll() }
                flushParagraph()
                flushBullets()
                flushQuote()
                isMarkdown = true
                pendingBlank = false
                ordered.append(match)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                flushOrdered()
                isMarkdown = true
                quote.append(String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1)))
                continue
            }
            flushBullets()
            flushOrdered()
            flushQuote()
            if pendingBlank {
                // 空行后的普通段落行：段落照旧分段
                flushParagraph()
                pendingBlank = false
            }
            paragraph.append(line)
        }
        if let code {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushAll()
        // 行内强特征：双星（加粗）/双反引号（行内码）/双波浪（删除线）。
        // 单星算术（2*3*4）不会被误判。
        if !isMarkdown,
            text.contains("**") || text.contains("``") || text.contains("~~") {
            isMarkdown = true
            blocks = [.paragraph(text)]
        }
        if !isMarkdown {
            return Document(isMarkdown: false, blocks: [.paragraph(text)])
        }
        return Document(isMarkdown: true, blocks: blocks)
    }

    /// 行内样式转 AttributedString：加粗/斜体/行内代码/删除线/链接。
    /// 链接只保留样式（accent+下划线）并剥掉可点击属性——卡片是拿来
    /// 读的，不误触打开陌生网页。解析不抛错，失败回退原字符串。
    /// 破损配对兜底：LLM 译文常把配对的 ** 挪错位置，Foundation 判定无法
    /// 闭合后原样露出字面 **。此时按 ** 切分、奇数段渲染为粗体——即使标
    /// 记错位，加粗效果照样显示。
    static func inline(
        _ text: String, fontSize: CGFloat, accentColor: Color, weight: Font.Weight = .medium
    ) -> AttributedString {
        let base = Font.system(size: fontSize, weight: weight)
        var attributed = convertedInline(text, base: base, accent: accentColor)
        guard String(attributed.characters).contains("**") else { return attributed }
        // 首轮解析仍残留字面 **（标记被引擎挪错位、配对破损）——按 ** 切分，
        // 奇数段渲染为粗体
        let segments = String(attributed.characters).components(separatedBy: "**")
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            var part = AttributedString(segment)
            part.swiftUI.font = index % 2 == 1 ? base.bold() : base
            result.append(part)
        }
        return result
    }

    private static func convertedInline(
        _ text: String, base: Font, accent: Color
    ) -> AttributedString {
        if var parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // 先收集 run 信息再逐段赋属性（边遍历边改会失效）
            let runInfos = parsed.runs.map { run in
                (range: run.range, intent: run.inlinePresentationIntent, hasLink: run.link != nil)
            }
            for info in runInfos {
                var font = base
                if let intent = info.intent {
                    if intent.contains(.code) { font = font.monospaced() }
                    if intent.contains(.stronglyEmphasized) { font = font.bold() }
                    if intent.contains(.emphasized) { font = font.italic() }
                }
                parsed[info.range].swiftUI.font = font
                if let intent = info.intent, intent.contains(.strikethrough) {
                    parsed[info.range].swiftUI.strikethroughStyle = .single
                }
                if info.hasLink {
                    // 链接只留样式：剥掉可点击属性，避免误触打开陌生网页
                    parsed[info.range].link = nil
                    parsed[info.range].swiftUI.underlineStyle = .single
                    parsed[info.range].swiftUI.foregroundColor = accent
                }
            }
            return parsed
        }
        var plain = AttributedString(text)
        plain.swiftUI.font = base
        return plain
    }

    // MARK: - 行模式匹配

    private static func headingMatch(_ line: String) -> (level: Int, content: String)? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, level < line.count else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletMatch(_ line: String) -> (indent: Int, content: String)? {
        var indent = 0
        for char in line {
            if char == " " { indent += 1 } else if char == "\t" { indent += 4 } else { break }
        }
        let rest = line.dropFirst(indent)
        guard let marker = rest.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let after = rest.dropFirst()
        guard after.first == " " || after.first == "\t" else { return nil }
        return (indent, after.trimmingCharacters(in: .whitespaces))
    }

    private static func orderedMatch(_ line: String) -> OrderedItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return nil }
        let marker = trimmed[trimmed.startIndex..<spaceIndex]
        guard marker.count <= 9, marker.hasSuffix("."),
              let number = Int(marker.dropLast()) else { return nil }
        return OrderedItem(number: number, text: String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let distinct = Set(trimmed)
        return distinct.count == 1 && (distinct.contains("-") || distinct.contains("*") || distinct.contains("_"))
    }
}

/// 渲染视图：Markdown 按块排版；非 Markdown 文本与旧行为完全一致
/// （单段 Text，字号/主题由外部环境与参数控制）。
struct MarkdownCardBodyView: View {
    let text: String
    let fontSize: CGFloat
    let accentColor: Color

    var body: some View {
        let document = MarkdownCard.parse(text)
        if document.isMarkdown {
            VStack(alignment: .leading, spacing: fontSize * 0.55) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        } else {
            plainBody(text)
        }
    }

    @ViewBuilder private func blockView(_ block: MarkdownCard.Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(MarkdownCard.inline(
                content, fontSize: headingFontSize(level), accentColor: accentColor, weight: .bold))
                .foregroundStyle(.primary)
        case .paragraph(let content):
            Text(MarkdownCard.inline(content, fontSize: fontSize, accentColor: accentColor))
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: fontSize * 0.35) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: fontSize * 0.4) {
                        Text("•").font(.system(size: fontSize, weight: .medium))
                        Text(MarkdownCard.inline(item.text, fontSize: fontSize, accentColor: accentColor))
                            .font(.system(size: fontSize, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * fontSize * 0.3)
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: fontSize * 0.35) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: fontSize * 0.4) {
                        Text("\(item.number).")
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(MarkdownCard.inline(item.text, fontSize: fontSize, accentColor: accentColor))
                            .font(.system(size: fontSize, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code):
            Text(code)
                .font(.system(size: max(10, fontSize - 1), weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 3)
                Text(MarkdownCard.inline(content, fontSize: fontSize, accentColor: accentColor))
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Divider()
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        let scales = [1.5, 1.35, 1.2, 1.1, 1.0, 1.0]
        let index = min(max(level - 1, 0), scales.count - 1)
        return fontSize * scales[index]
    }

    private func plainBody(_ content: String) -> some View {
        Text(content)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
