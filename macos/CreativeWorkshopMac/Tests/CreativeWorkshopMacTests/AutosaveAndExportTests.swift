import XCTest
@testable import CreativeWorkshopCore

/// R5 瘦身·任务 23：自动保存存储层与三十日报告组装的独立测试。
@MainActor
final class AutosaveControllerTests: XCTestCase {
    private func makeController(suite: String) -> (AutosaveController, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AutosaveController(defaults: defaults, key: "test.autosave"), defaults)
    }

    private func makeSnapshot(title: String) -> AutoSavedDraft {
        AutoSavedDraft(
            selectedArticleID: nil,
            selectedTopicID: nil,
            articleStatus: "草稿",
            title: title,
            summary: "",
            content: "正文",
            outline: "",
            ideaInput: "",
            writingDirection: "情感文学",
            materials: "",
            draftTags: [],
            pendingDraftReview: nil,
            latestSelfCheck: nil,
            savedAt: "2026-07-08T00:00:00Z"
        )
    }

    func testPersistLoadClearRoundtrip() {
        let suite = "autosave-tests-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(controller.load())
        controller.persist(makeSnapshot(title: "回路标题"))
        XCTAssertEqual(controller.load()?.title, "回路标题")
        controller.clear()
        XCTAssertNil(controller.load(), "clear 后不得再读到快照")
    }

    func testScheduleDebouncesConsecutiveCallsIntoOneWrite() async {
        let suite = "autosave-tests-\(UUID().uuidString)"
        let (controller, defaults) = makeController(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var writeCount = 0
        for _ in 0..<5 {
            controller.schedule(debounceNanoseconds: 50_000_000) { writeCount += 1 }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(writeCount, 1, "防抖窗口内的连续调度应合并为一次写入")

        controller.schedule(debounceNanoseconds: 50_000_000) { writeCount += 1 }
        controller.cancelPending()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(writeCount, 1, "cancelPending 应取消挂起的写入")
    }
}

final class ArticleExportFormatterTests: XCTestCase {
    private func makeReview(title: String, score: Int, focus: [String]) -> WritingReview {
        WritingReview(
            id: Int.random(in: 1...99999),
            article_id: nil,
            title_snapshot: title,
            summary: "一句话诊断",
            overall_score: score,
            strengths: [],
            issues: [WritingReviewIssue(dimension: "结构", severity: "中", excerpt: nil, problem: "结尾松散", suggestion: "收紧")],
            revision_plan: [],
            training_focus: focus,
            style_notes: [],
            raw_output: nil,
            model: nil,
            created_at: ISO8601DateFormatter().string(from: Date()),
            resolved_from_last: [],
            reviewed_snapshot: nil
        )
    }

    func testThirtyDayReportComposesCountsAndFocus() throws {
        let reviews = [
            makeReview(title: "文章甲", score: 80, focus: ["结尾"]),
            makeReview(title: "文章乙", score: 90, focus: ["结尾", "细节"])
        ]

        let report = try ArticleExportFormatter.thirtyDayReviewReport(
            reviews: reviews,
            generatedAt: "2026-07-08T00:00:00Z"
        )

        XCTAssertTrue(report.contains("# 30 天写作教练报告"))
        XCTAssertTrue(report.contains("诊断次数：2"))
        XCTAssertTrue(report.contains("平均评分：85"))
        XCTAssertTrue(report.contains("结尾（2 次）"), "高频训练重点应带出现次数")
        XCTAssertTrue(report.contains("文章甲"))
    }

    func testThirtyDayReportThrowsWhenNoRecentReviews() {
        XCTAssertThrowsError(
            try ArticleExportFormatter.thirtyDayReviewReport(reviews: [], generatedAt: "2026-07-08T00:00:00Z")
        )
    }
}
