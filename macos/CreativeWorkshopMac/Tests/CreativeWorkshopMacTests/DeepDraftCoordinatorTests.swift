import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

/// DeepDraftCoordinator 的测试从 WorkshopStoreTests 搬出来，独立成一个
/// **非 @MainActor** 的 XCTestCase。
///
/// 原因不是归类整齐，是这几个测试在 CI 上会挂：它们是 async 测试，此前身处
/// `@MainActor final class WorkshopStoreTests`，于是每次进入测试体都要做一次
/// 主线程跳转。CI 上约 40% 的概率卡在这一跳上——采样显示主线程停在
/// `-[XCTestCase _dequeuePrimaryThreadWork]` 下的 mach_msg，所有工作线程空闲、
/// 常驻内存 23MB，即等一个永远不来的调度交接。
///
/// 这几个测试本来就不需要主线程：不碰 store、不碰任何 UI 状态，只测
/// DeepDraftCoordinator 这个纯逻辑协调器（该类型内零并发原语，FakeAIClient
/// 也是纯同步假实现）。搬出 @MainActor 后主线程跳转不再发生。
///
/// 本地复现不了（19 次全过，含把协作池压成单线程），只在核心数少的托管
/// runner 上出现，所以验证靠 CI 的连跑实验，不是靠本地跑一遍。
final class DeepDraftCoordinatorTests: XCTestCase {

    func testDeepDraftStopsAtConfiguredMaxRoundsAndKeepsBestDraft() async throws {
        let ai = FakeAIClient()
        ai.writingReviewResponses = [
            reviewResponse(score: 60, issue: "第一轮问题"),
            reviewResponse(score: 64, issue: "第二轮问题")
        ]
        ai.improveDraftResponses = [
            draftResponse(content: "第一轮修订正文", summary: "第一轮修订"),
            draftResponse(content: "第二轮修订正文", summary: "第二轮修订")
        ]

        let output = try await DeepDraftCoordinator(aiClient: ai).run(
            input: deepDraftInput(maxRounds: 2)
        )

        XCTAssertEqual(output.iterations.count, 2)
        XCTAssertEqual(output.steps.count, 4)
        XCTAssertEqual(output.iterations.last?.stoppedReason, "达到最大轮数")
        XCTAssertEqual(output.draft.content, "第二轮修订正文")
        XCTAssertEqual(ai.writingReviewCallCount, 2)
        XCTAssertEqual(ai.improveDraftCallCount, 2)
    }

