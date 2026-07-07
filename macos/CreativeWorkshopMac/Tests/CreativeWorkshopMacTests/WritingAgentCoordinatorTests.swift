import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

/// PRD 23.6 有界代理循环内核：全部用假 executor 做确定性测试，覆盖验收标准 1-7。
final class WritingAgentCoordinatorTests: XCTestCase {
    func testBudgetExhaustionDeliversBestVersionWithBudgetSummary() async {
        // 总预算只有 2 次：从第一轮起就落入"剩余 ≤2"收缩集合，因此选用收缩集合内的
        // writing_review 作为唯一动作，验证预算耗尽后交付当前最好版本（诊断已保留）。
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.writingReview.rawValue, reason: "先看看现状", stop: false))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(callBudget: 2))

        XCTAssertEqual(result.stopReason, .budgetExhausted)
        XCTAssertEqual(result.finalState.budgetSummaryText, "已用 2/2 次")
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertNotNil(result.finalState.latestReview, "预算耗尽前已执行的动作产物应保留，交付当前最好版本")
        XCTAssertEqual(result.steps.first?.step_type, "decision")
        XCTAssertTrue(result.steps.first?.decision_json?.contains("writing_review") == true)
    }

    func testSameActionThreeTimesConsecutivelyForcesStop() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.polishNatural.rawValue, reason: "润色1", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.polishNatural.rawValue, reason: "润色2", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.polishNatural.rawValue, reason: "润色3", stop: false))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(content: "已经有一版正文，足够长，不会被判定为空。"))

        XCTAssertEqual(result.stopReason, .repeatedActionLimit)
        XCTAssertEqual(executor.callLog.filter { $0 == "polish-natural-native" }.count, 2, "第 3 次连续选择应直接停机，不应真正执行")
        XCTAssertEqual(result.steps.filter { $0.step_type == "decision" }.count, 3)
    }

    func testStallDetectionStopsAfterTwoConsecutiveUnchangedRounds() async {
        // 用两个不同动作（避免触发"连续同一动作"护栏）但让假 executor 每次都原样返回
        // 已有标题/正文，模拟"模型没有真正改进草稿"：状态哈希连续两轮不变应判定为空转。
        let unchangedTitle = "标题"
        let unchangedContent = "完全没有变化的正文。"
        let executor = ScriptedAgentExecutor()
        executor.fixedDraftOverride = DraftResult(title: unchangedTitle, content: unchangedContent, summary: "摘要", tags: nil, raw_output: nil)
        executor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.polishNatural.rawValue, reason: "润色1", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.polishTighten.rawValue, reason: "润色2", stop: false))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        var input = Self.makeInput(content: unchangedContent)
        input.title = unchangedTitle
        let result = await coordinator.run(input: input)

        XCTAssertEqual(result.stopReason, .stalled, "连续两轮动作执行后状态哈希未变化，应判定为空转")
        XCTAssertEqual(result.steps.filter { $0.step_type == "action" }.count, 2)
    }

    func testActionOutOfBoundsGetsOneCorrectiveRetryThenStops() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(action: "delete_everything", reason: "越界动作", stop: false)),
            .json(AgentDecisionResult(action: "delete_everything", reason: "仍然越界", stop: false))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput())

        XCTAssertEqual(result.stopReason, .invalidDecision)
        XCTAssertEqual(result.steps.count, 2, "两次决策都应记录，且都不应执行任何动作")
        XCTAssertEqual(executor.callLog.count, 2)
    }

    func testInvalidDecisionJSONTriggersSafeStop() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [.failure("模型返回内容不是有效 JSON。")]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput())

        guard case .circuitBreak(let reason) = result.stopReason else {
            XCTFail("应停在 circuitBreak，实际是 \(result.stopReason)")
            return
        }
        XCTAssertEqual(reason, "模型返回内容不是有效 JSON。")
        XCTAssertEqual(result.steps.count, 1)
    }

    func testAskAuthorProducesQuestionsAndResumableHandleWithInheritedBudget() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(
                action: AgentSessionAction.askAuthor.rawValue,
                arguments: AgentDecisionArguments(query: "需要更多关于XX的素材\n需要确认YY的时间线"),
                reason: "缺证据",
                stop: false
            ))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let firstResult = await coordinator.run(input: Self.makeInput(callBudget: 12))

        XCTAssertEqual(firstResult.stopReason, .askAuthor)
        XCTAssertEqual(firstResult.askAuthorQuestions, ["需要更多关于XX的素材", "需要确认YY的时间线"])
        XCTAssertTrue(firstResult.finalState.askAuthorUsed)
        XCTAssertEqual(firstResult.finalState.usedCalls, 1)

        // 续跑：预算继承自暂停时的状态；模型又选择 ask_author，但本会话已用过一次，
        // 越界后走一次纠正重试，仍越界则安全停机。
        let resumeExecutor = ScriptedAgentExecutor()
        resumeExecutor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.askAuthor.rawValue, reason: "再次提问", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.askAuthor.rawValue, reason: "还是提问", stop: false))
        ]
        let resumeCoordinator = WritingAgentCoordinator(executor: resumeExecutor)
        let resumeResult = await resumeCoordinator.resume(
            state: firstResult.finalState,
            before: firstResult.before,
            input: Self.makeInput(callBudget: 12)
        )

        XCTAssertEqual(resumeResult.stopReason, .invalidDecision)
        XCTAssertEqual(resumeResult.finalState.usedCalls, 3, "预算继承：首次 1 次 + 续跑两次纠正决策 = 3")
    }

    func testMissingAPIKeyRejectsAtEntryWithoutEnteringLoop() async {
        let executor = ScriptedAgentExecutor()
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(apiKey: ""))

        XCTAssertEqual(result.stopReason, .missingAPIKey)
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertTrue(executor.callLog.isEmpty, "会话入口直接拒绝，不应发起任何模型调用")
    }

    func testAgentQuickDraftProducesContentAndQualityGate() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.agentQuickDraft.rawValue, reason: "先出一版初稿", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.finish.rawValue, reason: "已经够用", stop: true))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput())

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertFalse(result.finalState.content.isEmpty)
        XCTAssertNotNil(result.finalState.latestGate)
        XCTAssertTrue(result.steps.contains { $0.step_type == "action" })
    }

    /// PRD 23.8.1 验收标准 2：search_materials 命中的素材应进入下一轮观察（actionHistoryLines），
    /// 完整片段落 agent_steps；且检索本身不计入模型调用预算（只有决策步计数）。
    func testSearchMaterialsEntersNextRoundObservationWithoutConsumingModelBudget() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(
                action: AgentSessionAction.searchMaterials.rawValue,
                arguments: AgentDecisionArguments(query: "胡同"),
                reason: "缺证据，先检索本地素材",
                stop: false
            )),
            .json(AgentDecisionResult(action: AgentSessionAction.finish.rawValue, reason: "够用了", stop: true))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(fragmentCorpus: Self.makeFragmentCorpus()))

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.finalState.searchCount, 1)
        XCTAssertEqual(result.finalState.usedCalls, 2, "两轮决策各计 1 次，检索本身不额外消耗预算")
        XCTAssertEqual(result.finalState.retrievedFragments.first?.citationTitle, "胡同的故事")
        XCTAssertTrue(result.finalState.actionHistoryLines.contains { $0.contains("胡同") }, "命中片段应压缩进下一轮观察")
        XCTAssertTrue(result.steps.contains { $0.name == "检索素材" && $0.status == "success" && $0.output_summary.contains("胡同") })
    }

    /// 同一 query 本会话第二次发起应被拒绝（不重复检索、不产生新片段），但会话应继续而非熔断。
    func testSearchMaterialsRejectsDuplicateQueryButSessionContinues() async {
        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            .json(AgentDecisionResult(action: AgentSessionAction.searchMaterials.rawValue, arguments: AgentDecisionArguments(query: "胡同"), reason: "先检索", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.searchMaterials.rawValue, arguments: AgentDecisionArguments(query: "胡同"), reason: "再检索一次同样的", stop: false)),
            .json(AgentDecisionResult(action: AgentSessionAction.finish.rawValue, reason: "够用了", stop: true))
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(fragmentCorpus: Self.makeFragmentCorpus()))

        XCTAssertEqual(result.stopReason, .finished, "重复 query 应被拒绝而非让会话熔断")
        XCTAssertEqual(result.finalState.searchCount, 1, "第二次同 query 检索不应计入检索次数")
        XCTAssertEqual(result.finalState.retrievedFragments.count, 1, "第二次同 query 检索不应重复产生片段")
        let searchSteps = result.steps.filter { $0.name == "检索素材" }
        XCTAssertEqual(searchSteps.count, 2)
        XCTAssertEqual(searchSteps.last?.status, "fallback")
        XCTAssertTrue(searchSteps.last?.output_summary.contains("已检索过") == true)
    }

    /// 每会话检索上限 4 次：第 5 次发起 search_materials 时前置条件已不满足，进入越界纠正流程后安全停机。
    func testSearchMaterialsRejectsAfterSessionCapOfFour() async {
        func search(_ query: String) -> ScriptedAgentExecutor.ScriptedDecision {
            .json(AgentDecisionResult(action: AgentSessionAction.searchMaterials.rawValue, arguments: AgentDecisionArguments(query: query), reason: "检索", stop: false))
        }
        func review() -> ScriptedAgentExecutor.ScriptedDecision {
            .json(AgentDecisionResult(action: AgentSessionAction.writingReview.rawValue, reason: "顺便看看诊断", stop: false))
        }

        let executor = ScriptedAgentExecutor()
        executor.decisions = [
            search("q1"), review(),
            search("q2"), review(),
            search("q3"), review(),
            search("q4"),
            search("q5"), // 第 5 次：此时已达会话上限，越界，纠正重试一次
            search("q5")  // 仍越界，安全停机
        ]
        let coordinator = WritingAgentCoordinator(executor: executor)

        let result = await coordinator.run(input: Self.makeInput(callBudget: 20, fragmentCorpus: Self.makeFragmentCorpus()))

        XCTAssertEqual(result.stopReason, .invalidDecision, "第 5 次检索前置条件不满足，应走越界纠正后安全停机")

        XCTAssertEqual(result.finalState.searchCount, 4, "会话检索次数不应超过上限 4 次")
        XCTAssertEqual(result.finalState.usedCalls, 12, "writing_review 每轮各计 2 次（决策+执行），search_materials 与越界重试各只计 1 次（决策）：3×2 + 4×1 + 2×1 = 12")
    }

    // MARK: - Fixtures

    private static func makeStyle() -> StyleProfile {
        StyleProfile(
            id: 1,
            name: "测试风格",
            language_style: "中文",
            tone: "克制",
            structure_preference: nil,
            favorite_expressions: nil,
            forbidden_expressions: nil,
            sample_texts: nil,
            title_style_like: nil,
            title_style_dislike: nil,
            is_default: 1
        )
    }

    private static func makeInput(
        content: String = "",
        outline: String = "",
        callBudget: Int = 12,
        apiKey: String = "fake-key",
        fragmentCorpus: [Fragment] = []
    ) -> WritingAgentSessionInput {
        WritingAgentSessionInput(
            idea: "一个想法",
            direction: "情感文学",
            materials: "一些素材",
            style: makeStyle(),
            title: "",
            summary: "",
            content: content,
            outline: outline,
            config: ModelConfig(),
            apiKey: apiKey,
            callBudget: callBudget,
            fragmentCorpus: fragmentCorpus
        )
    }

    private static func makeFragmentCorpus() -> [Fragment] {
        [
            Fragment(
                id: 10,
                source_type: "idea",
                source_id: 10,
                title: "胡同的故事",
                content: "胡同里邻居总在傍晚闲聊。",
                keywords: ["胡同", "邻居"],
                created_at: nil,
                updated_at: nil
            )
        ]
    }
}

