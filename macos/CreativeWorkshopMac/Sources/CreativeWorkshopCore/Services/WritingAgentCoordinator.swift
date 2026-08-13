import Foundation

/// 一次代理会话的输入：会话开始时的编辑器快照 + 风格 + 模型配置 + 可选自定义模板。
package struct WritingAgentSessionInput {
    package var idea: String
    package var direction: String
    package var materials: String
    package var style: StyleProfile
    package var title: String
    package var summary: String
    package var content: String
    package var outline: String
    package var config: ModelConfig
    package var apiKey: String
    package var callBudget: Int
    package var decisionTemplate: PromptTemplate?
    package var writingReviewTemplate: PromptTemplate?
    package var polishTemplate: PromptTemplate?
    package var draftTemplate: PromptTemplate?
    package var outlineTemplate: PromptTemplate?
    /// search_materials 动作的本地检索语料（任务 16）；本协调器不接触数据库，语料由调用方一次性传入。
    package var fragmentCorpus: [Fragment]
    /// 无头评测置 false（第二轮评测修缮）：评测环境没有作者可问，ask_author 从动作空间移除。
    package var allowAskAuthor: Bool

    package init(
        idea: String,
        direction: String,
        materials: String,
        style: StyleProfile,
        title: String = "",
        summary: String = "",
        content: String = "",
        outline: String = "",
        config: ModelConfig,
        apiKey: String,
        callBudget: Int = 12,
        decisionTemplate: PromptTemplate? = nil,
        writingReviewTemplate: PromptTemplate? = nil,
        polishTemplate: PromptTemplate? = nil,
        draftTemplate: PromptTemplate? = nil,
        outlineTemplate: PromptTemplate? = nil,
        fragmentCorpus: [Fragment] = [],
        allowAskAuthor: Bool = true
    ) {
        self.idea = idea
        self.direction = direction
        self.materials = materials
        self.style = style
        self.title = title
        self.summary = summary
        self.content = content
        self.outline = outline
        self.config = config
        self.apiKey = apiKey
        self.callBudget = callBudget
        self.decisionTemplate = decisionTemplate
        self.writingReviewTemplate = writingReviewTemplate
        self.polishTemplate = polishTemplate
        self.draftTemplate = draftTemplate
        self.outlineTemplate = outlineTemplate
        self.fragmentCorpus = fragmentCorpus
        self.allowAskAuthor = allowAskAuthor
    }
}

