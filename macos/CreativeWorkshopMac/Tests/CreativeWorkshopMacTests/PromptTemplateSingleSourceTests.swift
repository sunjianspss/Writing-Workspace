import XCTest
@testable import CreativeWorkshopCore

/// 内置 prompt 只有一份文案（PRD 24.11 / P2-6）。
///
/// 修复前每个工作流有两份：`defaultPromptTemplates()` 里的模板，和 `template == nil` 时才走的
/// 内联字符串。而建库时模板一定被 seed 进 `prompt_templates`、`promptTemplate(for:)` 一定命中，
/// 线上跑的永远是模板那份——内联那份在生产路径上执行不到，改它没有任何效果，测试还是绿的。
/// 两份文案也确实已经漂移（内联版给写作诊断带了作者样本，模板版没有）。
///
/// 这三条守卫锁的就是"不许再长出第二份"：
/// 1. 每个 key 都有种子（新加 key 忘了写模板 → 线上发空 prompt）
/// 2. 传 nil 与传内置模板必须逐字相同（谁再插一个内联分支，这条立刻红）
/// 3. 渲染后不许残留 `{{变量}}`（种子用了函数没提供的变量 → 占位符原样发给模型）
final class PromptTemplateSingleSourceTests: XCTestCase {
    // MARK: - 各 key 的调用（新增 key 时这里必须补一行，否则 testEveryKeyIsCovered 会红）

    /// 返回 (key, 传 nil 的结果, 传内置模板的结果)。
    private func renderedPairs() -> [(key: PromptTemplateKey, viaNil: [ChatMessage], viaTemplate: [ChatMessage])] {
        let style = makeStyle()
        let context = makeContext()
        let topic = makeTopic()
        let review = makeReview()
        let state = AgentSessionState(
            idea: "一个想法",
            direction: "情感文学",
            materials: "素材若干",
            style: style,
            title: "会话标题",
            content: "会话正文",
            outline: "会话大纲",
            callBudget: 12
        )

        func pair(_ key: PromptTemplateKey, _ make: (PromptTemplate?) -> [ChatMessage]) -> (PromptTemplateKey, [ChatMessage], [ChatMessage]) {
            (key, make(nil), make(NativePrompts.defaultTemplate(key)))
        }

        return [
            pair(.topics) { NativePrompts.topics(context: context, style: style, template: $0) },
            pair(.outline) { NativePrompts.outline(topic: topic, context: context, style: style, template: $0) },
            pair(.draft) { NativePrompts.draft(topic: topic, context: context, style: style, template: $0) },
            pair(.polishDraft) {
                NativePrompts.polishDraft(context: context, content: "正文", mode: .natural, style: style, template: $0)
            },
            pair(.writingReview) {
                NativePrompts.writingReview(context: context, style: style, previousReview: review, template: $0)
            },
            pair(.publishAssets) { NativePrompts.publishAssets(context: context, style: style, template: $0) },
            pair(.rewriteSelection) {
                NativePrompts.rewriteSelection(
                    context: context,
                    selectedText: "选中片段",
                    surroundingText: "上下文片段",
                    mode: .shorten,
                    style: style,
                    template: $0
                )
            },
            pair(.writingAdvisor) { NativePrompts.writingAdvisor(context: context, style: style, template: $0) },
            pair(.draftSelfCheck) { NativePrompts.draftSelfCheck(context: context, style: style, template: $0) },
            pair(.pitfallSummary) {
                NativePrompts.summarizePitfalls(
                    issues: [(reviewID: 1, dimension: "开头", problem: "铺垫过长")],
                    style: style,
                    template: $0
                )
            },
            pair(.editPreferenceSummary) {
                NativePrompts.summarizeEditPreferences(records: [makeEditRecord()], style: style, template: $0)
            },
            pair(.readerPerspective) { NativePrompts.readerPerspective(context: context, style: style, template: $0) },
            pair(.prePublishAudit) { NativePrompts.prePublishAudit(context: context, style: style, template: $0) },
            pair(.candidateJudge) {
                NativePrompts.judgeDraftCandidates(
                    context: context,
                    base: DraftSnapshot(title: "原稿", summary: "原摘要", content: "原正文"),
                    candidates: [DraftCandidate(index: 1, label: "更克制", title: "候选", summary: "摘要", content: "正文")],
                    style: style,
                    template: $0
                )
            },
            pair(.agentDecision) {
                NativePrompts.agentDecision(state: state, availableActions: [.writingReview, .finish], template: $0)
            }
        ].map { (key: $0.0, viaNil: $0.1, viaTemplate: $0.2) }
    }

