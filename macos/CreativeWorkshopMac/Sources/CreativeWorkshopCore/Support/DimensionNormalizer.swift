import Foundation

/// 诊断维度的归一口径。App 侧的写作雷达与评测侧的配对重判**共用这一份**。
///
/// 维度是模型的自由文本，同一个维度会被写成十几种样子：
///
///     语言腔调
///     语言腔调（轻微文艺腔）
///     语言腔调（议论是否节制）
///     语言腔调（是否滑向文艺腔/鸡汤腔/营销腔）
///
/// 不归一就散成一堆只出现一次的条目，频次表读不出东西。作者库里这一组合起来是 10 次，
/// 足以排第一，散开后六条小尾巴一条都进不了前列——**读数会给出相反的结论**。
///
/// 这份规则原先只存在于 `RejudgeReport`（评测侧私有）。App 的雷达没有它，于是同一批数据
/// 两边两套口径。搬来 Core 是为了让"维度怎么算同一个"只有一个答案。
package enum DimensionNormalizer {
    /// 落空时的占位名。宁可显式标出来，也不要让空维度并进别人。
    package static let unlabeled = "未标维度"

    /// 剥掉括号补语与首个分隔符之后的主干。
    ///
    /// 只剥这两类，不做同义词合并：「语言腔调」与「腔调」仍算两个维度。同义异名要合并
    /// 得有一张受控词表，那是另一个决定——这里只做机械、可解释、不会误伤的那一半。
    package static func normalize(_ dimension: String) -> String {
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
        return text.isEmpty ? unlabeled : text
    }
}
