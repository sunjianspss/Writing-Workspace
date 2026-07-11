import XCTest
@testable import CreativeWorkshopCore

/// R5 瘦身·任务 21：待复核状态机的机器级测试（迁移前这些语义只能靠 Store 级测试间接覆盖）。
final class PendingReviewMachineTests: XCTestCase {
    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

    private func deliverSample(_ machine: PendingReviewMachine) throws -> (DraftVersion, PendingDraftReview) {
        try machine.deliver(
            articleID: nil,
            titleSnapshot: "测试标题",
            actionTitle: "测试生成",
            note: "备注",
            before: DraftSnapshot(title: "旧标题", summary: "旧摘要", content: "旧正文"),
            after: DraftSnapshot(title: "新标题", summary: "新摘要", content: "新正文"),
            usedFallback: false,
            selfCheck: nil,
            matchedPitfalls: [],
            agentTrace: nil,
            retrievedFragments: [],
            sectionFragmentContexts: [],
            iterationSummary: nil,
            candidateJudgement: nil
        )
    }

    func testDeliverThenConfirmFlipsRowToConfirmed() throws {
        let database = try makeDatabase()
        let machine = PendingReviewMachine(database: database)

        let (version, pending) = try deliverSample(machine)
        XCTAssertEqual(version.review_status, "pending", "交付时版本行必须是 pending")
        XCTAssertEqual(pending.draftVersionID, version.id)
        XCTAssertEqual(pending.before.content, "旧正文")

        let confirmed = try machine.confirm(versionID: version.id)
        XCTAssertEqual(confirmed.review_status, "confirmed")
        XCTAssertEqual(try database.draftVersion(id: version.id)?.review_status, "confirmed")
    }

    func testDeliverThenDiscardRemovesRowAndKeepsRestoreSnapshot() throws {
        let database = try makeDatabase()
        let machine = PendingReviewMachine(database: database)

        let (version, pending) = try deliverSample(machine)
        try machine.discard(versionID: version.id)

        XCTAssertNil(try database.draftVersion(id: version.id), "放弃后该行应被删除")
        XCTAssertEqual(pending.before.title, "旧标题", "恢复用快照由待复核卡携带，供调用方回退正文")
    }

    func testCleanupOrphanDeletesPendingButNeverConfirmed() throws {
        let database = try makeDatabase()
        let machine = PendingReviewMachine(database: database)

        // pending 孤儿：应被清理
        let (orphan, _) = try deliverSample(machine)
        try machine.cleanupOrphan(versionID: orphan.id)
        XCTAssertNil(try database.draftVersion(id: orphan.id))

        // confirmed 行：隐式清理绝不可误删
        let (kept, _) = try deliverSample(machine)
        _ = try machine.confirm(versionID: kept.id)
        try machine.cleanupOrphan(versionID: kept.id)
        XCTAssertEqual(try database.draftVersion(id: kept.id)?.review_status, "confirmed", "confirmed 行必须保留")
    }
}