    // MARK: - 守卫

    func testDefaultPromptTemplatesCoverAllKeys() {
        let seeded = NativePrompts.defaultPromptTemplates().map(\.key)
        XCTAssertEqual(
            Set(seeded),
            Set(PromptTemplateKey.allCases),
            "每个 PromptTemplateKey 都必须有内置模板：漏一个，建库时它就不进 prompt_templates，线上取不到模板"
        )
        XCTAssertEqual(seeded.count, Set(seeded).count, "同一个 key 不能有两个种子")
    }

    func testEveryKeyIsCovered() {
        XCTAssertEqual(
            Set(renderedPairs().map(\.key)),
            Set(PromptTemplateKey.allCases),
            "新增 prompt key 时必须在 renderedPairs() 里补一行，否则它逃过下面两条守卫"
        )
    }

    /// 核心守卫：不传模板与传内置模板必须产出逐字相同的消息——也就是不存在第二份文案。
    func testInlinePathRendersTheSameTextAsTheBuiltInTemplate() {
        for pair in renderedPairs() {
            XCTAssertEqual(
                pair.viaNil.map(\.role) + pair.viaNil.map(\.content),
                pair.viaTemplate.map(\.role) + pair.viaTemplate.map(\.content),
                "\(pair.key.rawValue)：兜底路径与内置模板文案不一致，说明又出现了第二份 prompt"
            )
        }
    }

    func testRenderedPromptsLeaveNoUnresolvedPlaceholders() {
        for pair in renderedPairs() {
            for message in pair.viaTemplate {
                XCTAssertFalse(
                    message.content.contains("{{"),
                    "\(pair.key.rawValue)：渲染后仍有未替换的占位符，模板用了调用方没提供的变量：\(unresolved(in: message.content))"
                )
            }
        }
    }

    private func unresolved(in text: String) -> [String] {
        text.components(separatedBy: "{{").dropFirst().compactMap { chunk in
            chunk.components(separatedBy: "}}").first.map { "{{\($0)}}" }
        }
    }

    // MARK: - 夹具

    private func makeStyle() -> StyleProfile {
        StyleProfile(
            id: 1,
            name: "测试风格",
            language_style: "中文",
            tone: "克制",
            structure_preference: "先场景后观察",
            favorite_expressions: "",
            forbidden_expressions: "不要标题党",
            sample_texts: [],
            title_style_like: nil,
            title_style_dislike: nil,
            is_default: 1
        )
    }

    private func makeContext() -> ContextPackage {
        ContextPackage(
            stage: "初稿阶段",
            title: "标题",
            summary: "摘要",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "大纲",
            content_excerpt: "正文",
            materials_excerpt: "素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 2,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
    }

    private func makeTopic() -> TopicPayload {
        TopicPayload(
            title: "选题标题",
            direction: "情感文学",
            core_viewpoint: "核心观点",
            target_reader: "目标读者",
            description: "选题说明",
            angle: "推荐角度",
            emotion: "克制",
            score: 4,
            status: "待写",
            tags: ["标签"]
        )
    }

    private func makeReview() -> WritingReview {
        WritingReview(
            id: 1,
            article_id: nil,
            title_snapshot: "旧标题",
            summary: "旧诊断",
            overall_score: 70,
            strengths: [],
            issues: [
                WritingReviewIssue(dimension: "开头", severity: "中", excerpt: nil, problem: "铺垫过长", suggestion: "直接进场景")
            ],
            revision_plan: [],
            training_focus: [],
            style_notes: []
        )
    }

    private func makeEditRecord() -> EditRecord {
        EditRecord(
            id: 1,
            article_id: 1,
            draft_version_id: 1,
            title_snapshot: "第一篇",
            added_characters: 20,
            removed_characters: 120,
            base_characters: 800,
            edit_ratio: 0.18,
            edit_level: "heavy",
            diff_summary: "removed_examples=- 总之我们要向前看",
            created_at: nil
        )
    }
}
