import Foundation
import CreativeWorkshopCore

struct PipelineOutcome: Codable {
    var pipeline: String
    var caseID: String
    var title: String
    var content: String
    var overallScore: Int?
    var highIssueCount: Int
    var mediumIssueCount: Int
    var lowIssueCount: Int
    var wordCount: Int
    var callCount: Int
    var fallbackCount: Int
    var elapsedMS: Int
    var success: Bool
    var error: String
    var verificationSummary: String
    /// search_materials 本地检索次数（PRD 23.8.1）：不计入 callCount，单独一列。
    var searchCount: Int
}

enum EvalError: LocalizedError {
    case unknownPipeline(String)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case let .unknownPipeline(name):
            return "未知的评测管线：\(name)"
        case .missingAPIKey:
            return "未配置 API Key，评测需要真实模型输出，已终止。"
        }
    }
}

/// 薄封装：把 evals 用例交给主 target 的 EvalPipelineFacade（复用 AgentDraftCoordinator /
/// DeepDraftCoordinator / NativeWorkflowCatalog，见 PRD 22.4.2），只在这里做结果形状转换。
struct PipelineRunner {
    static let pipelineNames = EvalPipelineFacade.pipelineNames

    let facade: EvalPipelineFacade

    func run(pipeline: String, evalCase: EvalCase) async throws -> PipelineOutcome {
        guard Self.pipelineNames.contains(pipeline) else {
            throw EvalError.unknownPipeline(pipeline)
        }
        let input = EvalCaseInput(
            id: evalCase.id,
            idea: evalCase.idea,
            direction: evalCase.direction,
            materials: evalCase.materials,
            content: evalCase.content
        )
        let outcome = try await facade.run(pipeline: pipeline, evalCase: input)
        return PipelineOutcome(
            pipeline: pipeline,
            caseID: evalCase.id,
            title: outcome.title,
            content: outcome.content,
            overallScore: outcome.overallScore,
            highIssueCount: outcome.highIssueCount,
            mediumIssueCount: outcome.mediumIssueCount,
            lowIssueCount: outcome.lowIssueCount,
            wordCount: outcome.wordCount,
            callCount: outcome.callCount,
            fallbackCount: outcome.fallbackCount,
            elapsedMS: outcome.elapsedMS,
            success: outcome.success,
            error: outcome.error,
            verificationSummary: outcome.verificationSummary,
            searchCount: outcome.searchCount
        )
    }
}
