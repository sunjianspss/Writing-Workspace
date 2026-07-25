import XCTest
@testable import CreativeWorkshopEval

final class ReleaseGateTests: XCTestCase {
    private func makeOutcome(
        pipeline: String,
        caseID: String,
        overallScore: Int?,
        callCount: Int,
        fallbackCount: Int,
        success: Bool = true
    ) -> PipelineOutcome {
        PipelineOutcome(
            pipeline: pipeline,
            caseID: caseID,
            title: "标题",
            content: "正文",
            overallScore: overallScore,
            highIssueCount: 0,
            mediumIssueCount: 0,
            lowIssueCount: 0,
            wordCount: 100,
            callCount: callCount,
            fallbackCount: fallbackCount,
            elapsedMS: 100,
            success: success,
            error: success ? "" : "The request timed out.",
            verificationSummary: "",
            searchCount: 0
        )
    }

    func testGateReportsNoAgenticDataWhenAgenticPipelineMissing() {
        let outcomes = [
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(verdict.lines.contains("放行门：暂无 agentic 管线数据"))
    }

    func testGatePassesWhenAllThreeCriteriaAreMet() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: 85, callCount: 10, fallbackCount: 0),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 1)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertTrue(verdict.passed)
        XCTAssertTrue(verdict.lines.contains("放行门：通过，可将代理会话设为默认入口"))
    }

    func testGateFailsWhenAgenticScoreIsLowerThanDeep() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: 70, callCount: 10, fallbackCount: 0),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(verdict.lines.contains { $0.contains("不通过") && $0.contains("rubric 平均总分") })
    }

    func testGateFailsWhenAgenticCallCountExceedsOneAndHalfTimesDeep() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: 85, callCount: 16, fallbackCount: 0),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(verdict.lines.contains { $0.contains("不通过") && $0.contains("平均模型调用次数") })
    }

    /// 24.9：放行门是 L2 转默认的唯一裁决依据，失败样本的分数（兜底稿/本地启发式）绝不能进
    /// 平均值。这里 deep 的一格超时失败带着 58 分——若被计入，deep 均分被拉到 69，agentic 就
    /// 会凭一次网络抖动"通过"放行门。
    func testGateExcludesFailedSamplesFromScoreAverage() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: 75, callCount: 10, fallbackCount: 0),
            makeOutcome(pipeline: "agentic", caseID: "case-02", overallScore: 75, callCount: 10, fallbackCount: 0),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0),
            makeOutcome(pipeline: "deep", caseID: "case-02", overallScore: 58, callCount: 10, fallbackCount: 1, success: false)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed, "deep 的有效样本只有 80 分那格，agentic 75 分不该通过")
        XCTAssertTrue(
            verdict.lines.contains { $0.contains("deep 80.00") && $0.contains("有效 1/2") },
            "报告需写明 deep 只有 1 格有效：\(verdict.lines)"
        )
    }

    /// 某条管线整列失败时不做判定，而不是拿 0 分或空平均值糊过去。
    func testGateReportsInsufficientValidSamples() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: nil, callCount: 10, fallbackCount: 1, success: false),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(
            verdict.lines.contains { $0.contains("有效样本不足") && $0.contains("agentic 0/1") },
            "整列失败应明说数据不足：\(verdict.lines)"
        )
    }

    func testGateFailsWhenAgenticFallbackRateExceedsDeep() {
        let outcomes = [
            makeOutcome(pipeline: "agentic", caseID: "case-01", overallScore: 85, callCount: 10, fallbackCount: 5),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 80, callCount: 10, fallbackCount: 0)
        ]

        let verdict = ReleaseGate.evaluate(outcomes: outcomes)

        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(verdict.lines.contains { $0.contains("不通过") && $0.contains("fallback/熔断率") })
    }
}
