import Foundation

package enum NativeWorkflowCatalog {
    package static func writingBrief(context: ContextPackage, style: StyleProfile) -> WorkflowDescriptor<WritingBriefResult> {
        WorkflowDescriptor(
            kind: .agentDraft,
            endpoint: "agent-draft-brief-native",
            buildMessages: {
                NativePrompts.writingBrief(context: context, style: style)
            },
            fallback: {
                NativeFallbacks.writingBrief(input: context.idea, direction: context.direction, materials: context.materials_excerpt)
            }
        )
    }

    package static func argumentCheck(brief: WritingBriefResult, context: ContextPackage, style: StyleProfile) -> WorkflowDescriptor<ArgumentCheckResult> {
        WorkflowDescriptor(
            kind: .agentDraft,
            endpoint: "agent-draft-argument-check-native",
            buildMessages: {
                NativePrompts.argumentCheck(brief: brief, context: context, style: style)
            },
            fallback: {
                NativeFallbacks.argumentCheck(brief: brief, materials: context.materials_excerpt)
            }
        )
    }

    package static func briefRevision(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> WorkflowDescriptor<WritingBriefResult> {
        WorkflowDescriptor(
            kind: .agentDraft,
            endpoint: "agent-draft-brief-revision-native",
            buildMessages: {
                NativePrompts.briefRevision(brief: brief, argumentCheck: argumentCheck, context: context, style: style)
            },
            fallback: {
                NativeFallbacks.briefRevision(brief: brief, argumentCheck: argumentCheck)
            }
        )
    }

    package static func sectionDraft(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> WorkflowDescriptor<SectionDraftResult> {
        WorkflowDescriptor(
            kind: .agentDraft,
            endpoint: "agent-draft-sections-native",
            buildMessages: {
                NativePrompts.sectionDraft(
                    brief: brief,
                    argumentCheck: argumentCheck,
                    context: context,
                    style: style
                )
            },
            fallback: {
                NativeFallbacks.sectionDraft(
                    brief: brief,
                    argumentCheck: argumentCheck,
                    context: context
                )
            }
        )
    }

    package static func draftCritique(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        sectionDraft: SectionDraftResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> WorkflowDescriptor<DraftCritiqueResult> {
        WorkflowDescriptor(
            kind: .agentDraft,
            endpoint: "agent-draft-critique-native",
            buildMessages: {
                NativePrompts.draftCritique(
                    brief: brief,
                    argumentCheck: argumentCheck,
                    sectionDraft: sectionDraft,
                    context: context,
                    style: style
                )
            },
            fallback: {
                NativeFallbacks.draftCritique(
                    brief: brief,
                    argumentCheck: argumentCheck,
                    sectionDraft: sectionDraft,
                    direction: context.direction
                )
            }
        )
    }

    package static func topics(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<GeneratedTopicsDocument> {
        WorkflowDescriptor(
            kind: .topics,
            endpoint: "topics-native",
            templateKey: .topics,
            buildMessages: {
                NativePrompts.topics(context: context, style: style, template: template)
            },
            fallback: {
                GeneratedTopicsDocument(topics: NativeFallbacks.topics(context: context))
            }
        )
    }

    package static func outline(
        topic: TopicPayload,
        context: ContextPackage,
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<OutlineResult> {
        WorkflowDescriptor(
            kind: .outline,
            endpoint: "outline-native",
            templateKey: .outline,
            buildMessages: {
                NativePrompts.outline(topic: topic, context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.outline(topic: topic, context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.outlineResult)
            }
        )
    }

    package static func draft(
        topic: TopicPayload,
        context: ContextPackage,
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<DraftResult> {
        WorkflowDescriptor(
            kind: .draft,
            endpoint: "draft-native",
            templateKey: .draft,
            buildMessages: {
                NativePrompts.draft(topic: topic, context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.draft(topic: topic, context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.draftResult)
            }
        )
    }

    package static func polishDraft(
        context: ContextPackage,
        content: String,
        mode: PolishMode,
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<DraftResult> {
        let endpointSuffix = mode.rawValue
        return WorkflowDescriptor(
            kind: .polishDraft,
            endpoint: "polish-\(endpointSuffix)-native",
            templateKey: .polishDraft,
            buildMessages: {
                NativePrompts.polishDraft(context: context, content: content, mode: mode, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.polishDraft(
                    title: context.title,
                    summary: context.summary,
                    content: content,
                    mode: mode
                )
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.draftResult)
            }
        )
    }

    package static func improveDraftFromReview(
        context: ContextPackage,
        content: String,
        review: WritingReview,
        style: StyleProfile
    ) -> WorkflowDescriptor<DraftResult> {
        WorkflowDescriptor(
            kind: .improveFromReview,
            endpoint: "review-driven-revision-native",
            buildMessages: {
                NativePrompts.improveDraftFromReview(context: context, content: content, review: review, style: style)
            },
            fallback: {
                NativeFallbacks.improveDraftFromReview(context: context, content: content, review: review)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.draftResult)
            }
        )
    }

    package static func writingReview(
        context: ContextPackage,
        style: StyleProfile,
        previousReview: WritingReview?,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<WritingReviewResult> {
        WorkflowDescriptor(
            kind: .writingReview,
            endpoint: "writing-coach-native",
            templateKey: .writingReview,
            buildMessages: {
                NativePrompts.writingReview(
                    context: context,
                    style: style,
                    previousReview: previousReview,
                    template: template
                )
            },
            fallback: {
                NativeFallbacks.writingReview(context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.writingReviewResult)
            }
        )
    }

    package static func publishAssets(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<PublishAssetsResult> {
        WorkflowDescriptor(
            kind: .publishAssets,
            endpoint: "publish-assets-native",
            templateKey: .publishAssets,
            buildMessages: {
                NativePrompts.publishAssets(context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.publishAssets(context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.publishAssetsResult)
            }
        )
    }

    package static func rewriteSelection(
        context: ContextPackage,
        selectedText: String,
        surroundingText: String,
        mode: RewriteMode,
        customInstruction: String?,
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<RewriteResult> {
        let endpointSuffix = mode == .custom ? "custom" : mode.rawValue
        return WorkflowDescriptor(
            kind: .rewriteSelection,
            endpoint: "rewrite-selection-\(endpointSuffix)-native",
            templateKey: .rewriteSelection,
            buildMessages: {
                NativePrompts.rewriteSelection(
                    context: context,
                    selectedText: selectedText,
                    surroundingText: surroundingText,
                    mode: mode,
                    customInstruction: customInstruction,
                    style: style,
                    template: template
                )
            },
            fallback: {
                NativeFallbacks.rewriteSelection(selectedText: selectedText, mode: mode, customInstruction: customInstruction)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.rewriteResult)
            }
        )
    }

    package static func writingAdvisor(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<WritingAdvisorResult> {
        WorkflowDescriptor(
            kind: .writingAdvisor,
            endpoint: "writing-advisor-native",
            templateKey: .writingAdvisor,
            buildMessages: {
                NativePrompts.writingAdvisor(context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.writingAdvisor(context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.writingAdvisorResult)
            }
        )
    }

    package static func draftSelfCheck(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<DraftSelfCheckResult> {
        WorkflowDescriptor(
            kind: .draftSelfCheck,
            endpoint: "draft-self-check-native",
            templateKey: .draftSelfCheck,
            buildMessages: {
                NativePrompts.draftSelfCheck(context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.draftSelfCheck(context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.draftSelfCheckResult)
            }
        )
    }

    package static func summarizePitfalls(
        issues: [(reviewID: Int, dimension: String, problem: String)],
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<PitfallSummaryResult> {
        WorkflowDescriptor(
            kind: .pitfallSummary,
            endpoint: "pitfall-summary-native",
            templateKey: .pitfallSummary,
            buildMessages: {
                NativePrompts.summarizePitfalls(issues: issues, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.summarizePitfalls(issues: issues)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.pitfallSummaryResult)
            }
        )
    }

    package static func summarizeEditPreferences(
        records: [EditRecord],
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<EditPreferenceSummaryResult> {
        WorkflowDescriptor(
            kind: .editPreferenceSummary,
            endpoint: "edit-preference-summary-native",
            templateKey: .editPreferenceSummary,
            buildMessages: {
                NativePrompts.summarizeEditPreferences(records: records, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.summarizeEditPreferences(records: records)
            }
        )
    }

    package static func readerPerspective(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<ReaderPerspectiveResult> {
        WorkflowDescriptor(
            kind: .readerPerspective,
            endpoint: "reader-perspective-native",
            templateKey: .readerPerspective,
            buildMessages: {
                NativePrompts.readerPerspective(context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.readerPerspective(context: context)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.readerPerspectiveResult)
            }
        )
    }

    package static func prePublishAudit(context: ContextPackage, style: StyleProfile, template: PromptTemplate?) -> WorkflowDescriptor<PrePublishAuditReport> {
        WorkflowDescriptor(
            kind: .prePublishAudit,
            endpoint: "pre-publish-audit-native",
            templateKey: .prePublishAudit,
            buildMessages: {
                NativePrompts.prePublishAudit(context: context, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.prePublishAudit(context: context, style: style)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.prePublishAuditReport)
            }
        )
    }

    /// 23.6 有界代理循环的决策步：判别类、低温、小输出，只选下一步动作或停下。
    package static func agentDecision(
        state: AgentSessionState,
        availableActions: [AgentSessionAction],
        correctionNote: String?,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<AgentDecisionResult> {
        WorkflowDescriptor(
            kind: .agentDecision,
            endpoint: "agent-decision-native",
            templateKey: .agentDecision,
            buildMessages: {
                NativePrompts.agentDecision(
                    state: state,
                    availableActions: availableActions,
                    correctionNote: correctionNote,
                    template: template
                )
            },
            fallback: {
                // 演示模式兜底：正文完全空白且 agent_quick_draft 可用时先补一版草稿，否则安全停机（不假装还能继续决策）。
                let isEmptyDraft = state.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let action: AgentSessionAction = (isEmptyDraft && availableActions.contains(.agentQuickDraft)) ? .agentQuickDraft : .finish
                return AgentDecisionResult(action: action.rawValue, reason: "未配置 API Key，使用本地兜底。", stop: action == .finish)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: NativeNonJSONDecoders.agentDecisionResult)
            }
        )
    }

    package static func judgeDraftCandidates(
        context: ContextPackage,
        base: DraftSnapshot,
        candidates: [DraftCandidate],
        style: StyleProfile,
        template: PromptTemplate?
    ) -> WorkflowDescriptor<CandidateJudgeResult> {
        WorkflowDescriptor(
            kind: .candidateJudge,
            endpoint: "candidate-judge-native",
            templateKey: .candidateJudge,
            buildMessages: {
                NativePrompts.judgeDraftCandidates(context: context, base: base, candidates: candidates, style: style, template: template)
            },
            fallback: {
                NativeFallbacks.judgeDraftCandidates(candidates: candidates)
            }
        )
    }
}

package enum NativeNonJSONDecoders {
    package static func draftResult(_ cleaned: String) -> DraftResult {
        DraftResult(title: nil, content: nil, summary: nil, tags: nil, raw_output: cleaned)
    }

    package static func outlineResult(_ cleaned: String) -> OutlineResult {
        OutlineResult(title: nil, opening: nil, sections: nil, ending: nil, raw_output: cleaned)
    }

    package static func writingReviewResult(_ cleaned: String) -> WritingReviewResult {
        WritingReviewResult(
            summary: "模型返回了非 JSON 诊断，已保留原文。",
            overall_score: nil,
            strengths: [],
            issues: [],
            revision_plan: [],
            training_focus: [],
            style_notes: [],
            raw_output: cleaned
        )
    }

    package static func publishAssetsResult(_ cleaned: String) -> PublishAssetsResult {
        PublishAssetsResult(
            summary: nil,
            cover_text: nil,
            moments_text: nil,
            tags: nil,
            xiaohongshu_text: nil,
            cover_image_prompt: nil,
            raw_output: cleaned
        )
    }

    package static func rewriteResult(_ cleaned: String) -> RewriteResult {
        RewriteResult(
            replacement: cleaned,
            note: "模型返回了非 JSON 改写，已直接作为替换文本。",
            raw_output: cleaned
        )
    }

    package static func writingAdvisorResult(_ cleaned: String) -> WritingAdvisorResult {
        WritingAdvisorResult(
            stage: nil,
            main_problem: "模型返回了非 JSON 建议，已保留原文。",
            next_action: "请先阅读原始建议，再手动选择下一步。",
            reason: nil,
            suggested_actions: ["writing_review"],
            focus_area: nil,
            context_findings: ["模型返回内容不是结构化 JSON，系统已保留原始文本供人工判断。"],
            execution_plan: ["先阅读原始建议。", "再运行写作诊断或手动选择下一步。"],
            risk_notes: ["非结构化输出无法保证建议覆盖了当前上下文。"],
            raw_output: cleaned
        )
    }

    package static func draftSelfCheckResult(_ cleaned: String) -> DraftSelfCheckResult {
        DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: cleaned)
    }

    package static func pitfallSummaryResult(_ cleaned: String) -> PitfallSummaryResult {
        PitfallSummaryResult(candidates: [], raw_output: cleaned)
    }

    package static func readerPerspectiveResult(_ cleaned: String) -> ReaderPerspectiveResult {
        ReaderPerspectiveResult(
            reader_persona: nil,
            drop_off_point: nil,
            most_memorable_point: nil,
            note: "模型返回了非 JSON 内容，已保留原文。",
            raw_output: cleaned
        )
    }

    package static func agentDecisionResult(_ cleaned: String) -> AgentDecisionResult {
        AgentDecisionResult(action: nil, reason: "模型返回了非 JSON 决策，视为动作越界。", stop: nil, raw_output: cleaned)
    }

    package static func prePublishAuditReport(_ cleaned: String) -> PrePublishAuditReport {
        PrePublishAuditReport(
            passed: false,
            summary: "模型返回了非 JSON 终审报告，已保留原文，请人工复核后再发布。",
            typo_issues: [],
            quote_issues: [],
            consistency_issues: [
                AuditIssue(
                    category: "终审格式",
                    severity: "中",
                    excerpt: nil,
                    problem: "终审结果不是结构化 JSON。",
                    suggestion: "查看原始输出，并人工复核错字、引文和一致性。"
                )
            ],
            pitfall_issues: [],
            raw_output: cleaned
        )
    }
}

package struct GeneratedTopicsDocument: Codable {
    package let topics: [TopicPayload]
}
