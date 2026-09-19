import XCTest

@testable import Pico

final class ParagraphingTests: XCTestCase {
    func testRebuildsParagraphsFromWeReadStyleRunOn() {
        let source =
            "像我和约翰这样的平凡人，这个夏天居然守着一座祖屋，可真是难得。一幢殖民地豪宅，世袭房产。我真想说这是间鬼屋——那样的话该多浪漫，多么让人开心！——是我想得太美了，那怎么可能。不过我还是要得意地宣布：这房子有些古怪。不然为什么租金这么便宜，而且这么长时间都无人问津？约翰嘲笑了我，不过结了婚嘛，他这么做也在意料之中。约翰是极其讲求实际的人。他对信仰一点儿耐心都没有，觉得那是迷信恐怖，但凡听到别人说起看不见摸不着的事情，他就会毫不留情地咒骂起来。他是个医生，而且可能……（我可不会对哪个活人这么说，不过这张纸是死的，让我放松多了）可能这就是我身体无法好转的原因。你知道吗，他根本不相信我病了！那我还能怎么办？如果你的丈夫是个医术高明的医生，他跟亲朋好友保证你一点事儿都没有，只不过是暂时的神经衰弱，有轻微的歇斯底里倾向——那你能怎么办？我哥哥也是个医生，医术高明，他也说了同样的话。"

        let result = TextParagraphing.restoreParagraphBreaks(source)
        XCTAssertNotEqual(result, source)
        XCTAssertTrue(result.contains("\n\n"))
        // 断段不增删内容：去掉分隔符后与原文完全一致。
        XCTAssertEqual(result.replacingOccurrences(of: "\n\n", with: ""), source)
        for paragraph in result.components(separatedBy: "\n\n") {
            XCTAssertFalse(paragraph.isEmpty)
            // 每段都落在句末标点或收尾符号之后。
            let last = paragraph.last!
            XCTAssertTrue(
                TextParagraphing.sentenceEnders.contains(last)
                    || TextParagraphing.closingMarks.contains(last))
            XCTAssertLessThanOrEqual(paragraph.count, 320)
        }
    }

    func testClosingQuotesStayWithTheirSentence() {
        let source = String(repeating: "他说：“这张纸是死的，让我放松多了。”", count: 10)
        let result = TextParagraphing.restoreParagraphBreaks(source)
        XCTAssertEqual(result.replacingOccurrences(of: "\n\n", with: ""), source)
        for paragraph in result.components(separatedBy: "\n\n") {
            // 收尾引号不落到段首。
            let first = paragraph.first!
            XCTAssertFalse(TextParagraphing.closingMarks.contains(first))
        }
    }

    func testEnglishRunOnSplitsAtSentencesNotAbbreviations() {
        let source =
            "Dr. Smith arrived in Washington. He said the U.S. delegation would follow within days. Then Mr. Lee asked whether the plan, i.e. the full proposal, was ready for review. It was not ready, and nobody believed it would be. The committee kept postponing every vote it had scheduled."
        let result = TextParagraphing.restoreParagraphBreaks(source)
        XCTAssertEqual(result.replacingOccurrences(of: "\n\n", with: ""), source)
        XCTAssertFalse(result.contains("Dr.\n\n"))
        XCTAssertFalse(result.contains("U.S.\n\n"))
        XCTAssertFalse(result.contains("i.e.\n\n"))
        XCTAssertFalse(result.contains("Mr.\n\n"))
        XCTAssertNotEqual(result, source)
    }

    func testDecimalNumbersStayIntact() {
        let source =
            "The measured value settled near 3.14159 after several runs of the experiment. The team recorded every sample. Nothing else changed during those hours of testing and review."
        let result = TextParagraphing.restoreParagraphBreaks(source)
        XCTAssertTrue(result.contains("3.14159"))
        XCTAssertEqual(result.replacingOccurrences(of: "\n\n", with: ""), source)
    }

    func testShortTextStaysUntouched() {
        let short = "第一句话。第二句话。第三句话稍微长一点，但整体仍然很短。"
        XCTAssertEqual(TextParagraphing.restoreParagraphBreaks(short), short)
    }

    func testTextWithExistingLineBreaksStaysUntouched() {
        let text = String(repeating: "这是一句足够长的话，用来撑过长度阈值。", count: 12) + "\n第二段"
        XCTAssertEqual(TextParagraphing.restoreParagraphBreaks(text), text)
    }

    func testRunOnWithoutTerminatorsStaysUntouched() {
        let text = String(repeating: "整段没有任何可以断句的标点", count: 20)
        XCTAssertEqual(TextParagraphing.restoreParagraphBreaks(text), text)
    }
}