/// PRD 23.6：有界代理循环的内核。模型每轮观察会话状态、在封闭动作空间选下一步，
/// 护栏校验/执行，结果回流会话状态，直到 finish / ask_author / 预算耗尽 / 熔断。
///
/// 关键约束（否则会与 Store 的待复核状态机死锁）：本协调器绝不调用 WorkshopStore 的
/// 生成类动作函数——所有中间产物只更新会话本地的 `AgentSessionState` 快照并入轨迹；
/// 只有会话结束时，调用方才把最终稿一次性交付 `pendingDraftReview`。
package struct WritingAgentCoordinator {
    package let executor: AIWorkflowExecuting

    package init(executor: AIWorkflowExecuting) {
        self.executor = executor
    }

    /// 开始一个新会话。`onStep` 供调用方（Store）驱动执行中的流式状态展示，非必需。
    package func run(
        input: WritingAgentSessionInput,
        onStep: (@Sendable (Int, String) -> Void)? = nil
    ) async -> AgentSessionResult {
        let before = DraftSnapshot(title: input.title, summary: input.summary, content: input.content)
        guard !input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AgentSessionResult(
                finalState: AgentSessionState(
                    idea: input.idea,
                    direction: input.direction,
                    materials: input.materials,
                    style: input.style,
                    title: input.title,
                    summary: input.summary,
                    content: input.content,
                    outline: input.outline,
                    callBudget: input.callBudget
                ),
                stopReason: .missingAPIKey,
                steps: [],
                askAuthorQuestions: nil,
                before: before,
                elapsed_ms: 0
            )
        }

        var state = AgentSessionState(
            idea: input.idea,
            direction: input.direction,
            materials: input.materials,
            style: input.style,
            title: input.title,
            summary: input.summary,
            content: input.content,
            outline: input.outline,
            callBudget: input.callBudget
        )
        state.allowAskAuthor = input.allowAskAuthor
        return await runLoop(state: state, before: before, input: input, onStep: onStep)
    }

    /// 续跑一个此前因 ask_author 暂停的会话：预算与 `askAuthorUsed` 均继承自传入的状态快照，
    /// 因此同一会话内 ask_author 至多只能触发一次（PRD 23.6.2）。
    package func resume(
        state: AgentSessionState,
        before: DraftSnapshot,
        input: WritingAgentSessionInput,
        onStep: (@Sendable (Int, String) -> Void)? = nil
    ) async -> AgentSessionResult {
        guard !input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AgentSessionResult(finalState: state, stopReason: .missingAPIKey, steps: [], askAuthorQuestions: nil, before: before, elapsed_ms: 0)
        }
        return await runLoop(state: state, before: before, input: input, onStep: onStep)
    }

    private func runLoop(
        state initialState: AgentSessionState,
        before: DraftSnapshot,
        input: WritingAgentSessionInput,
        onStep: (@Sendable (Int, String) -> Void)?
    ) async -> AgentSessionResult {
        var state = initialState
        var steps: [AgentStepPayload] = []
        let start = Date()
        var correctionNote: String?
        var consecutiveInvalidDecisions = 0

        while true {
            guard state.remainingCalls > 0 else {
                return result(state: state, steps: steps, stopReason: .budgetExhausted, askAuthorQuestions: nil, before: before, start: start)
            }

            let availableActions = state.availableActions
            let decisionRun: AIRun<AgentDecisionResult> = await executor.execute(
                NativeWorkflowCatalog.agentDecision(
                    state: state,
                    availableActions: availableActions,
                    correctionNote: correctionNote,
                    template: input.decisionTemplate
                ),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            steps.append(
                AgentStepPayload(
                    step_index: steps.count + 1,
                    name: "决策",
                    status: decisionRun.success ? "success" : "fallback",
                    input_summary: decisionRun.inputSummary,
                    output_summary: decisionRun.result.reason ?? decisionRun.result.action ?? "（无原因）",
                    elapsed_ms: decisionRun.elapsedMS,
                    error: decisionRun.error,
                    step_type: AgentSessionStepKind.decision.rawValue,
                    decision_json: Self.decisionJSON(decisionRun.result)
                )
            )

            guard decisionRun.success else {
                return result(state: state, steps: steps, stopReason: .circuitBreak(reason: decisionRun.error), askAuthorQuestions: nil, before: before, start: start)
            }

            guard
                let actionRaw = decisionRun.result.action,
                let action = AgentSessionAction(rawValue: actionRaw),
                availableActions.contains(action)
            else {
                guard consecutiveInvalidDecisions < 1 else {
                    return result(state: state, steps: steps, stopReason: .invalidDecision, askAuthorQuestions: nil, before: before, start: start)
                }
                consecutiveInvalidDecisions += 1
                let invalidLabel = decisionRun.result.action ?? "（空）"
                correctionNote = "上一次选择的动作「\(invalidLabel)」不在当前可用动作清单中，或不满足前置条件，请重新从【可用动作】中选择。"
                continue
            }
            consecutiveInvalidDecisions = 0
            correctionNote = nil

            if state.lastAction == action {
                state.lastActionRepeatCount += 1
            } else {
                state.lastAction = action
                state.lastActionRepeatCount = 1
            }
            guard state.lastActionRepeatCount < 3 else {
                return result(state: state, steps: steps, stopReason: .repeatedActionLimit, askAuthorQuestions: nil, before: before, start: start)
            }

            onStep?(steps.count, action.title)

            switch action {
            case .finish:
                return result(state: state, steps: steps, stopReason: .finished, askAuthorQuestions: nil, before: before, start: start)

            case .askAuthor:
                state.askAuthorUsed = true
                let questions = Self.splitQuestions(decisionRun.result.arguments?.query)
                return result(state: state, steps: steps, stopReason: .askAuthor, askAuthorQuestions: questions, before: before, start: start)

            default:
                let preHash = state.stateHash
                let outcome = await execute(action: action, query: decisionRun.result.arguments?.query, state: &state, input: input)
                steps.append(contentsOf: outcome.steps)
                guard outcome.success else {
                    return result(state: state, steps: steps, stopReason: .circuitBreak(reason: outcome.error), askAuthorQuestions: nil, before: before, start: start)
                }
                state.actionHistoryLines.append(outcome.historyLine)
                if state.stateHash == preHash {
                    state.stallCount += 1
                } else {
                    state.stallCount = 0
                }
                guard state.stallCount < 2 else {
                    return result(state: state, steps: steps, stopReason: .stalled, askAuthorQuestions: nil, before: before, start: start)
                }
            }
        }
    }

    private func result(
        state: AgentSessionState,
        steps: [AgentStepPayload],
        stopReason: AgentSessionStopReason,
        askAuthorQuestions: [String]?,
        before: DraftSnapshot,
        start: Date
    ) -> AgentSessionResult {
        AgentSessionResult(
            finalState: state,
            stopReason: stopReason,
            steps: AgentRunPayloads.reindexed(steps),
            askAuthorQuestions: askAuthorQuestions,
            before: before,
            elapsed_ms: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    // MARK: - 动作执行（会话本地状态，绝不调用 Store）

    private struct ActionExecutionOutcome {
        var success: Bool
        var error: String
        var steps: [AgentStepPayload]
        var historyLine: String
    }

    private func execute(
        action: AgentSessionAction,
        query: String?,
        state: inout AgentSessionState,
        input: WritingAgentSessionInput
    ) async -> ActionExecutionOutcome {
        switch action {
        case .generateOutline:
            let topic = Self.sessionTopic(state)
            let context = makeContext(state: state, stage: "会话：生成大纲")
            let run: AIRun<OutlineResult> = await executor.execute(
                NativeWorkflowCatalog.outline(topic: topic, context: context, style: state.style, template: input.outlineTemplate),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            let step = Self.actionStep(action, run: run)
            guard run.success else {
                return ActionExecutionOutcome(success: false, error: run.error, steps: [step], historyLine: "")
            }
            if let generatedTitle = run.result.title, !generatedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.title = generatedTitle
            }
            state.outline = run.result.markdown
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: [step],
                historyLine: historyLine(action, note: "已生成大纲", state: state)
            )

        case .draftFromOutline:
            let topic = Self.sessionTopic(state)
            var context = makeContext(state: state, stage: "会话：大纲成稿")
            context.outline_excerpt = state.outline
            let run: AIRun<DraftResult> = await executor.execute(
                NativeWorkflowCatalog.draft(topic: topic, context: context, style: state.style, template: input.draftTemplate),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            let step = Self.actionStep(action, run: run)
            guard run.success else {
                return ActionExecutionOutcome(success: false, error: run.error, steps: [step], historyLine: "")
            }
            Self.applyDraft(run.result, to: &state)
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: [step],
                historyLine: historyLine(action, note: "已生成正文（\(state.content.count) 字）", state: state)
            )

        case .agentQuickDraft:
            let context = makeContext(state: state, stage: "会话：代理式初稿")
            let response = await AgentDraftCoordinator(executor: executor).run(
                context: context,
                style: state.style,
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += response.steps.count
            let steps = response.steps.map { step -> AgentStepPayload in
                AgentStepPayload(
                    step_index: 0,
                    name: "\(action.title)：\(step.name)",
                    status: step.status,
                    input_summary: step.input_summary,
                    output_summary: step.output_summary,
                    elapsed_ms: step.elapsed_ms,
                    error: step.error,
                    step_type: AgentSessionStepKind.action.rawValue
                )
            }
            guard response.circuitBreak == nil else {
                return ActionExecutionOutcome(success: false, error: response.error, steps: steps, historyLine: "")
            }
            state.title = response.result.title ?? state.title
            state.summary = response.result.summary ?? state.summary
            state.content = response.result.content ?? response.result.raw_output ?? state.content
            state.latestGate = AgentDraftQualityGateEvaluator.evaluate(
                trace: response.trace,
                selfCheck: state.latestSelfCheck,
                content: state.content,
                knownPitfalls: (state.style.known_pitfalls ?? []).map(\.description)
            )
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: steps,
                historyLine: historyLine(action, note: "已生成代理式初稿（\(state.content.count) 字）", state: state)
            )

        case .writingReview:
            let context = makeContext(state: state, stage: "会话：写作诊断")
            let run: AIRun<WritingReviewResult> = await executor.execute(
                NativeWorkflowCatalog.writingReview(
                    context: context,
                    style: state.style,
                    previousReview: state.latestReview,
                    template: input.writingReviewTemplate
                ),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            let step = AgentStepPayload(
                step_index: 0,
                name: action.title,
                status: run.success ? "success" : "fallback",
                input_summary: run.inputSummary,
                output_summary: run.outputSummary,
                elapsed_ms: run.elapsedMS,
                error: run.error,
                step_type: AgentSessionStepKind.verification.rawValue
            )
            guard run.success else {
                return ActionExecutionOutcome(success: false, error: run.error, steps: [step], historyLine: "")
            }
            state.latestReview = Self.transientReview(from: run.result, title: state.title)
            let scoreNote = state.latestReview?.overall_score.map { "评分 \($0)" } ?? "无评分"
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: [step],
                historyLine: historyLine(action, note: "完成诊断（\(scoreNote)）", state: state)
            )

        case .improveFromReview:
            guard let review = state.latestReview else {
                return ActionExecutionOutcome(success: false, error: "会话内没有可用诊断", steps: [], historyLine: "")
            }
            let context = makeContext(state: state, stage: "会话：按诊断修订")
            let run: AIRun<DraftResult> = await executor.execute(
                NativeWorkflowCatalog.improveDraftFromReview(context: context, content: state.content, review: review, style: state.style),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            let step = Self.actionStep(action, run: run)
            guard run.success else {
                return ActionExecutionOutcome(success: false, error: run.error, steps: [step], historyLine: "")
            }
            Self.applyDraft(run.result, to: &state)
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: [step],
                historyLine: historyLine(action, note: "已按诊断修订正文", state: state)
            )

        case .polishNatural, .polishTighten:
            let mode: PolishMode = action == .polishNatural ? .natural : .tighten
            let context = makeContext(state: state, stage: "会话：\(action.title)")
            let run: AIRun<DraftResult> = await executor.execute(
                NativeWorkflowCatalog.polishDraft(context: context, content: state.content, mode: mode, style: state.style, template: input.polishTemplate),
                config: input.config,
                apiKey: input.apiKey
            )
            state.usedCalls += 1
            let step = Self.actionStep(action, run: run)
            guard run.success else {
                return ActionExecutionOutcome(success: false, error: run.error, steps: [step], historyLine: "")
            }
            Self.applyDraft(run.result, to: &state)
            return ActionExecutionOutcome(
                success: true,
                error: "",
                steps: [step],
                historyLine: historyLine(action, note: "已完成\(action.title)", state: state)
            )

        case .searchMaterials:
            return executeSearchMaterials(query: query, state: &state, input: input)

        case .askAuthor, .finish:
            // 由 runLoop 直接处理，不会走到这里。
            return ActionExecutionOutcome(success: true, error: "", steps: [], historyLine: "")
        }
    }

    /// 本地纯检索，不发起模型调用（不计入 usedCalls）；同一 query 本会话只生效一次，会话上限 4 次
    /// 由 `AgentSessionAction.searchMaterials.isAvailable` 在决策前过滤，这里只处理"query 重复"的运行时拒绝（PRD 23.8.1）。
    private func executeSearchMaterials(
        query: String?,
        state: inout AgentSessionState,
        input: WritingAgentSessionInput
    ) -> ActionExecutionOutcome {
        let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            let step = Self.searchStep(query: "（空）", hits: [], rejected: true, reason: "query 为空，未执行检索")
            return ActionExecutionOutcome(success: true, error: "", steps: [step], historyLine: historyLine(.searchMaterials, note: "query 为空，未执行检索", state: state))
        }
        guard !state.searchedQueries.contains(trimmedQuery) else {
            let step = Self.searchStep(query: trimmedQuery, hits: [], rejected: true, reason: "该 query 本会话已检索过，拒绝重复检索")
            return ActionExecutionOutcome(success: true, error: "", steps: [step], historyLine: historyLine(.searchMaterials, note: "「\(trimmedQuery)」已检索过，未重复调用", state: state))
        }

        let hits = FragmentRetriever.retrieve(query: trimmedQuery, fragments: input.fragmentCorpus, limit: 3)
        state.searchedQueries.insert(trimmedQuery)
        state.searchCount += 1
        state.retrievedFragments = FragmentRetriever.unique(state.retrievedFragments + hits)

        let step = Self.searchStep(query: trimmedQuery, hits: hits, rejected: false, reason: nil)
        let observation = hits.isEmpty ? "未检索到相关素材" : Self.compressedObservation(hits)
        return ActionExecutionOutcome(
            success: true,
            error: "",
            steps: [step],
            historyLine: historyLine(.searchMaterials, note: "检索「\(trimmedQuery)」→ \(observation)", state: state)
        )
    }

    private func makeContext(state: AgentSessionState, stage: String) -> ContextPackage {
        let trimmedContent = state.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphCount = trimmedContent
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return ContextPackage(
            stage: stage,
            title: state.title,
            summary: state.summary,
            idea: state.idea,
            direction: state.direction,
            outline_excerpt: state.outline,
            content_excerpt: Self.excerptContent(trimmedContent),
            materials_excerpt: state.materials,
            selected_topic_title: state.selectedTopicTitle,
            selected_topic_summary: nil,
            style_name: state.style.name,
            style_brief: state.style.tone ?? "",
            word_count: trimmedContent.count,
            paragraph_count: paragraphCount,
            material_count: state.materials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1,
            recent_article_titles: [],
            recent_training_focus: state.latestReview?.training_focus ?? [],
            recent_issues: (state.latestReview?.issues ?? []).prefix(6).map { "\($0.dimension)：\($0.problem)" },
            genre: state.style.genre,
            known_pitfalls: (state.style.known_pitfalls ?? []).map(\.description),
            last_review_summary: state.latestReview?.summary,
            learned_preferences: (state.style.learned_preferences ?? []).map(\.description)
        )
    }

    private func historyLine(_ action: AgentSessionAction, note: String, state: AgentSessionState) -> String {
        "\(action.title) → \(note) → \(state.verificationReport.summaryLine)"
    }

    /// 观察压缩铁律：正文只给首尾节选进决策 prompt，完整产物只入轨迹（PRD 23.6.1 / 设计律 a）。
    private static func excerptContent(_ content: String) -> String {
        guard content.count > 2_000 else {
            return content
        }
        let prefix = content.prefix(1_000)
        let suffix = content.suffix(800)
        return "\(prefix)\n\n...\n\n\(suffix)"
    }

    private static func sessionTopic(_ state: AgentSessionState) -> TopicPayload {
        let titleCandidate = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return TopicPayload(
            title: titleCandidate.isEmpty ? state.idea : titleCandidate,
            direction: state.direction,
            core_viewpoint: nil,
            target_reader: nil,
            description: nil,
            angle: nil,
            emotion: nil,
            score: nil,
            status: nil,
            tags: nil
        )
    }

    private static func applyDraft(_ result: DraftResult, to state: inout AgentSessionState) {
        if let title = result.title, !title.isEmpty {
            state.title = title
        }
        if let summary = result.summary, !summary.isEmpty {
            state.summary = summary
        }
        state.content = result.content ?? result.raw_output ?? state.content
    }

    private static func actionStep<T>(_ action: AgentSessionAction, run: AIRun<T>) -> AgentStepPayload {
        AgentStepPayload(
            step_index: 0,
            name: action.title,
            status: run.success ? "success" : "fallback",
            input_summary: run.inputSummary,
            output_summary: run.outputSummary,
            elapsed_ms: run.elapsedMS,
            error: run.error,
            step_type: AgentSessionStepKind.action.rawValue
        )
    }

    /// search_materials 的 agent_steps 记录：output_summary 落地 query / 返回数 / 最高分 + 完整片段（审计用途，
    /// PRD 23.8.1 命中率记录）；进入下一轮决策 prompt 的观察另走 `compressedObservation`（只给来源 + 首行）。
    private static func searchStep(query: String, hits: [RetrievedFragment], rejected: Bool, reason: String?) -> AgentStepPayload {
        let summary: String
        if rejected {
            summary = reason ?? "检索被拒绝"
        } else {
            let topScoreText = hits.map(\.score).max().map { String(format: "%.2f", $0) } ?? "无"
            let fullFragments = hits
                .map { "\($0.citationTitle)（\(String(format: "%.2f", $0.score))）：\($0.content)" }
                .joined(separator: "\n")
            summary = "query：\(query)；返回 \(hits.count) 条；最高分 \(topScoreText)\(fullFragments.isEmpty ? "" : "\n\(fullFragments)")"
        }
        return AgentStepPayload(
            step_index: 0,
            name: AgentSessionAction.searchMaterials.title,
            status: rejected ? "fallback" : "success",
            input_summary: "query: \(query)",
            output_summary: summary,
            elapsed_ms: 0,
            error: "",
            step_type: AgentSessionStepKind.action.rawValue
        )
    }

    /// 观察压缩铁律：进入下一轮决策 prompt 的只有"来源 + 首行"，完整片段只入 agent_steps。
    private static func compressedObservation(_ hits: [RetrievedFragment]) -> String {
        hits.map { "\($0.citationTitle)：\(firstLine($0.content))" }.joined(separator: "；")
    }

    private static func firstLine(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? text
    }

    /// transient：与 DeepDraftCoordinator 的先例一致，不写入 writing_reviews，只用于本会话决策上下文。
    private static func transientReview(from result: WritingReviewResult, title: String) -> WritingReview {
        WritingReview(
            id: -1,
            article_id: nil,
            title_snapshot: title,
            summary: result.summary ?? "已完成一轮会话内写作诊断。",
            overall_score: result.overall_score,
            strengths: result.strengths ?? [],
            issues: result.issues ?? [],
            revision_plan: result.revision_plan ?? [],
            training_focus: result.training_focus ?? [],
            style_notes: result.style_notes ?? [],
            raw_output: result.raw_output,
            model: nil,
            created_at: nil,
            resolved_from_last: result.resolved_from_last ?? [],
            reviewed_snapshot: nil,
            pitfall_hits: result.pitfall_hits ?? []
        )
    }

    private static func decisionJSON(_ result: AgentDecisionResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) else {
            return result.raw_output ?? ""
        }
        return text
    }

    /// PRD 23.6.3 的输出契约只有单个 "query" 字段；ask_author 场景下按行/分号拆成具体问题清单。
    private static func splitQuestions(_ query: String?) -> [String] {
        guard let query else { return [] }
        let separators = CharacterSet(charactersIn: "\n；;")
        return query
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension AgentDraftResponse {
    /// 与 WorkshopStore 中 `agentDraftTrace(_:)` 的私有构造逻辑保持一致，供质量门评估使用。
    var trace: AgentDraftTrace {
        AgentDraftTrace(
            workingTitle: brief.working_title ?? result.title ?? "未命名代理初稿",
            coreQuestion: brief.core_question ?? "未返回核心问题",
            thesis: brief.thesis ?? "未返回核心主张",
            targetReader: brief.target_reader ?? "未返回目标读者",
            argumentDirectives: argumentCheck.revision_directives ?? [],
            missingEvidence: argumentCheck.missing_evidence ?? [],
            sectionSummaries: (sectionDraft.sections ?? []).map { section in
                let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
                let check = section.self_check?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let check, !check.isEmpty {
                    return "\(heading.isEmpty ? "未命名段落" : heading)：\(check)"
                }
                return heading.isEmpty ? String(section.content.prefix(40)) : heading
            },
            critiqueNotes: critique.critique_notes ?? [],
            unresolvedGaps: brief.unresolved_gaps ?? [],
            plannedSectionCount: brief.structure_plan?.count ?? 0
        )
    }
}
