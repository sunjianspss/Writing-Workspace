import XCTest
@testable import CreativeWorkshopCore

/// 这些不变量此前埋在 `@MainActor` 的 WorkshopStore 里，只能连着整个 Store 才测得到。
final class DraftTextLocatorTests: XCTestCase {
    func testLocateReturnsExactRangeForPresentExcerpt() throws {
        let locator = DraftTextLocator("我们没有。理由不是它写得不够好，而是说不清它什么时候会写坏。")

        let range = try XCTUnwrap(locator.locate(excerpt: "说不清它什么时候会写坏"))

        XCTAssertEqual(locator.selectedText(in: range), "说不清它什么时候会写坏")
    }

    func testLocateTrimsSurroundingWhitespaceBeforeMatching() throws {
        let locator = DraftTextLocator("评测分数在 78 到 91 之间摆动。")

        let range = try XCTUnwrap(locator.locate(excerpt: "  78 到 91 之间摆动  \n"))

        XCTAssertEqual(locator.selectedText(in: range), "78 到 91 之间摆动")
    }

    /// 18.3.1：定位不到就必须失败，不能退化成近似匹配。
    func testLocateFailsRatherThanApproximatingWhenExcerptIsAbsent() {
        let locator = DraftTextLocator("评测分数在 78 到 91 之间摆动。")

        XCTAssertNil(locator.locate(excerpt: "评测分数在 60 到 70 之间摆动"))
        XCTAssertNil(locator.locate(excerpt: "   "))
        XCTAssertNil(locator.locate(excerpt: nil))
    }

    func testSelectedTextRejectsEmptySelection() {
        let locator = DraftTextLocator("一段正文")

        XCTAssertNil(locator.selectedText(in: NSRange(location: 2, length: 0)))
    }

    func testContextIsClampedToTheAvailableText() {
        let locator = DraftTextLocator("abcdefghij")
        let range = NSRange(location: 4, length: 2)

        XCTAssertEqual(locator.context(around: range, radius: 2), "cdefgh")
        XCTAssertEqual(locator.context(around: range, radius: 100), "abcdefghij")
    }

    func testReplacingReturnsUpdatedTextAndSelectionCoveringTheReplacement() throws {
        let locator = DraftTextLocator("原文的第二段需要改写。")
        let range = try XCTUnwrap(locator.locate(excerpt: "第二段"))

        let result = try XCTUnwrap(
            locator.replacing(range: range, expectedText: "第二段", with: "开头那一段")
        )

        XCTAssertEqual(result.text, "原文的开头那一段需要改写。")
        XCTAssertEqual(
            DraftTextLocator(result.text).selectedText(in: result.selection),
            "开头那一段"
        )
    }

    /// 正文在生成期间被改动过时，替换必须整体放弃，不能按旧偏移强写。
    func testReplacingRefusesWhenTheRangeNoLongerHoldsTheExpectedText() {
        let locator = DraftTextLocator("作者已经把这一段重写过了。")

        XCTAssertNil(
            locator.replacing(
                range: NSRange(location: 3, length: 3),
                expectedText: "旧的片段",
                with: "新的片段"
            )
        )
    }

    func testReplacingRefusesAnOutOfBoundsRange() {
        let locator = DraftTextLocator("短")

        XCTAssertNil(
            locator.replacing(
                range: NSRange(location: 5, length: 4),
                expectedText: "短",
                with: "长"
            )
        )
    }
}
