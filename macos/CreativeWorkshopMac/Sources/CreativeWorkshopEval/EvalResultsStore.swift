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
    func previousRunScores(before runTimestamp: String) throws -> [String: Int] {
        let sql = """
        SELECT case_id, pipeline, overall_score FROM eval_results
        WHERE run_id = (
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
