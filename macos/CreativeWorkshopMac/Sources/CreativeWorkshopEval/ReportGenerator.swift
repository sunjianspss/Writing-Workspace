import Foundation

/// 生成 evals/reports/{时间戳}.md：一张表里同一用例对比三条管线的分数与成本，
/// 并附上与上一次 run 的总分差值（PRD 22.4.2 第 5 条）。
enum ReportGenerator {
    static func generate(
        runID: String,
        runTimestamp: String,
        gitDescribe: String,
        outcomes: [PipelineOutcome],
        previousScores: [String: Int],
        styleSampleNames: [String] = []
    ) -> String {
        var lines: [String] = []
        lines.append("# 写作质量评测报告")
        lines.append("")
        lines.append("- run_id：\(runID)")
        lines.append("- 时间：\(runTimestamp)")
        lines.append("- git：\(gitDescribe)")
        // 注入了哪几篇风格样本必须写进报告：样本换了分数就不可比，而"样本是否同时是某条
        // 用例的来源"无法可靠自动判定（正文可能带 frontmatter，idea 侧孪生更无从比对），
        // 只能靠可见性让人复核（24.4）。
        lines.append("- 风格样本：\(styleSampleNames.isEmpty ? "无（零样本配置）" : styleSampleNames.joined(separator: "、"))")
        lines.append("")

        var seenCaseIDs = Set<String>()
        var caseIDs: [String] = []
        for outcome in outcomes where !seenCaseIDs.contains(outcome.caseID) {
            seenCaseIDs.insert(outcome.caseID)
            caseIDs.append(outcome.caseID)
        }

        for caseID in caseIDs {
            lines.append("## \(caseID)")
            lines.append("")
            lines.append("| 管线 | 总分 | 高危问题 | 中危问题 | 低危问题 | 字数 | 调用次数 | 检索次数 | fallback次数 | 耗时(ms) | 上次总分 | 差值 | 验证信号 |")
            lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
            for pipeline in PipelineRunner.pipelineNames {
                guard let outcome = outcomes.first(where: { $0.caseID == caseID && $0.pipeline == pipeline }) else {
                    continue
                }
                let previous = previousScores["\(caseID)|\(pipeline)"]
                let diffText: String
                if let previous, let current = outcome.overallScore {
                    let diff = current - previous
                    diffText = diff > 0 ? "+\(diff)" : "\(diff)"
                } else {
                    diffText = "-"
                }
                let statusSuffix = outcome.success ? "" : "（失败：\(outcome.error)）"
                lines.append(
                    "| \(pipeline)\(statusSuffix) | \(outcome.overallScore.map(String.init) ?? "-") "
                        + "| \(outcome.highIssueCount) | \(outcome.mediumIssueCount) | \(outcome.lowIssueCount) "
                        + "| \(outcome.wordCount) | \(outcome.callCount) | \(outcome.searchCount) | \(outcome.fallbackCount) | \(outcome.elapsedMS) "
                        + "| \(previous.map(String.init) ?? "-") | \(diffText) | \(outcome.verificationSummary) |"
                )
            }
            // agentic 会话轨迹（评测仪器修缮）：无头评测不落 agent_runs，摘要直接进报告，
            // 便于诊断"为什么跑满预算/为什么提前停"。
            for outcome in outcomes where outcome.caseID == caseID && !outcome.sessionSummary.isEmpty {
                lines.append("")
                lines.append("- \(outcome.pipeline) 会话：\(outcome.sessionSummary)")
            }
            lines.append("")
        }

        lines.append("## 放行门")
        lines.append("")
        lines.append(contentsOf: ReleaseGate.evaluate(outcomes: outcomes).lines)
        lines.append("")

        return lines.joined(separator: "\n")
    }
}

enum GitDescribe {
    static func current(repositoryPath: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repositoryPath, "describe", "--always", "--dirty"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "unknown" : text
        } catch {
            return "unknown"
        }
    }
}
