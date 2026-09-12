import XCTest
@testable import CreativeWorkshopCore
@testable import CreativeWorkshopEval

/// 配对重判与对照实验的守卫（24.14）。
final class RejudgeComparisonTests: XCTestCase {

    // MARK: - 实验完整性：两臂必须只差一个变量

    /// **这是整套对照实验的地基**：两个评分变量除了输出示例那一处，正文必须逐字相同。
    /// 谁去改了其中一臂的措辞，A/B 就从单变量实验变成双变量实验，差值再也归因不到示例值上——
    /// 而这种漂移不会让任何别的测试变红（两臂各自都能正常渲染）。
    func testTwoScoringArmsDifferOnlyInTheScoreExampleSlot() {
        let armA = EvalPipelineFacade.scoringTemplate(variant: .anchored83)
        let armB = EvalPipelineFacade.scoringTemplate(variant: .placeholder)

        XCTAssertEqual(armA.system_prompt, armB.system_prompt, "两臂的 system prompt 必须相同")

        func canonicalize(_ template: PromptTemplate, _ variant: EvalPipelineFacade.ScoringVariant) -> String {
            template.user_template
                .replacingOccurrences(of: variant.outputNote, with: "<OUTPUT_NOTE>")
                .replacingOccurrences(of: "\"overall_score\":\(variant.scoreExample)", with: "\"overall_score\":<SLOT>")
        }

        XCTAssertEqual(
            canonicalize(armA, .anchored83),
            canonicalize(armB, .placeholder),
            "两个评分变量除示例位与输出说明外必须逐字相同，否则对照实验不是单变量"
        )
    }

    /// 改动后的臂不许再出现任何写死的分数——它就是被审计出来的那个锚点。
    func testPlaceholderArmCarriesNoLiteralScore() {
        let rendered = EvalPipelineFacade.scoringTemplate(variant: .placeholder).user_template
        XCTAssertFalse(
            rendered.contains("\"overall_score\":83"),
            "占位符臂不许写死示例分数"
        )
        XCTAssertTrue(rendered.contains("\"overall_score\":<"), "占位符臂的示例位应是尖括号占位")
        XCTAssertTrue(
            EvalPipelineFacade.scoringTemplate(variant: .anchored83).user_template.contains("\"overall_score\":83"),
            "对照臂必须保留改动前的 83，否则没有基线可比"
        )
    }

    /// 主评分路径必须固定用占位符臂，别哪天被换成对照臂还没人发现。
    func testMainScoringPathUsesPlaceholderArm() {
        XCTAssertEqual(
            EvalPipelineFacade.scoringTemplate.user_template,
            EvalPipelineFacade.scoringTemplate(variant: .placeholder).user_template
        )
    }

    // MARK: - 配对统计

    private func row(
        _ variant: EvalPipelineFacade.ScoringVariant,
        _ caseID: String,
        _ pipeline: String,
        _ score: Int?,
        success: Bool = true,
        issues: [EvalPipelineFacade.RejudgedIssue] = []
    ) -> RejudgeRow {
        RejudgeRow(
            variant: variant.rawValue,
            caseID: caseID,
            pipeline: pipeline,
            overallScore: score,
            issues: issues,
            success: success,
            error: "",
            elapsedMS: 10
        )
    }

    func testPairingKeepsOnlyCellsThatSucceededInBothArms() {
        let rows = [
            row(.anchored83, "case-01", "direct", 83),
            row(.placeholder, "case-01", "direct", 79),
            row(.anchored83, "case-02", "deep", 83),
            // case-02 的 B 臂失败：没有差值可言，整格不进配对
            row(.placeholder, "case-02", "deep", nil, success: false),
            // case-03 只有 B 臂
            row(.placeholder, "case-03", "agent", 85)
        ]

        let comparison = RejudgeReport.pair(
            rows: rows,
            before: EvalPipelineFacade.ScoringVariant.anchored83.rawValue,
            after: EvalPipelineFacade.ScoringVariant.placeholder.rawValue
        )

        XCTAssertEqual(comparison.n, 1, "只有两臂都成功的 case-01 能配对")
        XCTAssertEqual(comparison.cells.first?.caseID, "case-01")
        XCTAssertEqual(comparison.meanDelta, -4, accuracy: 0.001)
    }

    /// 全部格子同向移动同样多时，差值标准差为 0 → 区间不跨 0 → 判定为显著。
    func testUniformShiftIsDetectedAsSignificant() {
        var rows: [RejudgeRow] = []
        for index in 1...10 {
            rows.append(row(.anchored83, "case-\(index)", "direct", 83))
            rows.append(row(.placeholder, "case-\(index)", "direct", 78))
        }
        let comparison = RejudgeReport.pair(
            rows: rows,
            before: EvalPipelineFacade.ScoringVariant.anchored83.rawValue,
            after: EvalPipelineFacade.ScoringVariant.placeholder.rawValue
        )
        XCTAssertEqual(comparison.n, 10)
        XCTAssertEqual(comparison.meanDelta, -5, accuracy: 0.001)
        XCTAssertEqual(comparison.deltaStdDev, 0, accuracy: 0.001)
        XCTAssertTrue(comparison.isSignificant)
        XCTAssertEqual(comparison.movedDown, 10)
        XCTAssertEqual(comparison.unchanged, 0)
    }

