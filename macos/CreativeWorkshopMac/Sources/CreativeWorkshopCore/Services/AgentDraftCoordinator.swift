import Foundation

package struct AgentDraftCoordinator {
    package let executor: AIWorkflowExecuting

    package init(executor: AIWorkflowExecuting) {
        self.executor = executor
    }

    package func run(
        context: ContextPackage,
        style: StyleProfile,
        config: ModelConfig,
        apiKey: String
    ) async -> AgentDraftResponse {
        let input = context.idea

        let briefRun: AIRun<WritingBriefResult> = await executor.execute(
            NativeWorkflowCatalog.writingBrief(context: context, style: style),
            config: config,
            apiKey: apiKey
        )
        let briefStep = AgentStepPayload(run: briefRun, index: 1, name: "Writing brief")
        if let breakInfo = circuitBreak(briefRun, step: briefStep) {
            return breakResponse(
                brief: briefRun.result,
                argumentCheck: Self.emptyArgumentCheck,
                sectionDraft: Self.emptySectionDraft,
                critique: Self.emptyCritique,
                fallbackTitle: briefRun.result.working_title ?? input,
                steps: [briefStep],
                breakInfo: breakInfo
            )
        }

        let argumentRun: AIRun<ArgumentCheckResult> = await executor.execute(
            NativeWorkflowCatalog.argumentCheck(
                brief: briefRun.result,
                context: context,
                style: style
            ),
            config: config,
            apiKey: apiKey
        )
        let argumentStep = AgentStepPayload(run: argumentRun, index: 2, name: "论点检查")
        if let breakInfo = circuitBreak(argumentRun, step: argumentStep) {
            return breakResponse(
                brief: briefRun.result,
                argumentCheck: argumentRun.result,
                sectionDraft: Self.emptySectionDraft,
                critique: Self.emptyCritique,
                fallbackTitle: briefRun.result.working_title ?? input,
                steps: [briefStep, argumentStep],
                breakInfo: breakInfo
            )
        }

        var steps = [briefStep, argumentStep]
        var brief = briefRun.result
        var revisionRun: AIRun<WritingBriefResult>?
        var nextStepIndex = 3

        // 论点检查未判定可以成稿，或仍标出缺证据项时，先跑一轮（最多一轮）Brief 修订，
        // 再用修订后的 brief 继续分段成稿（PRD 22.2.1）。
        if argumentRun.result.ready_to_draft == false || !(argumentRun.result.missing_evidence ?? []).isEmpty {
            let run: AIRun<WritingBriefResult> = await executor.execute(
                NativeWorkflowCatalog.briefRevision(
                    brief: brief,
                    argumentCheck: argumentRun.result,
                    context: context,
                    style: style
                ),
                config: config,
                apiKey: apiKey
            )
            let revisionStep = AgentStepPayload(run: run, index: nextStepIndex, name: "Brief 修订")
            nextStepIndex += 1
            steps.append(revisionStep)
            revisionRun = run
            brief = run.result
            if let breakInfo = circuitBreak(run, step: revisionStep) {
                return breakResponse(
                    brief: brief,
                    argumentCheck: argumentRun.result,
                    sectionDraft: Self.emptySectionDraft,
                    critique: Self.emptyCritique,
                    fallbackTitle: brief.working_title ?? input,
                    steps: steps,
                    breakInfo: breakInfo
                )
            }
        }

        let sectionFragmentContexts = FragmentRetriever.sectionContexts(
            for: brief,
            fragments: context.fragment_corpus ?? [],
            limit: 3
        )
        var sectionContext = context
        sectionContext.section_fragment_contexts = sectionFragmentContexts

        let sectionRun: AIRun<SectionDraftResult> = await executor.execute(
            NativeWorkflowCatalog.sectionDraft(
                brief: brief,
                argumentCheck: argumentRun.result,
                context: sectionContext,
                style: style
            ),
            config: config,
            apiKey: apiKey
        )
        let sectionStep = AgentStepPayload(run: sectionRun, index: nextStepIndex, name: "分段成稿")
        nextStepIndex += 1
        steps.append(sectionStep)
        if let breakInfo = circuitBreak(sectionRun, step: sectionStep) {
            return breakResponse(
                brief: brief,
                argumentCheck: argumentRun.result,
                sectionDraft: sectionRun.result,
                critique: Self.emptyCritique,
                fallbackTitle: brief.working_title ?? input,
                sectionFragmentContexts: sectionFragmentContexts,
                steps: steps,
                breakInfo: breakInfo
            )
        }

        let critiqueRun: AIRun<DraftCritiqueResult> = await executor.execute(
            NativeWorkflowCatalog.draftCritique(
                brief: brief,
                argumentCheck: argumentRun.result,
                sectionDraft: sectionRun.result,
                context: sectionContext,
                style: style
            ),
            config: config,
            apiKey: apiKey
        )
        let critiqueStep = AgentStepPayload(run: critiqueRun, index: nextStepIndex, name: "自我批评与整合")
        steps.append(critiqueStep)
        if let breakInfo = circuitBreak(critiqueRun, step: critiqueStep) {
            return breakResponse(
                brief: brief,
                argumentCheck: argumentRun.result,
                sectionDraft: sectionRun.result,
                critique: critiqueRun.result,
                fallbackTitle: brief.working_title ?? input,
                sectionFragmentContexts: sectionFragmentContexts,
                steps: steps,
                breakInfo: breakInfo
            )
        }

        let result = critiqueRun.result.draftResult(
            fallbackTitle: brief.working_title ?? input,
            fallbackContent: sectionRun.result.markdown
        )
        let errors = [briefRun.error, argumentRun.error, revisionRun?.error ?? "", sectionRun.error, critiqueRun.error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let success = briefRun.success && argumentRun.success && (revisionRun?.success ?? true) && sectionRun.success && critiqueRun.success
        return AgentDraftResponse(
            result: result,
            brief: brief,
            argumentCheck: argumentRun.result,
            sectionDraft: sectionRun.result,
            critique: critiqueRun.result,
            sectionFragmentContexts: sectionFragmentContexts,
            elapsed_ms: briefRun.elapsedMS + argumentRun.elapsedMS + (revisionRun?.elapsedMS ?? 0) + sectionRun.elapsedMS + critiqueRun.elapsedMS,
            success: success,
            error: errors.joined(separator: "；"),
            input_summary: steps.map(\.input_summary).joined(separator: "\n---\n"),
            output_summary: [
                brief.summaryText,
                argumentRun.result.summaryText,
                critiqueRun.result.critique_notes?.prefix(3).joined(separator: "；") ?? ""
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n---\n"),
            steps: steps,
            circuitBreak: nil
        )
    }

    /// 某一步的错误若不是"未配置 API Key"的演示模式，管线必须立即熔断（PRD 22.3.3-B），
    /// 不得让该步的本地兜底结果继续流入下游步骤。
    private func circuitBreak<T>(_ run: AIRun<T>, step: AgentStepPayload) -> AgentDraftCircuitBreak? {
        guard !run.success, !NativeAIError.isMissingAPIKey(errorText: run.error) else {
            return nil
        }
        return AgentDraftCircuitBreak(stepIndex: step.step_index, stepName: step.name, reason: run.error)
    }

    private func breakResponse(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        sectionDraft: SectionDraftResult,
        critique: DraftCritiqueResult,
        fallbackTitle: String,
        sectionFragmentContexts: [SectionFragmentContext] = [],
        steps: [AgentStepPayload],
        breakInfo: AgentDraftCircuitBreak
    ) -> AgentDraftResponse {
        AgentDraftResponse(
            result: DraftResult(title: fallbackTitle, content: sectionDraft.markdown, summary: nil, tags: nil, raw_output: nil),
            brief: brief,
            argumentCheck: argumentCheck,
            sectionDraft: sectionDraft,
            critique: critique,
            sectionFragmentContexts: sectionFragmentContexts,
            elapsed_ms: steps.reduce(0) { $0 + $1.elapsed_ms },
            success: false,
            error: breakInfo.reason,
            input_summary: steps.map(\.input_summary).joined(separator: "\n---\n"),
            output_summary: steps.map(\.output_summary).joined(separator: "\n---\n"),
            steps: steps,
            circuitBreak: breakInfo
        )
    }

    private static let emptyArgumentCheck = ArgumentCheckResult(
        thesis_strength: nil,
        weak_points: nil,
        missing_evidence: nil,
        revision_directives: nil,
        ready_to_draft: nil,
        raw_output: nil
    )

    private static let emptySectionDraft = SectionDraftResult(title: nil, sections: nil, raw_output: nil)

    private static let emptyCritique = DraftCritiqueResult(
        critique_notes: nil,
        title: nil,
        content: nil,
        summary: nil,
        tags: nil,
        raw_output: nil
    )
}

private extension AgentStepPayload {
    init<T>(run: AIRun<T>, index: Int, name: String) {
        self.init(
            step_index: index,
            name: name,
            status: run.success ? "success" : "fallback",
            input_summary: run.inputSummary,
            output_summary: run.outputSummary,
            elapsed_ms: run.elapsedMS,
            error: run.error
        )
    }
}
