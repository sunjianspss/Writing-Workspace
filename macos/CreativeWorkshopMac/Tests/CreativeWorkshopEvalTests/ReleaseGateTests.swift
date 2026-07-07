import XCTest
@testable import CreativeWorkshopEval

final class ReleaseGateTests: XCTestCase {
    private func makeOutcome(
        pipeline: String,
        caseID: String,
        overallScore: Int?,
        callCount: Int,
        fallbackCount: Int
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
            success: true,
            error: "",
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
