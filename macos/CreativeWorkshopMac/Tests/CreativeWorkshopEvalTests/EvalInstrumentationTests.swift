import XCTest
@testable import CreativeWorkshopCore
@testable import CreativeWorkshopEval

/// 脚本化评分 executor（评测仪器修缮测试）：写作诊断类调用按脚本依次返回指定分数
/// （nil 模拟"非 JSON 被宽松解码吞掉"的无分数结果），其余工作流沿用 fallback 成功产出。
/// 同时捕获评分 prompt 文本，用于断言锚点模板确实生效。
private final class ScriptedScoringExecuting: AIWorkflowExecuting {
    private let scores: [Int?]
    private(set) var reviewCallCount = 0
    private(set) var lastReviewPrompt = ""

    init(scores: [Int?]) {
        self.scores = scores
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if descriptor.kind == .writingReview {
            let index = reviewCallCount
            reviewCallCount += 1
            lastReviewPrompt = descriptor.buildMessages().map(\.content).joined(separator: "\n")
            let score = index < scores.count ? scores[index] : scores.last ?? nil
            let review = WritingReviewResult(
                summary: "脚本评分",
                overall_score: score,
                strengths: [],
                issues: [],
                revision_plan: [],
                training_focus: [],
                style_notes: [],
                raw_output: nil
            )
            if let output = review as? Output {
                return AIRun(result: output, elapsedMS: 3, success: true, error: "", inputSummary: "scripted", outputSummary: "scripted")
            }
        }
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 3,
            success: true,
            error: "",
            inputSummary: "fake",
            outputSummary: "fake"
        )
    }
}

