import XCTest
@testable import CreativeWorkshopCore

/// 说明文案的截断与省略规则此前埋在 WorkshopStore 里，改错了没有任何测试会响。
final class WorkflowNarrationTests: XCTestCase {
    func testReviewRevisionNoteTruncatesLongPlansAndKeepsOrder() {
        let review = makeReview(
            summary: "结构清楚，证据偏薄。",
            revisionPlan: ["补来源", "改结尾", "拆第三段", "统一称谓", "删重复例子"],
            trainingFocus: ["先给证据", "少用副词", "收束更早", "控制段长"]
        )

        let note = WorkflowNarration.reviewRevisionNote(review)

        XCTAssertTrue(note.contains("诊断摘要：结构清楚，证据偏薄。"))
        XCTAssertTrue(note.contains("修改顺序：补来源；改结尾；拆第三段；统一称谓"))
        XCTAssertFalse(note.contains("删重复例子"), "修改顺序只取前 4 条")
        XCTAssertTrue(note.contains("训练重点：先给证据；少用副词；收束更早"))
        XCTAssertFalse(note.contains("控制段长"), "训练重点只取前 3 条")
    }

    /// 空清单必须整行略去，而不是留下「修改顺序：」这样的空标签。
    func testReviewRevisionNoteOmitsEmptySectionsEntirely() {
        let review = makeReview(summary: "可以发。", revisionPlan: [], trainingFocus: [])

        let note = WorkflowNarration.reviewRevisionNote(review)

        XCTAssertFalse(note.contains("修改顺序"))
        XCTAssertFalse(note.contains("训练重点"))
        XCTAssertTrue(note.contains("诊断摘要：可以发。"))
    }

    func testTopicPayloadFromDraftPrefersTitleAndFallsBackToTruncatedIdea() {
        let withTitle = TopicPayload(
            draftTitle: "  为什么我们把 L2 留在实验室  ",
            idea: "代理跑通了但不该碰发布",
            summary: "",
            direction: "技术随笔"
        )
        XCTAssertEqual(withTitle?.title, "为什么我们把 L2 留在实验室")
        XCTAssertEqual(withTitle?.core_viewpoint, "代理跑通了但不该碰发布")
        XCTAssertNil(withTitle?.angle, "摘要为空时不应塞入空白 angle")

        let ideaOnly = TopicPayload(
            draftTitle: "   ",
            idea: String(repeating: "字", count: 50),
            summary: "",
            direction: "技术随笔"
        )
        XCTAssertEqual(ideaOnly?.title.count, 32, "无标题时用想法前 32 字")
    }

    /// 标题和想法都空，就没有值得记录的选题。
    func testTopicPayloadFromDraftReturnsNilWhenThereIsNothingToRecord() {
        XCTAssertNil(
            TopicPayload(draftTitle: "  ", idea: "\n", summary: "有摘要也不算", direction: "技术随笔")
        )
    }

    private func makeReview(
        summary: String,
        revisionPlan: [String],
        trainingFocus: [String]
    ) -> WritingReview {
        WritingReview(
            id: 1,
            article_id: nil,
            title_snapshot: nil,
            summary: summary,
            overall_score: 82,
            strengths: [],
            issues: [],
            revision_plan: revisionPlan,
            training_focus: trainingFocus,
            style_notes: [],
            raw_output: nil,
            model: nil,
            created_at: nil
        )
    }
}
