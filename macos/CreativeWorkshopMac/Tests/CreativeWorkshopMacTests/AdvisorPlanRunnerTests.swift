import XCTest
@testable import CreativeWorkshopCore

/// 23.5 半自动调度：AdvisorPlanRunner 是纯 Core 排序器，这里用假执行器验证顺序执行、
/// 跳过规则与三种停止语义，完全不依赖 WorkshopStore/数据库。
final class AdvisorPlanRunnerTests: XCTestCase {
    func testSequentialExecutionAwaitsEachStepInOrder() async {
        let executor = FakeAdvisorPlanStepExecutor()
        let actions: [AdvisorAction] = [.generateTopics, .generateOutline, .draftFromOutline]
        let runner = AdvisorPlanRunner(actions: actions, executor: executor)

        let result = await runner.run { _ in }

        XCTAssertEqual(executor.executedActions, actions)
        XCTAssertEqual(result.records.map(\.status), ["success", "success", "success"])
        XCTAssertEqual(result.stopReason, .finished)
    }

    func testSkipsRewriteSelectionAndSaveArticleWithoutCallingExecutor() async {
        let executor = FakeAdvisorPlanStepExecutor()
        let actions: [AdvisorAction] = [.rewriteSelectionNatural, .quickDraft, .saveArticle]
        let runner = AdvisorPlanRunner(actions: actions, executor: executor)

        let result = await runner.run { _ in }

        XCTAssertEqual(executor.executedActions, [.quickDraft])
        XCTAssertEqual(result.records.count, 3)
        XCTAssertEqual(result.records[0].status, "skipped")
        XCTAssertEqual(result.records[0].note, "已跳过：需要作者手动执行")
        XCTAssertEqual(result.records[1].status, "success")
        XCTAssertEqual(result.records[2].status, "skipped")
        XCTAssertEqual(result.stopReason, .finished)
    }

    func testStopsAtFirstFailureAndDoesNotRunLaterSteps() async {
        let executor = FakeAdvisorPlanStepExecutor()
        executor.scriptedOutcomes[.draftFromOutline] = .failed(reason: "网络失败")
        let actions: [AdvisorAction] = [.generateOutline, .draftFromOutline, .writingReview]
        let runner = AdvisorPlanRunner(actions: actions, executor: executor)

        let result = await runner.run { _ in }

        XCTAssertEqual(executor.executedActions, [.generateOutline, .draftFromOutline])
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records.last?.status, "failed")
        XCTAssertEqual(result.records.last?.note, "网络失败")
        XCTAssertEqual(result.stopReason, .failed(action: .draftFromOutline, index: 2, reason: "网络失败"))
    }

    func testStopsWhenStepReportsCancelled() async {
        let executor = FakeAdvisorPlanStepExecutor()
        executor.scriptedOutcomes[.generateOutline] = .cancelled
        let actions: [AdvisorAction] = [.generateOutline, .draftFromOutline]
        let runner = AdvisorPlanRunner(actions: actions, executor: executor)

        let result = await runner.run { _ in }

        XCTAssertEqual(executor.executedActions, [.generateOutline])
        XCTAssertEqual(result.stopReason, .cancelled)
    }

    func testStopsWhenAuthorAbandonsPendingReview() async {
        let executor = FakeAdvisorPlanStepExecutor()
        executor.scriptedOutcomes[.quickDraft] = .abandoned(reason: "作者放弃了该步骤的产物")
        let actions: [AdvisorAction] = [.quickDraft, .polishNatural]
        let runner = AdvisorPlanRunner(actions: actions, executor: executor)

        let result = await runner.run { _ in }

        XCTAssertEqual(executor.executedActions, [.quickDraft])
        XCTAssertEqual(result.stopReason, .abandoned(action: .quickDraft, index: 1, reason: "作者放弃了该步骤的产物"))
    }
}

private final class FakeAdvisorPlanStepExecutor: AdvisorPlanStepExecuting {
    var scriptedOutcomes: [AdvisorAction: AdvisorPlanStepOutcome] = [:]
    private(set) var executedActions: [AdvisorAction] = []

    func executeAdvisorPlanStep(_ action: AdvisorAction) async -> AdvisorPlanStepOutcome {
        executedActions.append(action)
        return scriptedOutcomes[action] ?? .completed
    }
}
