import XCTest

@testable import Pico

final class EngineOutputRegressionTests: XCTestCase {
    /// 本地引擎对本条 Markdown 源的真实输出形态（从用户机器复制按钮探针取得）
    private let engineOutput = """
    # First-level title

    This is a mixed paragraph of **bold** and *italic* and `in-line code`.

    ## Secondary title

    - List Item One

    - List item two

    > Reference content test

    ````swift

    Let a=1

    Let b=2
    ````

    The end.
    """

    func testEngineOutputIsDetectedAsMarkdown() {
        XCTAssertTrue(MarkdownCard.parse(engineOutput).isMarkdown)
    }

    func testEngineOutputBlockStructure() {
        let blocks = MarkdownCard.parse(engineOutput).blocks
        guard case .heading(let level, let text) = blocks.first else {
            return XCTFail("首块应是标题：\(blocks)")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "First-level title")
        // 空行分隔的列表项各自成组也在预期内，关键是代码块围栏要闭合
        XCTAssertTrue(blocks.contains { block in
            if case .code(let code) = block { return code.contains("Let a=1") }
            return false
        })
        XCTAssertTrue(blocks.contains { block in
            if case .quote(let content) = block { return content.contains("Reference content test") }
            return false
        })
    }

    func testEngineOutputParagraphCarriesInlineStyles() {
        let attributed = MarkdownCard.inline(
            "This is a mixed paragraph of **bold** and *italic* and `in-line code`.",
            fontSize: 13,
            accentColor: .blue)
        let text = String(attributed.characters)
        XCTAssertFalse(text.contains("**"), "加粗标记必须被解析掉")
        XCTAssertFalse(text.contains("`"), "反引号必须被解析掉")
    }
}
