import XCTest
@testable import CreativeWorkshopCore

/// 内置 prompt 只有一份文案（PRD 24.11 / P2-6）。
///
/// 修复前每个工作流有两份：`defaultPromptTemplates()` 里的模板，和 `template == nil` 时才走的
/// 内联字符串。而建库时模板一定被 seed 进 `prompt_templates`、`promptTemplate(for:)` 一定命中，
/// 线上跑的永远是模板那份——内联那份在生产路径上执行不到，改它没有任何效果，测试还是绿的。
/// 两份文案也确实已经漂移（内联版给写作诊断带了作者样本，模板版没有）。
///
/// 这四条守卫锁的就是"不许再长出第二份"：
/// 1. 每个 key 都有种子（新加 key 忘了写模板 → 线上发空 prompt）
/// 2. 传 nil 与传内置模板必须逐字相同（谁再插一个内联分支，这条立刻红）
/// 3. 渲染后不许残留 `{{变量}}`（种子用了函数没提供的变量 → 占位符原样发给模型）
/// 4. 调用参数必须真的出现在渲染结果里（见 `mustContain`）
///
/// 第 4 条是补上的（后续复审）：前三条对"参数收下就扔"这一类是隐形的——`agentDecision`
/// 的 `correctionNote` 就这样被丢了，两条路径渲染结果一致、占位符也没残留，三条全绿。
final class PromptTemplateSingleSourceTests: XCTestCase {
    // MARK: - 各 key 的调用（新增 key 时这里必须补一行，否则 testEveryKeyIsCovered 会红）

    private struct RenderedCase {
        let key: PromptTemplateKey
        let viaNil: [ChatMessage]
        let viaTemplate: [ChatMessage]
        /// 这次调用传进去的、必须出现在渲染结果里的值（哨兵）。夹具刻意用"哨兵…"这种
        /// 不会和模板固定文案撞车的字符串，撞上了就说明是真的透传过去的。
        let mustContain: [String]
    }

    /// 返回每个 key 的两条渲染路径与该次调用的哨兵。
    private func renderedPairs() -> [RenderedCase] {
        let style = makeStyle()
        let context = makeContext()
        let topic = makeTopic()
        let review = makeReview()
        let state = AgentSessionState(
            idea: Sentinel.sessionIdea,
            direction: "情感文学",
            materials: "素材若干",
            style: style,
            title: "会话标题",
            content: "会话正文",
            outline: "会话大纲",
            callBudget: 12
        )

        func pair(
            _ key: PromptTemplateKey,
            mustContain: [String],
            _ make: (PromptTemplate?) -> [ChatMessage]
        ) -> RenderedCase {
            RenderedCase(
                key: key,
                viaNil: make(nil),
                viaTemplate: make(NativePrompts.defaultTemplate(key)),
                mustContain: mustContain
            )
        }

        return [
            pair(.topics, mustContain: [Sentinel.idea, Sentinel.direction, Sentinel.materials]) {
                NativePrompts.topics(context: context, style: style, template: $0)
            },
            pair(.outline, mustContain: [Sentinel.topicTitle, Sentinel.topicAngle, Sentinel.materials]) {
                NativePrompts.outline(topic: topic, context: context, style: style, template: $0)
            },
            pair(.draft, mustContain: [Sentinel.topicTitle, Sentinel.outline, Sentinel.materials]) {
                NativePrompts.draft(topic: topic, context: context, style: style, template: $0)
            },
            // context_json 会把整个 context 塞进去，所以这里只用不在 context 里的值当哨兵：
            // 独立的 content 参数、以及 mode 推导出来的 polish_goal。
            pair(.polishDraft, mustContain: [Sentinel.polishContent, PolishMode.natural.promptInstruction]) {
                NativePrompts.polishDraft(context: context, content: Sentinel.polishContent, mode: .natural, style: style, template: $0)
            },
            pair(.writingReview, mustContain: [Sentinel.title, Sentinel.content, Sentinel.previousIssue]) {
                NativePrompts.writingReview(context: context, style: style, previousReview: review, template: $0)
            },
            pair(.publishAssets, mustContain: [Sentinel.title, Sentinel.summary, Sentinel.content]) {
                NativePrompts.publishAssets(context: context, style: style, template: $0)
            },
            pair(.rewriteSelection, mustContain: [Sentinel.selectedText, Sentinel.surroundingText, Sentinel.rewriteInstruction]) {
                NativePrompts.rewriteSelection(
                    context: context,
                    selectedText: Sentinel.selectedText,
                    surroundingText: Sentinel.surroundingText,
                    mode: .shorten,
                    customInstruction: Sentinel.rewriteInstruction,
                    style: style,
                    template: $0
                )
            },
            pair(.writingAdvisor, mustContain: [Sentinel.idea, Sentinel.content]) {
                NativePrompts.writingAdvisor(context: context, style: style, template: $0)
            },
            pair(.draftSelfCheck, mustContain: [Sentinel.title, Sentinel.outline, Sentinel.idea, Sentinel.content]) {
                NativePrompts.draftSelfCheck(context: context, style: style, template: $0)
            },
            pair(.pitfallSummary, mustContain: [Sentinel.pitfallProblem]) {
                NativePrompts.summarizePitfalls(
                    issues: [(reviewID: 1, dimension: "开头", problem: Sentinel.pitfallProblem)],
                    style: style,
                    template: $0
                )
            },
            pair(.editPreferenceSummary, mustContain: [Sentinel.editRecordTitle]) {
                NativePrompts.summarizeEditPreferences(records: [makeEditRecord()], style: style, template: $0)
            },
            pair(.readerPerspective, mustContain: [Sentinel.title, Sentinel.summary, Sentinel.content]) {
                NativePrompts.readerPerspective(context: context, style: style, template: $0)
            },
            pair(.prePublishAudit, mustContain: [Sentinel.title, Sentinel.summary, Sentinel.content]) {
                NativePrompts.prePublishAudit(context: context, style: style, template: $0)
            },
            pair(.candidateJudge, mustContain: [Sentinel.baseDraft, Sentinel.candidateDraft]) {
                NativePrompts.judgeDraftCandidates(
                    context: context,
                    base: DraftSnapshot(title: "原稿", summary: "原摘要", content: Sentinel.baseDraft),
                    candidates: [DraftCandidate(index: 1, label: "更克制", title: "候选", summary: "摘要", content: Sentinel.candidateDraft)],
                    style: style,
                    template: $0
                )
            },
            // `correctionNote` 就是被丢掉的那个参数：越界重试时它没进 prompt，重试与上一轮
            // 逐字节相同，模型复读同一个越界动作，会话以 invalidDecision 停机。
            pair(.agentDecision, mustContain: [Sentinel.sessionIdea, Sentinel.correctionNote]) {
                NativePrompts.agentDecision(
                    state: state,
                    availableActions: [.writingReview, .finish],
                    correctionNote: Sentinel.correctionNote,
                    template: $0
                )
            }
        ]
    }

