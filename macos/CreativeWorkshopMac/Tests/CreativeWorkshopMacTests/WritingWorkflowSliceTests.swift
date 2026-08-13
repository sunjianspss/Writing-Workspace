import SQLite3
import XCTest
@testable import CreativeWorkshopCore

// 24.16 迁出的 AI 编排纵切片。每条切片的共同约定：模型调用与证据落库归
// `WritingWorkflow`；稿件是否被改动、候选是否交付，仍由调用方决定。

/// 局部改写：模型调用与运行轨迹落库归 `WritingWorkflow`，正文是否替换由调用方决定。
@MainActor
final class WritingWorkflowRewriteTests: XCTestCase {
    func testRewriteReturnsReplacementAndRecordsExactlyOneAgentRun() async throws {
        let database = try makeDatabase()
        let executor = RewriteExecutor(replacement: "改写后的句子", note: "更具体了")
        let workflow = WritingWorkflow(database: database, executor: executor)

        let outcome = try await workflow.rewriteSelection(makeRequest(database: database))

        XCTAssertEqual(executor.kinds, [.rewriteSelection])
        XCTAssertEqual(outcome.replacement, "改写后的句子")
        XCTAssertEqual(outcome.note, "更具体了")
        XCTAssertFalse(outcome.usedFallback)
        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
    }

    /// 空替换必须在落库前失败：一次没产出的改写不该在运行记录里留下痕迹。
    func testEmptyReplacementThrowsAndWritesNoAgentRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: RewriteExecutor(replacement: "   \n  ", note: nil)
        )

        do {
            _ = try await workflow.rewriteSelection(makeRequest(database: database))
            XCTFail("空替换必须抛错")
        } catch WritingWorkflow.WorkflowError.emptyRewriteReplacement {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    /// 模型没给 replacement 时退回 raw_output，仍算一次有效改写。
    func testFallsBackToRawOutputWhenReplacementIsMissing() async throws {
        let database = try makeDatabase()
        let executor = RewriteExecutor(replacement: nil, note: nil, rawOutput: "原始输出正文")
        let workflow = WritingWorkflow(database: database, executor: executor)

        let outcome = try await workflow.rewriteSelection(makeRequest(database: database))

        XCTAssertEqual(outcome.replacement, "原始输出正文")
        XCTAssertNil(outcome.note, "空白 note 不应变成空串")
    }

    /// 调用失败时运行记录必须落成 fallback，而不是假装成功。
    func testFailedRunIsRecordedAsFallbackWithItsError() async throws {
        let database = try makeDatabase()
        let executor = RewriteExecutor(
            replacement: "本地兜底改写",
            note: nil,
            success: false,
            error: "未配置 API Key"
        )
        let workflow = WritingWorkflow(database: database, executor: executor)

        let outcome = try await workflow.rewriteSelection(makeRequest(database: database))

        XCTAssertTrue(outcome.usedFallback)
        XCTAssertEqual(outcome.error, "未配置 API Key")
        XCTAssertEqual(try database.listAgentRuns(limit: 1).first?.status, "fallback")
    }

    func testMissingExecutorThrowsBeforeAnyWrite() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.rewriteSelection(makeRequest(database: database))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    // MARK: - Fixtures

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "rewrite-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.RewriteSelectionRequest {
        let style = try database.defaultStyle()
        return .init(
            articleID: nil,
            titleSnapshot: "测试稿",
            context: ContextPackage(
                stage: "改写",
                title: "测试稿",
                summary: "",
                idea: "",
                direction: "随笔",
                outline_excerpt: "",
                content_excerpt: "原始正文里的一句话。",
                materials_excerpt: "",
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: style.name,
                style_brief: "",
                word_count: 10,
                paragraph_count: 1,
                material_count: 0,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: [],
                genre: style.genre,
                known_pitfalls: []
            ),
            selectedText: "一句话",
            surroundingText: "原始正文里的一句话。",
            mode: .custom,
            customInstruction: "写得更具体",
            style: style,
            template: nil,
            config: ModelConfig(model: "test-model"),
            apiKey: "fake-key",
            actionTitle: "定点改写",
            fallbackSummary: "写得更具体"
        )
    }
}

private final class RewriteExecutor: AIWorkflowExecuting {
    private(set) var kinds: [AIWorkflowKind] = []
    private let replacement: String?
    private let note: String?
    private let rawOutput: String?
    private let success: Bool
    private let error: String

