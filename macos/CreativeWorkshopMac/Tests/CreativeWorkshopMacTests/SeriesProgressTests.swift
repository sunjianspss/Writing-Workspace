import XCTest
@testable import CreativeWorkshopCore

/// 系列进度：把「这个系列有谁、写了谁、还剩谁」算出来。
///
/// 用例里的数据照着作者真实库的形状构造：红楼系列的标签本来就不齐（6 篇里只有 3 篇带
/// 「红楼梦」，黛玉和晴雯钻被窝的 tags 是空的），所以这里也留了没打标签的文章——它们
/// 理应不计入系列，而不是被猜进来。
final class SeriesProgressTests: XCTestCase {
    func testGroupsWrittenArticlesAndPendingTopicsByTag() {
        let series = SeriesProgress.build(
            seriesTags: ["红楼梦"],
            articles: [
                article(id: 1, title: "鸳鸯", tags: ["文学", "红楼梦", "书评"]),
                article(id: 2, title: "惯养娇生笑你痴", tags: ["红楼梦", "判词"]),
                article(id: 3, title: "成都的慢", tags: ["城市生活"])
            ],
            topics: [
                topic(id: 10, title: "王熙凤", tags: ["红楼梦"]),
                topic(id: 11, title: "探春", tags: ["红楼梦"]),
                topic(id: 12, title: "和 AI 协作", tags: ["技术分享"])
            ]
        )

        XCTAssertEqual(series.count, 1)
        let honglou = try? XCTUnwrap(series.first)
        XCTAssertEqual(honglou?.written.compactMap(\.title), ["鸳鸯", "惯养娇生笑你痴"])
        XCTAssertEqual(honglou?.pending.map(\.title), ["王熙凤", "探春"])
        XCTAssertEqual(honglou?.total, 4)
        XCTAssertEqual(honglou?.completion ?? 0, 0.5, accuracy: 0.0001)
    }

    /// 没打标签的文章不该被猜进系列——这正是作者库里黛玉和晴雯钻被窝的处境。
    func testUntaggedArticlesAreNotGuessedIntoTheSeries() {
        let series = SeriesProgress.build(
            seriesTags: ["红楼梦"],
            articles: [
                article(id: 1, title: "如何写红楼梦的林黛玉？", tags: []),
                article(id: 2, title: "晴雯钻被窝", tags: nil)
            ],
            topics: []
        )

        XCTAssertEqual(series.first?.total, 0, "标题里有「红楼梦」也不算——系列由标签决定，不靠猜")
        XCTAssertEqual(series.first?.completion, 0, "空系列的进度是 0，不是除零崩溃")
    }

    /// 已翻「已写」的选题不再算待写：它已由对应文章代表，两边都算会让进度虚低。
    func testWrittenTopicsAreNotCountedAsPending() {
        let series = SeriesProgress.build(
            seriesTags: ["红楼梦"],
            articles: [article(id: 1, title: "香菱", tags: ["红楼梦"])],
            topics: [
                topic(id: 10, title: "香菱", tags: ["红楼梦"], status: Topic.writtenStatus),
                topic(id: 11, title: "妙玉", tags: ["红楼梦"])
            ]
        )

        XCTAssertEqual(series.first?.pending.map(\.title), ["妙玉"])
        XCTAssertEqual(series.first?.total, 2)
    }

    /// 标签比对忽略首尾空白与大小写：手敲标签多一个空格太常见。
    func testTagMatchingIgnoresWhitespaceAndCase() {
        let series = SeriesProgress.build(
            seriesTags: [" 红楼梦 "],
            articles: [article(id: 1, title: "鸳鸯", tags: ["红楼梦"])],
            topics: [topic(id: 10, title: "凤姐", tags: ["红楼梦 "])]
        )

        XCTAssertEqual(series.first?.tag, "红楼梦", "展示名去掉首尾空白")
        XCTAssertEqual(series.first?.total, 2)
    }

    /// 顺序跟随作者排的顺序，不按数量重排；重复标签只出现一次。
    func testKeepsAuthorOrderAndDropsDuplicates() {
        let series = SeriesProgress.build(
            seriesTags: ["技术分享", "红楼梦", "红楼梦", "  "],
            articles: [
                article(id: 1, title: "鸳鸯", tags: ["红楼梦"]),
                article(id: 2, title: "香菱", tags: ["红楼梦"]),
                article(id: 3, title: "Fable 5", tags: ["技术分享"])
            ],
            topics: []
        )

        XCTAssertEqual(series.map(\.tag), ["技术分享", "红楼梦"], "顺序是作者排的；重复与空白标签被丢掉")
    }

    func testCandidateTagsAreRankedByFrequency() {
        let tags = SeriesProgress.candidateTags(
            articles: [
                article(id: 1, title: "A", tags: ["红楼梦", "书评"]),
                article(id: 2, title: "B", tags: ["红楼梦"])
            ],
            topics: [
                topic(id: 10, title: "C", tags: ["红楼梦", "技术分享"])
            ]
        )

        XCTAssertEqual(tags.first, "红楼梦", "出现最多的排最前")
        XCTAssertEqual(Set(tags), ["红楼梦", "书评", "技术分享"])
    }

    // MARK: - Fixtures

    private func article(id: Int, title: String, tags: [String]?) -> Article {
        Article(
            id: id, title: title, content: "正文", summary: "摘要", status: "已归档",
            type: nil, tags: tags, updated_at: nil, created_at: nil,
            related_topic_id: nil, genre: nil, audit_report: nil
        )
    }

    private func topic(id: Int, title: String, tags: [String]?, status: String = Topic.pendingStatus) -> Topic {
        Topic(
            id: id, title: title, direction: "情感文学", core_viewpoint: nil, target_reader: nil,
            description: nil, angle: nil, emotion: nil, score: 4, status: status,
            tags: tags, updated_at: nil, created_at: nil
        )
    }
}
