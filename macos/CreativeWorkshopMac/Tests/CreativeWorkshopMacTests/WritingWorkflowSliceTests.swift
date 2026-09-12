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

    /// 诊断落库失败时，运行轨迹必须随同一事务回滚——不能留下"有轨迹无诊断"的记录。
    func testReviewFailureRollsBackTheRunTraceInTheSameTransaction() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: ReviewExecutor())
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE writing_reviews", nil, nil, nil), SQLITE_OK)

        do {
            _ = try await workflow.runWritingReview(
                makeRequest(database: database, reviewedSnapshot: "正文")
            )
            XCTFail("诊断表缺失时必须抛错")
        } catch {
            // 预期负向路径。
        }

        XCTAssertTrue(
            try database.listAgentRuns(limit: 10).isEmpty,
            "诊断写入失败时 AgentRun 必须随事务回滚"
        )
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

/// 智能下一步纵切片（24.16）。此前这条切片完全没有测试。
@MainActor
final class WritingWorkflowAdvisorTests: XCTestCase {
    func testAdvisorRunAndTraceCommitTogether() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: AdvisorExecutor())

        let outcome = try await workflow.runWritingAdvisor(makeRequest(database: database))

        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertEqual(try database.listWritingAdvisorRuns().map(\.id), [outcome.advisorRun.id])
        XCTAssertEqual(outcome.advisorRun.next_action, "补第二段的来源")
        XCTAssertFalse(outcome.usedFallback)
    }

    /// 判断结果落库失败时，运行轨迹必须随同一事务回滚。
    func testAdvisorFailureRollsBackTheRunTraceInTheSameTransaction() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: AdvisorExecutor())
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE writing_advisor_runs", nil, nil, nil), SQLITE_OK)

        do {
            _ = try await workflow.runWritingAdvisor(makeRequest(database: database))
            XCTFail("顾问表缺失时必须抛错")
        } catch {
            // 预期负向路径。
        }

        XCTAssertTrue(
            try database.listAgentRuns(limit: 10).isEmpty,
            "判断结果写入失败时 AgentRun 必须随事务回滚"
        )
    }

    /// 模型没给下一步时退回最大问题，运行记录不留空。
    func testRunSummaryFallsBackToMainProblem() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: AdvisorExecutor(nextAction: nil, mainProblem: "证据太薄")
        )

        let outcome = try await workflow.runWritingAdvisor(makeRequest(database: database))

        XCTAssertEqual(outcome.agentRun.summary, "证据太薄")
    }

    func testMissingExecutorWritesNothing() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.runWritingAdvisor(makeRequest(database: database))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
        XCTAssertTrue(try database.listWritingAdvisorRuns().isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "advisor-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.AnalysisRequest {
        let style = try database.defaultStyle()
        return .init(
            articleID: nil,
            titleSnapshot: "测试稿",
            context: ContextPackage(
                stage: "判断",
                title: "测试稿",
                summary: "",
                idea: "一个想法",
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

private final class AdvisorExecutor: AIWorkflowExecuting {
    private let nextAction: String?
    private let mainProblem: String?

    init(nextAction: String? = "补第二段的来源", mainProblem: String? = "证据不足") {
        self.nextAction = nextAction
        self.mainProblem = mainProblem
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = WritingAdvisorResult(
            stage: "修订",
            main_problem: mainProblem,
            next_action: nextAction,
            reason: "全文唯一的量化证据没有出处",
            suggested_actions: ["定点改写"],
            focus_area: "证据"
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 3, success: true, error: "",
                inputSummary: "判断输入", outputSummary: "判断输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}

/// 生成大纲纵切片（24.17），以及从两处私有扩展收拢的大纲渲染。
@MainActor
final class WritingWorkflowOutlineTests: XCTestCase {
    func testOutlineRecordsRunAndReturnsResult() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: OutlineExecutor())

        let outcome = try await workflow.generateOutline(
            makeRequest(database: database),
            validateBeforeCommit: {}
        )

        XCTAssertEqual(outcome.result.title, "大纲标题")
        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertEqual(outcome.agentRun.summary, "大纲标题")
    }

    /// 生成期间作者动过稿件：整次作废，不留下没人用得上的运行轨迹。
    func testStaleSessionFailsBeforeWritingAnyRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: OutlineExecutor())

        do {
            _ = try await workflow.generateOutline(
                makeRequest(database: database),
                validateBeforeCommit: { throw OutlineTestFailure.staleSession }
            )
            XCTFail("会话过期必须在落库前失败")
        } catch OutlineTestFailure.staleSession {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    /// 大纲成稿共用同一个请求结构，但产出的是正文候选，且不做交付。
    func testDraftFromOutlineRecordsRunWithoutDelivering() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: OutlineExecutor())

        let outcome = try await workflow.draftFromOutline(makeRequest(database: database))

        XCTAssertEqual(outcome.result.content, "大纲成稿的正文")
        XCTAssertEqual(outcome.agentRun.run_type, "大纲成稿")
        XCTAssertEqual(try database.listAgentRuns(limit: 10).map(\.id), [outcome.agentRun.id])
        XCTAssertTrue(
            try database.listDraftVersions(limit: 10).isEmpty,
            "交付归调用方，本切片不落待复核版本"
        )
    }

    /// 模型没给摘要时退回固定说明，运行记录不留空。
    func testDraftRunSummaryFallsBackWhenModelGivesNone() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: OutlineExecutor(draftSummary: nil)
        )

        let outcome = try await workflow.draftFromOutline(makeRequest(database: database))

        XCTAssertEqual(outcome.agentRun.summary, "根据当前大纲生成正文。")
    }

    func testMissingExecutorWritesNoRun() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.generateOutline(
                makeRequest(database: database),
                validateBeforeCommit: {}
            )
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    /// 渲染规则此前在 WorkshopStore 与 WritingAgentCoordinator 各有一份逐字相同的副本。
    func testMarkdownAssemblesStructuredOutline() {
        let result = OutlineResult(
            title: "为什么把 L2 留在实验室",
            opening: "先讲那次运行。",
            sections: [
                OutlineSection(
                    heading: "证据不足",
                    points: ["分数区间", "样本量"],
                    material_hint: "评测报告"
                )
            ],
            ending: "收在判断标准上。",
            raw_output: nil
        )

        XCTAssertEqual(
            result.markdown,
            """
            # 为什么把 L2 留在实验室

            ## 开头
            先讲那次运行。

            ## 证据不足
            - 分数区间
            - 样本量
            素材位置：评测报告

            ## 结尾
            收在判断标准上。
            """
        )
    }

    /// 模型给了原始输出就直接用，不再按结构拼装。
    func testMarkdownPrefersRawOutputWhenPresent() {
        let result = OutlineResult(
            title: "会被忽略的标题",
            opening: nil,
            sections: nil,
            ending: nil,
            raw_output: "模型直接给的大纲原文"
        )

        XCTAssertEqual(result.markdown, "模型直接给的大纲原文")
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "outline-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeRequest(database: NativeDatabase) throws -> WritingWorkflow.TopicDraftingRequest {
        let style = try database.defaultStyle()
        return .init(
            analysis: .init(
                articleID: nil,
                titleSnapshot: "测试稿",
                context: ContextPackage(
                    stage: "大纲",
                    title: "测试稿",
                    summary: "",
                    idea: "一个想法",
                    direction: "随笔",
                    outline_excerpt: "",
                    content_excerpt: "",
                    materials_excerpt: "",
                    selected_topic_title: nil,
                    selected_topic_summary: nil,
                    style_name: style.name,
                    style_brief: "",
                    word_count: 0,
                    paragraph_count: 0,
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
            topic: TopicPayload(
                title: "测试选题",
                direction: "随笔",
                core_viewpoint: nil,
                target_reader: nil,
                description: nil,
                angle: nil,
                emotion: nil,
                score: 3,
                status: "待写",
                tags: ["随笔"]
            )
        )
    }
}

private enum OutlineTestFailure: Error {
    case staleSession
}

private final class OutlineExecutor: AIWorkflowExecuting {
    private let draftSummary: String?

    init(draftSummary: String? = "已成稿") {
        self.draftSummary = draftSummary
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = DraftResult(
            title: "成稿标题",
            content: "大纲成稿的正文",
            summary: draftSummary,
            tags: nil,
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 4, success: true, error: "",
                inputSummary: "成稿输入", outputSummary: "成稿输出"
            )
        }
        if let result = OutlineResult(
            title: "大纲标题",
            opening: "开头",
            sections: nil,
            ending: nil,
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 3, success: true, error: "",
                inputSummary: "大纲输入", outputSummary: "大纲输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}

/// 生成选题纵切片（24.18）。这条路径与其他切片相反：先写业务事实、后写轨迹，
/// 迁出前是三次独立写入，所以事务是它的核心约束。
@MainActor
final class WritingWorkflowTopicsTests: XCTestCase {
    func testTopicsAreCreatedAndDuplicatesReportedWithoutBeingStored() async throws {
        let database = try makeDatabase()
        let existing = try database.createTopics([payload(title: "已有选题")])
        let workflow = WritingWorkflow(
            database: database,
            executor: TopicsExecutor(titles: ["已有选题", "全新选题"])
        )

        let outcome = try await workflow.generateTopics(
            makeRequest(database: database, existingTopics: existing)
        )

        XCTAssertEqual(outcome.created.map(\.title), ["全新选题"])
        XCTAssertEqual(outcome.duplicates.map(\.title), ["已有选题"])
        XCTAssertEqual(try database.listTopics().count, 2, "重复候选不得入库")
        XCTAssertEqual(outcome.agentRun.summary, "生成 1 个选题，过滤 1 个重复选题。")
    }

    /// 轨迹写入失败时，选题必须随同一事务回滚——不能留下没有轨迹的选题。
    func testRunTraceFailureRollsBackTheCreatedTopics() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: TopicsExecutor(titles: ["新选题"])
        )
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE agent_runs", nil, nil, nil), SQLITE_OK)

        do {
            _ = try await workflow.generateTopics(makeRequest(database: database, existingTopics: []))
            XCTFail("轨迹表缺失时必须抛错")
        } catch {
            // 预期负向路径。
        }

        XCTAssertTrue(
            try database.listTopics().isEmpty,
            "运行轨迹写入失败时，已创建的选题必须随事务回滚"
        )
    }

    /// 素材入口：标记已用与选题、轨迹在同一事务里，不能出现"标记已用却没生成选题"。
    func testIdeaIsMarkedUsedInsideTheSameTransaction() async throws {
        let database = try makeDatabase()
        let idea = try database.saveIdea(
            id: nil,
            payload: IdeaSaveRequest(
                title: "一条素材",
                content: "素材正文",
                type: "灵感",
                tags: [],
                used: 0,
                related_article_id: nil
            )
        )
        let workflow = WritingWorkflow(
            database: database,
            executor: TopicsExecutor(titles: ["由素材生成"])
        )

        _ = try await workflow.generateTopics(
            makeRequest(
                database: database,
                existingTopics: [],
                actionTitle: "从素材生成选题",
                markIdeaUsedID: idea.id
            )
        )

        XCTAssertEqual(try database.listIdeas().first(where: { $0.id == idea.id })?.used, 1)
    }

    /// 素材入口的运行记录：动作名是「从素材生成选题」，但步骤名仍是「生成选题」。
    func testIdeaEntryKeepsItsOwnActionTitleButSharedStepName() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(
            database: database,
            executor: TopicsExecutor(titles: ["由素材生成"])
        )

        let outcome = try await workflow.generateTopics(
            makeRequest(
                database: database,
                existingTopics: [],
                actionTitle: "从素材生成选题"
            )
        )

        XCTAssertEqual(outcome.agentRun.run_type, "从素材生成选题")
        XCTAssertEqual(outcome.agentRun.steps.first?.name, "生成选题")
    }

    func testMissingExecutorWritesNothing() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.generateTopics(makeRequest(database: database, existingTopics: []))
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listTopics().isEmpty)
        XCTAssertTrue(try database.listAgentRuns(limit: 10).isEmpty)
    }

    /// 兜底产物不入库：真实库里 123 条选题有 18 条是 `NativeFallbacks` 的三句模板
    /// （「{想法}，为什么值得认真写一次」等）套用当前想法生成的，与真选题混在一起、
    /// 没有任何标记。选题列表一旦不可信，管线的第一站就断了。
    func testFallbackTopicsAreNotStored() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: FailingTopicsExecutor())

        let outcome = try await workflow.generateTopics(
            makeRequest(database: database, existingTopics: [])
        )

        XCTAssertTrue(outcome.created.isEmpty, "调用失败时不得写入任何选题")
        XCTAssertTrue(outcome.usedFallback)
        XCTAssertTrue(try database.listTopics().isEmpty, "兜底模板绝不能落库")
        // 失败的调用本身仍是证据，轨迹要留下——否则作者查不到"那次为什么没出选题"。
        let runs = try database.listAgentRuns(limit: 10)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.summary, "模型调用失败，未写入任何选题。")
    }

    /// 兜底时素材不该被标记已用——它并没有被真的用掉。
    func testFallbackDoesNotConsumeTheSourceIdea() async throws {
        let database = try makeDatabase()
        let idea = try database.saveIdea(
            id: nil,
            payload: IdeaSaveRequest(
                title: "一条素材",
                content: "素材正文",
                type: "灵感",
                tags: [],
                used: 0,
                related_article_id: nil
            )
        )
        let workflow = WritingWorkflow(database: database, executor: FailingTopicsExecutor())

        _ = try await workflow.generateTopics(
            makeRequest(
                database: database,
                existingTopics: [],
                actionTitle: "从素材生成选题",
                markIdeaUsedID: idea.id
            )
        )

        XCTAssertEqual(
            try database.listIdeas().first(where: { $0.id == idea.id })?.used,
            0,
            "没生成出选题就把素材标记已用，等于凭空吃掉一条素材"
        )
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "topics-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func payload(title: String) -> TopicPayload {
        TopicPayload(
            title: title,
            direction: "随笔",
            core_viewpoint: nil,
            target_reader: nil,
            description: nil,
            angle: nil,
            emotion: nil,
            score: 3,
            status: "待写",
            tags: ["随笔"]
        )
    }

    private func makeRequest(
        database: NativeDatabase,
        existingTopics: [Topic],
        actionTitle: String = "生成选题",
        markIdeaUsedID: Int? = nil
    ) throws -> WritingWorkflow.TopicsRequest {
        let style = try database.defaultStyle()
        return .init(
            analysis: .init(
                articleID: nil,
                titleSnapshot: "测试稿",
                context: ContextPackage(
                    stage: "选题",
                    title: "",
                    summary: "",
                    idea: "一个想法",
                    direction: "随笔",
                    outline_excerpt: "",
                    content_excerpt: "",
                    materials_excerpt: "",
                    selected_topic_title: nil,
                    selected_topic_summary: nil,
                    style_name: style.name,
                    style_brief: "",
                    word_count: 0,
                    paragraph_count: 0,
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
            actionTitle: actionTitle,
            existingTopics: existingTopics,
            markIdeaUsedID: markIdeaUsedID
        )
    }
}

private final class TopicsExecutor: AIWorkflowExecuting {
    private let titles: [String]

    init(titles: [String]) {
        self.titles = titles
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        let payloads = titles.map { title in
            TopicPayload(
                title: title,
                direction: "随笔",
                core_viewpoint: nil,
                target_reader: nil,
                description: nil,
                angle: nil,
                emotion: nil,
                score: 3,
                status: "待写",
                tags: ["随笔"]
            )
        }
        if let result = GeneratedTopicsDocument(topics: payloads) as? Output {
            return AIRun(
                result: result, elapsedMS: 3, success: true, error: "",
                inputSummary: "选题输入", outputSummary: "选题输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}

/// 模拟"无 API Key / 调用失败"：交出描述符声明的 fallback，且 success = false。
/// 这正是真实库里那 18 条模板选题的来路。
private final class FailingTopicsExecutor: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "missing API key", inputSummary: "选题输入", outputSummary: ""
        )
    }
}

/// 自检与补偿回收（24.19）：此前 `polishDraft` 与 `finalizeGeneratedDraft` 各抄了一遍
/// stage/catch/cleanup，且自检位置一处在工作流内、一处在 Store，是两份会各自漂移的协议。
@MainActor
final class WritingWorkflowCommitPendingTests: XCTestCase {
    /// 投影失败时，已落库的 pending 版本必须被回收——否则库里留下界面看不见、
    /// 也无法确认或放弃的孤儿版本。
    func testFailedStageCleansUpTheDeliveredPendingVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: SelfCheckExecutor())
        let delivered = try await workflow.selfCheckAndDeliver(
            selfCheck: makeSelfCheck(database: database),
            delivery: makeDelivery()
        )
        XCTAssertEqual(try database.listDraftVersions(limit: 10).count, 1)

        do {
            try workflow.commitPending(version: delivered.version, pending: delivered.pending) { _ in
                throw CommitTestFailure.staleRevision
            }
            XCTFail("投影失败必须抛出")
        } catch CommitTestFailure.staleRevision {
            // 预期负向路径：原始投影错误优先抛出。
        }

        XCTAssertTrue(
            try database.listDraftVersions(limit: 10).isEmpty,
            "投影失败后 pending 版本必须已被回收"
        )
    }

    /// 投影成功时不得回收。
    func testSuccessfulStageKeepsThePendingVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: SelfCheckExecutor())
        let delivered = try await workflow.selfCheckAndDeliver(
            selfCheck: makeSelfCheck(database: database),
            delivery: makeDelivery()
        )

        var staged: PendingDraftReview?
        try workflow.commitPending(version: delivered.version, pending: delivered.pending) { pending in
            staged = pending
        }

        XCTAssertEqual(staged?.draftVersionID, delivered.version.id)
        XCTAssertEqual(try database.listDraftVersions(limit: 10).count, 1)
    }

    /// 回收成功时抛出的必须仍是原始投影错误——那才是作者要处理的那个。
    func testSuccessfulCleanupStillThrowsTheOriginalProjectionError() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: SelfCheckExecutor())
        let delivered = try await workflow.selfCheckAndDeliver(
            selfCheck: makeSelfCheck(database: database),
            delivery: makeDelivery()
        )

        do {
            try workflow.commitPending(version: delivered.version, pending: delivered.pending) { _ in
                throw CommitTestFailure.staleRevision
            }
            XCTFail("投影失败必须抛出")
        } catch CommitTestFailure.staleRevision {
            // 预期：回收成功，原始错误原样抛出。
        } catch {
            XCTFail("回收成功时不应改写错误类型，实际抛出：\(error)")
        }
    }

    /// 回收本身也失败时，必须报出遗留的版本号——否则库里那条孤儿记录对作者不可见。
    func testFailedCleanupSurfacesBothTheProjectionErrorAndTheOrphanedVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: SelfCheckExecutor())
        let delivered = try await workflow.selfCheckAndDeliver(
            selfCheck: makeSelfCheck(database: database),
            delivery: makeDelivery()
        )

        // 让回收无从下手：删掉它要操作的表。
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.databaseURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, "DROP TABLE draft_versions", nil, nil, nil), SQLITE_OK)

        do {
            try workflow.commitPending(version: delivered.version, pending: delivered.pending) { _ in
                throw CommitTestFailure.staleRevision
            }
            XCTFail("投影与回收都失败时必须抛出")
        } catch let WritingWorkflow.WorkflowError.pendingCleanupFailed(versionID, projection, _) {
            XCTAssertEqual(versionID, delivered.version.id, "必须指名遗留的是哪个版本")
            XCTAssertTrue(
                projection is CommitTestFailure,
                "原始投影错误必须被保留，而不是被回收失败盖掉"
            )
            let message = try XCTUnwrap(
                (WritingWorkflow.WorkflowError.pendingCleanupFailed(
                    versionID: versionID,
                    projection: projection,
                    cleanup: CommitTestFailure.staleRevision
                ) as LocalizedError).errorDescription
            )
            XCTAssertTrue(message.contains("#\(delivered.version.id)"), "错误文案要带上版本号：\(message)")
        }
    }

    /// 自检结果必须随 pending 一起落库；分两步写会出现有 pending 无自检的记录。
    func testSelfCheckResultIsPersistedWithThePendingVersion() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database, executor: SelfCheckExecutor())

        let delivered = try await workflow.selfCheckAndDeliver(
            selfCheck: makeSelfCheck(database: database),
            delivery: makeDelivery()
        )

        XCTAssertEqual(delivered.selfCheck?.flagged_excerpts?.first?.excerpt, "存疑的一句")
        XCTAssertEqual(
            delivered.pending.selfCheck?.flagged_excerpts?.first?.excerpt,
            "存疑的一句",
            "自检结果必须随 pending 一起交付"
        )
    }

    func testMissingExecutorDeliversNothing() async throws {
        let database = try makeDatabase()
        let workflow = WritingWorkflow(database: database)

        do {
            _ = try await workflow.selfCheckAndDeliver(
                selfCheck: makeSelfCheck(database: database),
                delivery: makeDelivery()
            )
            XCTFail("未配置 executor 必须抛错")
        } catch WritingWorkflow.WorkflowError.missingExecutor {
            // 预期负向路径。
        }

        XCTAssertTrue(try database.listDraftVersions(limit: 10).isEmpty)
    }

    private func makeDatabase() throws -> NativeDatabase {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "commit-\(UUID().uuidString).sqlite3")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try NativeDatabase(databaseURL: url)
    }

    private func makeSelfCheck(database: NativeDatabase) throws -> WritingWorkflow.SelfCheckRequest {
        let style = try database.defaultStyle()
        return .init(
            context: ContextPackage(
                stage: "自检",
                title: "改后标题",
                summary: "",
                idea: "",
                direction: "随笔",
                outline_excerpt: "",
                content_excerpt: "改后正文",
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
        )
    }

    private func makeDelivery() -> WritingWorkflow.PendingDelivery {
        .init(
            articleID: nil,
            titleSnapshot: "测试稿",
            actionTitle: "大纲成稿",
            note: "已成稿",
            before: DraftSnapshot(title: "原标题", summary: "", content: "原正文"),
            after: DraftSnapshot(title: "改后标题", summary: "", content: "改后正文"),
            usedFallback: false
        )
    }
}

private enum CommitTestFailure: Error {
    case staleRevision
}

private final class SelfCheckExecutor: AIWorkflowExecuting {
    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        if let result = DraftSelfCheckResult(
            has_concerns: true,
            flagged_excerpts: [FlaggedExcerpt(excerpt: "存疑的一句", concern: "缺少来源")],
            raw_output: nil
        ) as? Output {
            return AIRun(
                result: result, elapsedMS: 2, success: true, error: "",
                inputSummary: "自检输入", outputSummary: "自检输出"
            )
        }
        return AIRun(
            result: descriptor.fallback(), elapsedMS: 1, success: false,
            error: "unexpected workflow", inputSummary: "", outputSummary: ""
        )
    }
}
