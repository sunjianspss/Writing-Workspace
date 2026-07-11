import XCTest
@testable import CreativeWorkshopCore

/// R5 瘦身·任务 20：多候选优选协调器的独立测试（迁移前这段编排在 Store 里，0 测试）。
private final class ScriptedCandidateExecutor: AIWorkflowExecuting {
    var judgeIndex: Int?
    /// 第 n 次 polish 调用返回失败（模拟某候选生成失败）。
    var failPolishAt: Int?
    private(set) var polishCount = 0
    private(set) var kindSequence: [AIWorkflowKind] = []

    init(judgeIndex: Int?) {
        self.judgeIndex = judgeIndex
    }

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        kindSequence.append(descriptor.kind)
        if descriptor.kind == .polishDraft {
            polishCount += 1
            if failPolishAt == polishCount {
                return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: false, error: "boom", inputSummary: "p\(polishCount)", outputSummary: "fb")
            }
            let draft = DraftResult(
                title: "候选\(polishCount)标题",
                content: "候选\(polishCount)的完整正文。",
                summary: "候选\(polishCount)摘要",
                tags: nil,
                raw_output: nil
            )
            if let output = draft as? Output {
                return AIRun(result: output, elapsedMS: 1, success: true, error: "", inputSummary: "p\(polishCount)", outputSummary: "ok")
            }
        }
        if descriptor.kind == .candidateJudge {
            let judgement = CandidateJudgeResult(
                best_candidate_index: judgeIndex,
                rankings: [],
                summary: judgeIndex.map { "选候选\($0)" },
                raw_output: nil
            )
            if let output = judgement as? Output {
                return AIRun(result: output, elapsedMS: 1, success: true, error: "", inputSummary: "judge", outputSummary: "ok")
            }
        }
        return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "fake", outputSummary: "fake")
    }
}

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class CandidateSelectionCoordinatorTests: XCTestCase {
    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

    private func makeInput(rngSeed: UInt64 = 7) throws -> (CandidateSelectionInput, NativeDatabase) {
        let database = try makeDatabase()
        let style = try database.defaultStyle()
        let base = DraftSnapshot(title: "原标题", summary: "原摘要", content: "原始正文，长度足够参与候选润色。")
        var context = ContextPackage(
            stage: "测试",
            title: base.title,
            summary: base.summary,
            idea: "一个想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: base.content,
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: style.name,
            style_brief: "",
            word_count: base.content.count,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: [],
            genre: style.genre,
            known_pitfalls: []
        )
        var judgeContext = context
        judgeContext.applyDraftSnapshot(base)
        _ = judgeContext
        let input = CandidateSelectionInput(
            base: base,
            context: context,
            judgeContext: judgeContext,
            style: style,
            outline: "",
            idea: "一个想法",
            direction: "情感文学",
            previousReview: nil,
            polishTemplate: nil,
            judgeTemplate: nil,
            writingReviewTemplate: nil,
            config: ModelConfig(),
            apiKey: "fake-key",
            shuffleRNG: AnyRandomNumberGenerator(SeededRNG(state: rngSeed))
        )
        context.title = base.title
        return (input, database)
    }

    private func makeCoordinator(
        executor: ScriptedCandidateExecutor,
        database: NativeDatabase,
        savedActions: NSMutableArray
    ) -> CandidateSelectionCoordinator {
        CandidateSelectionCoordinator(
            executor: executor,
            saveVersion: { action, note, after in
                savedActions.add("\(action)|\(note.prefix(6))")
                return try database.saveDraftVersion(
                    articleID: nil,
                    titleSnapshot: "测试",
                    action: action,
                    note: note,
                    before: DraftSnapshot(title: "原标题", summary: "原摘要", content: "原始正文"),
                    after: after
                )
            },
            retrieve: { _ in ("", []) }
        )
    }

    func testGeneratesThreeCandidatesInModeOrderAndJudgeSelectsByIndex() async throws {
        let executor = ScriptedCandidateExecutor(judgeIndex: 2)
        let (input, database) = try makeInput()
        let savedActions = NSMutableArray()
        let coordinator = makeCoordinator(executor: executor, database: database, savedActions: savedActions)

        let output = try await coordinator.run(input: input)

        // 三个候选按 natural/tighten/deepen 顺序生成，编号稳定
        XCTAssertEqual(output.candidates.map(\.label), [PolishMode.natural, .tighten, .deepen].map(\.title))
        XCTAssertEqual(output.candidates.map(\.index), [1, 2, 3])
        XCTAssertEqual(output.createdVersions.count, 3)
        XCTAssertEqual(savedActions.count, 3)
        // 评委按稳定编号选中候选 2（不受呈现顺序打乱影响）
        XCTAssertEqual(output.selectedCandidate.index, 2)
        XCTAssertEqual(output.selectedCandidate.title, "候选2标题")
        // 调用顺序：3 次润色 → 1 次评委 → 深度成稿（诊断开头）
        XCTAssertEqual(Array(executor.kindSequence.prefix(4)), [.polishDraft, .polishDraft, .polishDraft, .candidateJudge])
        XCTAssertTrue(executor.kindSequence.dropFirst(4).contains(.writingReview), "评委之后应进入深度成稿的诊断循环")
        // 评委步记录呈现顺序，且步骤已统一重编号
        let judgeStep = try XCTUnwrap(output.steps.first { $0.name == "候选评委排序" })
        XCTAssertTrue(judgeStep.input_summary.contains("呈现顺序："))
        XCTAssertEqual(output.steps.map(\.step_index), Array(1...output.steps.count))
    }

    func testFailedCandidateStillProducesVersionAndFlowContinues() async throws {
        let executor = ScriptedCandidateExecutor(judgeIndex: 1)
        executor.failPolishAt = 2
        let (input, database) = try makeInput()
        let savedActions = NSMutableArray()
        let coordinator = makeCoordinator(executor: executor, database: database, savedActions: savedActions)

        let output = try await coordinator.run(input: input)

        // 失败候选仍落版本（fallback 内容），流程不中断——与迁移前行为一致
        XCTAssertEqual(output.createdVersions.count, 3)
        let failedStep = try XCTUnwrap(output.steps.first { $0.name == "候选·\(PolishMode.tighten.title)" })
        XCTAssertEqual(failedStep.status, "fallback")
        XCTAssertTrue((savedActions[1] as! String).contains("本地候选"), "失败候选的版本备注应标明本地候选")
        XCTAssertEqual(output.selectedCandidate.index, 1)
        XCTAssertNotNil(output.deepOutput.draft.content)
    }

    func testJudgeWithoutIndexFallsBackToFirstCandidate() async throws {
        let executor = ScriptedCandidateExecutor(judgeIndex: nil)
        let (input, database) = try makeInput()
        let coordinator = makeCoordinator(executor: executor, database: database, savedActions: NSMutableArray())

        let output = try await coordinator.run(input: input)

        XCTAssertEqual(output.selectedCandidate.index, 1, "评委未给编号时应回退到候选 1")
    }
}
