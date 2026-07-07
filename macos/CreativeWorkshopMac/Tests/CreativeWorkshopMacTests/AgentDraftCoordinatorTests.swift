import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

/// PRD 22.2.1：论点检查的裁决必须真正控制流程——ready_to_draft=false 或 missing_evidence 非空时，
/// 必须先跑一轮（且只跑一轮）Brief 修订，再继续分段成稿。
final class AgentDraftCoordinatorTests: XCTestCase {
    func testBriefRevisionRunsOnceWhenArgumentCheckIsNotReadyToDraft() async {
        let executor = KeyedResultExecutor()
        executor.argumentResult = ArgumentCheckResult(
            thesis_strength: "偏弱",
            weak_points: ["中段空泛"],
            missing_evidence: [],
            revision_directives: ["开头落到场景"],
            ready_to_draft: false,
            raw_output: nil
        )

        let response = await AgentDraftCoordinator(executor: executor).run(
            context: Self.makeContext(),
            style: Self.makeStyle(),
            config: ModelConfig(),
            apiKey: "fake-key"
        )

        XCTAssertEqual(executor.callCounts["agent-draft-brief-revision-native"], 1)
        XCTAssertTrue(response.steps.contains { $0.name == "Brief 修订" })
    }

    func testBriefRevisionRunsOnceWhenMissingEvidenceIsNonEmptyEvenIfReadyToDraft() async {
        let executor = KeyedResultExecutor()
        executor.argumentResult = ArgumentCheckResult(
            thesis_strength: "可写",
            weak_points: [],
            missing_evidence: ["缺一段亲历的具体场景"],
            revision_directives: [],
            ready_to_draft: true,
            raw_output: nil
        )

        let response = await AgentDraftCoordinator(executor: executor).run(
            context: Self.makeContext(),
            style: Self.makeStyle(),
            config: ModelConfig(),
            apiKey: "fake-key"
        )

        XCTAssertEqual(executor.callCounts["agent-draft-brief-revision-native"], 1)
        XCTAssertTrue(response.steps.contains { $0.name == "Brief 修订" })
    }

    func testBriefRevisionDoesNotRunWhenReadyToDraftAndNoMissingEvidence() async {
        let executor = KeyedResultExecutor()
        executor.argumentResult = ArgumentCheckResult(
            thesis_strength: "可写",
            weak_points: [],
            missing_evidence: [],
            revision_directives: ["开头落到场景"],
            ready_to_draft: true,
            raw_output: nil
        )

        let response = await AgentDraftCoordinator(executor: executor).run(
            context: Self.makeContext(),
            style: Self.makeStyle(),
            config: ModelConfig(),
            apiKey: "fake-key"
        )

        XCTAssertEqual(executor.callCounts["agent-draft-brief-revision-native"] ?? 0, 0)
        XCTAssertFalse(response.steps.contains { $0.name == "Brief 修订" })
    }

    private static func makeContext() -> ContextPackage {
        ContextPackage(
            stage: "想法阶段",
            title: "",
            summary: "",
            idea: "一个想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "",
            materials_excerpt: "一段素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
    }

    private static func makeStyle() -> StyleProfile {
        StyleProfile(
            id: 1,
            name: "测试风格",
            language_style: "中文",
            tone: "克制",
            structure_preference: "先场景后观察",
            favorite_expressions: nil,
            forbidden_expressions: nil,
            sample_texts: nil,
            title_style_like: nil,
            title_style_dislike: nil,
            is_default: 1
        )
    }
}

/// 按 endpoint 精确控制每一步返回结果内容的假执行器，用于验证依赖论点检查结果内容（而非仅成败）的分支逻辑。
private final class KeyedResultExecutor: AIWorkflowExecuting {
    private(set) var callCounts: [String: Int] = [:]

    var argumentResult = ArgumentCheckResult(
        thesis_strength: "可写",
        weak_points: [],
        missing_evidence: [],
        revision_directives: [],
        ready_to_draft: true,
        raw_output: nil
    )

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callCounts[descriptor.endpoint, default: 0] += 1
        if descriptor.endpoint == "agent-draft-argument-check-native", let result = argumentResult as? Output {
            return AIRun(result: result, elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
        }
        return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
    }
}
