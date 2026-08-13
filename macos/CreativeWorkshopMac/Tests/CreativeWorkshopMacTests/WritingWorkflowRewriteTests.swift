import XCTest
@testable import CreativeWorkshopCore

/// 局部改写纵切片（24.16）：模型调用与运行轨迹落库归 `WritingWorkflow`，
/// 正文是否替换仍由调用方决定。
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
