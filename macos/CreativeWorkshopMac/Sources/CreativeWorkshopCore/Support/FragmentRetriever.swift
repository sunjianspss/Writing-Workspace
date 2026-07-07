import Foundation

package enum FragmentRetriever {
    package static func split(text: String, targetLength: Int = 320) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var output: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count > targetLength, !current.isEmpty {
                output.append(current)
                current = paragraph
            } else {
                current = [current, paragraph].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
        }
        if !current.isEmpty {
            output.append(current)
        }
        return output.flatMap { chunk in
            chunk.count <= targetLength * 2 ? [chunk] : strideChunks(chunk, size: targetLength)
        }
    }

    package static func keywords(for text: String, limit: Int = 24) -> [String] {
        let normalized = normalize(text)
        let bigrams = characterBigrams(normalized).filter { !isStopword($0) }
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 2 && !isStopword($0) }
        let values = Array(Set(bigrams + tokens))
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs < rhs }
                return lhs.count > rhs.count
            }
        return Array(values.prefix(limit))
    }

    package static func retrieve(query: String, fragments: [Fragment], limit: Int = 3) -> [RetrievedFragment] {
        let queryKeywords = Set(keywords(for: query, limit: 40))
        guard !queryKeywords.isEmpty else { return [] }
        let fragmentKeywordSets = fragments.map { fragment in
            Set(fragment.keywords.isEmpty ? keywords(for: fragment.content) : fragment.keywords)
        }
        let idf = idfWeights(for: fragmentKeywordSets)
        return zip(fragments, fragmentKeywordSets)
            .map { fragment, fragmentKeywords in
                let intersection = queryKeywords.intersection(fragmentKeywords)
                let union = queryKeywords.union(fragmentKeywords)
                let intersectionWeight = intersection.reduce(0.0) { $0 + (idf[$1] ?? 0) }
                let unionWeight = union.reduce(0.0) { $0 + (idf[$1] ?? 0) }
                let keywordScore = unionWeight == 0 ? 0 : intersectionWeight / unionWeight
                let titleBonus = (fragment.title ?? "").localizedStandardContains(query) ? 0.15 : 0
                let contentBonus = fragment.content.localizedStandardContains(query) ? 0.2 : 0
                return RetrievedFragment(
                    fragment_id: fragment.id,
                    source_type: fragment.source_type,
                    source_id: fragment.source_id,
                    title: fragment.title,
                    content: fragment.content,
                    score: keywordScore + titleBonus + contentBonus
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.fragment_id < rhs.fragment_id }
                return lhs.score > rhs.score
            }
            .prefix(max(1, limit))
            .map(\.self)
    }

    package static func sectionContexts(for brief: WritingBriefResult, fragments: [Fragment], limit: Int = 3) -> [SectionFragmentContext] {
        guard !fragments.isEmpty else { return [] }
        return (brief.structure_plan ?? []).enumerated().compactMap { index, section in
            let query = [
                section.heading,
                section.purpose,
                section.key_points?.joined(separator: " "),
                section.material_hint
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            let retrieved = retrieve(query: query, fragments: fragments, limit: limit)
            guard !retrieved.isEmpty else { return nil }
            return SectionFragmentContext(
                section_index: index + 1,
                heading: section.heading,
                query: query,
                fragments: retrieved
            )
        }
    }

    package static func unique(_ fragments: [RetrievedFragment]) -> [RetrievedFragment] {
        var seen: Set<Int> = []
        var output: [RetrievedFragment] = []
        for fragment in fragments where !seen.contains(fragment.fragment_id) {
            seen.insert(fragment.fragment_id)
            output.append(fragment)
        }
        return output
    }

    private static func strideChunks(_ text: String, size: Int) -> [String] {
        let chars = Array(text)
        guard chars.count > size else { return [text] }
        var output: [String] = []
        var index = 0
        while index < chars.count {
            let end = min(chars.count, index + size)
            output.append(String(chars[index..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            index = end
        }
        return output.filter { !$0.isEmpty }
    }

    private static func characterBigrams(_ text: String) -> [String] {
        let chars = Array(text)
        guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars)] }
        return (0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }

    /// 常用中文虚词表（PRD 23.8.1）：过滤掉这些词/字组成的 bigram、token，避免虚词命中拉高检索得分。
    private static let stopwords: Set<String> = [
        "的", "了", "是", "在", "和", "与", "就", "都", "也", "还", "很", "这", "那",
        "你", "我", "他", "她", "它", "啊", "吧", "呢", "吗", "着", "过", "被", "把",
        "我们", "你们", "他们", "她们", "它们", "一个", "一些", "一种", "一下",
        "这个", "那个", "这样", "那样", "什么", "怎么", "因为", "所以",
        "而且", "可以", "应该", "没有", "不是", "自己", "但是", "就是"
    ]

    private static func isStopword(_ value: String) -> Bool {
        if stopwords.contains(value) { return true }
        guard value.count == 2 else { return false }
        return value.allSatisfy { stopwords.contains(String($0)) }
    }

    /// 平滑 IDF：idf = log((N+1)/(df+1)) + 1，语料内越常见的词权重越低，稀有关键词权重越高（PRD 23.8.1）。
    private static func idfWeights(for keywordSets: [Set<String>]) -> [String: Double] {
        guard !keywordSets.isEmpty else { return [:] }
        var documentFrequency: [String: Int] = [:]
        for set in keywordSets {
            for keyword in set {
                documentFrequency[keyword, default: 0] += 1
            }
        }
        let totalDocuments = Double(keywordSets.count)
        return documentFrequency.mapValues { df in
            log((totalDocuments + 1) / (Double(df) + 1)) + 1
        }
    }
}