    init(
        replacement: String?,
        note: String?,
        rawOutput: String? = nil,
        success: Bool = true,
        error: String = ""
    ) {
        self.replacement = replacement
        self.note = note
        self.rawOutput = rawOutput
        self.success = success
        self.error = error
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        kinds.append(descriptor.kind)

        if let result = RewriteResult(
            replacement: replacement,
            note: note,
            raw_output: rawOutput
        ) as? Output {
            return AIRun(
                result: result,
                elapsedMS: 3,
                success: success,
                error: error,
                inputSummary: "改写输入",
                outputSummary: "改写输出"
            )
        }

        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: false,
            error: "unexpected workflow",
            inputSummary: "",
            outputSummary: ""
        )
    }
}

/// 写作诊断纵切片（24.16）。
@MainActor
final class WritingWorkflowReviewTests: XCTestCase {
    /// 防空转（18.3.2）的基准必须跟诊断一起落库，且是本次送检的那份文本。
    func testReviewPersistsTheSnapshotItActuallyReviewed() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: ReviewExecutor())

        let outcome = try await workflow.runWritingReview(
            makeRequest(database: database, reviewedSnapshot: "送检的那份正文")
        )

        XCTAssertEqual(outcome.review.reviewed_snapshot, "送检的那份正文")
        XCTAssertEqual(
            try database.listWritingReviews(limit: 1).first?.reviewed_snapshot,
            "送检的那份正文",
            "落库的记录必须带同一份基准，否则下一轮防空转失灵"
        )
    }

    func testReviewCommitsRunTraceAndReviewTogether() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: ReviewExecutor())

        let outcome = try await workflow.runWritingReview(
            makeRequest(database: database, reviewedSnapshot: "正文")
        )

        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertEqual(try database.listWritingReviews(limit: 10).map(\.id), [outcome.review.id])
        XCTAssertEqual(outcome.review.summary, "结构清楚，证据偏薄。")
        XCTAssertFalse(outcome.usedFallback)
    }

    func testMissingExecutorLeavesNoReviewAndNoRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.runWritingReview(
                makeRequest(database: database, reviewedSnapshot: "正文")
            )
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listWritingReviews(limit: 10).isEmpty)
        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "review-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(
        database: NativeDatabase,
        reviewedSnapshot: String
    ) throws -> WritingWorkflow.ReviewRequest {
        let style = try database.defaultStyle()
        return .init(
            analysis: .init(
                articleID: nil,
                titleSnapshot: "测试稿",
                context: ContextPackage(
                    stage: "诊断",
                    title: "测试稿",
                    summary: "",
                    idea: "",
                    direction: "随笔",
                    outline_excerpt: "",
                    content_excerpt: reviewedSnapshot,
                    materials_excerpt: "",
                    selected_topic_title: nil,
                    selected_topic_summary: nil,
                    style_name: style.name,
                    style_brief: "",
                    word_count: reviewedSnapshot.count,
                    paragraph_count: 1,
                    material_count: 0,
                    recent_article_titles: [],
                    recent_training_focus: [],
                    recent_issues: [],
                    genre: style.genre,
                    known_pitfalls: []
                ),
                style: style,
                template: nil,
                config: ModelConfig(model: "test-model"),
                apiKey: "fake-key"
            ),
            previousReview: nil,
            reviewedSnapshot: reviewedSnapshot
        )
    }
}

private final class ReviewExecutor: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = WritingReviewResult(
            summary: "结构清楚，证据偏薄。",
            overall_score: 82,
            strengths: [],
            issues: [],
            revision_plan: ["补来源"],
            training_focus: ["先给证据"],
            style_notes: [],
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result,
                elapsedMS: 5,
                success: true,
                error: "",
                inputSummary: "诊断输入",
                outputSummary: "诊断输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: false,
            error: "unexpected workflow",
            inputSummary: "",
            outputSummary: ""
        )
    }
}