    func testDeepDraftReturnsCurrentDraftWhenReviewFails() async throws {
        let ai = FakeAIClient()
        ai.writingReviewResponses = [
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "诊断失败，本地结果为空风险。",
                    overall_score: nil,
                    strengths: [],
                    issues: [],
                    revision_plan: [],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil
                ),
                elapsed_ms: 1,
                success: false,
                error: "网络失败",
                input_summary: "fake",
                output_summary: "fake"
            )
        ]

        let output = try await DeepDraftCoordinator(aiClient: ai).run(
            input: deepDraftInput(maxRounds: 3)
        )

        XCTAssertFalse(output.success)
        XCTAssertEqual(output.error, "网络失败")
        XCTAssertEqual(output.draft.title, "标题")
        XCTAssertEqual(output.draft.summary, "摘要")
        XCTAssertEqual(output.draft.content, "原始正文")
        XCTAssertEqual(output.iterations.count, 1)
        XCTAssertEqual(output.steps.count, 1)
        XCTAssertEqual(output.iterations.first?.stoppedReason, "第 1 轮诊断调用失败，提前结束")
        XCTAssertEqual(ai.improveDraftCallCount, 0)
    }

    /// pitfall_hits 非空时，即使诊断没有剩余高/中严重度问题，也不得停止深度成稿循环（PRD 22.4.3）。
    func testDeepDraftDoesNotStopWhenModelReportedPitfallHitRemains() async throws {
        let ai = FakeAIClient()
        ai.writingReviewResponses = [
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "分数高，但雷区仍在。",
                    overall_score: 95,
                    strengths: [],
                    issues: [
                        WritingReviewIssue(
                            dimension: "作者雷区",
                            severity: "低",
                            excerpt: nil,
                            problem: "不要鸡汤式收束",
                            suggestion: "把结尾落回具体经验。"
                        )
                    ],
                    revision_plan: ["修正雷区"],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil,
                    resolved_from_last: [],
                    pitfall_hits: ["不要鸡汤式收束"]
                ),
                elapsed_ms: 1,
                success: true,
                error: "",
                input_summary: "fake",
                output_summary: "fake"
            ),
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "雷区已解除。",
                    overall_score: 96,
                    strengths: [],
                    issues: [],
                    revision_plan: [],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil
                ),
                elapsed_ms: 1,
                success: true,
                error: "",
                input_summary: "fake",
                output_summary: "fake"
            )
        ]
        ai.improveDraftResponses = [
            draftResponse(content: "修正雷区后的正文", summary: "已修正雷区")
        ]
        var input = deepDraftInput(maxRounds: 3)
        input.style.known_pitfalls = [
            AuthorPitfall(description: "不要鸡汤式收束", source_review_id: 1, created_at: nil)
        ]

        let output = try await DeepDraftCoordinator(aiClient: ai).run(input: input)

        XCTAssertEqual(ai.improveDraftCallCount, 1)
        XCTAssertEqual(output.draft.content, "修正雷区后的正文")
        XCTAssertTrue(output.iterations.first?.remainingIssues.contains { $0.contains("作者雷区") } == true)
        XCTAssertEqual(output.iterations.last?.stoppedReason, "无高/中严重度问题且未命中作者雷区")
    }

    /// 主判据：上一轮高/中严重度 issues 的核销率 ≥0.8 且本轮无新增高严重度问题、无 pitfall_hits 时应停止（PRD 22.4.3）。
    func testDeepDraftStopsWhenResolutionRateOfLastHighMediumIssuesIsHighEnough() async throws {
        let ai = FakeAIClient()
        let previousIssues = (1...5).map { index in
            WritingReviewIssue(
                dimension: "结构",
                severity: "高",
                excerpt: nil,
                problem: "历史问题\(index)",
                suggestion: "继续修订"
            )
        }
        let previousReview = WritingReview(
            id: 1,
            article_id: nil,
            title_snapshot: "标题",
            summary: "上一轮诊断",
            overall_score: 60,
            strengths: [],
            issues: previousIssues,
            revision_plan: [],
            training_focus: [],
            style_notes: [],
            raw_output: nil,
            model: nil,
            created_at: nil,
            resolved_from_last: [],
            reviewed_snapshot: nil
        )
        ai.writingReviewResponses = [
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "高严重度问题已基本核销。",
                    overall_score: 82,
                    strengths: [],
                    issues: [
                        WritingReviewIssue(
                            dimension: "表达",
                            severity: "中",
                            excerpt: nil,
                            problem: "仍有一处表达偏软",
                            suggestion: "再具体一点"
                        )
                    ],
                    revision_plan: [],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil,
                    resolved_from_last: ["历史问题1", "历史问题2", "历史问题3", "历史问题4"]
                ),
                elapsed_ms: 1,
                success: true,
                error: "",
                input_summary: "fake",
                output_summary: "fake"
            )
        ]
        var input = deepDraftInput(maxRounds: 3)
        input.previousReview = previousReview

        let output = try await DeepDraftCoordinator(aiClient: ai).run(input: input)

        XCTAssertEqual(ai.improveDraftCallCount, 0)
        XCTAssertEqual(output.iterations.count, 1)
        XCTAssertEqual(output.iterations.first?.stoppedReason, "上一轮问题核销率达标")
    }

    /// 连续两轮核销率 < 0.3 判定为空转，即使还没到最大轮数也应停止（PRD 22.4.3）。
    func testDeepDraftStopsWhenResolutionRateStaysLowForTwoConsecutiveRounds() async throws {
        let ai = FakeAIClient()
        let previousIssues = (1...5).map { index in
            WritingReviewIssue(
                dimension: "结构",
                severity: "高",
                excerpt: nil,
                problem: "历史问题\(index)",
                suggestion: "继续修订"
            )
        }
        let previousReview = WritingReview(
            id: 1,
            article_id: nil,
            title_snapshot: "标题",
            summary: "上一轮诊断",
            overall_score: 50,
            strengths: [],
            issues: previousIssues,
            revision_plan: [],
            training_focus: [],
            style_notes: [],
            raw_output: nil,
            model: nil,
            created_at: nil,
            resolved_from_last: [],
            reviewed_snapshot: nil
        )
        ai.writingReviewResponses = [
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "第一轮几乎没有推进。",
                    overall_score: 52,
                    strengths: [],
                    issues: (1...4).map { index in
                        WritingReviewIssue(
                            dimension: "结构",
                            severity: "高",
                            excerpt: nil,
                            problem: "新问题\(index)",
                            suggestion: "继续修订"
                        )
                    },
                    revision_plan: ["继续修订"],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil,
                    resolved_from_last: []
                ),
                elapsed_ms: 1,
                success: true,
                error: "",
                input_summary: "fake",
                output_summary: "fake"
            ),
            WritingReviewResponse(
                result: WritingReviewResult(
                    summary: "第二轮仍然没有推进。",
                    overall_score: 53,
                    strengths: [],
                    issues: (1...3).map { index in
                        WritingReviewIssue(
                            dimension: "结构",
                            severity: "高",
                            excerpt: nil,
                            problem: "遗留问题\(index)",
                            suggestion: "继续修订"
                        )
                    },
                    revision_plan: ["继续修订"],
                    training_focus: [],
                    style_notes: [],
                    raw_output: nil,
                    resolved_from_last: []
                ),
                elapsed_ms: 1,
                success: true,
                error: "",
                input_summary: "fake",
                output_summary: "fake"
            )
        ]
        ai.improveDraftResponses = [
            draftResponse(content: "第一轮修订正文", summary: "第一轮修订")
        ]
        var input = deepDraftInput(maxRounds: 5)
        input.previousReview = previousReview

        let output = try await DeepDraftCoordinator(aiClient: ai).run(input: input)

        XCTAssertEqual(ai.writingReviewCallCount, 2)
        XCTAssertEqual(ai.improveDraftCallCount, 1)
        XCTAssertEqual(output.iterations.count, 2)
        XCTAssertEqual(output.iterations.last?.stoppedReason, "连续两轮问题核销率过低，判定为空转")
    }

    private func deepDraftInput(maxRounds: Int) -> DeepDraftInput {
        DeepDraftInput(
            title: "标题",
            summary: "摘要",
            content: "原始正文",
            outline: "大纲",
            idea: "想法",
            direction: "情感文学",
            materials: "素材",
            style: StyleProfile(
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
            ),
            previousReview: nil,
            writingReviewTemplate: nil,
            config: ModelConfig(),
            apiKey: "fake-key",
            maxRounds: maxRounds,
            targetScore: 90
        )
    }

    private func reviewResponse(score: Int, issue: String) -> WritingReviewResponse {
        WritingReviewResponse(
            result: WritingReviewResult(
                summary: issue,
                overall_score: score,
                strengths: [],
                issues: [
                    WritingReviewIssue(
                        dimension: "结构",
                        severity: "高",
                        excerpt: nil,
                        problem: issue,
                        suggestion: "继续修订"
                    )
                ],
                revision_plan: ["继续修订"],
                training_focus: ["结构"],
                style_notes: [],
                raw_output: nil
            ),
            elapsed_ms: 1,
            success: true,
            error: "",
            input_summary: "fake",
            output_summary: "fake"
        )
    }

    private func draftResponse(content: String, summary: String) -> DraftResponse {
        DraftResponse(
            result: DraftResult(title: "标题", content: content, summary: summary, tags: nil, raw_output: nil),
            elapsed_ms: 1,
            success: true,
            error: "",
            input_summary: "fake",
            output_summary: "fake"
        )
    }
}
