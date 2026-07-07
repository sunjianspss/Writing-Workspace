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