/// 按诊断改全文纵切片（24.16）：产出候选与轨迹，交付留给调用方。
@MainActor
final class WritingWorkflowReviseTests: XCTestCase {
    /// 本切片不得自行交付：待复核版本由调用方在证明会话未过期后才创建。
    func testReviseRecordsRunButCreatesNoPendingVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: ReviseExecutor())

        let outcome = try await workflow.reviseFromReview(makeRequest(database: database))

        XCTAssertEqual(outcome.result.content, "按诊断改过的正文")
        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertTrue(
            try database.listDraftVersions(limit: 10).isEmpty,
            "交付是调用方的职责，本切片不能自行落待复核版本"
        )
    }

    /// 模型没给摘要时退回诊断自己的摘要，运行记录不留空。
    func testRunSummaryFallsBackToTheReviewSummary() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: ReviseExecutor(summary: nil)
        )

        let outcome = try await workflow.reviseFromReview(makeRequest(database: database))

        XCTAssertEqual(outcome.agentRun.summary, "结构清楚，证据偏薄。")
    }

    func testMissingExecutorWritesNothing() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.reviseFromReview(makeRequest(database: database))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "revise-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.ReviseFromReviewRequest {
        let style = try database.defaultStyle()
        let review = try database.saveWritingReview(
            result: WritingReviewResult(
                summary: "结构清楚，证据偏薄。",
                overall_score: 82,
                strengths: [],
                issues: [],
                revision_plan: ["补来源"],
                training_focus: [],
                style_notes: [],
                raw_output: nil
            ),
            articleID: nil,
            titleSnapshot: "测试稿",
            model: "test-model",
            reviewedSnapshot: "原始正文"
        )
        return .init(
            analysis: .init(
                articleID: nil,
                titleSnapshot: "测试稿",
                context: ContextPackage(
                    stage: "修订",
                    title: "测试稿",
                    summary: "",
                    idea: "",
                    direction: "随笔",
                    outline_excerpt: "",
                    content_excerpt: "原始正文",
                    materials_excerpt: "",
                    selected_topic_title: nil,
                    selected_topic_summary: nil,
                    style_name: style.name,
                    style_brief: "",
                    word_count: 4,
                    paragraph_count: 1,
                    material_count: 0,
                    recent_article_titles: [],
                    recent_training_focus: [],
                    recent_issues: [],
                    genre: style.genre,
                    known_pitfalls: []
                ),
                style: style,
                template: nil,
                config: ModelConfig(model: "test-model"),
                apiKey: "fake-key"
            ),
            content: "原始正文",
            review: review
        )
    }
}

private final class ReviseExecutor: AIWorkflowExecuting {
    private let summary: String?

    init(summary: String? = "已按诊断修订") {
        self.summary = summary
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = DraftResult(
            title: "改过的标题",
            content: "按诊断改过的正文",
            summary: summary,
            tags: nil,
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result,
                elapsedMS: 6,
                success: true,
                error: "",
                inputSummary: "修订输入",
                outputSummary: "修订输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(),
            elapsedMS: 1,
            success: false,
            error: "unexpected workflow",
            inputSummary: "",
            outputSummary: ""
        )
    }
}

/// 深度成稿纵切片（24.16）：三段串联归 DeepDraftCoordinator，本切片只落多步轨迹。
@MainActor
final class WritingWorkflowDeepReviseTests: XCTestCase {
    /// 轨迹必须保留协调器给出的每一步，压成一步就无法复盘是哪一段出的问题。
    func testDeepReviseKeepsEveryCoordinatorStepInTheRunTrace() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: DeepReviseExecutor())

        let outcome = try await workflow.deepRevise(makeRequest(database: database))

        let persisted = try XCTUnwrap(try database.listAgentRuns(limit: 1).first)
        XCTAssertEqual(persisted.id, outcome.agentRun.id)
        XCTAssertGreaterThan(
            outcome.output.steps.count,
            1,
            "三段串联至少应留下多于一步的轨迹"
        )
        XCTAssertEqual(outcome.agentRun.steps.count, outcome.output.steps.count)
    }

    /// 同样不做交付：待复核版本由调用方在校验会话后创建。
    func testDeepReviseCreatesNoPendingVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: DeepReviseExecutor())

        _ = try await workflow.deepRevise(makeRequest(database: database))

        XCTAssertTrue(try database.listDraftVersions(limit: 10).isEmpty)
    }

    func testMissingExecutorWritesNoRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.deepRevise(makeRequest(database: database))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "deep-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.DeepRevisionRequest {
        let style = try database.defaultStyle()
        return .init(
            articleID: nil,
            titleSnapshot: "测试稿",
            input: DeepDraftInput(
                title: "测试稿",
                summary: "",
                content: "原始正文需要深度成稿。",
                outline: "",
                idea: "",
                direction: "随笔",
                materials: "",
                style: style,
                previousReview: nil,
                writingReviewTemplate: nil,
                config: ModelConfig(model: "test-model"),
                apiKey: "fake-key"
            )
        )
    }
}

