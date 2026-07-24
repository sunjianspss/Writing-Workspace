import XCTest
import SQLite3
@testable import CreativeWorkshopEval

final class EvalResultsStoreAndReportTests: XCTestCase {
    private func makeTempDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-results-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("eval_results.sqlite3")
    }

    private func makeOutcome(
        pipeline: String,
        caseID: String,
        overallScore: Int?,
        callCount: Int = 3,
        fallbackCount: Int = 0,
        verificationSummary: String = "验证通过：3 项检查全部通过。",
        searchCount: Int = 0
    ) -> PipelineOutcome {
        PipelineOutcome(
            pipeline: pipeline,
            caseID: caseID,
            title: "标题",
            content: "正文内容",
            overallScore: overallScore,
            highIssueCount: 1,
            mediumIssueCount: 2,
            lowIssueCount: 0,
            wordCount: 4,
            callCount: callCount,
            fallbackCount: fallbackCount,
            elapsedMS: 120,
            success: true,
            error: "",
            verificationSummary: verificationSummary,
            searchCount: searchCount
        )
    }

    func testInsertAndReadBackRawJSON() throws {
        let store = try EvalResultsStore(databaseURL: try makeTempDatabaseURL())
        let outcome = makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 70)

        try store.insert(runID: "run-1", runTimestamp: "2026-07-05T10:00:00Z", gitDescribe: "abc123", outcome: outcome, rawJSON: "{}")

        // previousRunScores 只应该看到严格早于给定时间戳的 run。
        let scoresBeforeSameRun = try store.previousRunScores(before: "2026-07-05T10:00:00Z")
        XCTAssertTrue(scoresBeforeSameRun.isEmpty)

        let scoresAfter = try store.previousRunScores(before: "2026-07-05T11:00:00Z")
        XCTAssertEqual(scoresAfter["case-01|direct"], 70)
    }

    /// 兼容旧数据（PRD 23.4 验收标准 4）：老版本写入的 eval_results.sqlite3 没有 fallback_count
    /// 列，CREATE TABLE IF NOT EXISTS 不会给已存在的表补列，必须靠单独迁移把列加回来。
    func testOpeningLegacyDatabaseWithoutFallbackCountColumnMigratesAndStaysUsable() throws {
        let databaseURL = try makeTempDatabaseURL()
        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE eval_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            run_timestamp TEXT NOT NULL,
            git_describe TEXT NOT NULL,
            case_id TEXT NOT NULL,
            pipeline TEXT NOT NULL,
            overall_score INTEGER,
            high_issue_count INTEGER NOT NULL,
            medium_issue_count INTEGER NOT NULL,
            low_issue_count INTEGER NOT NULL,
            word_count INTEGER NOT NULL,
            call_count INTEGER NOT NULL,
            elapsed_ms INTEGER NOT NULL,
            success INTEGER NOT NULL,
            error TEXT NOT NULL,
            raw_json TEXT NOT NULL
        )
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let store = try EvalResultsStore(databaseURL: databaseURL)
        let outcome = makeOutcome(pipeline: "direct", caseID: "case-legacy", overallScore: 60, fallbackCount: 2)
        try store.insert(runID: "run-legacy", runTimestamp: "2026-07-05T09:00:00Z", gitDescribe: "abc123", outcome: outcome, rawJSON: "{}")

        let scores = try store.previousRunScores(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy|direct"], 60)
    }

    /// 兼容旧数据（PRD 23.7）：老版本写入的 eval_results.sqlite3 既没有 fallback_count 也没有
    /// verification_summary 列，两次迁移必须都补上且互不干扰。
    func testOpeningLegacyDatabaseWithoutVerificationSummaryColumnMigratesAndStaysUsable() throws {
        let databaseURL = try makeTempDatabaseURL()
        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE eval_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            run_timestamp TEXT NOT NULL,
            git_describe TEXT NOT NULL,
            case_id TEXT NOT NULL,
            pipeline TEXT NOT NULL,
            overall_score INTEGER,
            high_issue_count INTEGER NOT NULL,
            medium_issue_count INTEGER NOT NULL,
            low_issue_count INTEGER NOT NULL,
            word_count INTEGER NOT NULL,
            call_count INTEGER NOT NULL,
            fallback_count INTEGER NOT NULL DEFAULT 0,
            elapsed_ms INTEGER NOT NULL,
            success INTEGER NOT NULL,
            error TEXT NOT NULL,
            raw_json TEXT NOT NULL
        )
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let store = try EvalResultsStore(databaseURL: databaseURL)
        let outcome = makeOutcome(pipeline: "direct", caseID: "case-legacy-2", overallScore: 60)
        try store.insert(runID: "run-legacy-2", runTimestamp: "2026-07-05T09:00:00Z", gitDescribe: "abc123", outcome: outcome, rawJSON: "{}")

        let scores = try store.previousRunScores(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy-2|direct"], 60)
    }

    /// 兼容旧数据（PRD 23.8.1）：老版本写入的 eval_results.sqlite3 没有 search_count 列。
    func testOpeningLegacyDatabaseWithoutSearchCountColumnMigratesAndStaysUsable() throws {
        let databaseURL = try makeTempDatabaseURL()
        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE eval_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            run_timestamp TEXT NOT NULL,
            git_describe TEXT NOT NULL,
            case_id TEXT NOT NULL,
            pipeline TEXT NOT NULL,
            overall_score INTEGER,
            high_issue_count INTEGER NOT NULL,
            medium_issue_count INTEGER NOT NULL,
            low_issue_count INTEGER NOT NULL,
            word_count INTEGER NOT NULL,
            call_count INTEGER NOT NULL,
            fallback_count INTEGER NOT NULL DEFAULT 0,
            elapsed_ms INTEGER NOT NULL,
            success INTEGER NOT NULL,
            error TEXT NOT NULL,
            raw_json TEXT NOT NULL,
            verification_summary TEXT NOT NULL DEFAULT ''
        )
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let store = try EvalResultsStore(databaseURL: databaseURL)
        let outcome = makeOutcome(pipeline: "agentic", caseID: "case-legacy-3", overallScore: 60, searchCount: 2)
        try store.insert(runID: "run-legacy-3", runTimestamp: "2026-07-05T09:00:00Z", gitDescribe: "abc123", outcome: outcome, rawJSON: "{}")

        let scores = try store.previousRunScores(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy-3|agentic"], 60)
    }

    func testReportIncludesEachCaseAndPipelineWithScoreDiff() throws {
        let outcomes = [
            makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 75, verificationSummary: "验证：3 项中有 1 项待复核。"),
            makeOutcome(pipeline: "agent", caseID: "case-01", overallScore: 80),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 85)
        ]
        let previousScores = ["case-01|direct": 70, "case-01|agent": 82]

        let report = ReportGenerator.generate(
            runID: "run-2",
            runTimestamp: "2026-07-05T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: outcomes,
            previousScores: previousScores
        )

        XCTAssertTrue(report.contains("case-01"))
        XCTAssertTrue(report.contains("direct"))
        XCTAssertTrue(report.contains("agent"))
        XCTAssertTrue(report.contains("deep"))
        // direct: 75 - 70 = +5；agent: 80 - 82 = -2；deep 没有上一次分数，应显示为 "-"。
        XCTAssertTrue(report.contains("+5"))
        XCTAssertTrue(report.contains("-2"))
        XCTAssertTrue(report.contains("验证：3 项中有 1 项待复核。"))
        XCTAssertTrue(report.contains("检索次数"), "报告表头应包含检索次数列（PRD 23.8.1）")
        XCTAssertTrue(report.contains("风格样本：无（零样本配置）"), "未注入样本时报告应写明是零样本配置（24.4）")
    }

    /// 注入了哪几篇风格样本必须写进报告：样本换了分数就不可比，而「样本是否同时是某条用例
    /// 的来源」无法可靠自动判定，只能靠报告里的可见性让人复核（24.4）。
    func testReportRecordsInjectedStyleSampleNames() {
        let report = ReportGenerator.generate(
            runID: "run-3",
            runTimestamp: "2026-07-25T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: [],
            previousScores: [:],
            styleSampleNames: ["01-时间扑面而来", "02-清白的人"]
        )

        XCTAssertTrue(report.contains("风格样本：01-时间扑面而来、02-清白的人"))
    }
}
