import XCTest

@testable import Pico

final class UpdateNotesTests: XCTestCase {
    func testParsesBulletsAndHeaders() {
        let body = """
        ### 本次更新
        - 拖动手感全面修复
        - **菜单栏**图标更稳

        ### 安装提示
        * 覆盖安装保留授权与设置
        """
        let lines = AutoUpdateController.parseReleaseNotes(body)
        XCTAssertEqual(lines, [
            ReleaseNoteLine(isHeader: true, text: "本次更新"),
            ReleaseNoteLine(isHeader: false, text: "拖动手感全面修复"),
            ReleaseNoteLine(isHeader: false, text: "菜单栏图标更稳"),
            ReleaseNoteLine(isHeader: true, text: "安装提示"),
            ReleaseNoteLine(isHeader: false, text: "覆盖安装保留授权与设置"),
        ])
    }

    func testStripsInlineCodeBackticks() {
        let lines = AutoUpdateController.parseReleaseNotes("遇到 `Sign in` 提示时自动重试")
        XCTAssertEqual(lines, [ReleaseNoteLine(isHeader: false, text: "遇到 Sign in 提示时自动重试")])
    }

    func testSkipsBlankLinesAndBulletOnlyLines() {
        let lines = AutoUpdateController.parseReleaseNotes("第一行\n\n- \n\n第二行")
        XCTAssertEqual(lines, [
            ReleaseNoteLine(isHeader: false, text: "第一行"),
            ReleaseNoteLine(isHeader: false, text: "第二行"),
        ])
    }

    func testPlainParagraphHasNoBulletMarker() {
        let lines = AutoUpdateController.parseReleaseNotes("普通段落没有列表符号")
        XCTAssertEqual(lines, [ReleaseNoteLine(isHeader: false, text: "普通段落没有列表符号")])
    }
}
