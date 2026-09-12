import Foundation
import CreativeWorkshopCore

/// 配对比较（24.14）。
///
/// 为什么必须配对：两个臂跑的是**同一批正文的同一个字节序列**，只有评分变量不同。
/// 独立两组比均值时，组间方差里绝大部分来自"这些稿子本身有好有坏"（实测总标准差 4.64）；
/// 配对之后这一项被完全消掉，剩下的只有变量本身的效应加评委噪声。24.13 审计里
/// "deep 对 agentic 差 0.73 分要 174 例才判得出"，正是因为那是**非配对**比较。
struct PairedComparison {
    struct Cell {
        var caseID: String
        var pipeline: String
        var before: Int
        var after: Int
        var delta: Int { after - before }
    }

    var cells: [Cell]

    var n: Int { cells.count }
    var meanBefore: Double { mean(cells.map { Double($0.before) }) }
    var meanAfter: Double { mean(cells.map { Double($0.after) }) }
    var meanDelta: Double { mean(cells.map { Double($0.delta) }) }

    /// 配对差值的标准差。注意这是**差值**的标准差，不是分数的标准差——两者可以差一个量级。
    var deltaStdDev: Double {
        guard n > 1 else { return 0 }
        let m = meanDelta
        let variance = cells.reduce(0.0) { $0 + pow(Double($1.delta) - m, 2) } / Double(n - 1)
        return variance.squareRoot()
    }

    var standardError: Double {
        guard n > 0 else { return 0 }
        return deltaStdDev / Double(n).squareRoot()
    }

    /// 95% 置信区间。跨 0 = 这次改动的方向判不出来。
    var confidenceInterval: (low: Double, high: Double) {
        let margin = 1.96 * standardError
        return (meanDelta - margin, meanDelta + margin)
    }

    var isSignificant: Bool {
        let ci = confidenceInterval
        return n > 1 && (ci.low > 0 || ci.high < 0)
    }

    var movedUp: Int { cells.filter { $0.delta > 0 }.count }
    var movedDown: Int { cells.filter { $0.delta < 0 }.count }
    var unchanged: Int { cells.filter { $0.delta == 0 }.count }

    /// 某个分值在两臂各占多少格——这是本次改动最直接的观察点（83 的占比会不会塌）。
    func occupancy(of score: Int) -> (before: Int, after: Int) {
        (cells.filter { $0.before == score }.count, cells.filter { $0.after == score }.count)
    }

