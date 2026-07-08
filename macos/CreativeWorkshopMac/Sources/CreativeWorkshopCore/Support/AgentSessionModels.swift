import Foundation

/// 23.6 有界代理循环的封闭动作空间。
package enum AgentSessionAction: String, CaseIterable, Codable, Hashable {
    case generateOutline = "generate_outline"
    case draftFromOutline = "draft_from_outline"
    case agentQuickDraft = "agent_quick_draft"
    case writingReview = "writing_review"
    case improveFromReview = "improve_from_review"
    case polishNatural = "polish_natural"
    case polishTighten = "polish_tighten"
    case searchMaterials = "search_materials"
    case askAuthor = "ask_author"
    case finish = "finish"

    package var title: String {
        switch self {
        case .generateOutline: return "生成大纲"
        case .draftFromOutline: return "大纲成稿"
        case .agentQuickDraft: return "代理式初稿"
        case .writingReview: return "写作诊断"
        case .improveFromReview: return "按诊断修订"
        case .polishNatural: return "自然化润色"
        case .polishTighten: return "紧凑化润色"
        case .searchMaterials: return "检索素材"
        case .askAuthor: return "向作者提问"
        case .finish: return "结束会话"
        }
    }

    /// 展示给模型的前置条件说明，供决策 prompt 的"可用动作"列表使用。
    package var preconditionNote: String {
        switch self {
        case .generateOutline: return "前置：大纲为空"
        case .draftFromOutline: return "前置：大纲非空"
        case .agentQuickDraft: return "前置：正文字数 < 300"
        case .writingReview: return "前置：存在可诊断文本"
        case .improveFromReview: return "前置：存在最近诊断且问题非空"
        case .polishNatural, .polishTighten: return "前置：正文非空"
        case .searchMaterials: return "前置：本会话检索次数 < 4；同一 query 本会话只生效一次，不计入模型调用预算"
        case .askAuthor: return "前置：本会话未用过（每会话至多 1 次）"
        case .finish: return "恒可用"
        }
    }

    /// 护栏强制：模型选择的动作是否满足当前会话状态的前置条件（PRD 23.6.2）。
    package func isAvailable(in state: AgentSessionState) -> Bool {
        switch self {
        case .generateOutline:
            return state.outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .draftFromOutline:
            return !state.outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .agentQuickDraft:
            return state.content.count < 300
        case .writingReview:
            return !state.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !state.outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !state.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .improveFromReview:
            return !(state.latestReview?.issues.isEmpty ?? true)
        case .polishNatural, .polishTighten:
            return !state.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .searchMaterials:
            return state.searchCount < 4
        case .askAuthor:
            // 无头评测没有作者可问（第二轮评测修缮）：allowAskAuthor=false 时该动作整体下架。
            return state.allowAskAuthor && !state.askAuthorUsed
        case .finish:
            // "不空手"收紧（第二轮评测修缮，取代 23.6.2 的"恒可用"）：正文为空时 finish 不可选，
            // 模型必须先产出内容或（在允许时）ask_author；预算耗尽等停机路径不受影响。
            return !state.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 预算剩余 ≤2 时的收缩集合（PRD 23.6.4）。
    package static let budgetShrinkSet: Set<AgentSessionAction> = [.writingReview, .askAuthor, .finish]
}

/// 23.6.1 会话状态（内存结构，从不落库为草稿版本，只有会话结束时才一次性交付）。
/// 观察压缩铁律：正文只给首尾节选进决策 prompt，完整产物只入轨迹。
package struct AgentSessionState {
    // 写作目标
    package var idea: String
    package var direction: String
    package var selectedTopicTitle: String?
    package var materials: String

    package var style: StyleProfile

    // 会话本地稿件快照（绝不写回 Store/数据库，直到会话结束一次性交付）
    package var title: String
    package var summary: String
    package var content: String
    package var outline: String

    // 最近诊断（transient，不写 writing_reviews）
    package var latestReview: WritingReview?
    package var latestSelfCheck: DraftSelfCheckResult?
    package var latestGate: AgentDraftQualityGate?

    // 动作历史："动作 → 一句话结果 → 信号变化"
    package var actionHistoryLines: [String] = []

    // search_materials：本会话已检索过的 query（去重）与检索次数（会话上限 4 次，不占模型调用预算）。
    package var searchedQueries: Set<String> = []
    package var searchCount: Int = 0
    // 本会话所有 search_materials 命中片段的去重累积，供交付时展示引用轨迹。
    package var retrievedFragments: [RetrievedFragment] = []

    // 预算
    package var callBudget: Int
    package var usedCalls: Int = 0

    package var askAuthorUsed: Bool = false
    /// 无头评测置 false（第二轮评测修缮）：ask_author 从可用动作清单整体移除。
    package var allowAskAuthor: Bool = true
    package var lastAction: AgentSessionAction?
    package var lastActionRepeatCount: Int = 0
    package var lastStateHash: Int?
    package var stallCount: Int = 0

    package init(
        idea: String,
        direction: String,
        selectedTopicTitle: String? = nil,
        materials: String,
        style: StyleProfile,
        title: String = "",
        summary: String = "",
        content: String = "",
        outline: String = "",
        callBudget: Int
    ) {
        self.idea = idea
        self.direction = direction
        self.selectedTopicTitle = selectedTopicTitle
        self.materials = materials
        self.style = style
        self.title = title
        self.summary = summary
        self.content = content
        self.outline = outline
        self.callBudget = max(1, callBudget)
    }

    package var remainingCalls: Int {
        max(0, callBudget - usedCalls)
    }

    package var verificationReport: VerificationReport {
        VerificationReport.build(gate: latestGate, selfCheck: latestSelfCheck, pitfalls: style.known_pitfalls)
    }

    /// 状态哈希（标题 + 正文 + 验证信号摘要 + 检索次数）用于空转检测（PRD 23.6.4）。
    /// 计入 searchCount 是为了让"成功的新检索"也算作有效进展，避免连续两轮新检索被误判为空转；
    /// 被拒绝的重复检索不改变 searchCount，因此仍会计入空转检测（符合"拒绝重复检索"的语义）。
    package var stateHash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(content)
        hasher.combine(verificationReport.summaryLine)
        hasher.combine(latestReview?.overall_score)
        hasher.combine(searchCount)
        return hasher.finalize()
    }

    /// 当前可选动作集合：前置条件 + 预算收缩双重过滤。
    package var availableActions: [AgentSessionAction] {
        let candidates = AgentSessionAction.allCases.filter { $0.isAvailable(in: self) }
        guard remainingCalls <= 2 else {
            return candidates
        }
        return candidates.filter { AgentSessionAction.budgetShrinkSet.contains($0) }
    }

    package var budgetSummaryText: String {
        "已用 \(usedCalls)/\(callBudget) 次"
    }
}

/// 会话步的持久化记录：区分决策 / 动作 / 验证步（PRD 23.6 验收标准 2）。
package enum AgentSessionStepKind: String {
    case decision
    case action
    case verification
}

/// 会话结束原因。
package enum AgentSessionStopReason: Equatable {
    case finished
    /// 作者在「代理提问」卡选择"就此结束"，未再消耗模型调用（PRD 23.6.5）。
    case authorEnded
    case askAuthor
    case budgetExhausted
    case repeatedActionLimit
    case stalled
    case invalidDecision
    case circuitBreak(reason: String)
    /// 决策环没有"假演示"的意义（PRD 23.6.4）：会话入口直接拒绝，不进入循环。
    case missingAPIKey

    package var summaryText: String {
        switch self {
        case .finished:
            return "模型判断可以结束会话"
        case .authorEnded:
            return "作者选择结束会话，交付当前最好版本"
        case .askAuthor:
            return "会话需要作者补充信息"
        case .budgetExhausted:
            return "预算耗尽"
        case .repeatedActionLimit:
            return "同一动作连续超过 2 次，强制停机"
        case .stalled:
            return "连续两轮验证信号未变化，判定为空转"
        case .invalidDecision:
            return "决策纠正后仍越界，安全停机"
        case .circuitBreak(let reason):
            return "调用失败：\(reason)"
        case .missingAPIKey:
            return "尚未配置 API Key，无法开始代理会话"
        }
    }
}

/// 会话结果：供 Store 交付 pendingDraftReview / ask_author 输出，以及落库 agent_runs/agent_steps。
package struct AgentSessionResult {
    package var finalState: AgentSessionState
    package var stopReason: AgentSessionStopReason
    package var steps: [AgentStepPayload]
    package var askAuthorQuestions: [String]?
    package var before: DraftSnapshot
    package var elapsed_ms: Int

    package init(
        finalState: AgentSessionState,
        stopReason: AgentSessionStopReason,
        steps: [AgentStepPayload],
        askAuthorQuestions: [String]?,
        before: DraftSnapshot,
        elapsed_ms: Int
    ) {
        self.finalState = finalState
        self.stopReason = stopReason
        self.steps = steps
        self.askAuthorQuestions = askAuthorQuestions
        self.before = before
        self.elapsed_ms = elapsed_ms
    }

    package var after: DraftSnapshot {
        DraftSnapshot(title: finalState.title, summary: finalState.summary, content: finalState.content)
    }

    package var isAskAuthor: Bool {
        stopReason == .askAuthor
    }

    /// 会话摘要：共 N 步、每步动作与理由、验证信号首尾对比、停止原因（PRD 23.6.5）。
    package var sessionSummaryLines: [String] {
        var lines: [String] = ["共 \(steps.count) 步，停止原因：\(stopReason.summaryText)"]
        lines += steps.map { step in
            "\(step.step_index). [\(step.step_type)] \(step.name)：\(step.output_summary)"
        }
        return lines
    }
}

/// ask_author 暂停结果：具体缺口清单 + 可续跑句柄（状态快照即预算继承，PRD 23.6.5）。
package struct AgentAskAuthorPrompt: Identifiable {
    package let id = UUID()
    package var questions: [String]
    package var resumeState: AgentSessionState
    package var before: DraftSnapshot

    package init(questions: [String], resumeState: AgentSessionState, before: DraftSnapshot) {
        self.questions = questions
        self.resumeState = resumeState
        self.before = before
    }
}
