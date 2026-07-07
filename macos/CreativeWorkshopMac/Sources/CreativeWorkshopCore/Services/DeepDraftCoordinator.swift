import Foundation

package struct DeepDraftInput {
    package var title: String
    package var summary: String
    package var content: String
    package var outline: String
    package var idea: String
    package var direction: String
    package var materials: String
    package var style: StyleProfile
    package var previousReview: WritingReview?
    package var writingReviewTemplate: PromptTemplate?
    package var config: ModelConfig
    package var apiKey: String
    package var maxRounds: Int = 3
    /// 已废弃：不再参与深度成稿循环的停止判定，停止判据改为上一轮问题核销率（PRD 22.4.3）。
    package var targetScore: Int = 85

    package init(
        title: String,
        summary: String,
        content: String,
        outline: String,
        idea: String,
        direction: String,
        materials: String,
        style: StyleProfile,
        previousReview: WritingReview? = nil,
        writingReviewTemplate: PromptTemplate? = nil,
        config: ModelConfig,
        apiKey: String,
        maxRounds: Int = 3,
        targetScore: Int = 85
    ) {
        self.title = title
        self.summary = summary
        self.content = content
        self.outline = outline
        self.idea = idea
        self.direction = direction
        self.materials = materials
        self.style = style
        self.previousReview = previousReview
        self.writingReviewTemplate = writingReviewTemplate
        self.config = config
        self.apiKey = apiKey
        self.maxRounds = maxRounds
        self.targetScore = targetScore
    }
}

