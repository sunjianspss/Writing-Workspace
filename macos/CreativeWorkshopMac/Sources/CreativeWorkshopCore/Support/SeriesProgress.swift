import Foundation

/// 系列进度：把「这个系列有谁、写了谁、还剩谁」算出来。纯逻辑，不碰数据库。
///
/// 背景：作者的红楼十二钗是一个**有限且明确**的清单，「下一篇写谁」本来不需要模型猜——
/// 可工坊此前没有任何地方能回答它。选题页只有一个 122 条的平铺列表，看不出哪些属于同一
/// 个系列、这个系列走到了哪里。于是"想不到题材"里有一部分其实是"看不见手上还剩什么"。
///
/// 系列用**标签**表达，不新增字段：文章和选题本来都有 tags。哪些标签算系列由作者显式指定
/// （存在 settings 的 `series_tags`），因为标签里大部分是「书评」「AI 工具」这种普通分类，
/// 机器分不出哪个是系列——分不出就别猜，让作者点一下。
package enum SeriesProgress {
    package struct Series: Identifiable, Hashable {
        /// 系列名即标签名。
        package var tag: String
        /// 已写：带该标签的文章，按最近更新在前。
        package var written: [Article]
        /// 待写：带该标签、且尚未翻成「已写」的选题。
        package var pending: [Topic]

        package var id: String { tag }
        package var total: Int { written.count + pending.count }

        /// 完成比例；系列为空时是 0 而不是除零。
        package var completion: Double {
            total == 0 ? 0 : Double(written.count) / Double(total)
        }

        package init(tag: String, written: [Article], pending: [Topic]) {
            self.tag = tag
            self.written = written
            self.pending = pending
        }
    }

    /// 按作者指定的系列标签归类。
    ///
    /// - 顺序跟随 `seriesTags`：那是作者自己排的，不要替他按数量重排。
    /// - 标签比对忽略首尾空白与大小写：`红楼梦 ` 与 `红楼梦` 是同一个系列，
    ///   而作者手敲标签时多一个空格太常见了。
    /// - 空标签整条跳过；重复标签只保留第一次出现，否则界面上会冒出两组一模一样的系列。
    package static func build(
        seriesTags: [String],
        articles: [Article],
        topics: [Topic]
    ) -> [Series] {
        var seen = Set<String>()
        var result: [Series] = []

        for rawTag in seriesTags {
            let key = normalized(rawTag)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }

            let written = articles.filter { hasTag(key, in: $0.tags) }
            // 已经翻成「已写」的选题不再算待写：它已经由对应文章代表了，
            // 两边都算会让 total 虚高、进度虚低。
            let pending = topics.filter {
                hasTag(key, in: $0.tags) && normalized($0.status ?? "") != normalized(Topic.writtenStatus)
            }
            result.append(Series(tag: rawTag.trimmingCharacters(in: .whitespacesAndNewlines), written: written, pending: pending))
        }

        return result
    }

    /// 候选系列标签：文章与选题里出现过的全部标签，按出现次数多的在前。
    /// 供界面列出来让作者勾选，免得靠手敲——手敲就会敲出 `红楼梦 ` 这种带空格的孪生标签。
    package static func candidateTags(articles: [Article], topics: [Topic]) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for tag in articles.flatMap({ $0.tags ?? [] }) + topics.flatMap({ $0.tags ?? [] }) {
            let key = normalized(tag)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
            // 同一个标签的不同写法，留第一次见到的那个作为展示名。
            if display[key] == nil {
                display[key] = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .compactMap { display[$0.key] }
    }

    private static func hasTag(_ key: String, in tags: [String]?) -> Bool {
        (tags ?? []).contains { normalized($0) == key }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