    /// 一半升一半降、净差为 0 时不许判成"有效果"——这正是抽样波动该有的样子。
    func testSymmetricNoiseIsNotSignificant() {
        var rows: [RejudgeRow] = []
        for index in 1...10 {
            rows.append(row(.anchored83, "case-\(index)", "direct", 83))
            rows.append(row(.placeholder, "case-\(index)", "direct", index % 2 == 0 ? 88 : 78))
        }
        let comparison = RejudgeReport.pair(
            rows: rows,
            before: EvalPipelineFacade.ScoringVariant.anchored83.rawValue,
            after: EvalPipelineFacade.ScoringVariant.placeholder.rawValue
        )
        XCTAssertEqual(comparison.meanDelta, 0, accuracy: 0.001)
        XCTAssertFalse(comparison.isSignificant, "净差为 0 必须判成『判不出』")
        XCTAssertEqual(comparison.movedUp, 5)
        XCTAssertEqual(comparison.movedDown, 5)
    }

    /// 83 占比是本次改动最直接的观察点，报告里那一行不能算错。
    func testOccupancyCountsTheAnchorScoreInBothArms() {
        let rows = [
            row(.anchored83, "case-01", "direct", 83),
            row(.placeholder, "case-01", "direct", 83),
            row(.anchored83, "case-02", "direct", 83),
            row(.placeholder, "case-02", "direct", 76)
        ]
        let comparison = RejudgeReport.pair(
            rows: rows,
            before: EvalPipelineFacade.ScoringVariant.anchored83.rawValue,
            after: EvalPipelineFacade.ScoringVariant.placeholder.rawValue
        )
        let occupancy = comparison.occupancy(of: 83)
        XCTAssertEqual(occupancy.before, 2)
        XCTAssertEqual(occupancy.after, 1)
    }

    /// 配对设计的价值就在这里：差值标准差越小，检出同样效应所需样本量越少。
    func testRequiredPairsShrinksWithTighterDeltas() {
        let noisy = PairedComparison(cells: (1...10).map {
            PairedComparison.Cell(caseID: "c\($0)", pipeline: "direct", before: 83, after: $0 % 2 == 0 ? 93 : 73)
        })
        let tight = PairedComparison(cells: (1...10).map {
            PairedComparison.Cell(caseID: "c\($0)", pipeline: "direct", before: 83, after: $0 % 2 == 0 ? 84 : 82)
        })
        XCTAssertGreaterThan(
            noisy.requiredPairs(toDetect: 1.0),
            tight.requiredPairs(toDetect: 1.0),
            "差值越散，检出同样效应需要的配对越多"
        )
    }

    // MARK: - 维度归一

    /// 模型会把维度写成「语言腔调（轻微文艺腔）」。不剥括号补语，同一个维度会散成一堆
    /// 只出现一次的条目，频次表读不出任何东西——这是查库分析时踩到的第一个坑。
    func testDimensionNormalizationStripsParentheticals() {
        XCTAssertEqual(RejudgeReport.normalize("语言腔调（轻微文艺腔）"), "语言腔调")
        XCTAssertEqual(RejudgeReport.normalize("情感真实度（总结稍显工整）"), "情感真实度")
        XCTAssertEqual(RejudgeReport.normalize("结构 (松散)"), "结构")
        XCTAssertEqual(RejudgeReport.normalize("文本引用关系·推断边界"), "文本引用关系")
        XCTAssertEqual(RejudgeReport.normalize("人称视角"), "人称视角")
        XCTAssertEqual(RejudgeReport.normalize("   "), "未标维度")
    }

    func testDimensionTableRanksByHighSeverityFirst() {
        let rows = [
            row(.placeholder, "case-01", "direct", 75, issues: [
                .init(dimension: "文本引用与推断的边界", severity: "高", excerpt: "判词写得清清楚楚", problem: "把推测当定论"),
                .init(dimension: "语言腔调（轻微文艺腔）", severity: "低", excerpt: "像一层薄灰", problem: "比喻刻意")
            ]),
            row(.placeholder, "case-02", "deep", 83, issues: [
                .init(dimension: "语言腔调", severity: "中", excerpt: "又浮上来", problem: "腔调游移"),
                .init(dimension: "语言腔调（鸡汤腔）", severity: "低", excerpt: "岁月漫长", problem: "落入套话")
            ])
        ]
        let table = RejudgeReport.dimensionTable(
            rows: rows,
            variant: EvalPipelineFacade.ScoringVariant.placeholder.rawValue
        )
        XCTAssertEqual(table.first?.dimension, "文本引用与推断的边界", "带高危的维度必须排在最前")
        XCTAssertEqual(table.first?.high, 1)
        let tone = table.first { $0.dimension == "语言腔调" }
        XCTAssertEqual(tone?.total, 3, "三条括号写法不同的『语言腔调』必须归成一个维度")
        XCTAssertEqual(tone?.cells, 2)
    }
}
