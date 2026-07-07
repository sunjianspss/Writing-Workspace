import XCTest
@testable import CreativeWorkshopCore

/// PRD 23.8.1 检索质量升级：停用词过滤 + IDF 加权。两条用例都构造"高频词命中 vs 低频关键词命中"
/// 的对照，验证排序/取舍确实随算法升级而改变。
final class FragmentRetrieverTests: XCTestCase {
    /// 停用词过滤：只命中虚词 bigram 的素材应被完全过滤（score 0，不进结果），
    /// 只有命中真正低频关键词的素材才应出现。
    func testStopwordFilteringExcludesFillerOnlyMatchesFromResults() {
        let fillerOnlyFragment = Fragment(
            id: 1,
            source_type: "idea",
            source_id: 1,
            title: "无关素材",
            content: "一段与查询无实质关联的占位内容。",
            keywords: ["的了", "了是", "是我", "我们", "一个"],
            created_at: nil,
            updated_at: nil
        )
        let meaningfulFragment = Fragment(
            id: 2,
            source_type: "idea",
            source_id: 2,
            title: "胡同邻里",
            content: "巷口的邻里总在傍晚聚在一起说话。",
            keywords: ["邻里", "巷口"],
            created_at: nil,
            updated_at: nil
        )

        // 查询本身是"虚词堆叠 + 一个低频实词"；不加空格是为了让分词退化成单一整体 token，
        // 只有 bigram 层面的停用词过滤才会真正起作用（与真实无空格中文查询一致）。
        let hits = FragmentRetriever.retrieve(query: "的了是我们一个邻里", fragments: [fillerOnlyFragment, meaningfulFragment], limit: 5)

        XCTAssertFalse(hits.contains { $0.fragment_id == 1 }, "只命中虚词 bigram 的素材应被停用词过滤挡在结果外")
        XCTAssertEqual(hits.first?.fragment_id, 2, "命中低频实词「邻里」的素材应进入结果")
    }

    /// IDF 加权：两个素材与查询的原始重合词数相同（各 1 个），但重合词在语料中的文档频率不同——
    /// 命中语料里更稀有关键词的素材应该获得更高分数，从而反超命中高频词的素材。
    func testIDFWeightingRanksRareKeywordMatchAboveCommonKeywordMatch() {
        func fragment(_ id: Int, keywords: [String]) -> Fragment {
            Fragment(
                id: id,
                source_type: "idea",
                source_id: id,
                title: "素材\(id)",
                content: "占位内容\(id)。",
                keywords: keywords,
                created_at: nil,
                updated_at: nil
            )
        }

        // "common" 在语料 6 篇中出现 5 篇（高频，低 IDF）；"rare" 只出现 1 篇（低频，高 IDF）。
        let fragments = [
            fragment(1, keywords: ["common", "other1"]),
            fragment(2, keywords: ["common", "other2"]),
            fragment(3, keywords: ["common", "other3"]),
            fragment(4, keywords: ["common", "other4"]),
            fragment(5, keywords: ["common", "fillerx"]),
            fragment(6, keywords: ["rare", "fillery"])
        ]

        let hits = FragmentRetriever.retrieve(query: "common rare", fragments: fragments, limit: 6)

        let commonMatch = try? XCTUnwrap(hits.first { $0.fragment_id == 5 })
        let rareMatch = try? XCTUnwrap(hits.first { $0.fragment_id == 6 })
        guard let commonMatch, let rareMatch else {
            XCTFail("两个候选素材都应命中且进入结果")
            return
        }

        XCTAssertGreaterThan(rareMatch.score, commonMatch.score, "命中稀有关键词「rare」的素材应因 IDF 加权获得更高分数")
        XCTAssertEqual(hits.first?.fragment_id, 6, "IDF 加权后，稀有关键词命中应排在最前")
    }
}