    /// 检出给定效应量所需的配对样本数（80% 功效、双侧 0.05 的常用近似 n ≈ 7.85·σ²/Δ²）。
    func requiredPairs(toDetect effect: Double) -> Int {
        guard effect > 0, deltaStdDev > 0 else { return 0 }
        return Int(ceil(7.85 * pow(deltaStdDev, 2) / pow(effect, 2)))
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum RejudgeReport {
    /// 只有两臂都成功评分的格子才进配对——单臂失败的格子没有差值可言，
    /// 强行拿另一臂的分数去比就是 24.9 修掉的那个病（失败样本混进平均）。
    static func pair(rows: [RejudgeRow], before: String, after: String) -> PairedComparison {
        var beforeMap: [String: Int] = [:]
        var afterMap: [String: Int] = [:]
        for row in rows where row.success {
            guard let score = row.overallScore else { continue }
            let key = "\(row.caseID)|\(row.pipeline)"
            if row.variant == before { beforeMap[key] = score }
            if row.variant == after { afterMap[key] = score }
        }
        let cells = beforeMap.keys.sorted().compactMap { key -> PairedComparison.Cell? in
            guard let b = beforeMap[key], let a = afterMap[key] else { return nil }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return PairedComparison.Cell(caseID: parts[0], pipeline: parts[1], before: b, after: a)
        }
        return PairedComparison(cells: cells)
    }

    /// 维度频次：主评测路径丢掉的就是这张表（24.13 环 6）。
    static func dimensionTable(rows: [RejudgeRow], variant: String) -> [(dimension: String, total: Int, high: Int, medium: Int, low: Int, cells: Int)] {
        var total: [String: Int] = [:]
        var high: [String: Int] = [:]
        var medium: [String: Int] = [:]
        var low: [String: Int] = [:]
        var cells: [String: Set<String>] = [:]
        for row in rows where row.variant == variant && row.success {
            for issue in row.issues {
                let dimension = normalize(issue.dimension)
                total[dimension, default: 0] += 1
                cells[dimension, default: []].insert("\(row.caseID)|\(row.pipeline)")
                switch issue.severity {
                case "高": high[dimension, default: 0] += 1
                case "中": medium[dimension, default: 0] += 1
                case "低": low[dimension, default: 0] += 1
                default: break
                }
            }
        }
        return total.keys
            .map { (
                dimension: $0,
                total: total[$0] ?? 0,
                high: high[$0] ?? 0,
                medium: medium[$0] ?? 0,
                low: low[$0] ?? 0,
                cells: cells[$0]?.count ?? 0
            ) }
            // 按高危数排序：只有高危会把分数打到 80 以下，这是"拖分最多"的正确排序键。
            .sorted { ($0.high, $0.total) > ($1.high, $1.total) }
    }

    /// 维度是自由文本，模型会写成「语言腔调（轻微文艺腔）」。括号补语要剥掉，
    /// 否则同一个维度会散成十几个只出现一次的条目，频次表读不出东西。
    static func normalize(_ dimension: String) -> String {
        var text = dimension.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = text.firstIndex(where: { $0 == "（" || $0 == "(" }) {
            text = String(text[text.startIndex..<index])
        }
        for separator in ["·", "：", ":", "/", "、"] {
            if let range = text.range(of: separator) {
                text = String(text[text.startIndex..<range.lowerBound])
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未标维度" : text
    }

    static func generate(
        rejudgeID: String,
        timestamp: String,
        sourceRunID: String,
        gitDescribe: String,
        rows: [RejudgeRow],
        before: EvalPipelineFacade.ScoringVariant,
        after: EvalPipelineFacade.ScoringVariant
    ) -> String {
        var lines: [String] = []
        lines.append("# 评分变量对照报告（配对重判）")
        lines.append("")
        lines.append("- rejudge_id：\(rejudgeID)")
        lines.append("- 时间：\(timestamp)")
        lines.append("- git：\(gitDescribe)")
        lines.append("- 正文来源 run：\(sourceRunID)（**正文未重新生成，两臂逐字节相同**）")
        lines.append("- 对照臂 A（before）：\(before.displayName)")
        lines.append("- 对照臂 B（after）：\(after.displayName)")
        lines.append("")

        let comparison = pair(rows: rows, before: before.rawValue, after: after.rawValue)
        let failed = rows.filter { !$0.success }
        if !failed.isEmpty {
            let detail = failed
                .map { "\($0.caseID)|\($0.pipeline)|\($0.variant)" }
                .joined(separator: "、")
            lines.append("- 无效格：\(failed.count) 格评分调用失败，不进配对 —— \(detail)")
            lines.append("")
        }

        lines.append("## 配对结果")
        lines.append("")
        guard comparison.n > 0 else {
            lines.append("两臂没有共同成功的格子，无法配对。")
            return lines.joined(separator: "\n")
        }
        let ci = comparison.confidenceInterval
        lines.append("| 指标 | 数值 |")
        lines.append("| --- | --- |")
        lines.append("| 配对格数 | \(comparison.n) |")
        lines.append(String(format: "| A 臂均分 | %.2f |", comparison.meanBefore))
        lines.append(String(format: "| B 臂均分 | %.2f |", comparison.meanAfter))
        lines.append(String(format: "| 配对差值 (B−A) | %+.2f |", comparison.meanDelta))
        lines.append(String(format: "| 差值标准差 | %.2f |", comparison.deltaStdDev))
        lines.append(String(format: "| 差值标准误 | %.2f |", comparison.standardError))
        lines.append(String(format: "| 95%% 置信区间 | %+.2f ~ %+.2f |", ci.low, ci.high))
        lines.append("| 判定 | \(comparison.isSignificant ? "**差异显著**（区间不跨 0）" : "判不出（区间跨 0）") |")
        lines.append("| 变动分布 | 升 \(comparison.movedUp) · 降 \(comparison.movedDown) · 不变 \(comparison.unchanged) |")
        lines.append("")

        // 本次改动的直接观察点：示例值那个数在两臂各占多少格。
        let occupancy83 = comparison.occupancy(of: 83)
        lines.append("**83 分占比**：A 臂 \(occupancy83.before)/\(comparison.n)，B 臂 \(occupancy83.after)/\(comparison.n)")
        lines.append("")
        if comparison.deltaStdDev > 0 {
            lines.append("配对设计下，检出 1 分效应需 \(comparison.requiredPairs(toDetect: 1.0)) 格，"
                + "检出 2 分效应需 \(comparison.requiredPairs(toDetect: 2.0)) 格。")
            lines.append("")
        }

        lines.append("## 逐格差值")
        lines.append("")
        lines.append("| 用例 | 管线 | A | B | 差值 |")
        lines.append("| --- | --- | --- | --- | --- |")
        for cell in comparison.cells.sorted(by: { $0.delta < $1.delta }) {
            let mark = cell.delta == 0 ? "0" : String(format: "%+d", cell.delta)
            lines.append("| \(cell.caseID) | \(cell.pipeline) | \(cell.before) | \(cell.after) | \(mark) |")
        }
        lines.append("")

        for variant in [before, after] {
            let table = dimensionTable(rows: rows, variant: variant.rawValue)
            lines.append("## 问题维度 · \(variant.displayName)")
            lines.append("")
            guard !table.isEmpty else {
                lines.append("（本臂没有记录到问题）")
                lines.append("")
                continue
            }
            lines.append("| 维度 | 出现 | 高 | 中 | 低 | 覆盖格数 |")
            lines.append("| --- | --- | --- | --- | --- | --- |")
            for entry in table {
                lines.append("| \(entry.dimension) | \(entry.total) | \(entry.high) | \(entry.medium) | \(entry.low) | \(entry.cells) |")
            }
            lines.append("")
        }

        lines.append("## 高危问题原文（B 臂）")
        lines.append("")
        var printed = false
        for row in rows where row.variant == after.rawValue && row.success {
            for issue in row.issues where issue.severity == "高" {
                printed = true
                lines.append("- **\(row.caseID) / \(row.pipeline)**（\(row.overallScore.map(String.init) ?? "-") 分）· \(issue.dimension)")
                lines.append("  - 原文：\(issue.excerpt.prefix(120))")
                lines.append("  - 判词：\(issue.problem.prefix(160))")
            }
        }
        if !printed {
            lines.append("（B 臂没有高危问题）")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
