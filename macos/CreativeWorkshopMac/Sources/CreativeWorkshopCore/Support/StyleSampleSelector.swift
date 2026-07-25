import Foundation

/// few-shot 风格样本的挑选规则（PRD 24.6）。纯逻辑，不碰数据库，便于用真实体裁串测试。
///
/// 背景：`articles.genre` 存的是保存时的**写作方向原文**，作者库里已经碎成「情感文学 / 文学原著 /
/// 技术分享 / 科研技术 / 广告创意 / 空」六值，红楼系列被劈在两个桶里。精确相等匹配（24.3 之前的
/// 唯一规则）动不动就归零；而 24.3 加的「落空就跨体裁取最近完成稿」又会拿技术文教文学腔——
/// 24.4 为评测选样本时已经判过「拿技术文当样本会教出错的腔调」，App 侧不该反着来。
///
/// 折中规则：体裁串共享 ≥2 个连续汉字即视为同族（"经典文学解读" ↔ "文学原著" ↔ "情感文学" 靠
/// "文学"连起来，"技术分享" ↔ "科研技术" 靠"技术"连起来，两族互不相认）。便宜、可解释、可测试。
package enum StyleSampleSelector {
    /// 同族判定的最小公共子串长度。1 个字太容易误连（"文学原著" 与 "原创广告" 共享"原"）。
    package static let minimumSharedRunLength = 2

    package static func isSameGenreFamily(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return false
        }
        if left == right {
            return true
        }
        return hasCommonRun(left, right, length: minimumSharedRunLength)
    }

    /// 按优先级挑样本，**只取最高的那一档**，不混档：
    /// 1. 体裁精确相同 2. 体裁同族 3. 其余（跨体裁，宁可跨也好过模型一篇都没见过作者的文字）
    ///
    /// 调用方负责先把候选限定为完成稿——改到一半的草稿不能当风格范本。
    package static func select(from articles: [Article], genreKey: String, limit: Int = 3) -> [Article] {
        let key = normalized(genreKey)
        let exact = articles.filter { normalized($0.genre) == key && !key.isEmpty }
        if !exact.isEmpty {
            return Array(exact.prefix(limit))
        }
        let family = articles.filter { isSameGenreFamily($0.genre, genreKey) }
        if !family.isEmpty {
            return Array(family.prefix(limit))
        }
        // 跨体裁这一档保守取 2 篇：腔调本就不一定对得上，注入多了反而带偏。
        return Array(articles.prefix(min(limit, 2)))
    }

    private static func normalized(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasCommonRun(_ lhs: String, _ rhs: String, length: Int) -> Bool {
        let left = Array(lhs)
        let right = Set(runs(of: Array(rhs), length: length))
        guard left.count >= length, !right.isEmpty else {
            return false
        }
        return runs(of: left, length: length).contains { right.contains($0) }
    }

    private static func runs(of characters: [Character], length: Int) -> [String] {
        guard characters.count >= length else {
            return []
        }
        return (0...(characters.count - length)).map { String(characters[$0..<($0 + length)]) }
    }
}
