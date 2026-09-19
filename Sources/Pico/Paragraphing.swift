import Foundation

/// 阅读器类应用（微信读书等）的复制会把整个选区压成没有换行符的一整串，
/// 译文随之糊成一片。送翻前按句子边界重建段落；只处理足够长且完全没有
/// 换行的文本，已有换行的选区视为自带结构，原样放行。
enum TextParagraphing {
    /// 短于该值的文本不重建：几句话连着仍然可读。
    static let minimumLength = 160
    /// 句子累积到该长度附近就断出一段。
    static let targetParagraphLength = 180

    static let sentenceEnders: Set<Character> = ["。", "！", "？", "；", ".", "?", "!", ";"]
    /// 句末标点之后可能紧跟的收尾符号，断句断在它们后面。
    static let closingMarks: Set<Character> = [
        "”", "』", "」", "）", ")", "\"", "’", "'", "\u{200B}",
    ]
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "st", "sr", "jr", "vs", "etc",
        "e.g", "i.e", "no", "fig", "approx", "inc", "ltd", "co", "al",
    ]

    static func restoreParagraphBreaks(_ text: String) -> String {
        guard text.count >= minimumLength, !text.contains("\n") else { return text }
        let units = sentenceUnits(in: text)
        guard units.count > 1 else { return text }

        var paragraphs: [String] = []
        var current = ""
        for unit in units {
            if !current.isEmpty, current.count + unit.count > targetParagraphLength {
                paragraphs.append(current)
                current = unit
            } else {
                current += unit
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        guard paragraphs.count > 1 else { return text }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func sentenceUnits(in text: String) -> [String] {
        var units: [String] = []
        var unitStart = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            if sentenceEnders.contains(text[index]), endsSentence(in: text, at: index) {
                var end = text.index(after: index)
                while end < text.endIndex, closingMarks.contains(text[end]) {
                    end = text.index(after: end)
                }
                // 句后空白归入刚结束的句子，段落断开处才不会丢空格。
                while end < text.endIndex, text[end].isWhitespace || text[end] == "\u{200B}" {
                    end = text.index(after: end)
                }
                units.append(String(text[unitStart..<end]))
                unitStart = end
                index = end
            } else {
                index = text.index(after: index)
            }
        }
        if unitStart < text.endIndex {
            units.append(String(text[unitStart...]))
        }
        return units
    }

    /// 中文标点总是句末；英文句点要躲开小数（点后无空白）、缩写词
    /// （Dr. / e.g. / U.S.）和「点后接小写」的情况。
    private static func endsSentence(in text: String, at index: String.Index) -> Bool {
        guard text[index] == "." else { return true }
        let next = text.index(after: index)
        guard next < text.endIndex, text[next].isWhitespace else { return false }
        if isAbbreviation(in: text, beforeDot: index) { return false }
        var probe = next
        while probe < text.endIndex,
            text[probe].isWhitespace || text[probe] == "\u{200B}"
        {
            probe = text.index(after: probe)
        }
        guard probe < text.endIndex else { return true }
        let following = text[probe]
        if following.isUppercase { return true }
        if let scalar = following.unicodeScalars.first, (0x4E00...0x9FFF).contains(scalar.value) {
            return true
        }
        return "“\"‘'(（—–-".contains(following)
    }

    private static func isAbbreviation(in text: String, beforeDot dotIndex: String.Index) -> Bool {
        var token = ""
        var probe = dotIndex
        while probe > text.startIndex, token.count < 8 {
            let previous = text.index(before: probe)
            let character = text[previous]
            guard character.isLetter || character == "." else { break }
            token = String(character) + token
            probe = previous
        }
        if token.count == 1, let only = token.first, only.isUppercase { return true }
        if token.contains("."), token.allSatisfy({ $0.isUppercase || $0 == "." }) { return true }
        return abbreviations.contains(token.lowercased())
    }
}