    /// 刻意选"不会和模板固定文案撞车"的字符串：撞上了就证明是真的透传过去的，
    /// 而不是模板自己的措辞碰巧长得像。
    private enum Sentinel {
        static let idea = "哨兵想法A1"
        static let direction = "哨兵方向B2"
        static let content = "哨兵正文C3"
        static let materials = "哨兵素材D4"
        static let outline = "哨兵大纲E5"
        static let title = "哨兵标题F6"
        static let summary = "哨兵摘要G7"
        static let topicTitle = "哨兵选题H8"
        static let topicAngle = "哨兵角度L12"
        static let previousIssue = "哨兵历史问题M13"
        static let editRecordTitle = "哨兵文章N14"
        static let selectedText = "哨兵选中O15"
        static let surroundingText = "哨兵上下文P16"
        static let rewriteInstruction = "哨兵改写要求W23"
        static let baseDraft = "哨兵原稿Q17"
        static let candidateDraft = "哨兵候选R18"
        static let sessionIdea = "哨兵会话想法S19"
        static let correctionNote = "哨兵纠正T20"
        static let polishContent = "哨兵润色正文U21"
        static let pitfallProblem = "哨兵雷区V22"
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

    /// 第四条守卫：调用参数必须真的进 `variables`。
    ///
    /// 前三条对"参数收下就扔"是隐形的——两条路径都丢，渲染结果照样逐字相同；种子里没有对应
    /// 占位符，也不会留下 `{{}}`。`agentDecision` 的 `correctionNote` 就是这样被丢了整整两章。
    func testEveryCallArgumentReachesTheRenderedPrompt() {
        for renderedCase in renderedPairs() {
            let rendered = renderedCase.viaTemplate.map(\.content).joined(separator: "\n")
            for sentinel in renderedCase.mustContain {
                XCTAssertTrue(
                    rendered.contains(sentinel),
                    "\(renderedCase.key.rawValue)：传进去的「\(sentinel)」没有出现在 prompt 里，说明这个参数被丢了"
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
            title: Sentinel.title,
            summary: Sentinel.summary,
            idea: Sentinel.idea,
            direction: Sentinel.direction,
            outline_excerpt: Sentinel.outline,
            content_excerpt: Sentinel.content,
            materials_excerpt: Sentinel.materials,
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
            title: Sentinel.topicTitle,
            direction: Sentinel.direction,
            core_viewpoint: "核心观点",
            target_reader: "目标读者",
            description: "选题说明",
            angle: Sentinel.topicAngle,
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
                WritingReviewIssue(dimension: "开头", severity: "中", excerpt: nil, problem: Sentinel.previousIssue, suggestion: "直接进场景")
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
            title_snapshot: Sentinel.editRecordTitle,
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
