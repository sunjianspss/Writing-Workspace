import Foundation

/// 上一轮同一「用例×管线」的可比结果（24.9-P1）。只从成功样本读取。
struct PreviousSample {
    var overallScore: Int?
    var highIssueCount: Int
    var mediumIssueCount: Int
    var lowIssueCount: Int
    var issueDimensions: [String]
}

/// 问题清单的跨轮对比（24.9-P1）。
///
/// 背景：24.2 三连诊断证明分数在档界会跳 10 分（"漏检一条低危"就能把 83 打成 73），裁决因此
/// 是"趋势改用问题清单而非分数来读"。但工具一直只跨轮比分数——报告只有「上次总分/差值」
/// 一列，issues 只有三个计数、连维度都不落库，于是那条裁决在工具上根本没法执行。
///
/// 纯函数，便于用真实维度串测试。
enum IssueTrend {
    /// 当前轮的问题清单一行摘要；有上一轮数据时附带条数变化与清单进出。
    static func describe(current: [String], previous: PreviousSample?) -> String {
        let currentList = current.isEmpty ? "无问题" : current.joined(separator: "、")
        guard let previous else {
            return "问题清单：\(currentList)"
        }

        let currentSet = Set(current)
        let previousSet = Set(previous.issueDimensions)
        let added = current.filter { !previousSet.contains($0) }
        let gone = previous.issueDimensions.filter { !currentSet.contains($0) }

        var parts = ["问题清单：\(currentList)"]
        let counts = countsDelta(current: current, previous: previous)
        if !counts.isEmpty {
            parts.append(counts)
        }
        if !added.isEmpty {
            parts.append("新增 \(added.joined(separator: "、"))")
        }
        if !gone.isEmpty {
            parts.append("已消失 \(gone.joined(separator: "、"))")
        }
        // 维度与严重度逐条相同：这才是"稳定"，值得明说——24.2 的第二例正是"问题稳定、分数跳 10 分"。
        if added.isEmpty && gone.isEmpty {
            parts.append("与上轮逐条相同")
        }
        return parts.joined(separator: "；")
    }

    /// 只输出真正变了的档位，没变的不占字。
    private static func countsDelta(current: [String], previous: PreviousSample) -> String {
        let currentCounts = severityCounts(current)
        let previousCounts = [
            "高": previous.highIssueCount,
            "中": previous.mediumIssueCount,
            "低": previous.lowIssueCount
        ]
        let changed = ["高", "中", "低"].compactMap { severity -> String? in
            let now = currentCounts[severity] ?? 0
            let before = previousCounts[severity] ?? 0
            guard now != before else { return nil }
            return "\(severity) \(before)→\(now)"
        }
        return changed.joined(separator: "、")
    }

    /// 从 `维度(严重度)` 串里数各档条数。取最后一对括号内的内容，维度名本身含括号也不会数错。
    static func severityCounts(_ dimensions: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in dimensions {
            guard let open = entry.lastIndex(of: "("), let close = entry.lastIndex(of: ")"), open < close else {
                continue
            }
            let severity = String(entry[entry.index(after: open)..<close])
            counts[severity, default: 0] += 1
        }
        return counts
    }
}
