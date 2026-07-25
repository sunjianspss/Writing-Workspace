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
        searchCount: Int = 0,
        success: Bool = true,
        issueDimensions: [String] = []
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
            success: success,
            error: success ? "" : "The request timed out.",
            verificationSummary: verificationSummary,
            searchCount: searchCount,
            issueDimensions: issueDimensions
        )
    }

    private func rawJSON(for outcome: PipelineOutcome) throws -> String {
        String(data: try JSONEncoder().encode(outcome), encoding: .utf8) ?? "{}"
    }

    private func makePrevious(
        score: Int?,
        high: Int = 1,
        medium: Int = 2,
        low: Int = 0,
        dimensions: [String] = []
    ) -> PreviousSample {
        PreviousSample(
            overallScore: score,
            highIssueCount: high,
            mediumIssueCount: medium,
            lowIssueCount: low,
            issueDimensions: dimensions
        )
    }

    func testInsertAndReadBackRawJSON() throws {
        let store = try EvalResultsStore(databaseURL: try makeTempDatabaseURL())
        let outcome = makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 70)

        try store.insert(runID: "run-1", runTimestamp: "2026-07-05T10:00:00Z", gitDescribe: "abc123", outcome: outcome, rawJSON: "{}")

        // previousRunScores 只应该看到严格早于给定时间戳的 run。
        let scoresBeforeSameRun = try store.previousRunSamples(before: "2026-07-05T10:00:00Z")
        XCTAssertTrue(scoresBeforeSameRun.isEmpty)

        let scoresAfter = try store.previousRunSamples(before: "2026-07-05T11:00:00Z")
        XCTAssertEqual(scoresAfter["case-01|direct"]?.overallScore, 70)
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

        let scores = try store.previousRunSamples(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy|direct"]?.overallScore, 60)
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

        let scores = try store.previousRunSamples(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy-2|direct"]?.overallScore, 60)
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

        let scores = try store.previousRunSamples(before: "2026-07-05T10:00:00Z")
        XCTAssertEqual(scores["case-legacy-3|agentic"]?.overallScore, 60)
    }

    func testReportIncludesEachCaseAndPipelineWithScoreDiff() throws {
        let outcomes = [
            makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 75, verificationSummary: "验证：3 项中有 1 项待复核。"),
            makeOutcome(pipeline: "agent", caseID: "case-01", overallScore: 80),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 85)
        ]
        let previousSamples = ["case-01|direct": makePrevious(score: 70), "case-01|agent": makePrevious(score: 82)]

        let report = ReportGenerator.generate(
            runID: "run-2",
            runTimestamp: "2026-07-05T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: outcomes,
            previousSamples: previousSamples
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
            previousSamples: [:],
            styleSampleNames: ["01-时间扑面而来", "02-清白的人"]
        )

        XCTAssertTrue(report.contains("风格样本：01-时间扑面而来、02-清白的人"))
    }

    /// 24.9：失败样本的分数当过"上次总分"就会凭空造出一列差值——7-24 那轮报告 -18/-27/-28
    /// 三个差值全部来自此处（对照的是三格超时失败结果）。
    func testPreviousRunScoresSkipsFailedSamples() throws {
        let store = try EvalResultsStore(databaseURL: try makeTempDatabaseURL())
        let good = makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 85)
        let failed = makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 58, success: false)
        try store.insert(runID: "run-1", runTimestamp: "2026-07-24T10:00:00Z", gitDescribe: "abc", outcome: good, rawJSON: try rawJSON(for: good))
        try store.insert(runID: "run-1", runTimestamp: "2026-07-24T10:00:00Z", gitDescribe: "abc", outcome: failed, rawJSON: try rawJSON(for: failed))

        let scores = try store.previousRunSamples(before: "2026-07-25T10:00:00Z")

        XCTAssertEqual(scores["case-01|direct"]?.overallScore, 85)
        XCTAssertNil(scores["case-01|deep"], "失败样本不得成为下一轮的基准分")
    }

    /// 24.9-P1：问题维度要能落库、读回，跨轮才比得出"哪条新出现、哪条消失"。
    /// 三档计数一起读回——分数在档界会跳 10 分，清单才是 24.2 裁决要看的东西。
    func testPreviousRunSamplesCarriesIssueDimensionsAndCounts() throws {
        let store = try EvalResultsStore(databaseURL: try makeTempDatabaseURL())
        let outcome = makeOutcome(
            pipeline: "deep",
            caseID: "case-27",
            overallScore: 83,
            issueDimensions: ["人称视角(中)", "意象与细节(中)"]
        )
        try store.insert(runID: "run-1", runTimestamp: "2026-07-24T10:00:00Z", gitDescribe: "abc", outcome: outcome, rawJSON: try rawJSON(for: outcome))

        let sample = try XCTUnwrap(try store.previousRunSamples(before: "2026-07-25T10:00:00Z")["case-27|deep"])

        XCTAssertEqual(sample.overallScore, 83)
        XCTAssertEqual(sample.issueDimensions, ["人称视角(中)", "意象与细节(中)"])
        XCTAssertEqual(sample.mediumIssueCount, 2)
    }

    /// 24.9-P1：报告要为每条有效样本出一行问题清单，并在有上一轮数据时写出清单进出。
    func testReportRendersIssueListTrendPerPipeline() {
        let outcomes = [
            makeOutcome(
                pipeline: "deep",
                caseID: "case-27",
                overallScore: 72,
                issueDimensions: ["人称视角(中)", "意象与细节(中)", "留白与节奏(中)"]
            )
        ]

        let report = ReportGenerator.generate(
            runID: "run-trend",
            runTimestamp: "2026-07-25T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: outcomes,
            previousSamples: [
                "case-27|deep": makePrevious(
                    score: 83,
                    high: 0,
                    medium: 2,
                    low: 0,
                    dimensions: ["人称视角(中)", "意象与细节(中)"]
                )
            ]
        )

        XCTAssertTrue(report.contains("- deep 问题清单：人称视角(中)、意象与细节(中)、留白与节奏(中)"), report)
        XCTAssertTrue(report.contains("中 2→3"), "条数变化要写出来：\(report)")
        XCTAssertTrue(report.contains("新增 留白与节奏(中)"), "清单进出才是 24.2 要看的趋势：\(report)")
    }

    /// 24.9 断点续跑：跳过集合只认成功样本，失败的格子续跑时要重跑；同一格重跑过则后写入的
    /// 行胜出，报告不该再展示那条已作废的结果。
    func testResumeSkipsOnlySuccessfulPairsAndLatestRowWins() throws {
        let store = try EvalResultsStore(databaseURL: try makeTempDatabaseURL())
        let done = makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 85)
        let failed = makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: nil, success: false)
        try store.insert(runID: "run-9", runTimestamp: "2026-07-25T00:00:00Z", gitDescribe: "abc", outcome: done, rawJSON: try rawJSON(for: done))
        try store.insert(runID: "run-9", runTimestamp: "2026-07-25T00:00:00Z", gitDescribe: "abc", outcome: failed, rawJSON: try rawJSON(for: failed))

        let latest = try store.latestRun()
        XCTAssertEqual(latest?.runID, "run-9")
        XCTAssertEqual(latest?.runTimestamp, "2026-07-25T00:00:00Z")

        let pairs = try store.completedPairs(runID: "run-9")
        XCTAssertEqual(pairs, ["case-01|direct"], "只有成功的格子才该跳过")

        // 续跑把 deep 那格重跑成功后写入同一 run_id。
        let retried = makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: 88)
        try store.insert(runID: "run-9", runTimestamp: "2026-07-25T00:00:00Z", gitDescribe: "def", outcome: retried, rawJSON: try rawJSON(for: retried))

        let reloaded = try store.outcomes(runID: "run-9")
        XCTAssertEqual(reloaded.count, 2, "同一 case×pipeline 只应留一条：\(reloaded.map { "\($0.caseID)|\($0.pipeline)" })")
        XCTAssertEqual(reloaded.first(where: { $0.pipeline == "deep" })?.overallScore, 88)
        XCTAssertEqual(reloaded.first(where: { $0.pipeline == "direct" })?.overallScore, 85)
    }

    /// 24.9：无效样本要在报告头点名，质量列（总分/问题数）画横线——"0 高危"会被读成质量好，
    /// 而它其实只是没打分。
    func testReportMarksInvalidSamplesAndBlanksQualityColumns() {
        let outcomes = [
            makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 85),
            makeOutcome(pipeline: "deep", caseID: "case-01", overallScore: nil, success: false)
        ]

        let report = ReportGenerator.generate(
            runID: "run-invalid",
            runTimestamp: "2026-07-25T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: outcomes,
            previousSamples: ["case-01|deep": makePrevious(score: 86)]
        )

        XCTAssertTrue(report.contains("无效样本：1/2 格不计分"), "报告头必须点名无效样本：\(report)")
        XCTAssertTrue(report.contains("case-01|deep（The request timed out.）"))
        XCTAssertTrue(report.contains("| deep（失败：The request timed out.） | — | — | — | — |"), "失败行的质量列应全是横线：\(report)")
        XCTAssertFalse(report.contains("-28"), "失败样本不该和上次总分算出差值")
    }

    func testReportSaysAllSuccessWhenNoInvalidSamples() {
        let report = ReportGenerator.generate(
            runID: "run-clean",
            runTimestamp: "2026-07-25T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: [makeOutcome(pipeline: "direct", caseID: "case-01", overallScore: 85)],
            previousSamples: [:]
        )

        XCTAssertTrue(report.contains("无效样本：无（全部成功）"))
    }

    /// 生成动作用的是库内模板（24.5），模板换了分数同样不可比，报告头必须记下这一轮的模板来源。
    func testReportRecordsPromptTemplateSource() {
        let report = ReportGenerator.generate(
            runID: "run-4",
            runTimestamp: "2026-07-25T12:00:00Z",
            gitDescribe: "abc123",
            outcomes: [],
            previousSamples: [:],
            promptTemplateSummary: "大纲成稿(默认)、生成大纲(作者自定义)"
        )

        XCTAssertTrue(report.contains("Prompt 模板：大纲成稿(默认)、生成大纲(作者自定义)"))
    }
}
