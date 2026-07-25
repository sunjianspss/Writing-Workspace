import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 评测结果的独立 SQLite（PRD 22.4.2 第 4 条）：与主库 `creative_workshop.sqlite3` 完全分离，
/// 不复用、不迁移主库 schema。
final class EvalResultsStore {
    let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw EvalStoreError.open(message: lastErrorMessage)
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS eval_results (
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
        )
        try addFallbackCountColumnIfMissing()
        try addVerificationSummaryColumnIfMissing()
        try addSearchCountColumnIfMissing()
    }

    /// 兼容旧数据（PRD 23.4 验收标准 4）：老版本写入的 eval_results.sqlite3 没有 fallback_count 列，
    /// CREATE TABLE IF NOT EXISTS 不会给已存在的表补列，需要单独迁移。
    private func addFallbackCountColumnIfMissing() throws {
        try addColumnIfMissing(name: "fallback_count", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    /// 兼容旧数据（PRD 23.7）：老版本写入的 eval_results.sqlite3 没有 verification_summary 列。
    private func addVerificationSummaryColumnIfMissing() throws {
        try addColumnIfMissing(name: "verification_summary", definition: "TEXT NOT NULL DEFAULT ''")
    }

    /// 兼容旧数据（PRD 23.8.1）：老版本写入的 eval_results.sqlite3 没有 search_count 列。
    private func addSearchCountColumnIfMissing() throws {
        try addColumnIfMissing(name: "search_count", definition: "INTEGER NOT NULL DEFAULT 0")
    }

    private func addColumnIfMissing(name: String, definition: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(eval_results)", -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        var hasColumn = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameText = sqlite3_column_text(statement, 1), String(cString: nameText) == name {
                hasColumn = true
                break
            }
        }
        guard !hasColumn else { return }
        try execute("ALTER TABLE eval_results ADD COLUMN \(name) \(definition)")
    }

    deinit {
        sqlite3_close(db)
    }

    func insert(runID: String, runTimestamp: String, gitDescribe: String, outcome: PipelineOutcome, rawJSON: String) throws {
        let sql = """
        INSERT INTO eval_results (
            run_id, run_timestamp, git_describe, case_id, pipeline,
            overall_score, high_issue_count, medium_issue_count, low_issue_count,
            word_count, call_count, fallback_count, elapsed_ms, success, error, raw_json,
            verification_summary, search_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, runID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, runTimestamp, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, gitDescribe, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, outcome.caseID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 5, outcome.pipeline, -1, sqliteTransient)
        if let score = outcome.overallScore {
            sqlite3_bind_int(statement, 6, Int32(score))
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_int(statement, 7, Int32(outcome.highIssueCount))
        sqlite3_bind_int(statement, 8, Int32(outcome.mediumIssueCount))
        sqlite3_bind_int(statement, 9, Int32(outcome.lowIssueCount))
        sqlite3_bind_int(statement, 10, Int32(outcome.wordCount))
        sqlite3_bind_int(statement, 11, Int32(outcome.callCount))
        sqlite3_bind_int(statement, 12, Int32(outcome.fallbackCount))
        sqlite3_bind_int(statement, 13, Int32(outcome.elapsedMS))
        sqlite3_bind_int(statement, 14, outcome.success ? 1 : 0)
        sqlite3_bind_text(statement, 15, outcome.error, -1, sqliteTransient)
        sqlite3_bind_text(statement, 16, rawJSON, -1, sqliteTransient)
        sqlite3_bind_text(statement, 17, outcome.verificationSummary, -1, sqliteTransient)
        sqlite3_bind_int(statement, 18, Int32(outcome.searchCount))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw EvalStoreError.step(message: lastErrorMessage)
        }
    }

    /// 严格早于给定时间戳的最近一次 run 里，各 case_id+pipeline 的 overall_score，供报告算差值。
    /// 只取成功样本（24.9）：失败样本的分数是兜底稿或本地启发式算出来的，当过"上次总分"就会
    /// 凭空造出一列差值——7-24 那轮报告的 -18/-27/-28 全部来自此处。
    func previousRunScores(before runTimestamp: String) throws -> [String: Int] {
        let sql = """
        SELECT case_id, pipeline, overall_score FROM eval_results
        WHERE success = 1 AND run_id = (
            SELECT run_id FROM eval_results
            WHERE run_timestamp < ?
            ORDER BY run_timestamp DESC
            LIMIT 1
        )
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, runTimestamp, -1, sqliteTransient)

        var result: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let caseIDText = sqlite3_column_text(statement, 0),
                  let pipelineText = sqlite3_column_text(statement, 1) else { continue }
            guard sqlite3_column_type(statement, 2) != SQLITE_NULL else { continue }
            let key = "\(String(cString: caseIDText))|\(String(cString: pipelineText))"
            result[key] = Int(sqlite3_column_int(statement, 2))
        }
        return result
    }

    /// 断点续跑（24.9）用的 run 元信息：最近一次 run 的 id/时间戳/git。
    /// 全量一轮 112 格约 8 小时，行是增量落盘的，但此前没有任何续跑入口——中断就得从
    /// case-01 重烧一遍模型时间。
    func latestRun() throws -> (runID: String, runTimestamp: String, gitDescribe: String)? {
        let sql = """
        SELECT run_id, run_timestamp, git_describe FROM eval_results
        ORDER BY run_timestamp DESC, id DESC LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let runIDText = sqlite3_column_text(statement, 0),
              let timestampText = sqlite3_column_text(statement, 1),
              let gitText = sqlite3_column_text(statement, 2) else {
            return nil
        }
        return (String(cString: runIDText), String(cString: timestampText), String(cString: gitText))
    }

    /// 指定 run 里已经跑成功的 `case_id|pipeline`。只认成功样本：失败的格子续跑时应当重跑，
    /// 而不是把一个无效结果留在报告里（24.9）。
    func completedPairs(runID: String) throws -> Set<String> {
        let sql = "SELECT case_id, pipeline FROM eval_results WHERE run_id = ? AND success = 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, runID, -1, sqliteTransient)

        var pairs: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let caseIDText = sqlite3_column_text(statement, 0),
                  let pipelineText = sqlite3_column_text(statement, 1) else { continue }
            pairs.insert("\(String(cString: caseIDText))|\(String(cString: pipelineText))")
        }
        return pairs
    }

    /// 指定 run 已入库的结果，供续跑时把报告补成整轮。同一格子重跑过的话后写入的行胜出
    /// （按 id 升序读、同键覆盖）。
    func outcomes(runID: String) throws -> [PipelineOutcome] {
        let sql = "SELECT case_id, pipeline, raw_json FROM eval_results WHERE run_id = ? ORDER BY id ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw EvalStoreError.prepare(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, runID, -1, sqliteTransient)

        let decoder = JSONDecoder()
        var byPair: [String: PipelineOutcome] = [:]
        var order: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let caseIDText = sqlite3_column_text(statement, 0),
                  let pipelineText = sqlite3_column_text(statement, 1),
                  let rawJSONText = sqlite3_column_text(statement, 2) else { continue }
            let key = "\(String(cString: caseIDText))|\(String(cString: pipelineText))"
            guard let data = String(cString: rawJSONText).data(using: .utf8),
                  let outcome = try? decoder.decode(PipelineOutcome.self, from: data) else { continue }
            if byPair[key] == nil {
                order.append(key)
            }
            byPair[key] = outcome
        }
        return order.compactMap { byPair[$0] }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw EvalStoreError.exec(message: lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let db else { return "unknown" }
        return String(cString: sqlite3_errmsg(db))
    }
}

enum EvalStoreError: LocalizedError {
    case open(message: String)
    case prepare(message: String)
    case step(message: String)
    case exec(message: String)

    var errorDescription: String? {
        switch self {
        case let .open(message):
            return "无法打开评测结果数据库：\(message)"
        case let .prepare(message):
            return "评测结果 SQL 准备失败：\(message)"
        case let .step(message):
            return "评测结果写入失败：\(message)"
        case let .exec(message):
            return "评测结果建表失败：\(message)"
        }
    }
}
