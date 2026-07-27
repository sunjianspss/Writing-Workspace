import XCTest
import CreativeWorkshopCore
@testable import CreativeWorkshopEval

/// 评测与 App 的 prompt 必须同源（PRD 24.5）。
///
/// App 的写作动作一律走 `prompt_templates` 库表里的模板，评测此前对 draft/outline/polish/
/// decision 一律传 nil，跑的是 App 从不执行的内联 prompt——量具和被测物是两份文案，分数
/// 无从代表 App 的真实质量（与 24.2「仪器修好了，教练没修」同一类断链）。
///
/// 例外是最终评分：量具必须固定，`EvalPipelineFacade.scoringTemplate` 写死在代码里，
/// 不随作者手改写作诊断模板而漂移。
final class EvalPromptTemplateSourceTests: XCTestCase {
    private let draftSentinel = "【模板哨兵-大纲成稿】"
    private let decisionSentinel = "【模板哨兵-代理决策】"
    private let reviewSentinel = "【模板哨兵-写作诊断】"
    /// 只出现在内联 draft prompt 里的句子：修复前 direct 管线发出去的就是它。
    /// 24.11 删掉了内联那份文案（P2-6，全仓已无第二份 prompt），这条断言从此是结构性成立的
    /// 冗余保险；真正的守卫在 `PromptTemplateSingleSourceTests`。
    private let inlineDraftMarker = "技术概念必须解释清楚定义、价值、例子和边界"

    private func makeDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-template-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("main.sqlite3")
    }

    /// 把某个 key 的模板改成带哨兵的内容（同时把 is_default 置 0，模拟作者手改过）。
    private func stampTemplate(_ key: PromptTemplateKey, sentinel: String, at databaseURL: URL) throws {
        let database = try NativeDatabase(databaseURL: databaseURL)
        let template = try XCTUnwrap(database.promptTemplate(key: key), "建库即应 seed 出 \(key.rawValue) 模板")
        _ = try database.savePromptTemplate(
            id: template.id,
            name: template.name,
            systemPrompt: template.system_prompt,
            userTemplate: sentinel + "\n" + template.user_template
        )
    }

    private func makeCase() -> EvalCaseInput {
        EvalCaseInput(
            id: "case-01",
            idea: "写一篇关于独处的随笔",
            direction: "情感文学随笔",
            materials: "周末爬山的经历",
            content: ""
        )
    }

    func testDirectPipelineSendsThePromptTemplateAppActuallyUses() async throws {
        let databaseURL = try makeDatabaseURL()
        try stampTemplate(.draft, sentinel: draftSentinel, at: databaseURL)
        let recorder = RecordingAIWorkflowExecuting()
        let facade = try EvalPipelineFacade(apiKey: "test-key", executor: recorder, databaseURL: databaseURL)

        _ = try await facade.run(pipeline: "direct", evalCase: makeCase())

        XCTAssertTrue(recorder.contains(draftSentinel), "direct 管线应当发出库里的成稿模板（App 用的那份）")
        XCTAssertFalse(recorder.contains(inlineDraftMarker), "不应再发内联 prompt——App 从不执行它")
    }

    func testAgenticPipelinePassesTemplatesIntoTheAgentSession() async throws {
        let databaseURL = try makeDatabaseURL()
        try stampTemplate(.agentDecision, sentinel: decisionSentinel, at: databaseURL)
        let recorder = RecordingAIWorkflowExecuting()
        let facade = try EvalPipelineFacade(apiKey: "test-key", executor: recorder, databaseURL: databaseURL)

        _ = try await facade.run(pipeline: "agentic", evalCase: makeCase())

        XCTAssertTrue(recorder.contains(decisionSentinel), "agentic 会话的决策调用应当用库里的模板")
    }

    /// 量具不随被测物漂移：作者改了写作诊断模板，评分仍走固定的锚点模板。
    func testScoringKeepsTheFixedAnchorTemplateEvenIfAuthorEditsTheReviewTemplate() async throws {
        let databaseURL = try makeDatabaseURL()
        try stampTemplate(.writingReview, sentinel: reviewSentinel, at: databaseURL)
        let recorder = RecordingAIWorkflowExecuting()
        let facade = try EvalPipelineFacade(apiKey: "test-key", executor: recorder, databaseURL: databaseURL)

        // direct 管线只有「成稿 + 评分」两步，没有生成路径上的诊断，评分调用可以被单独观察。
        _ = try await facade.run(pipeline: "direct", evalCase: makeCase())

        XCTAssertTrue(recorder.contains("评分流程（必须按顺序执行）"), "评分应当用固定的锚点模板")
        XCTAssertFalse(recorder.contains(reviewSentinel), "评分量具不得改用作者手改过的诊断模板")
    }

    func testPromptTemplateSummaryNamesAuthorCustomizedTemplates() throws {
        let databaseURL = try makeDatabaseURL()
        try stampTemplate(.draft, sentinel: draftSentinel, at: databaseURL)
        let facade = try EvalPipelineFacade(
            apiKey: "test-key",
            executor: RecordingAIWorkflowExecuting(),
            databaseURL: databaseURL
        )

        XCTAssertTrue(
            facade.promptTemplateSummary.contains("大纲成稿(作者自定义)"),
            "作者手改过的模板必须在报告头点名：这一轮量的就不是内置 prompt 了"
        )
        XCTAssertTrue(facade.promptTemplateSummary.contains("生成大纲(默认)"))
    }
}
