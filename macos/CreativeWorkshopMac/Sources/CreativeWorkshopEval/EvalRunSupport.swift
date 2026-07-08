import Foundation

/// 评测韧性（第二轮评测事故后的修缮）：离线错误瞬间返回，串行循环曾在几秒内烧穿剩余
/// 9 个用例（约 40% 数据被污染）。识别"瞬时网络失败"→ 丢弃该结果、等待重试；持续离线
/// 达到上限则中止本轮——配合增量落盘，已完成的结果不再丢失。
enum OfflineBreaker {
    /// 整条管线在此毫秒数内失败视为"瞬时失败"（真实调用最短也要数秒；离线错误 0-4ms 返回）。
    static let instantFailureThresholdMS = 5_000
    static let waitSeconds = 30
    static let maxWaits = 20

    static func isInstantNetworkFailure(success: Bool, error: String, elapsedMS: Int) -> Bool {
        guard !success, elapsedMS < instantFailureThresholdMS else { return false }
        let lower = error.lowercased()
        let signatures = [
            "offline",
            "connection was lost",
            "network connection",
            "not connected to internet",
            "cannot connect to host",
            "似乎已断开",
            "尚未连接到互联网",
            "网络连接"
        ]
        return signatures.contains { lower.contains($0) }
    }
}

enum CaseFilterError: LocalizedError {
    case unknownCaseIDs([String], available: [String])

    var errorDescription: String? {
        switch self {
        case let .unknownCaseIDs(unknown, available):
            return "未知的用例 id：\(unknown.joined(separator: ","))（可选：\(available.joined(separator: ",")))"
        }
    }
}

/// `--cases case-01,case-07` 过滤（评测韧性修缮）：日常回归只跑受影响子集，
/// 全量对照留给里程碑节点。结果保持目录排序，与全量运行一致。
enum CaseFilter {
    static func apply(_ requested: [String], to cases: [EvalCase]) throws -> [EvalCase] {
        let availableIDs = cases.map(\.id)
        let unknown = requested.filter { !availableIDs.contains($0) }
        guard unknown.isEmpty else {
            throw CaseFilterError.unknownCaseIDs(unknown, available: availableIDs)
        }
        let wanted = Set(requested)
        return cases.filter { wanted.contains($0.id) }
    }
}
