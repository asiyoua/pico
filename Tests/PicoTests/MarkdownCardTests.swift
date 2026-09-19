import SwiftUI
import XCTest

@testable import Pico

final class MarkdownCardTests: XCTestCase {
    func testPlainChineseStaysPlainWithoutAnyMarkdownGuessing() {
        let document = MarkdownCard.parse("今天天气不错，适合出门散步。")
        XCTAssertFalse(document.isMarkdown)
        XCTAssertEqual(document.blocks, [.paragraph("今天天气不错，适合出门散步。")])
    }

    func testMathAsterisksAreNotMistakenForEmphasis() {
        // 没有块级强特征、也没有双星行内特征的文本不启用 Markdown
        let document = MarkdownCard.parse("2*3*4 等于 24")
        XCTAssertFalse(document.isMarkdown)
    }

    func testInlineOnlyBoldTextIsDetectedAsMarkdown() {
        // 双星行内特征（AI 输出最常见的形态）也必须启用渲染
        let document = MarkdownCard.parse("这是**加粗**和*斜体*的混排段落。")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(document.blocks.count, 1)
        if case .paragraph(let text) = document.blocks[0] {
            XCTAssertEqual(text, "这是**加粗**和*斜体*的混排段落。")
        } else {
            XCTFail("应为单段落块")
        }
    }

    func testHeadingLevelAndTrailingParagraph() {
        let document = MarkdownCard.parse("### 标题\n正文内容")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(
            document.blocks,
            [.heading(level: 3, text: "标题"), .paragraph("正文内容")])
    }

    func testBulletItemsGroupUntilBlankLine() {
        let document = MarkdownCard.parse("- 甲\n- 乙\n\n收尾段落")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(
            document.blocks,
            [.bullet(items: [
                MarkdownCard.ListItem(indent: 0, text: "甲"),
                MarkdownCard.ListItem(indent: 0, text: "乙"),
            ]), .paragraph("收尾段落")])
    }

    func testOrderedItems() {
        let document = MarkdownCard.parse("1. 第一\n2. 第二")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(document.blocks, [.ordered(items: ["第一", "第二"])])
    }

    func testFencedCodeKeepsLinesVerbatimAndStripsLanguage() {
        let document = MarkdownCard.parse("```swift\nlet a = 1\nlet b = 2\n```")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(document.blocks, [.code("let a = 1\nlet b = 2")])
    }

    func testQuoteLinesMerge() {
        let document = MarkdownCard.parse("> 引用一\n> 引用二")
        XCTAssertTrue(document.isMarkdown)
        XCTAssertEqual(document.blocks, [.quote("引用一\n引用二")])
    }

    func testDividerNeedsThreeIdenticalMarks() {
        XCTAssertTrue(MarkdownCard.parse("---").isMarkdown)
        XCTAssertTrue(MarkdownCard.parse("***").isMarkdown)
        // 行中段出现横杠不算分隔线；行首的「- 」是列表符号、同样不是分隔线
        XCTAssertFalse(MarkdownCard.parse("普通文本-含横杠不是分隔线").isMarkdown)
    }

    func testConsecutiveChineseLinesMergeWithoutSpace() {
        // 有 Markdown 强特征（标题）时，后续连续中文行按段落合并、不留空格
        let document = MarkdownCard.parse("### 标题\n第一行内容\n第二行内容")
        XCTAssertEqual(
            document.blocks,
            [.heading(level: 3, text: "标题"), .paragraph("第一行内容第二行内容")])
    }

    func testPlainTextFallbackKeepsRawTextVerbatim() {
        // 非 Markdown 文本必须原样保留（含换行），和旧行为完全一致
        let document = MarkdownCard.parse("第一行内容\n第二行内容")
        XCTAssertFalse(document.isMarkdown)
        XCTAssertEqual(document.blocks, [.paragraph("第一行内容\n第二行内容")])
    }

    func testInlineKeepsCodeIntentAndStripsLinkTapTarget() {
        let attributed = MarkdownCard.inline(
            "**加粗**与`行内码`以及[链接](https://example.com)",
            fontSize: 13,
            accentColor: .blue)
        var sawCode = false
        var sawLinkRemoved = true
        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.code) == true { sawCode = true }
            if run.link != nil { sawLinkRemoved = false }
        }
        XCTAssertTrue(sawCode, "行内码必须带 code intent")
        XCTAssertTrue(sawLinkRemoved, "链接必须剥掉可点击属性（隐私：不误触打开网页）")
    }

    func testInlineFallsBackGracefullyOnUnbalancedMarkers() {
        let attributed = MarkdownCard.inline("**没闭合的加粗", fontSize: 13, accentColor: .blue)
        XCTAssertEqual(String(attributed.characters), "**没闭合的加粗")
    }

    func testInlineStrikethroughGetsLineStyle() {
        let attributed = MarkdownCard.inline("~~划掉~~", fontSize: 13, accentColor: .blue)
        var hasStyle = false
        for run in attributed.runs where run.swiftUI.strikethroughStyle != nil {
            hasStyle = true
        }
        XCTAssertTrue(hasStyle, "删除线必须映射到 strikethroughStyle")
    }
}
