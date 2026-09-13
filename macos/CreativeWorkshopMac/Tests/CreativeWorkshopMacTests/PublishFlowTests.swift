import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

/// 发布这一段的分步流程。
///
/// 背景：作者的原话是"到处都是按钮，反而不知道下一步应该点什么"。发布区此前摊着四个语义
/// 重叠的控件（分段选择器 / 更新状态 / 归档 / 保存），其中分段选择器选了不生效、还会被刷新
/// 冲掉；而「保存」会把状态顺手写库却跳过终审与编辑量记录。真实后果：作者两次把文章 17 改成
/// 「已发布」，库里始终是「已归档」。
@MainActor
final class PublishFlowTests: XCTestCase {
    // MARK: - published_at 落地

    /// 这一列建表时就有，但全仓没有任何代码写过它——于是"有没有真的走过发表"无从判断。
    func testPublishingStampsPublishedAt() throws {
        let database = try makeDatabase()
        let article = try saveArticle(database, title: "稿", status: Article.draftStatus)
        XCTAssertNil(article.published_at)

        let published = try database.updateArticleStatus(id: article.id, status: Article.publishedStatus)

        let stamp = try XCTUnwrap(published.published_at)
        XCTAssertFalse(stamp.isEmpty, "翻已发布必须写下首发时间")
    }

    /// 再次点已发布不该把首发日期改成今天。
    func testRepublishingKeepsTheOriginalStamp() throws {
        let database = try makeDatabase()
        let article = try saveArticle(database, title: "稿", status: Article.draftStatus)
        let first = try XCTUnwrap(
            try database.updateArticleStatus(id: article.id, status: Article.publishedStatus).published_at
        )

        _ = try database.updateArticleStatus(id: article.id, status: Article.archivedStatus)
        let again = try database.updateArticleStatus(id: article.id, status: Article.publishedStatus)

        XCTAssertEqual(again.published_at, first, "首发时间只写一次")
    }

    /// 非发布状态不碰这一列。
    func testOtherStatusesDoNotStampPublishedAt() throws {
        let database = try makeDatabase()
        let article = try saveArticle(database, title: "稿", status: Article.draftStatus)

        let archived = try database.updateArticleStatus(id: article.id, status: Article.archivedStatus)

        XCTAssertNil(archived.published_at, "直接归档没走过发表，这一列必须留空")
    }

    // MARK: - 下一步

    func testPublishStepWalksTheFlowInOneDirection() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        XCTAssertEqual(store.publishStep, .needsSave, "还没存成文章时没有下一步")

        let article = try saveArticle(database, title: "稿", status: Article.draftStatus)
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id

        XCTAssertEqual(store.publishStep, .publish)
        XCTAssertEqual(store.publishStep.primaryTitle, "发表这篇")

        _ = try database.updateArticleStatus(id: article.id, status: Article.publishedStatus)
        store.articles = try database.listArticles()
        XCTAssertEqual(store.publishStep, .archive)

        _ = try database.updateArticleStatus(id: article.id, status: Article.archivedStatus)
        store.articles = try database.listArticles()
        XCTAssertEqual(store.publishStep, .done, "走过发表再归档，流程就走完了")
        XCTAssertNil(store.publishStep.primaryTitle, "终态没有主按钮")
    }

    /// 直接归档、没经过发表的稿子要能被认出来——文章 17 就是这个处境。
    /// 识别依据是 published_at 为空，而不是状态本身。
    func testArchivedWithoutPublishingIsDetectedAndOffersBackfill() throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let article = try saveArticle(database, title: "跳过发表的稿", status: Article.draftStatus)
        _ = try database.updateArticleStatus(id: article.id, status: Article.archivedStatus)
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id

        XCTAssertEqual(store.publishStep, .archivedWithoutPublishing)
        XCTAssertEqual(store.publishStep.primaryTitle, "补记发表")
        XCTAssertTrue(store.publishStep.hint.contains("终审和编辑量都没记"), store.publishStep.hint)
    }

    // MARK: - 保存不再改状态

    /// 「选了已发布、点保存、结果还是已归档」的反面：保存一律沿用库里已有的状态。
    func testSavingDoesNotChangeAnExistingArticleStatus() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        let article = try saveArticle(database, title: "已归档的稿", status: Article.archivedStatus)
        store.articles = try database.listArticles()
        store.selectedArticleID = article.id
        store.title = "已归档的稿"
        store.content = "改过的正文"
        // 即使有人把这个投影量设成别的，保存也不该据此改库。
        store.articleStatus = Article.publishedStatus

        await store.saveArticle()

        let reloaded = try XCTUnwrap(try database.listArticles().first { $0.id == article.id })
        XCTAssertEqual(reloaded.status, Article.archivedStatus, "保存只保存内容，状态归发布流程管")
        XCTAssertNil(reloaded.published_at, "保存不得伪造发表记录")
    }

    /// 新文章一律存成草稿，不带上一篇的残留状态。
    func testSavingANewArticleAlwaysStartsAsDraft() async throws {
        let database = try makeDatabase()
        let store = try WorkshopStore(database: database, aiClient: FakeAIClient())
        store.selectedArticleID = nil
        store.title = "新稿"
        store.content = "正文"
        store.articleStatus = Article.archivedStatus  // 上一篇留下的残留

        await store.saveArticle()

        let saved = try XCTUnwrap(try database.listArticles().first { $0.title == "新稿" })
        XCTAssertEqual(saved.status, Article.draftStatus, "新文章不该继承上一篇的状态")
    }

    // MARK: - Fixtures

    private func saveArticle(_ database: NativeDatabase, title: String, status: String) throws -> Article {
        try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: title, content: "正文", summary: "摘要", status: status,
                tags: [], related_topic_id: nil, genre: "情感文学"
            )
        )
    }

    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }
}
