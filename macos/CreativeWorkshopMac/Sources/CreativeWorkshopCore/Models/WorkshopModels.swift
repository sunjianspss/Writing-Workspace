import Foundation

package struct RuntimeStatus: Equatable {
    package let model: String
    package let backend: String
}

package enum AIWorkflowKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case agentDraft = "agent_draft"
    case topics = "topics"
    case outline = "outline"
    case draft = "draft"
    case polishDraft = "polish_draft"
    case improveFromReview = "improve_from_review"
    case writingReview = "writing_review"
    case publishAssets = "publish_assets"
    case rewriteSelection = "rewrite_selection"
    case writingAdvisor = "writing_advisor"
    case draftSelfCheck = "draft_self_check"
    case pitfallSummary = "pitfall_summary"
    case editPreferenceSummary = "edit_preference_summary"
    case readerPerspective = "reader_perspective"
    case deepDraft = "deep_draft"
    case prePublishAudit = "pre_publish_audit"
    case candidateJudge = "candidate_judge"
    /// 23.6 有界代理循环的决策步：判别类、低温、小输出，只选下一步动作或停下。
    case agentDecision = "agent_decision"

    package var id: String { rawValue }

    /// 按工作流类型区分的代码级默认采样参数（22.3.4）：判别类用低温防止评分噪声，
    /// 生成类保留高温创造性并提高 max_tokens/超时以避免长输出截断或超时。
    package var defaultParameters: AIWorkflowDefaultParameters {
        switch self {
        case .writingReview, .candidateJudge, .prePublishAudit, .draftSelfCheck,
             .pitfallSummary, .editPreferenceSummary, .writingAdvisor, .readerPerspective,
             .agentDecision:
            return AIWorkflowDefaultParameters(temperature: 0.2, maxTokens: 4096, timeoutSeconds: 120)
        case .agentDraft, .draft, .polishDraft, .improveFromReview, .deepDraft, .rewriteSelection:
            return AIWorkflowDefaultParameters(temperature: 0.75, maxTokens: 8192, timeoutSeconds: 240)
        case .topics, .outline, .publishAssets:
            return AIWorkflowDefaultParameters(temperature: 0.75, maxTokens: 4096, timeoutSeconds: 120)
        }
    }
}

package struct AIWorkflowDefaultParameters: Equatable {
    package var temperature: Double
    package var maxTokens: Int
    package var timeoutSeconds: TimeInterval
}

/// package：AIWorkflowExecuting 协议需要它作为参数类型，供 evals 可执行文件（PRD 22.4.2）跨模块调用。
package struct ModelConfig: Codable, Equatable {
    package var baseURL: String = "https://api.deepseek.com"
    package var model: String = "deepseek-v4-pro"
    package var workflowOverrides: [String: ModelRouteConfig] = [:]

    package init(
        baseURL: String = "https://api.deepseek.com",
        model: String = "deepseek-v4-pro",
        workflowOverrides: [String: ModelRouteConfig] = [:]
    ) {
        self.baseURL = baseURL
        self.model = model
        self.workflowOverrides = workflowOverrides
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "deepseek-v4-pro"
        workflowOverrides = try container.decodeIfPresent([String: ModelRouteConfig].self, forKey: .workflowOverrides) ?? [:]
    }

    package func resolved(for workflow: AIWorkflowKind?) -> ModelConfig {
        guard let workflow,
              let override = workflowOverrides[workflow.rawValue] else {
            return self
        }
        var resolved = self
        if let baseURL = override.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !baseURL.isEmpty {
            resolved.baseURL = baseURL
        }
        if let model = override.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            resolved.model = model
        }
        resolved.workflowOverrides = workflowOverrides
        return resolved
    }
}

package struct ModelRouteConfig: Codable, Equatable, Hashable {
    package var baseURL: String?
    package var model: String?
    package var temperature: Double?
    package var timeoutSeconds: TimeInterval?
    package var maxTokens: Int?
}

package struct StyleProfile: Codable, Identifiable, Hashable {
    package let id: Int
    package var name: String
    package var language_style: String?
    package var tone: String?
    package var structure_preference: String?
    package var favorite_expressions: String?
    package var forbidden_expressions: String?
    package var sample_texts: [String]?
    package var title_style_like: String?
    package var title_style_dislike: String?
    package var is_default: Int?
    /// 体裁标签，如"情感文学随笔""经典文本再解读"。用于按写作方向匹配风格档案（18.3.4）。
    package var genre: String?
    /// 该体裁的评价重点补充文本，会拼入写作诊断和生成类 prompt（18.3.4）。
    package var genre_focus: String?
    /// 已确认的作者雷区清单（18.3.3），只包含作者手动确认过的条目。
    package var known_pitfalls: [AuthorPitfall]?
    /// 已确认的编辑偏好校准规则（20.4），只包含作者手动确认过的条目。
    package var learned_preferences: [LearnedPreference]?

    package init(
        id: Int,
        name: String,
        language_style: String? = nil,
        tone: String? = nil,
        structure_preference: String? = nil,
        favorite_expressions: String? = nil,
        forbidden_expressions: String? = nil,
        sample_texts: [String]? = nil,
        title_style_like: String? = nil,
        title_style_dislike: String? = nil,
        is_default: Int? = nil,
        genre: String? = nil,
        genre_focus: String? = nil,
        known_pitfalls: [AuthorPitfall]? = nil,
        learned_preferences: [LearnedPreference]? = nil
    ) {
        self.id = id
        self.name = name
        self.language_style = language_style
        self.tone = tone
        self.structure_preference = structure_preference
        self.favorite_expressions = favorite_expressions
        self.forbidden_expressions = forbidden_expressions
        self.sample_texts = sample_texts
        self.title_style_like = title_style_like
        self.title_style_dislike = title_style_dislike
        self.is_default = is_default
        self.genre = genre
        self.genre_focus = genre_focus
        self.known_pitfalls = known_pitfalls
        self.learned_preferences = learned_preferences
    }
}

/// 作者雷区：从历史写作诊断中沉淀下来、经作者确认的高频问题（18.3.3）。
package struct AuthorPitfall: Codable, Identifiable, Hashable {
    package var description: String
    package var source_review_id: Int?
    package var created_at: String?

    package var id: String {
        "\(source_review_id ?? 0)|\(description)"
    }

    package init(description: String, source_review_id: Int? = nil, created_at: String? = nil) {
        self.description = description
        self.source_review_id = source_review_id
        self.created_at = created_at
    }
}

package struct LearnedPreference: Codable, Identifiable, Hashable {
    package var description: String
    package var source_edit_record_ids: [Int]?
    package var created_at: String?

    package var id: String {
        "\((source_edit_record_ids ?? []).map(String.init).joined(separator: ","))|\(description)"
    }

    package init(description: String, source_edit_record_ids: [Int]? = nil, created_at: String? = nil) {
        self.description = description
        self.source_edit_record_ids = source_edit_record_ids
        self.created_at = created_at
    }
}

