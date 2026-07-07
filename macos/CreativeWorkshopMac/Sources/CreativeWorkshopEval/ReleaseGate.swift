import Foundation

/// 放行门判定（PRD 23.4）：L2 代理循环（agentic）是否值得设为默认入口，由这三条硬指标说了算，
/// 不是主观判断。三项全过才通过；agentic 管线由任务 14 接入，接入前只输出"暂无数据"。
enum ReleaseGate {
    static let agenticPipelineName = "agentic"
    static let deepPipelineName = "deep"
    static let maxCallCountRatio = 1.5

    struct Verdict {
        var passed: Bool
        var lines: [String]
    }

    static func evaluate(outcomes: [PipelineOutcome]) -> Verdict {
        let agentic = outcomes.filter { $0.pipeline == agenticPipelineName }
        let deep = outcomes.filter { $0.pipeline == deepPipelineName }

        guard !agentic.isEmpty, !deep.isEmpty else {
            return Verdict(passed: false, lines: ["放行门：暂无 agentic 管线数据"])
        }

        let agenticAvgScore = averageScore(agentic)
        let deepAvgScore = averageScore(deep)
        let agenticAvgCallCount = averageCallCount(agentic)
        let deepAvgCallCount = averageCallCount(deep)
        let callCountThreshold = deepAvgCallCount * maxCallCountRatio
        let agenticFallbackRate = fallbackRate(agentic)
        let deepFallbackRate = fallbackRate(deep)

        let scorePassed = agenticAvgScore >= deepAvgScore
        let callCountPassed = agenticAvgCallCount <= callCountThreshold
        let fallbackRatePassed = agenticFallbackRate <= deepFallbackRate

        var lines: [String] = []
        lines.append(
            String(format: "- rubric 平均总分：agentic %.2f，deep %.2f → %@",
                   agenticAvgScore, deepAvgScore, scorePassed ? "通过" : "不通过")
        )
        lines.append(
            String(format: "- 平均模型调用次数：agentic %.2f，deep %.2f（阈值 ≤ %.2f） → %@",
                   agenticAvgCallCount, deepAvgCallCount, callCountThreshold, callCountPassed ? "通过" : "不通过")
        )
        lines.append(
            String(format: "- fallback/熔断率：agentic %.2f%%，deep %.2f%% → %@",
                   agenticFallbackRate * 100, deepFallbackRate * 100, fallbackRatePassed ? "通过" : "不通过")
        )

        let allPassed = scorePassed && callCountPassed && fallbackRatePassed
        if allPassed {
            lines.append("放行门：通过，可将代理会话设为默认入口")
        } else {
            var failedItems: [String] = []
            if !scorePassed {
                failedItems.append(String(format: "rubric 平均总分（差 %.2f）", deepAvgScore - agenticAvgScore))
            }
            if !callCountPassed {
                failedItems.append(String(format: "平均模型调用次数（超出阈值 %.2f）", agenticAvgCallCount - callCountThreshold))
            }
            if !fallbackRatePassed {
                failedItems.append(String(format: "fallback/熔断率（差 %.2f%%）", (agenticFallbackRate - deepFallbackRate) * 100))
            }
            lines.append("放行门：不通过，未过项：" + failedItems.joined(separator: "；"))
        }

        return Verdict(passed: allPassed, lines: lines)
    }

    private static func averageScore(_ outcomes: [PipelineOutcome]) -> Double {
        let scores = outcomes.compactMap(\.overallScore)
        guard !scores.isEmpty else { return 0 }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    private static func averageCallCount(_ outcomes: [PipelineOutcome]) -> Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.map(\.callCount).reduce(0, +)) / Double(outcomes.count)
    }

    /// fallback/熔断率 = 总 fallback/熔断发生数 ÷ 总模型调用次数，衡量单次调用出岔子的概率。
    private static func fallbackRate(_ outcomes: [PipelineOutcome]) -> Double {
        let totalCalls = outcomes.map(\.callCount).reduce(0, +)
        guard totalCalls > 0 else { return 0 }
        let totalFallbacks = outcomes.map(\.fallbackCount).reduce(0, +)
        return Double(totalFallbacks) / Double(totalCalls)
    }
}
