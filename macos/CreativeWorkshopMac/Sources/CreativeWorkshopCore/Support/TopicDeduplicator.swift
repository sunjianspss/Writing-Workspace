import Foundation

/// 选题生成去重（18.5.2）：生成新选题前，与近期已有选题做相似度比较，过滤明显重复项。
///
/// 用字符双元组（bigram）Jaccard 相似度做轻量判断，不依赖任何外部服务或向量模型，
/// 足以拦截"标题完全一致"或"几乎一字不差"这类真实出现过的重复（见 18.1 第 6 条）。
package enum TopicDeduplicator {
    package static let defaultSimilarityThreshold = 0.6

    package static func filterDuplicates(
        _ candidates: [TopicPayload],
        against existing: [Topic],
        threshold: Double = defaultSimilarityThreshold
    ) -> (unique: [TopicPayload], duplicates: [TopicPayload]) {
        let existingTitles = existing.map(\.title)
        var unique: [TopicPayload] = []
        var duplicates: [TopicPayload] = []
        var acceptedTitles = existingTitles

        for candidate in candidates {
            let isDuplicate = acceptedTitles.contains { existingTitle in
                similarity(candidate.title, existingTitle) >= threshold
            }
            if isDuplicate {
                duplicates.append(candidate)
            } else {
                unique.append(candidate)
                acceptedTitles.append(candidate.title)
            }
        }
        return (unique, duplicates)
    }

    package static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        if left.isEmpty || right.isEmpty {
            return normalize(lhs) == normalize(rhs) ? 1 : 0
        }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let normalized = Array(normalize(text))
        guard normalized.count >= 2 else {
            return normalized.isEmpty ? [] : [String(normalized)]
        }
        var result: Set<String> = []
        for index in 0..<(normalized.count - 1) {
            result.insert(String(normalized[index...index + 1]))
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