package struct DraftResponse: Codable {
    package let result: DraftResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct AgentDraftResponse {
    package let result: DraftResult
    package let brief: WritingBriefResult
    package let argumentCheck: ArgumentCheckResult
    package let sectionDraft: SectionDraftResult
    package let critique: DraftCritiqueResult
    package let sectionFragmentContexts: [SectionFragmentContext]
    package let elapsed_ms: Int
    package let success: Bool
    package let error: String
    package let input_summary: String
    package let output_summary: String
    package let steps: [AgentStepPayload]
    /// 非空表示管线在某一步（非 missingAPIKey 演示模式）失败后熔断（PRD 22.3.3-B）：
    /// 调用方不得据此产出待复核草稿，只应记录已完成步骤并提示失败原因。
    package let circuitBreak: AgentDraftCircuitBreak?
}

package struct AgentDraftCircuitBreak: Equatable {
    package let stepIndex: Int
    package let stepName: String
    package let reason: String
}

package struct AgentDraftTrace: Codable, Hashable {
    package var workingTitle: String
    package var coreQuestion: String
    package var thesis: String
    package var targetReader: String
    package var argumentDirectives: [String]
    package var missingEvidence: [String]
    package var sectionSummaries: [String]
    package var critiqueNotes: [String]
    package var unresolvedGaps: [String] = []
    /// brief.structure_plan 的计划段落数，用于质量门的结构偏差检查（PRD 22.2.2）。
    package var plannedSectionCount: Int = 0

    package init(
        workingTitle: String,
        coreQuestion: String,
        thesis: String,
        targetReader: String,
        argumentDirectives: [String],
        missingEvidence: [String],
        sectionSummaries: [String],
        critiqueNotes: [String],
        unresolvedGaps: [String] = [],
        plannedSectionCount: Int = 0
    ) {
        self.workingTitle = workingTitle
        self.coreQuestion = coreQuestion
        self.thesis = thesis
        self.targetReader = targetReader
        self.argumentDirectives = argumentDirectives
        self.missingEvidence = missingEvidence
        self.sectionSummaries = sectionSummaries
        self.critiqueNotes = critiqueNotes
        self.unresolvedGaps = unresolvedGaps
        self.plannedSectionCount = plannedSectionCount
    }
}

package struct AgentStepPayload: Codable, Hashable, Identifiable {
    package var step_index: Int
    package var name: String
    package var status: String
    package var input_summary: String
    package var output_summary: String
    package var elapsed_ms: Int
    package var error: String
    /// 23.6：区分决策/动作/验证步，历史调用点不传时默认 "action"。
    package var step_type: String
    /// 23.6：决策步的原始 JSON，供轨迹审计；非决策步为 nil。
    package var decision_json: String?

    package var id: String {
        "\(step_index)|\(name)"
    }

    package init(
        step_index: Int,
        name: String,
        status: String,
        input_summary: String,
        output_summary: String,
        elapsed_ms: Int,
        error: String,
        step_type: String = "action",
        decision_json: String? = nil
    ) {
        self.step_index = step_index
        self.name = name
        self.status = status
        self.input_summary = input_summary
        self.output_summary = output_summary
        self.elapsed_ms = elapsed_ms
        self.error = error
        self.step_type = step_type
        self.decision_json = decision_json
    }
}

package struct DeepDraftIteration: Codable, Hashable, Identifiable {
    package var round: Int
    package var score: Int?
    package var highIssueCount: Int
    package var mediumIssueCount: Int
    package var remainingIssues: [String]
    package var revisionSummary: String?
    package var stoppedReason: String?

    package var id: Int { round }
}

package struct DeepDraftOutput: Codable {
    package var draft: DraftResult
    package var iterations: [DeepDraftIteration]
    package var steps: [AgentStepPayload]
    package var elapsed_ms: Int
    package var success: Bool
    package var error: String

    package var scoreTrail: String {
        iterations.compactMap(\.score).map(String.init).joined(separator: "→")
    }

    package var summaryText: String {
        let rounds = "共迭代 \(iterations.count) 轮"
        let score = scoreTrail.isEmpty ? nil : "分数 \(scoreTrail)"
        let remaining = iterations.last?.remainingIssues.prefix(3).joined(separator: "；")
        return [rounds, score, remaining?.isEmpty == false ? "剩余问题：\(remaining!)" : nil]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

package struct OutlineResponse: Codable {
    package let result: OutlineResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct WritingReviewResponse: Codable {
    package let result: WritingReviewResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct PublishAssetsResponse: Codable {
    package let result: PublishAssetsResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct RewriteSelectionResponse: Codable {
    package let result: RewriteResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct WritingAdvisorResponse: Codable {
    package let result: WritingAdvisorResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package enum RewriteMode: String, Identifiable, Hashable {
    case natural
    case expand
    case shorten
    case deepen
    case vivid
    case conversational
    /// 由诊断 issue 驱动的定点改写：改写目标来自 issue.suggestion，而不是固定模板。
    /// 不出现在工具栏「局部改写」菜单里，因此不放进 `menuCases`。
    case custom

    package var id: String { rawValue }

    /// 供 UI 菜单遍历的固定模式列表，不包含 `.custom`。
    package static var menuCases: [RewriteMode] {
        [.natural, .expand, .shorten, .deepen, .vivid, .conversational]
    }

    package var title: String {
        switch self {
        case .natural:
            return "选中自然"
        case .expand:
            return "选中扩写"
        case .shorten:
            return "选中缩短"
        case .deepen:
            return "选中加深"
        case .vivid:
            return "增强画面感"
        case .conversational:
            return "改成口语化"
        case .custom:
            return "按诊断建议改写"
        }
    }

    package var systemImage: String {
        switch self {
        case .natural:
            return "sparkles"
        case .expand:
            return "plus"
        case .shorten:
            return "minus"
        case .deepen:
            return "book.closed"
        case .vivid:
            return "camera.viewfinder"
        case .conversational:
            return "quote.bubble"
        case .custom:
            return "target"
        }
    }

    package var promptInstruction: String {
        switch self {
        case .natural:
            return "把选中片段改得更自然，减少 AI 味，保留原意和作者个人表达。"
        case .expand:
            return "在不跑题的前提下扩写选中片段，补足场景、原因或细节，让表达更饱满。"
        case .shorten:
            return "压缩选中片段，删掉重复和空话，保留最关键的信息和语气。"
        case .deepen:
            return "加深选中片段的观察和思考，但不要拔高成口号或培训腔。"
        case .vivid:
            return "增强选中片段的画面感，用具体动作、场景或感官细节替代抽象判断。"
        case .conversational:
            return "把选中片段改成更像真实作者口吻的口语化表达，避免营销腔和过度文学化。"
        case .custom:
            return "按给定的具体修改建议调整选中片段，不要引入建议之外的新改动。"
        }
    }
}

package enum PolishMode: String, CaseIterable, Identifiable, Hashable {
    case natural
    case tighten
    case deepen
    case conversational

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .natural:
            return "全文自然"
        case .tighten:
            return "全文收紧"
        case .deepen:
            return "全文加深"
        case .conversational:
            return "全文口语"
        }
    }

    package var systemImage: String {
        switch self {
        case .natural:
            return "wand.and.stars"
        case .tighten:
            return "arrow.down.right.and.arrow.up.left"
        case .deepen:
            return "book.closed"
        case .conversational:
            return "quote.bubble"
        }
    }

    package var promptInstruction: String {
        switch self {
        case .natural:
            return "减少 AI 味，让全文更像真实作者自然写出的文章。保留原意、结构和个人表达，不要过度包装。"
        case .tighten:
            return "压缩全文里的重复、空话和绕路表达，让文章更紧凑，但保留关键场景、事实和情绪。"
        case .deepen:
            return "在不拔高成口号的前提下，加深全文的观察和论证，让关键判断更有支撑。"
        case .conversational:
            return "把全文调整得更接近日常说话的中文，减少书面腔、营销腔和培训腔。"
        }
    }
}

package struct Article: Codable, Identifiable, Hashable {
    package let id: Int
    package var title: String?
    package var content: String?
    package var summary: String?
    package var status: String?
    package var type: String?
    package var tags: [String]?
    package var updated_at: String?
    package var created_at: String?
    package var related_topic_id: Int?
    /// 保存时写入的写作方向/体裁标签，用于体裁化 few-shot 样本匹配（18.3.4）。
    package var genre: String?
    /// 最近一次发表前终审报告快照（20.5 / 20.7）。
    package var audit_report: PrePublishAuditReport?

    package var displayTitle: String {
        let value = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未命名文章" : value
    }

    package var subtitle: String {
        let tagLine = (tags ?? []).joined(separator: "，")
        if let status, !tagLine.isEmpty {
            return "\(status) · \(tagLine)"
        }
        return status ?? tagLine
    }
}

package struct Topic: Codable, Identifiable, Hashable {
    /// 选题的两个状态。此前这两个字符串散在建表默认值、prompt 种子、兜底和统计查询里，
    /// 而**没有任何代码会把「待写」改成别的**——选题一律以「待写」入库并永远留在那里。
    package static let pendingStatus = "待写"
    package static let writtenStatus = "已写"

    package let id: Int
    package var title: String
    package var direction: String?
    package var core_viewpoint: String?
    package var target_reader: String?
    package var description: String?
    package var angle: String?
    package var emotion: String?
    package var score: Int?
    package var status: String?
    package var tags: [String]?
    package var updated_at: String?
    package var created_at: String?

    package var subtitle: String {
        [
            status,
            direction,
            score.map { "推荐 \($0)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

package struct Idea: Codable, Identifiable, Hashable {
    package let id: Int
    package var title: String?
    package var content: String
    package var type: String?
    package var tags: [String]
    package var used: Int?
    package var related_article_id: Int?
    package var updated_at: String?
    package var created_at: String?

    package var displayTitle: String {
        let value = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }
        let contentPrefix = content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)
        return contentPrefix.isEmpty ? "未命名素材" : String(contentPrefix)
    }

    package var subtitle: String {
        [
            type,
            used == 1 ? "已使用" : "未使用",
            tags.isEmpty ? nil : tags.joined(separator: "，")
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

package struct OverviewStats: Codable {
    package let article_total: Int?
    package let published_total: Int?
    package let week_article_total: Int?
    package let month_article_total: Int?
    package let week_published_total: Int?
    package let month_published_total: Int?
    package let idea_total: Int?
    package let idea_used: Int?
    package let topic_pending: Int?
    package let topic_total: Int?
    package let top_direction: String?
    package let current_streak: Int?
}

package struct AICallRecord: Codable, Identifiable, Hashable {
    package let id: Int
    package var endpoint: String?
    package var model: String?
    package var elapsed_ms: Int?
    package var success: Int?
    package var error: String?
    package var input_summary: String?
    package var output_summary: String?
    package var created_at: String?
}

package enum PromptTemplateKey: String, CaseIterable, Identifiable, Codable {
    case topics = "topics"
    case outline = "outline"
    case draft = "draft"
    case polishDraft = "polish_draft"
    case writingReview = "writing_review"
    case publishAssets = "publish_assets"
    case rewriteSelection = "rewrite_selection"
    case writingAdvisor = "writing_advisor"
    case draftSelfCheck = "draft_self_check"
    case pitfallSummary = "pitfall_summary"
    case editPreferenceSummary = "edit_preference_summary"
    case readerPerspective = "reader_perspective"
    case prePublishAudit = "pre_publish_audit"
    case candidateJudge = "candidate_judge"
    case agentDecision = "agent_decision"

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .topics:
            return "生成选题"
        case .outline:
            return "生成大纲"
        case .draft:
            return "大纲成稿"
        case .polishDraft:
            return "全文润色"
        case .writingReview:
            return "写作诊断"
        case .publishAssets:
            return "发布物料"
        case .rewriteSelection:
            return "局部改写"
        case .writingAdvisor:
            return "智能下一步"
        case .draftSelfCheck:
            return "生成后自检"
        case .pitfallSummary:
            return "归纳作者雷区"
        case .editPreferenceSummary:
            return "归纳编辑偏好"
        case .readerPerspective:
            return "读者视角模拟"
        case .prePublishAudit:
            return "发表前终审"
        case .candidateJudge:
            return "候选评委"
        case .agentDecision:
            return "代理决策"
        }
    }
}

package struct PromptTemplate: Codable, Identifiable, Hashable {
    package let id: Int
    package var key: String
    package var name: String
    package var system_prompt: String
    package var user_template: String
    package var is_default: Int?
    package var updated_at: String?
    package var created_at: String?

    package var templateKey: PromptTemplateKey? {
        PromptTemplateKey(rawValue: key)
    }
}

package struct PromptTemplateSeed: Hashable {
    package var key: PromptTemplateKey
    package var name: String
    package var system_prompt: String
    package var user_template: String
}

package struct DraftResult: Codable {
    package var title: String?
    package var content: String?
    package var summary: String?
    package var tags: [String]?
    package var raw_output: String?

    package init(
        title: String? = nil,
        content: String? = nil,
        summary: String? = nil,
        tags: [String]? = nil,
        raw_output: String? = nil
    ) {
        self.title = title
        self.content = content
        self.summary = summary
        self.tags = tags
        self.raw_output = raw_output
    }
}

package struct WritingBriefResult: Codable, Hashable {
    package var working_title: String?
    package var core_question: String?
    package var thesis: String?
    package var target_reader: String?
    package var emotional_center: String?
    package var material_strategy: [String]?
    package var structure_plan: [WritingBriefSection]?
    package var must_keep: [String]?
    package var avoid: [String]?
    package var raw_output: String?
    /// 论点检查判定 brief 不足以支撑成稿时，Brief 修订步骤中现有素材仍无法覆盖的证据/场景缺口（PRD 22.2.1）。
    package var unresolved_gaps: [String]? = nil

    package var summaryText: String {
        [
            working_title.map { "标题方向：\($0)" },
            core_question.map { "核心问题：\($0)" },
            thesis.map { "主张：\($0)" },
            target_reader.map { "读者：\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

package struct WritingBriefSection: Codable, Hashable, Identifiable {
    package var heading: String
    package var purpose: String
    package var key_points: [String]?
    package var material_hint: String?

    package var id: String {
        [heading, purpose, material_hint ?? ""].joined(separator: "|")
    }
}

package struct ArgumentCheckResult: Codable, Hashable {
    package var thesis_strength: String?
    package var weak_points: [String]?
    package var missing_evidence: [String]?
    package var revision_directives: [String]?
    package var ready_to_draft: Bool?
    package var raw_output: String?

    package var summaryText: String {
        [
            thesis_strength.map { "论点强度：\($0)" },
            weak_points?.isEmpty == false ? "薄弱处：\(weak_points!.prefix(3).joined(separator: "；"))" : nil,
            missing_evidence?.isEmpty == false ? "缺证据：\(missing_evidence!.prefix(3).joined(separator: "；"))" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

package struct SectionDraftResult: Codable, Hashable {
    package var title: String?
    package var sections: [DraftSection]?
    package var raw_output: String?

    package var markdown: String {
        if let raw_output,
           !raw_output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw_output
        }
        return (sections ?? [])
            .map { section in
                let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !heading.isEmpty else { return content }
                return "### \(heading)\n\n\(content)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

package struct DraftSection: Codable, Hashable, Identifiable {
    package var heading: String
    package var content: String
    package var self_check: String?

    package var id: String {
        [heading, String(content.prefix(80)), self_check ?? ""].joined(separator: "|")
    }
}

package struct DraftCritiqueResult: Codable, Hashable {
    package var critique_notes: [String]?
    package var title: String?
    package var content: String?
    package var summary: String?
    package var tags: [String]?
    package var raw_output: String?

    package func draftResult(fallbackTitle: String, fallbackContent: String) -> DraftResult {
        DraftResult(
            title: title ?? fallbackTitle,
            content: content ?? raw_output ?? fallbackContent,
            summary: summary,
            tags: tags,
            raw_output: raw_output
        )
    }
}

package struct OutlineResult: Codable {
    package var title: String?
    package var opening: String?
    package var sections: [OutlineSection]?
    package var ending: String?
    package var raw_output: String?
}

package struct OutlineSection: Codable {
    package var heading: String?
    package var points: [String]?
    package var material_hint: String?
}

package struct WritingReview: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var summary: String
    package var overall_score: Int?
    package var strengths: [String]
    package var issues: [WritingReviewIssue]
    package var revision_plan: [String]
    package var training_focus: [String]
    package var style_notes: [String]
    package var raw_output: String?
    package var model: String?
    package var created_at: String?
    /// 本次诊断判定为"已解决"的历史问题（18.3.2）。
    package var resolved_from_last: [String] = []
    /// 本次诊断时的可复核文本快照，用于下次诊断前的变化检测（18.3.2）。
    package var reviewed_snapshot: String?
    /// 本次诊断判定命中的"作者常见雷区"原文描述（22.4.3），由模型显式输出，未命中留空。
    package var pitfall_hits: [String] = []
}

package struct WritingReviewResult: Codable, Hashable {
    package var summary: String?
    package var overall_score: Int?
    package var strengths: [String]?
    package var issues: [WritingReviewIssue]?
    package var revision_plan: [String]?
    package var training_focus: [String]?
    package var style_notes: [String]?
    package var raw_output: String?
    /// 本次判定为"已解决"的历史问题摘要（18.3.2）。
    package var resolved_from_last: [String]?
    /// 本次诊断判定命中的"作者常见雷区"原文描述（22.4.3），由模型显式输出，未命中留空。
    package var pitfall_hits: [String]?

    package init(
        summary: String? = nil,
        overall_score: Int? = nil,
        strengths: [String]? = nil,
        issues: [WritingReviewIssue]? = nil,
        revision_plan: [String]? = nil,
        training_focus: [String]? = nil,
        style_notes: [String]? = nil,
        raw_output: String? = nil,
        resolved_from_last: [String]? = nil,
        pitfall_hits: [String]? = nil
    ) {
        self.summary = summary
        self.overall_score = overall_score
        self.strengths = strengths
        self.issues = issues
        self.revision_plan = revision_plan
        self.training_focus = training_focus
        self.style_notes = style_notes
        self.raw_output = raw_output
        self.resolved_from_last = resolved_from_last
        self.pitfall_hits = pitfall_hits
    }

    /// `overall_score` 走宽松解码（与 `TopicPayload.score` 同一处理）：示例值改成占位符之后，
    /// 模型偶尔会把分数当字符串回成 `"83"`。合成 Codable 在这里抛 typeMismatch，**整条诊断**
    /// 连同 issues 一起解码失败——分数字段的一个类型抖动会赔掉整次调用。
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        overall_score = Self.decodeFlexibleInt(container, key: .overall_score)
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths)
        issues = try container.decodeIfPresent([WritingReviewIssue].self, forKey: .issues)
        revision_plan = try container.decodeIfPresent([String].self, forKey: .revision_plan)
        training_focus = try container.decodeIfPresent([String].self, forKey: .training_focus)
        style_notes = try container.decodeIfPresent([String].self, forKey: .style_notes)
        raw_output = try container.decodeIfPresent(String.self, forKey: .raw_output)
        resolved_from_last = try container.decodeIfPresent([String].self, forKey: .resolved_from_last)
        pitfall_hits = try container.decodeIfPresent([String].self, forKey: .pitfall_hits)
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case overall_score
        case strengths
        case issues
        case revision_plan
        case training_focus
        case style_notes
        case raw_output
        case resolved_from_last
        case pitfall_hits
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

package struct WritingReviewIssue: Codable, Identifiable, Hashable {
    package var dimension: String
    package var severity: String
    package var excerpt: String?
    package var problem: String
    package var suggestion: String

    package var id: String {
        [dimension, severity, excerpt ?? "", problem, suggestion].joined(separator: "|")
    }
}

package struct ContextPackage: Codable, Hashable {
    package var stage: String
    package var title: String
    package var summary: String
    package var idea: String
    package var direction: String
    package var outline_excerpt: String
    package var content_excerpt: String
    package var materials_excerpt: String
    package var selected_topic_title: String?
    package var selected_topic_summary: String?
    package var style_name: String
    package var style_brief: String
    package var word_count: Int
    package var paragraph_count: Int
    package var material_count: Int
    package var recent_article_titles: [String]
    package var recent_training_focus: [String]
    package var recent_issues: [String]
    /// 当前生效风格档案的体裁标签（18.3.4 / 18.7）。
    package var genre: String?
    /// 当前生效风格档案下已确认的作者雷区描述（18.3.3 / 18.7）。
    package var known_pitfalls: [String] = []
    /// 最近一次写作诊断的一句话摘要（18.3.2 / 18.7）。
    package var last_review_summary: String?
    /// 本地检索命中的个人素材片段（20.3），生成类 prompt 可直接读取。
    /// 不参与 Codable 编码（22.3.1）：仅供内存中直接读取，避免整库素材被序列化进 AI prompt。
    package var retrieved_fragments: [RetrievedFragment] = []
    /// 本地片段语料库（20.3），供代理式写作在 brief 生成后按段二次检索。
    /// 不参与 Codable 编码（22.3.1）：仅供内存中直接读取，避免整库素材被序列化进 AI prompt。
    package var fragment_corpus: [Fragment]? = nil
    /// brief 生成后按段检索出的个人素材上下文（20.3 / 21.3 R3）。
    /// 不参与 Codable 编码（22.3.1）：仅供内存中直接读取，避免整库素材被序列化进 AI prompt。
    package var section_fragment_contexts: [SectionFragmentContext]? = nil
    /// 当前生效风格档案下已确认的编辑偏好校准规则（20.4）。
    package var learned_preferences: [String] = []

    package enum CodingKeys: String, CodingKey {
        case stage, title, summary, idea, direction, outline_excerpt, content_excerpt, materials_excerpt
        case selected_topic_title, selected_topic_summary, style_name, style_brief
        case word_count, paragraph_count, material_count
        case recent_article_titles, recent_training_focus, recent_issues
        case genre, known_pitfalls, last_review_summary, learned_preferences
    }

    package var summaryText: String {
        """
        阶段：\(stage)
        标题：\(title.isEmpty ? "未填写" : title)
        方向：\(direction)
        字数：\(word_count)，段落：\(paragraph_count)，素材数：\(material_count)
        最近训练重点：\(recent_training_focus.prefix(3).joined(separator: "，"))
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

package enum AdvisorAction: String, CaseIterable, Identifiable, Hashable {
    case quickDraft = "quick_draft"
    case generateTopics = "generate_topics"
    case generateOutline = "generate_outline"
    case draftFromOutline = "draft_from_outline"
    case writingReview = "writing_review"
    case rewriteSelectionNatural = "rewrite_selection_natural"
    case rewriteSelectionExpand = "rewrite_selection_expand"
    case polishNatural = "polish_natural"
    case polishTighten = "polish_tighten"
    case publishAssets = "publish_assets"
    case saveArticle = "save_article"

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .quickDraft:
            return "直接成稿"
        case .generateTopics:
            return "生成选题"
        case .generateOutline:
            return "生成大纲"
        case .draftFromOutline:
            return "大纲成稿"
        case .writingReview:
            return "写作诊断"
        case .rewriteSelectionNatural:
            return "选中自然"
        case .rewriteSelectionExpand:
            return "选中扩写"
        case .polishNatural:
            return "全文自然"
        case .polishTighten:
            return "全文收紧"
        case .publishAssets:
            return "发布物料"
        case .saveArticle:
            return "保存文章"
        }
    }

    package var systemImage: String {
        switch self {
        case .quickDraft:
            return "bolt"
        case .generateTopics:
            return "sparkles"
        case .generateOutline:
            return "list.bullet.rectangle"
        case .draftFromOutline:
            return "square.and.pencil"
        case .writingReview:
            return "text.magnifyingglass"
        case .rewriteSelectionNatural:
            return "wand.and.stars"
        case .rewriteSelectionExpand:
            return "plus"
        case .polishNatural:
            return "wand.and.stars"
        case .polishTighten:
            return "arrow.down.right.and.arrow.up.left"
        case .publishAssets:
            return "square.and.arrow.up"
        case .saveArticle:
            return "tray.and.arrow.down"
        }
    }
}

package struct WritingAdvisorResult: Codable, Hashable {
    package var stage: String?
    package var main_problem: String?
    package var next_action: String?
    package var reason: String?
    package var suggested_actions: [String]?
    package var focus_area: String?
    /// Claude Code / Codex 式推进：先列出本轮判断依据，避免建议悬空。
    package var context_findings: [String]? = nil
    /// 可执行的分步计划，用于把"智能下一步"从一句建议升级为代理式运行计划。
    package var execution_plan: [String]? = nil
    /// 本轮最需要防范的写作风险或质量风险。
    package var risk_notes: [String]? = nil
    package var raw_output: String?
}

package struct WritingAdvisorRun: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var stage: String
    package var main_problem: String
    package var next_action: String
    package var reason: String
    package var suggested_actions: [String]
    package var focus_area: String?
    package var context_findings: [String] = []
    package var execution_plan: [String] = []
    package var risk_notes: [String] = []
    package var context_summary: String?
    package var raw_output: String?
    package var model: String?
    package var created_at: String?

    package var actions: [AdvisorAction] {
        suggested_actions.compactMap(AdvisorAction.init(rawValue:))
    }
}

package struct AgentRun: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var run_type: String
    package var status: String
    package var summary: String?
    package var model: String?
    package var elapsed_ms: Int?
    package var input_summary: String?
    package var output_summary: String?
    package var error: String?
    /// 23.5：半自动调度序列写入 "plan_execution"；单步操作的历史行为空。
    package var session_kind: String?
    /// 23.6：有界代理循环会话结束时的预算用量摘要（如"已用 7/12 次"）；非代理会话为空。
    package var budget_summary: String?
    package var created_at: String?
    package var steps: [AgentStep] = []
}

package struct AgentStep: Codable, Identifiable, Hashable {
    package let id: Int
    package var run_id: Int
    package var step_index: Int
    package var name: String
    package var status: String
    package var input_summary: String?
    package var output_summary: String?
    package var elapsed_ms: Int?
    package var error: String?
    /// 23.6：decision / action / verification；历史行迁移后默认 "action"。
    package var step_type: String
    /// 23.6：决策步的原始 JSON；非决策步为 nil。
    package var decision_json: String?
    package var created_at: String?
}

package struct Fragment: Codable, Identifiable, Hashable {
    package let id: Int
    package var source_type: String
    package var source_id: Int
    package var title: String?
    package var content: String
    package var keywords: [String]
    package var created_at: String?
    package var updated_at: String?
}

package struct RetrievedFragment: Codable, Identifiable, Hashable {
    package var fragment_id: Int
    package var source_type: String
    package var source_id: Int
    package var title: String?
    package var content: String
    package var score: Double

    package var id: Int { fragment_id }

    package var citationTitle: String {
        let titleText = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return titleText.isEmpty ? "\(source_type)#\(source_id)" : titleText
    }
}

package struct SectionFragmentContext: Codable, Identifiable, Hashable {
    package var section_index: Int
    package var heading: String
    package var query: String
    package var fragments: [RetrievedFragment]

    package var id: Int { section_index }
}

package struct EditRecord: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int
    package var draft_version_id: Int?
    package var title_snapshot: String?
    package var added_characters: Int
    package var removed_characters: Int
    package var base_characters: Int
    package var edit_ratio: Double
    package var edit_level: String
    package var diff_summary: String?
    package var created_at: String?
}

package struct EditRecordStats: Codable, Hashable {
    package var total: Int
    package var zeroEditRate: Double
    package var lightEditRate: Double
    package var averageEditRatio: Double
}

package struct PrePublishAuditReport: Codable, Hashable {
    package var passed: Bool?
    package var summary: String?
    package var typo_issues: [AuditIssue]?
    package var quote_issues: [AuditIssue]?
    package var consistency_issues: [AuditIssue]?
    package var pitfall_issues: [AuditIssue]?
    package var raw_output: String?

    package var allIssues: [AuditIssue] {
        (typo_issues ?? []) + (quote_issues ?? []) + (consistency_issues ?? []) + (pitfall_issues ?? [])
    }
}

package struct AuditIssue: Codable, Identifiable, Hashable {
    package var category: String
    package var severity: String
    package var excerpt: String?
    package var problem: String
    package var suggestion: String?

    package var id: String {
        [category, severity, excerpt ?? "", problem, suggestion ?? ""].joined(separator: "|")
    }
}

package struct PrePublishAuditResponse: Codable {
    package let result: PrePublishAuditReport
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct DraftCandidate: Codable, Hashable, Identifiable {
    package var index: Int
    package var label: String
    package var title: String
    package var summary: String
    package var content: String

    package var id: Int { index }

    package init(index: Int, label: String, title: String, summary: String, content: String) {
        self.index = index
        self.label = label
        self.title = title
        self.summary = summary
        self.content = content
    }
}

package struct CandidateScore: Codable, Hashable, Identifiable {
    package var candidate_index: Int
    package var score: Int
    package var reason: String
    package var strengths: [String]?
    package var risks: [String]?

    package var id: Int { candidate_index }

    package init(
        candidate_index: Int,
        score: Int,
        reason: String,
        strengths: [String]? = nil,
        risks: [String]? = nil
    ) {
        self.candidate_index = candidate_index
        self.score = score
        self.reason = reason
        self.strengths = strengths
        self.risks = risks
    }

    /// 两个整数字段接受"整数"与"能解析成整数的字符串"两种形态。这里比诊断那处更要紧：
    /// 二者都是**非可选**且整个结构嵌在 `rankings` 数组里——模型把分数回成 `"86"`，合成
    /// Codable 抛 typeMismatch，赔掉的不是一个字段，是整份候选排序。
    ///
    /// 只放宽类型，不放宽"字段缺失"：字段真没有时照旧抛错，让这次调用干净地失败并走 fallback。
    /// 给它兜一个 0 会造出一条指向不存在候选的排序，比失败更难查。
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidate_index = try Self.decodeInt(container, key: .candidate_index)
        score = try Self.decodeInt(container, key: .score)
        reason = try container.decode(String.self, forKey: .reason)
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths)
        risks = try container.decodeIfPresent([String].self, forKey: .risks)
    }

    private enum CodingKeys: String, CodingKey {
        case candidate_index
        case score
        case reason
        case strengths
        case risks
    }

    private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: key),
           let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(key.stringValue) 既不是整数，也不是能解析成整数的字符串"
        )
    }
}

package struct CandidateJudgeResult: Codable, Hashable {
    package var best_candidate_index: Int?
    package var rankings: [CandidateScore]
    package var summary: String?
    package var raw_output: String?

    package var bestReason: String? {
        guard let best_candidate_index else { return summary }
        return rankings.first { $0.candidate_index == best_candidate_index }?.reason ?? summary
    }
}

package struct CandidateJudgeResponse: Codable {
    package let result: CandidateJudgeResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

package struct PrePublishAudit: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var passed: Int
    package var summary: String?
    package var issues: [AuditIssue]
    package var raw_output: String?
    package var model: String?
    package var created_at: String?
}

package struct PublishAssets: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var summary: String?
    package var cover_text: String?
    package var moments_text: String?
    package var tags: [String]
    package var xiaohongshu_text: String?
    package var cover_image_prompt: String?
    package var raw_output: String?
    package var model: String?
    package var created_at: String?
}

package struct PublishAssetsResult: Codable, Hashable {
    package var summary: String?
    package var cover_text: String?
    package var moments_text: String?
    package var tags: [String]?
    package var xiaohongshu_text: String?
    package var cover_image_prompt: String?
    package var raw_output: String?

    package init(
        summary: String?,
        cover_text: String?,
        moments_text: String?,
        tags: [String]?,
        xiaohongshu_text: String?,
        cover_image_prompt: String?,
        raw_output: String?
    ) {
        self.summary = summary
        self.cover_text = cover_text
        self.moments_text = moments_text
        self.tags = tags
        self.xiaohongshu_text = xiaohongshu_text
        self.cover_image_prompt = cover_image_prompt
        self.raw_output = raw_output
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        cover_text = try container.decodeIfPresent(String.self, forKey: .cover_text)
        moments_text = try container.decodeIfPresent(String.self, forKey: .moments_text)
        xiaohongshu_text = try container.decodeIfPresent(String.self, forKey: .xiaohongshu_text)
        cover_image_prompt = try container.decodeIfPresent(String.self, forKey: .cover_image_prompt)
        raw_output = try container.decodeIfPresent(String.self, forKey: .raw_output)
        tags = Self.decodeFlexibleTags(container, key: .tags)
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case cover_text
        case moments_text
        case tags
        case xiaohongshu_text
        case cover_image_prompt
        case raw_output
    }

    private static func decodeFlexibleTags(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> [String]? {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return text
                .split { character in
                    character == "," || character == "，" || character == "、" || character == " "
                }
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        return nil
    }
}

package struct RewriteResult: Codable, Hashable {
    package var replacement: String?
    package var note: String?
    package var raw_output: String?
}

/// 生成后轻量自检结果（18.3.5）：只标记高风险信号，不修改正文，不阻塞主流程。
package struct DraftSelfCheckResult: Codable, Hashable {
    package var has_concerns: Bool?
    package var flagged_excerpts: [FlaggedExcerpt]?
    package var raw_output: String?
}

package struct FlaggedExcerpt: Codable, Hashable, Identifiable {
    package var excerpt: String
    package var concern: String

    package var id: String {
        "\(excerpt)|\(concern)"
    }
}

/// 23.6 有界代理循环的决策步输出：模型每轮只在封闭动作空间里选一个动作，或选择停下。
package struct AgentDecisionResult: Codable, Hashable {
    package var action: String?
    package var arguments: AgentDecisionArguments?
    package var reason: String?
    package var expected_gain: String?
    package var stop: Bool?
    package var raw_output: String?

    package init(
        action: String? = nil,
        arguments: AgentDecisionArguments? = nil,
        reason: String? = nil,
        expected_gain: String? = nil,
        stop: Bool? = nil,
        raw_output: String? = nil
    ) {
        self.action = action
        self.arguments = arguments
        self.reason = reason
        self.expected_gain = expected_gain
        self.stop = stop
        self.raw_output = raw_output
    }
}

package struct AgentDecisionArguments: Codable, Hashable {
    /// search_materials / ask_author 才需要；ask_author 场景下承载具体缺口清单原文。
    package var query: String?

    package init(query: String? = nil) {
        self.query = query
    }
}

package struct DraftSelfCheckResponse: Codable {
    package let result: DraftSelfCheckResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

/// 从历史诊断归纳出的候选作者雷区（18.3.3），须经作者手动确认才写入 `StyleProfile.known_pitfalls`。
package struct PitfallCandidate: Codable, Hashable {
    package var description: String
    package var supporting_review_ids: [Int]?
}

package struct PitfallSummaryResult: Codable, Hashable {
    package var candidates: [PitfallCandidate]?
    package var raw_output: String?
}

package struct PitfallSummaryResponse: Codable {
    package let result: PitfallSummaryResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

/// 从发布前人工修改记录中归纳出的候选风格校准规则（20.4），须经作者确认才写入 `StyleProfile.learned_preferences`。
package struct EditPreferenceCandidate: Codable, Hashable {
    package var description: String
    package var source_edit_record_ids: [Int]?
}

package struct EditPreferenceSummaryResult: Codable, Hashable {
    package var candidates: [EditPreferenceCandidate]?
    package var monthly_summary: String?
    package var raw_output: String?
}

package struct EditPreferenceSummaryResponse: Codable {
    package let result: EditPreferenceSummaryResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

/// 读者视角模拟（18.4.3）：定性补充诊断，不计入 overall_score，不替代编辑视角诊断。
package struct ReaderPerspectiveResult: Codable, Hashable {
    package var reader_persona: String?
    package var drop_off_point: String?
    package var most_memorable_point: String?
    package var note: String?
    package var raw_output: String?
}

package struct ReaderPerspectiveResponse: Codable {
    package let result: ReaderPerspectiveResult
    package let elapsed_ms: Int?
    package let success: Bool?
    package let error: String?
    package var input_summary: String? = nil
    package var output_summary: String? = nil
}

/// 诊断-改写闭环中的一次待确认改写候选（18.3.1）：生成候选后先展示，人工确认才写入正文。
package struct PendingIssueRewrite: Identifiable {
    package let id = UUID()
    package var issue: WritingReviewIssue
    package var range: NSRange
    package var originalText: String
    package var replacement: String
    package var note: String?
    package var usedFallback: Bool

    package init(
        issue: WritingReviewIssue,
        range: NSRange,
        originalText: String,
        replacement: String,
        note: String? = nil,
        usedFallback: Bool
    ) {
        self.issue = issue
        self.range = range
        self.originalText = originalText
        self.replacement = replacement
        self.note = note
        self.usedFallback = usedFallback
    }
}

/// 大范围生成动作（代理式初稿/大纲成稿/全文润色）的"待复核"候选（18.4.1）。
package struct PendingDraftReview: Identifiable, Codable {
    package let id = UUID()
    /// 对应 `draft_versions` 表中 `review_status = pending` 的那一行，确认/放弃时按此 id 操作。
    package var draftVersionID: Int
    package var actionTitle: String
    package var articleID: Int?
    package var before: DraftSnapshot
    package var after: DraftSnapshot
    package var note: String?
    package var usedFallback: Bool
    package var selfCheck: DraftSelfCheckResult?
    package var matchedPitfalls: [AuthorPitfall]
    package var agentTrace: AgentDraftTrace?
    package var retrievedFragments: [RetrievedFragment]?
    package var sectionFragmentContexts: [SectionFragmentContext]? = nil
    package var iterationSummary: [DeepDraftIteration]?
    package var candidateJudgement: CandidateJudgeResult?
    /// 23.6.5：有界代理循环会话摘要（共 N 步、每步动作与理由、停止原因）；非代理会话为空。
    package var agentSessionSummary: [String]?
    /// 24.9-P1：本次生成注入了哪几篇 few-shot 风格样本、命中哪一档。评测报告早有「风格样本」
    /// 行，App 侧一直看不见——作者怀疑"写出来不像我"时只能查库。
    package var styleSamples: StyleSampleProvenance?

    package init(
        draftVersionID: Int,
        actionTitle: String,
        articleID: Int? = nil,
        before: DraftSnapshot,
        after: DraftSnapshot,
        note: String? = nil,
        usedFallback: Bool,
        selfCheck: DraftSelfCheckResult? = nil,
        matchedPitfalls: [AuthorPitfall],
        agentTrace: AgentDraftTrace? = nil,
        retrievedFragments: [RetrievedFragment]? = nil,
        sectionFragmentContexts: [SectionFragmentContext]? = nil,
        iterationSummary: [DeepDraftIteration]? = nil,
        candidateJudgement: CandidateJudgeResult? = nil,
        agentSessionSummary: [String]? = nil,
        styleSamples: StyleSampleProvenance? = nil
    ) {
        self.draftVersionID = draftVersionID
        self.actionTitle = actionTitle
        self.articleID = articleID
        self.before = before
        self.after = after
        self.note = note
        self.usedFallback = usedFallback
        self.selfCheck = selfCheck
        self.matchedPitfalls = matchedPitfalls
        self.agentTrace = agentTrace
        self.retrievedFragments = retrievedFragments
        self.sectionFragmentContexts = sectionFragmentContexts
        self.iterationSummary = iterationSummary
        self.candidateJudgement = candidateJudgement
        self.agentSessionSummary = agentSessionSummary
        self.styleSamples = styleSamples
    }

    package enum CodingKeys: String, CodingKey {
        case draftVersionID
        case actionTitle
        case articleID
        case before
        case after
        case note
        case usedFallback
        case selfCheck
        case matchedPitfalls
        case agentTrace
        case retrievedFragments
        case sectionFragmentContexts
        case iterationSummary
        case candidateJudgement
        case agentSessionSummary
        case styleSamples
    }
}

/// 本次生成注入的 few-shot 风格样本出处（24.9-P1）：篇名 + 命中档位 + 是否退到了草稿。
/// 24.6 的残留边界写明「注入了哪几篇样本 App 界面上仍然看不见」，这个类型就是为补上它。
package struct StyleSampleProvenance: Codable, Equatable {
    package var tierLabel: String
    package var titles: [String]
    /// 一篇完成稿都没有时才会为真：范本是改到一半的草稿，腔调不可当准。
    package var usedDraftFallback: Bool

    package init(tierLabel: String, titles: [String], usedDraftFallback: Bool) {
        self.tierLabel = tierLabel
        self.titles = titles
        self.usedDraftFallback = usedDraftFallback
    }

    /// 界面一行摘要。样本为空时也要说话——静默返回"（暂无样本文章…）"正是 24.3 的病根之一。
    package var summaryLine: String {
        guard !titles.isEmpty else {
            return "本次未注入风格样本（模型只能靠几个抽象形容词模仿你）"
        }
        let suffix = usedDraftFallback ? "，草稿兜底" : ""
        return "本次风格样本：\(titles.joined(separator: "、"))（\(tierLabel)\(suffix)）"
    }
}

/// 第三阶段自动保存：保存当前编辑器状态和待复核候选，供 App 重启后恢复。
package struct AutoSavedDraft: Codable {
    package var selectedArticleID: Int?
    package var selectedTopicID: Int?
    package var articleStatus: String
    package var title: String
    package var summary: String
    package var content: String
    package var outline: String
    package var ideaInput: String
    package var writingDirection: String
    package var materials: String
    package var draftTags: [String]
    package var pendingDraftReview: PendingDraftReview?
    package var latestSelfCheck: DraftSelfCheckResult?
    package var savedAt: String

    package init(
        selectedArticleID: Int? = nil,
        selectedTopicID: Int? = nil,
        articleStatus: String,
        title: String,
        summary: String,
        content: String,
        outline: String,
        ideaInput: String,
        writingDirection: String,
        materials: String,
        draftTags: [String],
        pendingDraftReview: PendingDraftReview?,
        latestSelfCheck: DraftSelfCheckResult?,
        savedAt: String
    ) {
        self.selectedArticleID = selectedArticleID
        self.selectedTopicID = selectedTopicID
        self.articleStatus = articleStatus
        self.title = title
        self.summary = summary
        self.content = content
        self.outline = outline
        self.ideaInput = ideaInput
        self.writingDirection = writingDirection
        self.materials = materials
        self.draftTags = draftTags
        self.pendingDraftReview = pendingDraftReview
        self.latestSelfCheck = latestSelfCheck
        self.savedAt = savedAt
    }
}

package struct DraftSnapshot: Codable, Hashable {
    package var title: String
    package var summary: String
    package var content: String

    package init(title: String, summary: String, content: String) {
        self.title = title
        self.summary = summary
        self.content = content
    }
}

/// 草稿版本的 action 取值里唯一"非模型产出"的一个：覆盖保存留痕。编辑量基准要排除它
/// （见 `NativeDatabase.latestModelDraftVersion`），因此提成常量，写库和查库共用一处。
package enum DraftVersionAction {
    package static let manualSave = "保存文章"
}

package struct DraftVersion: Codable, Identifiable, Hashable {
    package let id: Int
    package var article_id: Int?
    package var title_snapshot: String?
    package var action: String
    package var note: String?
    package var before_title: String
    package var before_summary: String
    package var before_content: String
    package var after_title: String
    package var after_summary: String
    package var after_content: String
    package var created_at: String?
    /// "待复核"工作流状态：`pending`/`confirmed`。历史记录一律视为 `confirmed`（18.4.1）。
    package var review_status: String = "confirmed"

    package var beforeSnapshot: DraftSnapshot {
        DraftSnapshot(title: before_title, summary: before_summary, content: before_content)
    }

    package var afterSnapshot: DraftSnapshot {
        DraftSnapshot(title: after_title, summary: after_summary, content: after_content)
    }
}

package struct TopicPayload: Codable {
    package let title: String
    package let direction: String?
    package let core_viewpoint: String?
    package let target_reader: String?
    package let description: String?
    package let angle: String?
    package let emotion: String?
    package let score: Int?
    package let status: String?
    package let tags: [String]?

    package init(
        title: String,
        direction: String?,
        core_viewpoint: String?,
        target_reader: String?,
        description: String?,
        angle: String?,
        emotion: String?,
        score: Int?,
        status: String?,
        tags: [String]?
    ) {
        self.title = title
        self.direction = direction
        self.core_viewpoint = core_viewpoint
        self.target_reader = target_reader
        self.description = description
        self.angle = angle
        self.emotion = emotion
        self.score = score
        self.status = status
        self.tags = tags
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        core_viewpoint = try container.decodeIfPresent(String.self, forKey: .core_viewpoint)
        target_reader = try container.decodeIfPresent(String.self, forKey: .target_reader)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        angle = try container.decodeIfPresent(String.self, forKey: .angle)
        emotion = try container.decodeIfPresent(String.self, forKey: .emotion)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        score = Self.decodeFlexibleInt(container, key: .score)
        tags = Self.decodeFlexibleTags(container, key: .tags)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case direction
        case core_viewpoint
        case target_reader
        case description
        case angle
        case emotion
        case score
        case status
        case tags
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func decodeFlexibleTags(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> [String]? {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return text
                .split { character in
                    character == "," || character == "，" || character == "、" || character == " "
                }
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        return nil
    }
}

package struct ArticleSaveRequest: Codable {
    package let title: String
    package let content: String
    package let summary: String
    package let status: String
    package let tags: [String]
    package let related_topic_id: Int?
    package let genre: String?
}

package struct IdeaSaveRequest: Codable {
    package let title: String
    package let content: String
    package let type: String
    package let tags: [String]
    package let used: Int
    package let related_article_id: Int?

    package init(title: String, content: String, type: String, tags: [String], used: Int, related_article_id: Int? = nil) {
        self.title = title
        self.content = content
        self.type = type
        self.tags = tags
        self.used = used
        self.related_article_id = related_article_id
    }
}

package struct ChatMessage: Codable {
    package let role: String
    package let content: String
}

package enum ArticleCopyFormat: String, CaseIterable, Identifiable {
    case plainText
    case markdown
    case html

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .plainText:
            return "TXT 纯文本"
        case .markdown:
            return "Markdown"
        case .html:
            return "HTML"
        }
    }

    package var systemImage: String {
        switch self {
        case .plainText:
            return "doc.plaintext"
        case .markdown:
            return "number"
        case .html:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    package var statusName: String {
        switch self {
        case .plainText:
            return "TXT"
        case .markdown:
            return "Markdown"
        case .html:
            return "HTML"
        }
    }
}
