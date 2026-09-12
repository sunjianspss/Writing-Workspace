import Foundation
import CreativeWorkshopCore

/// 配对重判（24.14）：拿存量正文重跑评分，不重新生成。
///
/// 24.13 的审计留下两个都要花钱才能回答的问题：一是"哪个维度拖分最多"（主评测路径只存三个
/// 计数，维度一条没有），二是"改完分数变了，是改对了还是抽样波动"。两个问题共用同一个答案：
/// **正文已经在库里了**（`eval_results.raw_json.content`），换评分变量重跑一遍，既拿到完整问题
/// 清单，又拿到一个配对对照——生成侧一次调用都不用发。
struct RejudgeRunner {
    let facade: EvalPipelineFacade
    let cases: [EvalCase]
    let sourceOutcomes: [PipelineOutcome]

    struct Plan {
        var variant: EvalPipelineFacade.ScoringVariant
        var outcome: PipelineOutcome
        var evalCase: EvalCase
    }

    /// 只重判**原轮成功且有正文**的格子：原轮失败的格子里躺的是兜底稿，给它打分得到的是
    /// 兜底模板的分数（24.9 已从主路径拆掉，这里不能又捡回来）。
    func plans(variants: [EvalPipelineFacade.ScoringVariant]) -> [Plan] {
        var result: [Plan] = []
        for variant in variants {
            for outcome in sourceOutcomes where outcome.success {
                guard !outcome.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let evalCase = cases.first(where: { $0.id == outcome.caseID }) else { continue }
                result.append(Plan(variant: variant, outcome: outcome, evalCase: evalCase))
            }
        }
        return result
    }

    func run(plan: Plan) async -> RejudgeRow {
        let outcome = await facade.rejudge(
            evalCase: EvalCaseInput(
                id: plan.evalCase.id,
                idea: plan.evalCase.idea,
                direction: plan.evalCase.direction,
                materials: plan.evalCase.materials,
                content: plan.evalCase.content
            ),
            title: plan.outcome.title,
            content: plan.outcome.content,
            variant: plan.variant
        )
        return RejudgeRow(
            variant: plan.variant.rawValue,
            caseID: plan.outcome.caseID,
            pipeline: plan.outcome.pipeline,
            overallScore: outcome.overallScore,
            issues: outcome.issues,
            success: outcome.success && outcome.overallScore != nil,
            error: outcome.error,
            elapsedMS: outcome.elapsedMS
        )
    }
}
