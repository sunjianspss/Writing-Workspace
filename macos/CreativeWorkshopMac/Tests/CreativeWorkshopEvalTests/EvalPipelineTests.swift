import XCTest
import CreativeWorkshopCore
@testable import CreativeWorkshopEval

final class EvalPipelineTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeCase(_ evalCase: EvalCase, in directory: URL) throws {
        let data = try JSONEncoder().encode(evalCase)
        try data.write(to: directory.appendingPathComponent("\(evalCase.id).json"))
    }

    func testLoadCasesReadsAllJSONFilesInDirectory() throws {
        let directory = try makeTempDirectory()
        let draftContent = String(repeating: "已有初稿正文内容。", count: 10)
        try writeCase(EvalCase(id: "case-b", kind: "idea", idea: "写一篇关于独处的随笔想法B", direction: "随笔", materials: "素材B", content: ""), in: directory)
        try writeCase(EvalCase(id: "case-a", kind: "draft", idea: "写一篇关于独处的随笔想法A", direction: "随笔", materials: "素材A", content: draftContent), in: directory)

        let cases = try EvalCaseLoader.loadCases(from: directory)

        XCTAssertEqual(cases.count, 2)
        // 按文件名排序，保证报告里用例顺序稳定可复现。
        XCTAssertEqual(cases.map(\.id), ["case-a", "case-b"])
        XCTAssertEqual(cases[0].content, draftContent)
    }

    func testPipelineRunnerProducesScoredOutcomeForEachPipelineWithoutRealModelCalls() async throws {
        let dbDirectory = try makeTempDirectory()
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: FakeAIWorkflowExecuting(),
            databaseURL: dbDirectory.appendingPathComponent("main.sqlite3")
        )
        let runner = PipelineRunner(facade: facade)
        let evalCase = EvalCase(
            id: "case-01",
            kind: "idea",
            idea: "写一篇关于独处的随笔",
            direction: "情感文学随笔",
            materials: "周末爬山的经历",
            content: ""
        )

        for pipeline in PipelineRunner.pipelineNames {
            let outcome = try await runner.run(pipeline: pipeline, evalCase: evalCase)
            XCTAssertEqual(outcome.pipeline, pipeline)
            XCTAssertEqual(outcome.caseID, "case-01")
            XCTAssertTrue(outcome.success, "管线 \(pipeline) 在假 executor 下应当全程成功")
            XCTAssertNotNil(outcome.overallScore, "管线 \(pipeline) 应当产出诊断分数")
            XCTAssertGreaterThan(outcome.callCount, 0)
            XCTAssertFalse(outcome.content.isEmpty)
        }
    }

    /// 24.9：生成失败时 content 是 NativeFallbacks 的本地兜底稿，给它打分得到的是"兜底模板的
    /// 分数"，此前却会一路进报告、进差值、进放行门（全库 68 行 success=0 的结果都带着分数）。
    /// 现在连评分调用都不发：省一次模型调用，也让无效样本结构上不可能有分数。
    func testFailedGenerationIsNotScoredAndSkipsScoringCall() async throws {
        let dbDirectory = try makeTempDirectory()
        let executor = FailingAIWorkflowExecuting()
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: executor,
            databaseURL: dbDirectory.appendingPathComponent("main.sqlite3")
        )
        let runner = PipelineRunner(facade: facade)
        let evalCase = EvalCase(
            id: "case-01",
            kind: "idea",
            idea: "写一篇关于独处的随笔",
            direction: "情感文学随笔",
            materials: "周末爬山的经历",
            content: ""
        )

        let outcome = try await runner.run(pipeline: "direct", evalCase: evalCase)

        XCTAssertFalse(outcome.success)
        XCTAssertNil(outcome.overallScore, "失败样本不得带分数")
        XCTAssertEqual(outcome.highIssueCount, 0)
        XCTAssertEqual(outcome.mediumIssueCount, 0)
        XCTAssertEqual(outcome.lowIssueCount, 0)
        XCTAssertTrue(outcome.verificationSummary.contains("未评分"), "验证信号要说明为什么没有分数：\(outcome.verificationSummary)")
        XCTAssertEqual(executor.callCount, 1, "生成已经失败，不该再为兜底稿发一次评分调用")
        XCTAssertEqual(outcome.callCount, 1)
    }

    /// 24.9：评分调用本身失败时，报告此前会展示 `NativeFallbacks.writingReview` 算出的本地
    /// 启发式分数（库里那些 58/66 就是它）。生成是成功的，但这一格没有可信分数，必须留空。
    func testFailedScoringCallProducesNoScore() async throws {
        let dbDirectory = try makeTempDirectory()
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: ScoringFailsAIWorkflowExecuting(),
            databaseURL: dbDirectory.appendingPathComponent("main.sqlite3")
        )
        let runner = PipelineRunner(facade: facade)
        let evalCase = EvalCase(
            id: "case-01",
            kind: "idea",
            idea: "写一篇关于独处的随笔",
            direction: "情感文学随笔",
            materials: "周末爬山的经历",
            content: ""
        )

        let outcome = try await runner.run(pipeline: "direct", evalCase: evalCase)

        XCTAssertFalse(outcome.content.isEmpty, "生成本身是成功的，正文应当在")
        XCTAssertFalse(outcome.success, "评分失败的样本不算有效")
        XCTAssertNil(outcome.overallScore, "本地启发式分数不得当成 rubric 分数")
        XCTAssertEqual(outcome.highIssueCount + outcome.mediumIssueCount + outcome.lowIssueCount, 0,
                       "兜底诊断的问题清单同样不得进报告")
    }

    func testUnknownPipelineNameThrows() async throws {
        let dbDirectory = try makeTempDirectory()
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: FakeAIWorkflowExecuting(),
            databaseURL: dbDirectory.appendingPathComponent("main.sqlite3")
        )
        let runner = PipelineRunner(facade: facade)
        let evalCase = EvalCase(id: "case-01", kind: "idea", idea: "想法", direction: "随笔", materials: "", content: "")

        do {
            _ = try await runner.run(pipeline: "not-a-real-pipeline", evalCase: evalCase)
            XCTFail("未知管线名应当抛出错误")
        } catch {
            // 预期路径：main.swift 会在调用前用 pipelineNames 做同样的校验并提前退出。
        }
    }
}
