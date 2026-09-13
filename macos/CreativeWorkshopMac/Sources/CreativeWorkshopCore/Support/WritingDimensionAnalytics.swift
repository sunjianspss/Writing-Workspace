import Foundation

/// 单个诊断维度（如"人称视角""意象与细节"）在最近样本中的出现趋势（18.4.2 文学写作能力雷达）。
package struct DimensionTrend: Identifiable, Hashable {
    package let dimension: String
    package let recentCount: Int
    package let earlierCount: Int

    package var id: String { dimension }
    package var totalCount: Int { recentCount + earlierCount }

    /// 用近半段相对早半段的出现次数变化，粗略判断"在减少"还是"在反复出现"。
    package var direction: TrendDirection {
        if recentCount > earlierCount { return .worsening }
        if recentCount < earlierCount { return .improving }
        return .steady
    }
}

package enum TrendDirection {
    case improving
    case steady
    case worsening
}

package enum WritingDimensionAnalytics {
    /// - Parameter reviews: 按时间倒序（最新在前）排列的历史诊断，如 `WorkshopStore.writingReviews`。
    /// - Parameter sampleSize: 参与统计的最近诊断条数上限。
    package static func trends(from reviews: [WritingReview], sampleSize: Int = 20) -> [DimensionTrend] {
        // 兜底诊断不参与统计：它是本地规则产出的，维度由规则决定而不是由稿件决定。
        // 作者库里「正文 8×」「展开 1×」这两个维度只在兜底里出现过，真诊断一次都没有——
        // 混进来就变成了看着像真实写作问题的假信号。先过滤再取样，否则兜底会占掉样本额度。
        let sample = Array(reviews.lazy.filter { !$0.used_fallback }.prefix(max(1, sampleSize)))
        guard !sample.isEmpty else { return [] }

        let half = max(1, sample.count / 2)
        var recentCounts: [String: Int] = [:]
        var earlierCounts: [String: Int] = [:]

        for (index, review) in sample.enumerated() {
            for issue in review.issues {
                // 归一后再计数：模型会把同一个维度写成「语言腔调（轻微文艺腔）」
                // 「语言腔调（议论是否节制）」等十几种样子，不归一就散成一堆只出现
                // 一次的条目，雷达会给出相反的排序（作者库里「语言腔调」合计 10 次、
                // 足以排第一，散开后六条小尾巴一条都进不了前列）。
                let dimension = DimensionNormalizer.normalize(issue.dimension)
                guard dimension != DimensionNormalizer.unlabeled else { continue }
                if index < half {
                    recentCounts[dimension, default: 0] += 1
                } else {
                    earlierCounts[dimension, default: 0] += 1
                }
            }
        }

        let dimensions = Set(recentCounts.keys).union(earlierCounts.keys)
        return dimensions
            .map { dimension in
                DimensionTrend(
                    dimension: dimension,
                    recentCount: recentCounts[dimension] ?? 0,
                    earlierCount: earlierCounts[dimension] ?? 0
                )
            }
            .sorted { $0.totalCount > $1.totalCount }
    }
}