/// 可脚本化的假 executor：决策步按序返回预设结果，其余动作步复用 descriptor 自带 fallback，
/// 但对生成类端点按调用序号生成不同正文，避免状态哈希意外相同触发空转检测。
private final class ScriptedAgentExecutor: AIWorkflowExecuting {
    enum ScriptedDecision {
        case json(AgentDecisionResult)
        case failure(String)
    }

    private(set) var callLog: [String] = []
    var decisions: [ScriptedDecision] = []
    /// 设置后，所有生成类端点都原样返回这个固定草稿（用于模拟"模型没有真正改进"的空转场景）。
    var fixedDraftOverride: DraftResult?
    private var decisionCursor = 0
    private var contentCounter = 0

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callLog.append(descriptor.endpoint)

        if descriptor.endpoint == "agent-decision-native" {
            guard decisionCursor < decisions.count else {
                let result = AgentDecisionResult(action: AgentSessionAction.finish.rawValue, stop: true)
                guard let typed = result as? Output else {
                    return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
                }
                return AIRun(result: typed, elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
            }
            let scripted = decisions[decisionCursor]
            decisionCursor += 1
            switch scripted {
            case .json(let decision):
                guard let typed = decision as? Output else {
                    return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: false, error: "type mismatch", inputSummary: "fake", outputSummary: "fake")
                }
                return AIRun(result: typed, elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
            case .failure(let message):
                return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: false, error: message, inputSummary: "fake", outputSummary: "fake")
            }
        }

        if descriptor.endpoint == "polish-natural-native" || descriptor.endpoint == "polish-tighten-native"
            || descriptor.endpoint == "draft-native" || descriptor.endpoint == "review-driven-revision-native" {
            let draft: DraftResult
            if let fixedDraftOverride {
                draft = fixedDraftOverride
            } else {
                contentCounter += 1
                draft = DraftResult(
                    title: "标题第\(contentCounter)版",
                    content: String(repeating: "正文第\(contentCounter)版。", count: 20),
                    summary: "摘要\(contentCounter)",
                    tags: nil,
                    raw_output: nil
                )
            }
            guard let typed = draft as? Output else {
                return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
            }
            return AIRun(result: typed, elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
        }

        return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
    }
}
