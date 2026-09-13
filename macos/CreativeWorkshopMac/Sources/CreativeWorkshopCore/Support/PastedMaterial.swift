import Foundation

/// 把剪贴板里的一段文字直接变成一条素材。纯逻辑，不碰剪贴板也不碰数据库。
///
/// 背景：作者的素材两个来源——微信收藏复制、Obsidian 里抄——**都以"复制 → 粘贴"收尾**。
/// 瓶颈不在来源，在粘贴的目的地太远：打开 App → 素材箱 → 新建素材 → 粘贴 → 保存，五步。
/// 于是库里 6 条素材对 104 条选题，比例整个倒过来：不是不想存，是每存一条要付五步。
///
/// 这里把后三步合成一步。标题从首行取，因为微信收藏和公众号正文几乎总是以标题开头。
package enum PastedMaterial {
    /// 标题取首行，但截断到这个长度——首行有时是一整段，整段当标题会把列表撑爆。
    package static let maximumTitleLength = 40

    package struct Draft: Equatable {
        package var title: String
        package var content: String

        package init(title: String, content: String) {
            self.title = title
            self.content = content
        }
    }

    /// 空白剪贴板返回 nil：调用方据此提示，而不是建一条空素材。
    package static func draft(from raw: String) -> Draft? {
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let firstLine = lines.first { !$0.isEmpty } ?? ""
        let hasMoreThanOneLine = lines.filter { !$0.isEmpty }.count > 1

        // 只有一行时不取标题：标题和正文一字不差地重复两遍，列表里反而更难认。
        // 留空交给 `Idea.displayTitle` 从正文取前缀。
        guard hasMoreThanOneLine, !firstLine.isEmpty else {
            return Draft(title: "", content: content)
        }

        return Draft(title: truncatedTitle(firstLine), content: content)
    }

    /// 正文完全相同就算重复。粘贴很容易手滑按两次，而素材箱没有撤销。
    ///
    /// 比对前把空白归一：从微信复制同一段，两次拿到的换行和全角空格可能不一致，
    /// 按原文比会把它们当成两条。
    package static func duplicate(of content: String, in ideas: [Idea]) -> Idea? {
        let key = normalized(content)
        guard !key.isEmpty else { return nil }
        return ideas.first { normalized($0.content) == key }
    }

    private static func truncatedTitle(_ line: String) -> String {
        line.count <= maximumTitleLength ? line : String(line.prefix(maximumTitleLength))
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
