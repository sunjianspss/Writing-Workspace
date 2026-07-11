import XCTest
@testable import CreativeWorkshopCore

/// R5 瘦身·任务 22：记忆闭环服务级测试。核心铁律：归纳只产候选、绝不写库；
/// 写库只发生在确认之后，且幂等。
private final class ScriptedMemoryExecutor: AIWorkflowExecuting {
    var pitfallCandidates: [PitfallCandidate] = []
    private(set) var callCount = 0

    func execute<Output: Codable>(
        _ descriptor: WorkflowDescriptor<Output>,
        config: ModelConfig,
        apiKey: String
    ) async -> AIRun<Output> {
        callCount += 1
        if descriptor.kind == .pitfallSummary,
           let output = PitfallSummaryResult(candidates: pitfallCandidates, raw_output: nil) as? Output {
            return AIRun(result: output, elapsedMS: 1, success: true, error: "", inputSummary: "in", outputSummary: "out")
        }
        return AIRun(result: descriptor.fallback(), elapsedMS: 1, success: true, error: "", inputSummary: "in", outputSummary: "out")
    }
}

final class MemoryLoopServiceTests: XCTestCase {
    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

    func testSummarizePitfallsProducesFilteredCandidatesWithoutWritingDatabase() async throws {
        let database = try makeDatabase()
        var style = try database.defaultStyle()
        style.known_pitfalls = [AuthorPitfall(description: "已确认的老雷区", source_review_id: nil, created_at: nil)]
        style = try database.saveStyleProfile(id: style.id, profile: style)

        let executor = ScriptedMemoryExecutor()
        executor.pitfallCandidates = [
            PitfallCandidate(description: "已确认的老雷区", supporting_review_ids: [1]),
            PitfallCandidate(description: "新发现的雷区", supporting_review_ids: [2, 3])
        ]
        let service = MemoryLoopService(database: database, executor: executor)

        let outcome = await service.summarizePitfallCandidates(
            issues: [(reviewID: 1, dimension: "结构", problem: "结尾松散")],
            style: style,
            template: nil,
            config: ModelConfig(),
            apiKey: "fake"
        )

        XCTAssertEqual(outcome.candidates.map(\.description), ["新发现的雷区"], "与已确认项重复的候选应被过滤")
        let reloaded = try database.defaultStyle()
        XCTAssertEqual(reloaded.known_pitfalls?.count, 1, "归纳绝不写库：确认清单不得变化")
    }

    func testConfirmPitfallWritesOnceAndIsIdempotent() async throws {
        let database = try makeDatabase()
        let style = try database.defaultStyle()
        let service = MemoryLoopService(database: database, executor: ScriptedMemoryExecutor())
        let candidate = PitfallCandidate(description: "总用金句收尾", supporting_review_ids: [7])

        guard case let .added(saved) = try service.confirmPitfall(candidate, style: style) else {
            return XCTFail("首次确认应写入")
        }
        XCTAssertEqual(saved.known_pitfalls?.map(\.description), ["总用金句收尾"])
        XCTAssertEqual(saved.known_pitfalls?.first?.source_review_id, 7)

        guard case .alreadyConfirmed = try service.confirmPitfall(candidate, style: saved) else {
            return XCTFail("重复确认应幂等跳过")
        }
        XCTAssertEqual(try database.defaultStyle().known_pitfalls?.count, 1)
    }

    func testConfirmAndDeleteEditPreference() async throws {
        let database = try makeDatabase()
        let style = try database.defaultStyle()
        let service = MemoryLoopService(database: database, executor: ScriptedMemoryExecutor())
        let candidate = EditPreferenceCandidate(description: "少用总结式收束", source_edit_record_ids: [3])

        guard case let .added(saved) = try service.confirmEditPreference(candidate, style: style) else {
            return XCTFail("确认应写入 learned_preferences")
        }
        XCTAssertEqual(saved.learned_preferences?.map(\.description), ["少用总结式收束"])

        let preference = try XCTUnwrap(saved.learned_preferences?.first)
        let afterDelete = try service.deleteEditPreference(preference, style: saved)
        XCTAssertEqual(afterDelete.learned_preferences?.count, 0, "删除应生效")
        XCTAssertEqual(try database.defaultStyle().learned_preferences?.count, 0)
    }

    func testEditPreferenceSummaryGatesOnRecordCountWithoutModelCall() async throws {
        let database = try makeDatabase()
        let style = try database.defaultStyle()
        let executor = ScriptedMemoryExecutor()
        let service = MemoryLoopService(database: database, executor: executor)

        let outcome = try await service.summarizeEditPreferenceCandidates(
            style: style,
            template: nil,
            config: ModelConfig(),
            apiKey: "fake"
        )

        guard case let .insufficientRecords(count) = outcome else {
            return XCTFail("无编辑记录时应走不足分支")
        }
        XCTAssertEqual(count, 0)
        XCTAssertEqual(executor.callCount, 0, "记录不足时不得发起模型调用")
    }
}
