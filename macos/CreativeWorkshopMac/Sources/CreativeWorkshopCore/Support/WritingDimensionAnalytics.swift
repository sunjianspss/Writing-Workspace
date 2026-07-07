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
        let sample = Array(reviews.prefix(max(1, sampleSize)))
        guard !sample.isEmpty else { return [] }

        let half = max(1, sample.count / 2)
        var recentCounts: [String: Int] = [:]
        var earlierCounts: [String: Int] = [:]

        for (index, review) in sample.enumerated() {
            for issue in review.issues {
                let dimension = issue.dimension.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dimension.isEmpty else { continue }
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