final class EvalInstrumentationTests: XCTestCase {
    private func makeTempDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-instrument-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("main.sqlite3")
    }

    private func makeIdeaCase() -> EvalCaseInput {
        EvalCaseInput(
            id: "case-t1",
            idea: "写一篇关于独处的随笔，讨论安静为什么是一种能力。",
            direction: "情感文学随笔",
            materials: "周末一个人爬山的经历。",
            content: ""
        )
    }

    // MARK: - 修缮 ①：内容级验证信号

    func testContentOnlyItemsFlagTruncationAndCannedEnding() {
        let truncated = AgentDraftQualityGateEvaluator.contentOnlyItems(
            content: "这是一段没有写完的正文，结尾停在半句",
            knownPitfalls: []
        )
        XCTAssertEqual(truncated.first?.title, "内容完整性")
        XCTAssertEqual(truncated.first?.status, .review, "结尾非句末标点应判疑似截断")

        let canned = AgentDraftQualityGateEvaluator.contentOnlyItems(
            content: "正文很长的一段内容。你学会了吗？",
            knownPitfalls: []
        )
        XCTAssertEqual(canned.last?.status, .review, "命中结尾套话应判待复核")
        XCTAssertTrue(canned.last?.detail.contains("你学会了吗") == true)

        let clean = AgentDraftQualityGateEvaluator.contentOnlyItems(
            content: "一段完整、结尾正常的正文。",
            knownPitfalls: []
        )
        XCTAssertTrue(clean.allSatisfy { $0.status == .passed })
    }

    func testEvalVerificationSummaryIsPopulatedFromContentChecks() async throws {
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: ScriptedScoringExecuting(scores: [80]),
            databaseURL: makeTempDatabaseURL()
        )
        let outcome = try await facade.run(pipeline: "direct", evalCase: makeIdeaCase())

        XCTAssertNotEqual(outcome.verificationSummary, "验证：暂无可用信号。", "验证信号列不得再为空")
        XCTAssertTrue(outcome.verificationSummary.hasPrefix("验证"), "应给出内容级检查的一行总结")
    }

    // MARK: - 修缮 ②：评分锚点模板 + 无分数重试

    func testScoringUsesAnchoredTemplateAndRetriesOnceWhenScoreMissing() async throws {
        let executor = ScriptedScoringExecuting(scores: [nil, 88])
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: executor,
            databaseURL: makeTempDatabaseURL()
        )
        let outcome = try await facade.run(pipeline: "direct", evalCase: makeIdeaCase())

        XCTAssertEqual(executor.reviewCallCount, 2, "首次无分数应重试一次")
        XCTAssertEqual(outcome.overallScore, 88)
        XCTAssertEqual(outcome.callCount, 3, "direct = 1 次成稿 + 2 次评分（含重试）")
        XCTAssertTrue(executor.lastReviewPrompt.contains("90–100"), "评分 prompt 应包含分档锚点")
        XCTAssertTrue(executor.lastReviewPrompt.contains("评分流程"), "评分 prompt 应要求先证据后分数")
    }

    func testScoringDoesNotRetryWhenScorePresent() async throws {
        let executor = ScriptedScoringExecuting(scores: [77])
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: executor,
            databaseURL: makeTempDatabaseURL()
        )
        let outcome = try await facade.run(pipeline: "direct", evalCase: makeIdeaCase())

        XCTAssertEqual(executor.reviewCallCount, 1)
        XCTAssertEqual(outcome.overallScore, 77)
        XCTAssertEqual(outcome.callCount, 2, "direct = 1 次成稿 + 1 次评分")
    }

    func testScoringReportsHoleWhenRetryStillHasNoScore() async throws {
        let executor = ScriptedScoringExecuting(scores: [nil, nil])
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: executor,
            databaseURL: makeTempDatabaseURL()
        )
        let outcome = try await facade.run(pipeline: "direct", evalCase: makeIdeaCase())

        XCTAssertEqual(executor.reviewCallCount, 2, "重试只做一次，不得无限重评")
        XCTAssertNil(outcome.overallScore)
        XCTAssertTrue(outcome.error.contains("评分重试后仍未返回结构化分数"))
    }

    // MARK: - 修缮 ③：agentic 会话轨迹

    func testAgentSessionSummaryFormatting() {
        let summary = EvalPipelineFacade.agentSessionSummary(
            stepNames: ["写作诊断", "按诊断修订", "finish"],
            stopReason: "已交付待复核"
        )
        XCTAssertEqual(summary, "步骤(3)：写作诊断→按诊断修订→finish；停止：已交付待复核")

        let empty = EvalPipelineFacade.agentSessionSummary(stepNames: [], stopReason: "预算耗尽")
        XCTAssertEqual(empty, "步骤：无；停止：预算耗尽")
    }

    func testAgenticOutcomeCarriesSessionSummary() async throws {
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: ScriptedScoringExecuting(scores: [80]),
            databaseURL: makeTempDatabaseURL()
        )
        let outcome = try await facade.run(pipeline: "agentic", evalCase: makeIdeaCase())

        XCTAssertTrue(outcome.sessionSummary.contains("步骤"), "agentic 产出必须携带会话摘要")
        XCTAssertTrue(outcome.sessionSummary.contains("停止"))
    }

    func testReportRendersAgenticSessionLine() {
        let agentic = PipelineOutcome(
            pipeline: "agentic",
            caseID: "case-01",
            title: "标题",
            content: "正文。",
            overallScore: 74,
            highIssueCount: 0,
            mediumIssueCount: 1,
            lowIssueCount: 0,
            wordCount: 100,
            callCount: 12,
            fallbackCount: 0,
            elapsedMS: 1000,
            success: true,
            error: "",
            verificationSummary: "验证通过：2 项检查全部通过。",
            searchCount: 1,
            sessionSummary: "步骤(3)：写作诊断→按诊断修订→finish；停止：已交付待复核"
        )
        var deep = agentic
        deep.pipeline = "deep"
        deep.sessionSummary = ""

        let report = ReportGenerator.generate(
            runID: "run-1",
            runTimestamp: "2026-07-07T00:00:00Z",
            gitDescribe: "test",
            outcomes: [deep, agentic],
            previousScores: [:]
        )

        XCTAssertTrue(report.contains("- agentic 会话：步骤(3)"), "报告应展示 agentic 会话轨迹")
        XCTAssertFalse(report.contains("- deep 会话："), "无摘要的管线不渲染会话行")
    }
}