package struct DeepDraftCoordinator {
    package let aiClient: AIWorkflowExecuting

    package init(aiClient: AIWorkflowExecuting) {
        self.aiClient = aiClient
    }

    package func run(input: DeepDraftInput) async throws -> DeepDraftOutput {
        let start = Date()
        var currentTitle = input.title
        var currentSummary = input.summary
        var currentContent = input.content
        var previousReview = input.previousReview
        var iterations: [DeepDraftIteration] = []
        var steps: [AgentStepPayload] = []
        var errors: [String] = []
        var lastScore: Int?
        var lowResolutionStreak = 0
        var bestDraft = DraftResult(title: currentTitle, content: currentContent, summary: currentSummary, tags: nil, raw_output: nil)

        let cappedMaxRounds = max(1, min(input.maxRounds, 5))
        for round in 1...cappedMaxRounds {
            try Task.checkCancellation()
            let reviewContext = ContextPackage(
                stage: "深度诊断第 \(round) 轮",
                title: currentTitle,
                summary: currentSummary,
                idea: input.idea,
                direction: input.direction,
                outline_excerpt: input.outline,
                content_excerpt: currentContent,
                materials_excerpt: input.materials,
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: input.style.name,
                style_brief: input.style.tone ?? "",
                word_count: currentContent.count,
                paragraph_count: currentContent.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                material_count: input.materials.isEmpty ? 0 : 1,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: [],
                genre: input.style.genre,
                known_pitfalls: (input.style.known_pitfalls ?? []).map(\.description),
                last_review_summary: previousReview?.summary,
                learned_preferences: (input.style.learned_preferences ?? []).map(\.description)
            )
            let reviewResponse = await aiClient.execute(
                NativeWorkflowCatalog.writingReview(
                    context: reviewContext,
                    style: input.style,
                    previousReview: previousReview,
                    template: input.writingReviewTemplate
                ),
                config: input.config,
                apiKey: input.apiKey
            ).writingReviewResponse
            try Task.checkCancellation()
            steps.append(
                AgentStepPayload(
                    step_index: steps.count + 1,
                    name: "第 \(round) 轮写作诊断",
                    status: reviewResponse.success == true ? "success" : "fallback",
                    input_summary: reviewResponse.input_summary ?? "",
                    output_summary: reviewResponse.output_summary ?? "",
                    elapsed_ms: reviewResponse.elapsed_ms ?? 0,
                    error: reviewResponse.error ?? ""
                )
            )
            if let error = reviewResponse.error.nilIfEmpty {
                errors.append(error)
            }
            if reviewResponse.success != true, !NativeAIError.isMissingAPIKey(errorText: reviewResponse.error ?? "") {
                iterations.append(
                    DeepDraftIteration(
                        round: round,
                        score: lastScore,
                        highIssueCount: 0,
                        mediumIssueCount: 0,
                        remainingIssues: [],
                        revisionSummary: nil,
                        stoppedReason: "第 \(round) 轮诊断调用失败，提前结束"
                    )
                )
                break
            }

            let review = transientReview(from: reviewResponse.result, title: currentTitle)
            let highCount = review.issues.filter { $0.severity == "高" }.count
            let mediumCount = review.issues.filter { $0.severity == "中" }.count
            let pitfallHits = Self.pitfallHits(in: review, pitfalls: input.style.known_pitfalls ?? [])
            let remaining = (review.issues.prefix(4).map { "[\($0.severity)] \($0.dimension)：\($0.problem)" }
                + pitfallHits.map { "[高] 作者雷区：\($0)" })
            let score = review.overall_score
            let hasPitfallHit = !pitfallHits.isEmpty
            let lowRisk = highCount == 0 && mediumCount == 0 && !hasPitfallHit

            // 主判据（PRD 22.4.3）：上一轮高/中严重度 issues 的核销率 = 本轮 resolved_from_last 覆盖的条数 ÷ 上一轮高+中 issue 总数。
            let previousHighMediumCount = previousReview?.issues.filter { $0.severity == "高" || $0.severity == "中" }.count ?? 0
            let resolutionRate: Double? = previousHighMediumCount > 0
                ? Double(review.resolved_from_last.count) / Double(previousHighMediumCount)
                : nil
            let highResolution = (resolutionRate ?? 0) >= 0.8 && highCount == 0 && !hasPitfallHit
            if let resolutionRate, resolutionRate < 0.3 {
                lowResolutionStreak += 1
            } else {
                lowResolutionStreak = 0
            }
            let stalled = lowResolutionStreak >= 2

            if lowRisk || highResolution {
                iterations.append(
                    DeepDraftIteration(
                        round: round,
                        score: score,
                        highIssueCount: highCount,
                        mediumIssueCount: mediumCount,
                        remainingIssues: remaining,
                        revisionSummary: nil,
                        stoppedReason: lowRisk ? "无高/中严重度问题且未命中作者雷区" : "上一轮问题核销率达标"
                    )
                )
                previousReview = review
                lastScore = score
                break
            }
            if stalled {
                iterations.append(
                    DeepDraftIteration(
                        round: round,
                        score: score,
                        highIssueCount: highCount,
                        mediumIssueCount: mediumCount,
                        remainingIssues: remaining,
                        revisionSummary: nil,
                        stoppedReason: "连续两轮问题核销率过低，判定为空转"
                    )
                )
                previousReview = review
                lastScore = score
                break
            }

            let context = ContextPackage(
                stage: "深度修订第 \(round) 轮",
                title: currentTitle,
                summary: currentSummary,
                idea: input.idea,
                direction: input.direction,
                outline_excerpt: input.outline,
                content_excerpt: currentContent,
                materials_excerpt: input.materials,
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: input.style.name,
                style_brief: input.style.tone ?? "",
                word_count: currentContent.count,
                paragraph_count: currentContent.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                material_count: input.materials.isEmpty ? 0 : 1,
                recent_article_titles: [],
                recent_training_focus: review.training_focus,
                recent_issues: remaining,
                genre: input.style.genre,
                known_pitfalls: (input.style.known_pitfalls ?? []).map(\.description),
                last_review_summary: review.summary,
                learned_preferences: (input.style.learned_preferences ?? []).map(\.description)
            )
            let revision = await aiClient.execute(
                NativeWorkflowCatalog.improveDraftFromReview(
                    context: context,
                    content: currentContent,
                    review: review,
                    style: input.style
                ),
                config: input.config,
                apiKey: input.apiKey
            ).draftResponse
            try Task.checkCancellation()
            steps.append(
                AgentStepPayload(
                    step_index: steps.count + 1,
                    name: "第 \(round) 轮按诊断修订",
                    status: revision.success == true ? "success" : "fallback",
                    input_summary: revision.input_summary ?? "",
                    output_summary: revision.output_summary ?? "",
                    elapsed_ms: revision.elapsed_ms ?? 0,
                    error: revision.error ?? ""
                )
            )
            if let error = revision.error.nilIfEmpty {
                errors.append(error)
            }
            if revision.success != true, !NativeAIError.isMissingAPIKey(errorText: revision.error ?? "") {
                iterations.append(
                    DeepDraftIteration(
                        round: round,
                        score: score,
                        highIssueCount: highCount,
                        mediumIssueCount: mediumCount,
                        remainingIssues: remaining,
                        revisionSummary: nil,
                        stoppedReason: "第 \(round) 轮修订调用失败，提前结束"
                    )
                )
                break
            }

            let draft = revision.result
            currentTitle = draft.title.nilIfEmpty ?? currentTitle
            currentSummary = draft.summary.nilIfEmpty ?? currentSummary
            currentContent = draft.content.nilIfEmpty ?? currentContent
            bestDraft = DraftResult(title: currentTitle, content: currentContent, summary: currentSummary, tags: draft.tags, raw_output: draft.raw_output)
            iterations.append(
                DeepDraftIteration(
                    round: round,
                    score: score,
                    highIssueCount: highCount,
                    mediumIssueCount: mediumCount,
                    remainingIssues: remaining,
                    revisionSummary: revision.result.summary ?? review.summary,
                    stoppedReason: round == cappedMaxRounds ? "达到最大轮数" : nil
                )
            )
            previousReview = review
            lastScore = score
        }

        return DeepDraftOutput(
            draft: bestDraft,
            iterations: iterations,
            steps: steps,
            elapsed_ms: Int(Date().timeIntervalSince(start) * 1000),
            success: errors.isEmpty,
            error: errors.joined(separator: "；")
        )
    }

    private func transientReview(from result: WritingReviewResult, title: String) -> WritingReview {
        WritingReview(
            id: -1,
            article_id: nil,
            title_snapshot: title,
            summary: result.summary ?? "已完成一轮深度诊断。",
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

    private static func pitfallHits(in review: WritingReview, pitfalls: [AuthorPitfall]) -> [String] {
        let descriptions = pitfalls
            .map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !descriptions.isEmpty else { return [] }

        let modelHits = review.pitfall_hits
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !modelHits.isEmpty {
            return Set(modelHits).sorted()
        }

        var hits: Set<String> = []
        for issue in review.issues {
            let issueText = [issue.dimension, issue.excerpt, issue.problem, issue.suggestion]
                .compactMap { $0 }
                .joined(separator: "\n")
            if issue.dimension.contains("雷区") || issue.problem.contains("雷区") {
                hits.insert(issue.problem)
            }
            for description in descriptions where issueText.localizedStandardContains(description) {
                hits.insert(description)
            }
        }
        return hits.sorted()
    }
}
