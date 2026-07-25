import XCTest
@testable import CreativeWorkshopCore

/// few-shot 样本挑选规则（PRD 24.6）。用的都是作者活库里真实出现过的体裁串。
final class StyleSampleSelectorTests: XCTestCase {
    private func article(_ title: String, genre: String?, status: String = "已归档") -> Article {
        Article(
            id: abs(title.hashValue % 10_000),
            title: title,
            content: "\(title)的正文",
            summary: nil,
            status: status,
            type: nil,
            tags: nil,
            updated_at: nil,
            created_at: nil,
            related_topic_id: nil,
            genre: genre,
            audit_report: nil
        )
    }

    func testGenreFamilyLinksTheAuthorsSplitLiteraryGenresButNotTechnicalOnes() {
        // 作者库里红楼系列被劈在"文学原著"与"情感文学"两桶，而当前方向写作"经典文学解读"。
        XCTAssertTrue(StyleSampleSelector.isSameGenreFamily("经典文学解读", "文学原著"))
        XCTAssertTrue(StyleSampleSelector.isSameGenreFamily("经典文学解读", "情感文学"))
        XCTAssertTrue(StyleSampleSelector.isSameGenreFamily("技术分享", "科研技术"))
        // 跨族不得相认：拿技术文当样本会教出错的腔调（24.4 已判过同一件事）。
        XCTAssertFalse(StyleSampleSelector.isSameGenreFamily("经典文学解读", "技术分享"))
        XCTAssertFalse(StyleSampleSelector.isSameGenreFamily("情感文学", "广告创意"))
        // 单字重合不算同族，否则"文学原著"会连上"原创广告"。
        XCTAssertFalse(StyleSampleSelector.isSameGenreFamily("文学原著", "原创广告"))
        XCTAssertFalse(StyleSampleSelector.isSameGenreFamily("情感文学", nil))
        XCTAssertFalse(StyleSampleSelector.isSameGenreFamily("情感文学", "   "))
    }

    func testSelectPrefersExactGenreThenFamilyAndNeverMixesTiers() {
        let candidates = [
            article("哀牢山地理志", genre: "技术分享"),
            article("叹香菱", genre: "文学原著"),
            article("晴雯钻被窝", genre: "情感文学")
        ]

        // 精确命中时只给精确档，不混入同族。
        XCTAssertEqual(
            StyleSampleSelector.select(from: candidates, genreKey: "文学原著").map(\.title),
            ["叹香菱"]
        )
        // 方向换个说法 → 精确落空，取同族的两篇文学文，技术文必须被挡在外面。
        XCTAssertEqual(
            StyleSampleSelector.select(from: candidates, genreKey: "经典文学解读").map(\.title),
            ["叹香菱", "晴雯钻被窝"]
        )
    }

    func testSelectFallsBackAcrossGenresOnlyWhenNoFamilyMatchExists() {
        let candidates = [
            article("哀牢山地理志", genre: "技术分享"),
            article("J-Space", genre: "科研技术"),
            article("无体裁旧稿", genre: nil)
        ]

        // 一篇同族的都没有：宁可跨体裁，也好过模型一篇都没见过作者的文字——但只取 2 篇。
        let selected = StyleSampleSelector.select(from: candidates, genreKey: "经典文学解读")
        XCTAssertEqual(selected.map(\.title), ["哀牢山地理志", "J-Space"])
    }

    func testEmptyGenreKeyDoesNotMatchArticlesWithEmptyGenre() {
        let candidates = [article("无体裁旧稿", genre: nil), article("叹香菱", genre: "文学原著")]

        // 体裁为空不该被当成"精确相等"而排到最前，否则未标体裁的旧稿会挤掉真正同族的文章。
        XCTAssertEqual(
            StyleSampleSelector.select(from: candidates, genreKey: "").map(\.title),
            ["无体裁旧稿", "叹香菱"]
        )
    }
}
