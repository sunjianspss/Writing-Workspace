import XCTest
@testable import CreativeWorkshopCore

/// 诊断维度的归一口径，App 侧雷达与评测侧配对重判共用这一份。
///
/// 用例照着作者库里真实出现过的写法构造——「语言腔调」这一组被模型写成了六种样子，
/// 合计 10 次足以排第一，不归一就散成六条小尾巴，雷达给出的排序是相反的。
final class DimensionNormalizerTests: XCTestCase {
    /// 作者库里真实出现的六种写法，归一后必须是同一个维度。
    func testRealWorldVariantsCollapseToOneDimension() {
        let variants = [
            "语言腔调",
            "语言腔调（轻微文艺腔）",
            "语言腔调（议论是否节制）",
            "语言腔调（文艺腔倾向）",
            "语言腔调（引申是否节制）",
            "语言腔调（是否滑向文艺腔/鸡汤腔/营销腔）"
        ]

        let normalized = Set(variants.map(DimensionNormalizer.normalize))

        XCTAssertEqual(normalized, ["语言腔调"], "六种写法必须归到同一个维度")
    }

    func testStripsHalfWidthParenthesesToo() {
        XCTAssertEqual(DimensionNormalizer.normalize("节奏(衔接转向)"), "节奏")
    }

    /// 分隔符后面的补语同样剥掉：「节奏·衔接」「结构：推进」都只留主干。
    func testStripsSeparatorSuffixes() {
        XCTAssertEqual(DimensionNormalizer.normalize("节奏·衔接转向"), "节奏")
        XCTAssertEqual(DimensionNormalizer.normalize("结构：推进关系"), "结构")
        XCTAssertEqual(DimensionNormalizer.normalize("表达/用词"), "表达")
        XCTAssertEqual(DimensionNormalizer.normalize("素材、细节"), "素材")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(DimensionNormalizer.normalize("  开头  "), "开头")
    }

    /// **不做同义词合并**：「语言腔调」与「腔调」仍是两个维度。同义异名要合并得有一张
    /// 受控词表，那是另一个决定；这里只做机械、可解释、不会误伤的那一半。
    func testDoesNotMergeSynonyms() {
        XCTAssertNotEqual(
            DimensionNormalizer.normalize("腔调"),
            DimensionNormalizer.normalize("语言腔调")
        )
    }

    /// 空维度显式标出来，不并进别人。
    func testBlankBecomesExplicitPlaceholder() {
        XCTAssertEqual(DimensionNormalizer.normalize(""), DimensionNormalizer.unlabeled)
        XCTAssertEqual(DimensionNormalizer.normalize("   "), DimensionNormalizer.unlabeled)
        XCTAssertEqual(DimensionNormalizer.normalize("（只有补语）"), DimensionNormalizer.unlabeled)
    }

    // MARK: - 雷达确实用上了归一

    /// 归一之前这六条各算一个维度，谁都进不了前列；归一之后它们合成 10 次的第一名。
    func testRadarCountsNormalizedVariantsTogether() {
        let reviews = [
            review(dimensions: ["语言腔调（轻微文艺腔）", "人称视角"]),
            review(dimensions: ["语言腔调（议论是否节制）", "人称视角"]),
            review(dimensions: ["语言腔调", "节奏（衔接转向）"]),
            review(dimensions: ["语言腔调（文艺腔倾向）", "节奏"])
        ]

        let trends = WritingDimensionAnalytics.trends(from: reviews)
        let tone = trends.first { $0.dimension == "语言腔调" }
        let rhythm = trends.first { $0.dimension == "节奏" }

        XCTAssertEqual(tone?.totalCount, 4, "四种写法合并成一个维度")
        XCTAssertEqual(rhythm?.totalCount, 2, "带括号补语的节奏也归到节奏")
        XCTAssertFalse(
            trends.contains { $0.dimension.contains("（") },
            "雷达里不该再出现带括号的维度：\(trends.map(\.dimension))"
        )
    }

    private func review(dimensions: [String]) -> WritingReview {
        WritingReview(
            id: 0,
            article_id: nil,
            title_snapshot: "稿",
            summary: "一句话诊断",
            overall_score: 80,
            strengths: [],
            issues: dimensions.map {
                WritingReviewIssue(dimension: $0, severity: "中", excerpt: nil, problem: "问题", suggestion: "建议")
            },
            revision_plan: [],
            training_focus: [],
            style_notes: [],
            raw_output: nil,
            model: "test-model",
            created_at: nil
        )
    }
}
