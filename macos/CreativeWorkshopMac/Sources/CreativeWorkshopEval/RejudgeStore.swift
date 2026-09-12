import Foundation
import SQLite3
import CreativeWorkshopCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 一格重判结果（24.14）。与 `eval_results` 分表存放：那张表是**基线**，形状变了跨轮就不可比；
/// 重判是可以随时重跑、随时加变量的对照实验，不该污染基线表。
struct RejudgeRow {
    var variant: String
    var caseID: String
    var pipeline: String
    var overallScore: Int?
    var issues: [EvalPipelineFacade.RejudgedIssue]
    var success: Bool
    var error: String
    var elapsedMS: Int

    var highIssueCount: Int { issues.filter { $0.severity == "高" }.count }
    var mediumIssueCount: Int { issues.filter { $0.severity == "中" }.count }
    var lowIssueCount: Int { issues.filter { $0.severity == "低" }.count }
}

/// 重判结果库。与 `EvalResultsStore` 共用同一个 sqlite 文件，另开一张表。
struct RejudgeStore {
    private let db: OpaquePointer

    init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "RejudgeStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法打开重判结果库：\(databaseURL.path)"
            ])
        }
        db = handle
        try execute("""
            CREATE TABLE IF NOT EXISTS rejudge_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                rejudge_id TEXT NOT NULL,
                rejudge_timestamp TEXT NOT NULL,
                source_run_id TEXT NOT NULL,
                variant TEXT NOT NULL,
                label TEXT NOT NULL,
                case_id TEXT NOT NULL,
                pipeline TEXT NOT NULL,
                overall_score INTEGER,
                high_issue_count INTEGER NOT NULL,
                medium_issue_count INTEGER NOT NULL,
                low_issue_count INTEGER NOT NULL,
                issues_json TEXT NOT NULL,
                success INTEGER NOT NULL,
                error TEXT NOT NULL,
                elapsed_ms INTEGER NOT NULL
            )
            """)
        // 断点续跑靠这条唯一索引：同一批次、同一变量、同一格只保留一条，重跑覆盖而不是叠加。
        try execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_rejudge_cell
            ON rejudge_results (rejudge_id, variant, case_id, pipeline)
            """)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(error)
            throw NSError(domain: "RejudgeStore", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func upsert(
        rejudgeID: String,
        timestamp: String,
        sourceRunID: String,
        label: String,
        row: RejudgeRow
    ) throws {
        let sql = """
            INSERT INTO rejudge_results
                (rejudge_id, rejudge_timestamp, source_run_id, variant, label, case_id, pipeline,
                 overall_score, high_issue_count, medium_issue_count, low_issue_count,
                 issues_json, success, error, elapsed_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT (rejudge_id, variant, case_id, pipeline) DO UPDATE SET
                overall_score = excluded.overall_score,
                high_issue_count = excluded.high_issue_count,
                medium_issue_count = excluded.medium_issue_count,
                low_issue_count = excluded.low_issue_count,
                issues_json = excluded.issues_json,
                success = excluded.success,
                error = excluded.error,
                elapsed_ms = excluded.elapsed_ms
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "RejudgeStore", code: 3, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
        defer { sqlite3_finalize(statement) }

        let issuesJSON = (try? JSONEncoder().encode(row.issues))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        sqlite3_bind_text(statement, 1, rejudgeID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, timestamp, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, sourceRunID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, row.variant, -1, sqliteTransient)
        sqlite3_bind_text(statement, 5, label, -1, sqliteTransient)
        sqlite3_bind_text(statement, 6, row.caseID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 7, row.pipeline, -1, sqliteTransient)
        if let score = row.overallScore {
            sqlite3_bind_int(statement, 8, Int32(score))
        } else {
            sqlite3_bind_null(statement, 8)
        }
        sqlite3_bind_int(statement, 9, Int32(row.highIssueCount))
        sqlite3_bind_int(statement, 10, Int32(row.mediumIssueCount))
        sqlite3_bind_int(statement, 11, Int32(row.lowIssueCount))
        sqlite3_bind_text(statement, 12, issuesJSON, -1, sqliteTransient)
        sqlite3_bind_int(statement, 13, row.success ? 1 : 0)
        sqlite3_bind_text(statement, 14, row.error, -1, sqliteTransient)
        sqlite3_bind_int(statement, 15, Int32(row.elapsedMS))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "RejudgeStore", code: 4, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
            ])
        }
    }

    /// 已完成的格子（用于续跑跳过）：键为 `variant|case|pipeline`。
    func completedCells(rejudgeID: String) throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "SELECT variant, case_id, pipeline FROM rejudge_results WHERE rejudge_id = ? AND success = 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rejudgeID, -1, sqliteTransient)
        var result: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let variant = String(cString: sqlite3_column_text(statement, 0))
            let caseID = String(cString: sqlite3_column_text(statement, 1))
            let pipeline = String(cString: sqlite3_column_text(statement, 2))
            result.insert("\(variant)|\(caseID)|\(pipeline)")
        }
        return result
    }

    func rows(rejudgeID: String) throws -> [RejudgeRow] {
        var statement: OpaquePointer?
        let sql = """
            SELECT variant, case_id, pipeline, overall_score, issues_json, success, error, elapsed_ms
            FROM rejudge_results WHERE rejudge_id = ? ORDER BY case_id, pipeline, variant
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rejudgeID, -1, sqliteTransient)

        var result: [RejudgeRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let issuesText = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "[]"
            let issues = (issuesText.data(using: .utf8))
                .flatMap { try? JSONDecoder().decode([EvalPipelineFacade.RejudgedIssue].self, from: $0) } ?? []
            result.append(
                RejudgeRow(
                    variant: String(cString: sqlite3_column_text(statement, 0)),
                    caseID: String(cString: sqlite3_column_text(statement, 1)),
                    pipeline: String(cString: sqlite3_column_text(statement, 2)),
                    overallScore: sqlite3_column_type(statement, 3) == SQLITE_NULL
                        ? nil : Int(sqlite3_column_int(statement, 3)),
                    issues: issues,
                    success: sqlite3_column_int(statement, 5) == 1,
                    error: sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "",
                    elapsedMS: Int(sqlite3_column_int(statement, 7))
                )
            )
        }
        return result
    }
}
