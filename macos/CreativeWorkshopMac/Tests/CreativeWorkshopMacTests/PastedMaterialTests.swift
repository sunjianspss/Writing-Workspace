import XCTest
@testable import CreativeWorkshopCore

/// 粘贴即存的领域逻辑：标题怎么取、算不算重复。
///
/// 用例照着作者真实的两个来源构造：微信收藏复制来的整段（首行是标题），以及 Obsidian
/// 里抄的片段（常常只有一行）。
final class PastedMaterialTests: XCTestCase {
    // MARK: - 标题

    /// 多行：首行当标题，正文保留全文——微信收藏和公众号正文几乎总是以标题开头。
    func testTakesFirstLineAsTitleForMultilineText() {
        let draft = PastedMaterial.draft(from: """
        高认知需求的人在思考方面就是这样

        如果你喜欢以下情况，你很可能就是其中之一。
        """)

        XCTAssertEqual(draft?.title, "高认知需求的人在思考方面就是这样")
        XCTAssertTrue(draft?.content.hasPrefix("高认知需求的人") == true, "正文保留全文，含首行")
        XCTAssertTrue(draft?.content.contains("很可能就是其中之一") == true)
    }

    /// 只有一行时不取标题：标题和正文一字不差地重复两遍，列表里反而更难认。
    func testLeavesTitleEmptyForSingleLineText() {
        let draft = PastedMaterial.draft(from: "  别只说你要什么，要说你为什么要这个。  ")

        XCTAssertEqual(draft?.title, "")
        XCTAssertEqual(draft?.content, "别只说你要什么，要说你为什么要这个。")
    }

    /// 首行太长就截断，否则整段当标题会把列表撑爆。
    func testTruncatesAnOverlongFirstLine() {
        let long = String(repeating: "长", count: 120)
        let draft = PastedMaterial.draft(from: long + "\n第二行")

        XCTAssertEqual(draft?.title.count, PastedMaterial.maximumTitleLength)
        XCTAssertTrue(draft?.content.contains("第二行") == true, "截断只影响标题，不动正文")
    }

    /// 前导空行不该变成空标题。
    func testSkipsLeadingBlankLinesWhenPickingTitle() {
        let draft = PastedMaterial.draft(from: "\n\n  真正的标题  \n\n正文在这里")

        XCTAssertEqual(draft?.title, "真正的标题")
    }

    /// 空白剪贴板返回 nil，调用方据此提示，而不是建一条空素材。
    func testBlankClipboardProducesNothing() {
        XCTAssertNil(PastedMaterial.draft(from: ""))
        XCTAssertNil(PastedMaterial.draft(from: "   \n\n \t "))
    }

    // MARK: - 重复

    /// 粘贴很容易手滑按两次，而素材箱没有撤销。
    func testDetectsAnExactDuplicate() {
        let existing = [idea(id: 1, content: "剥夺大模型的控制权：用外部脚本接管循环")]

        let hit = PastedMaterial.duplicate(of: "剥夺大模型的控制权：用外部脚本接管循环", in: existing)

        XCTAssertEqual(hit?.id, 1)
    }

    /// 空白归一后再比：从微信复制同一段，两次拿到的换行和空格可能不一致，
    /// 按原文比会把它们当成两条。
    func testTreatsWhitespaceVariantsAsTheSameMaterial() {
        let existing = [idea(id: 7, content: "四轮方法论：\n先理解这个仓库")]

        let hit = PastedMaterial.duplicate(of: "四轮方法论：  先理解这个仓库\n", in: existing)

        XCTAssertEqual(hit?.id, 7, "只有换行与空格不同，仍是同一条")
    }

    func testDifferentContentIsNotADuplicate() {
        let existing = [idea(id: 1, content: "第一条素材")]

        XCTAssertNil(PastedMaterial.duplicate(of: "另一条完全不同的素材", in: existing))
    }

    // MARK: - Fixtures

    private func idea(id: Int, content: String) -> Idea {
        Idea(
            id: id, title: nil, content: content, type: "灵感", tags: [],
            used: 0, related_article_id: nil, updated_at: nil, created_at: nil
        )
    }
}