private final class DeepReviseExecutor: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        // 必须留一个高危问题，否则协调器判定「无高/中问题」，一轮就停、不会进入修订段。
        if let result = WritingReviewResult(
            summary: "还能更紧。",
            overall_score: 80,
            strengths: [],
            issues: [
                WritingReviewIssue(
                    dimension: "证据",
                    severity: "高",
                    excerpt: "原始正文",
                    problem: "缺少来源",
                    suggestion: "补一句出处"
                )
            ],
            revision_plan: ["收紧结尾"],
            training_focus: [],
            style_notes: [],
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 3, success: true, error: "",
                inputSummary: "诊断输入", outputSummary: "诊断输出"
            )
        }
        if let result = DraftResult(
            title: "深度成稿标题",
            content: "深度成稿后的正文。",
            summary: "已完成深度成稿",
            tags: nil,
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 4, success: true, error: "",
                inputSummary: "修订输入", outputSummary: "修订输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}

/// 发布物料纵切片（24.16）：派生文案，不改稿件事实。
@MainActor
final class WritingWorkflowPublishAssetsTests: XCTestCase {
    func testAssetsAndRunTraceCommitTogether() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: PublishAssetsExecutor())

        let outcome = try await workflow.generatePublishAssets(makeRequest(database: database))

        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertEqual(try database.listPublishAssets(limit: 10).map(\.id), [outcome.assets.id])
        XCTAssertEqual(outcome.assets.summary, "一句话摘要")
        XCTAssertEqual(outcome.assets.tags, ["写作", "工具"])
        XCTAssertFalse(outcome.usedFallback)
    }

    /// 物料是派生文案，不是稿件事实：本切片不得写文章或改稿版本。
    func testAssetsGenerationTouchesNoArticleOrDraftVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: PublishAssetsExecutor())

        _ = try await workflow.generatePublishAssets(makeRequest(database: database))

        XCTAssertTrue(try database.listArticles().isEmpty)
        XCTAssertTrue(try database.listDraftVersions(limit: 10).isEmpty)
    }

    /// 模型只给了封面文案时，运行记录退回封面文案而不是留空。
    func testRunSummaryFallsBackToCoverTextWhenSummaryIsMissing() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: PublishAssetsExecutor(summary: nil, coverText: "封面这句")
        )

        let outcome = try await workflow.generatePublishAssets(makeRequest(database: database))

        XCTAssertEqual(outcome.agentRun.summary, "封面这句")
    }

    /// 物料落库失败时，运行轨迹必须随同一事务回滚——不能留下"有轨迹无物料"的记录。
    func testAssetsFailureRollsBackTheRunTraceInTheSameTransaction() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: PublishAssetsExecutor())
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE publish_assets", nil, nil, nil), SQLITE_OK)

        do {
            _ = try await workflow.generatePublishAssets(makeRequest(database: database))
            XCTFail("物料表缺失时必须抛错")
        } catch {
            // 预期负向路径。
        }

        XCTAssertTrue(
            try database.listAgentRuns(limit: 10).isEmpty,
            "物料写入失败时 AgentRun 必须随事务回滚"
        )
    }

    func testMissingExecutorWritesNeitherAssetsNorRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.generatePublishAssets(makeRequest(database: database))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
        XCTAssertTrue(try database.listPublishAssets(limit: 10).isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "assets-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.AnalysisRequest {
        let style = try database.defaultStyle()
        return .init(
            articleID: nil,
            titleSnapshot: "测试稿",
            context: ContextPackage(
                stage: "物料",
                title: "测试稿",
                summary: "",
                idea: "",
                direction: "随笔",
                outline_excerpt: "",
                content_excerpt: "正文",
                materials_excerpt: "",
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: style.name,
                style_brief: "",
                word_count: 2,
                paragraph_count: 1,
                material_count: 0,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: [],
                genre: style.genre,
                known_pitfalls: []
            ),
            style: style,
            template: nil,
            config: ModelConfig(model: "test-model"),
            apiKey: "fake-key"
        )
    }
}

private final class PublishAssetsExecutor: AIWorkflowExecuting {
    private let summary: String?
    private let coverText: String?

    init(summary: String? = "一句话摘要", coverText: String? = "封面文案") {
        self.summary = summary
        self.coverText = coverText
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = PublishAssetsResult(
            summary: summary,
            cover_text: coverText,
            moments_text: nil,
            tags: ["写作", "工具"],
            xiaohongshu_text: nil,
            cover_image_prompt: nil,
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 4, success: true, error: "",
                inputSummary: "物料输入", outputSummary: "物料输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}
