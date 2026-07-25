import XCTest
@testable import CreativeWorkshopEval

/// 问题清单跨轮对比（24.9-P1）。24.2 的裁决是"趋势改用问题清单而非分数来读"——这些用例钉住
/// 那条裁决在工具上的实现：清单本身、条数变化、清单进出，以及"问题稳定"这一情形要能被说出来。
final class IssueTrendTests: XCTestCase {
    private func previous(
        high: Int = 0,
        medium: Int = 0,
        low: Int = 0,
        dimensions: [String]
    ) -> PreviousSample {
        PreviousSample(
            overallScore: 83,
            highIssueCount: high,
            mediumIssueCount: medium,
            lowIssueCount: low,
            issueDimensions: dimensions
        )
    }

    func testNoPreviousRunShowsCurrentListOnly() {
        let text = IssueTrend.describe(current: ["人称视角(中)", "意象与细节(中)"], previous: nil)

        XCTAssertEqual(text, "问题清单：人称视角(中)、意象与细节(中)")
    }

    func testEmptyCurrentListSaysNoIssues() {
        XCTAssertEqual(IssueTrend.describe(current: [], previous: nil), "问题清单：无问题")
    }

    /// 24.2 第二例的形状：正文相似度 99.78%、问题逐条相同，分数却掉 10 分。报告必须能明说
    /// "清单没变"，否则读报告的人只会看见分数在跳。
    func testIdenticalListsAreCalledOutAsStable() {
        let dimensions = ["人称视角(中)", "意象与细节(中)"]

        let text = IssueTrend.describe(current: dimensions, previous: previous(medium: 2, dimensions: dimensions))

        XCTAssertTrue(text.contains("与上轮逐条相同"), text)
        XCTAssertFalse(text.contains("新增"), text)
        XCTAssertFalse(text.contains("已消失"), text)
    }

    /// 24.2 三连诊断的形状：第三条问题（结尾抒情）首次被漏检，第二轮才出现。
    func testAddedAndDisappearedDimensionsWithCountDelta() {
        let text = IssueTrend.describe(
            current: ["人称视角(中)", "留白与节奏(中)"],
            previous: previous(medium: 1, low: 1, dimensions: ["人称视角(中)", "语言腔调(低)"])
        )

        XCTAssertTrue(text.contains("新增 留白与节奏(中)"), text)
        XCTAssertTrue(text.contains("已消失 语言腔调(低)"), text)
        XCTAssertTrue(text.contains("中 1→2"), text)
        XCTAssertTrue(text.contains("低 1→0"), text)
    }

    /// 严重度重新定级（24.2 第二例的主因）不能被当成"问题消失了"：同名维度换档要既算新增
    /// 也算消失，读者才看得出这是定级摇摆而非质量变化。
    func testSeverityRegradeShowsAsBothAddedAndGone() {
        let text = IssueTrend.describe(
            current: ["文本引用与推断的边界(高)"],
            previous: previous(medium: 1, dimensions: ["文本引用与推断的边界(中)"])
        )

        XCTAssertTrue(text.contains("新增 文本引用与推断的边界(高)"), text)
        XCTAssertTrue(text.contains("已消失 文本引用与推断的边界(中)"), text)
    }

    func testSeverityCountsParsesTrailingParentheses() {
        let counts = IssueTrend.severityCounts(["人称视角(中)", "意象(细节)与描写(中)", "结构(高)"])

        XCTAssertEqual(counts["中"], 2, "维度名自带括号时也要按最后一对括号取严重度")
        XCTAssertEqual(counts["高"], 1)
    }
}
