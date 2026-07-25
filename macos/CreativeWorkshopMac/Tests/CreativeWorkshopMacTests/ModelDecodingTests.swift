import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

final class ModelDecodingTests: XCTestCase {
    func testTopicPayloadDecodesFlexibleScoreAndTags() throws {
        let data = """
        {
          "title": "一个选题",
          "direction": "情感文学",
          "score": "5",
          "tags": "成都，长期主义、写作"
        }
        """.data(using: .utf8)!

        let topic = try JSONDecoder().decode(TopicPayload.self, from: data)

        XCTAssertEqual(topic.title, "一个选题")
        XCTAssertEqual(topic.score, 5)
        XCTAssertEqual(topic.tags, ["成都", "长期主义", "写作"])
    }

    func testWritingReviewResultDecodesStructuredCoachFeedback() throws {
        let data = """
        {
          "summary": "文章方向清楚，但开头还需要更具体。",
          "overall_score": 76,
          "strengths": ["观点明确"],
          "issues": [
            {
              "dimension": "开头",
              "severity": "中",
              "excerpt": "我想说的是",
              "problem": "进入太抽象。",
              "suggestion": "先写一个具体场景。"
            }
          ],
          "revision_plan": ["补开头", "理结构"],
          "training_focus": ["场景化表达"],
          "style_notes": ["语气保持克制"]
        }
        """.data(using: .utf8)!

        let review = try JSONDecoder().decode(WritingReviewResult.self, from: data)

        XCTAssertEqual(review.overall_score, 76)
        XCTAssertEqual(review.issues?.first?.dimension, "开头")
        XCTAssertEqual(review.training_focus, ["场景化表达"])
        XCTAssertNil(review.pitfall_hits)
    }

    /// 诊断 JSON 含 pitfall_hits 字段（模型显式命中作者雷区，PRD 22.4.3）时应可解码。
    func testWritingReviewResultDecodesWithPitfallHits() throws {
        let data = """
        {
          "summary": "结构清楚，但再次出现了作者常见雷区。",
          "overall_score": 80,
          "strengths": ["观点明确"],
          "issues": [],
          "revision_plan": ["调整结尾"],
          "training_focus": ["结尾克制"],
          "style_notes": [],
          "pitfall_hits": ["少用金句收束"]
        }
        """.data(using: .utf8)!

        let review = try JSONDecoder().decode(WritingReviewResult.self, from: data)

        XCTAssertEqual(review.pitfall_hits, ["少用金句收束"])
    }

    func testWritingReviewPromptReadsContextPackageAndPreviousReview() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "初稿阶段",
            title: "诊断标题",
            summary: "诊断摘要",
            idea: "诊断想法",
            direction: "情感文学",
            outline_excerpt: "诊断大纲",
            content_excerpt: "诊断正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 4,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        let previous = WritingReview(
            id: 7,
            article_id: nil,
            title_snapshot: "旧标题",
            summary: "旧诊断",
            overall_score: 70,
            strengths: [],
            issues: [
                WritingReviewIssue(
                    dimension: "开头",
                    severity: "中",
                    excerpt: nil,
                    problem: "旧问题需要核销",
                    suggestion: "补一个场景"
                )
            ],
            revision_plan: ["补场景"],
            training_focus: [],
            style_notes: [],
            raw_output: nil,
            model: nil,
            created_at: nil,
            resolved_from_last: [],
            reviewed_snapshot: nil
        )

        let messages = NativePrompts.writingReview(context: context, style: style, previousReview: previous)
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("诊断标题"))
        XCTAssertTrue(prompt.contains("诊断摘要"))
        XCTAssertTrue(prompt.contains("诊断想法"))
        XCTAssertTrue(prompt.contains("诊断大纲"))
        XCTAssertTrue(prompt.contains("诊断正文"))
        XCTAssertTrue(prompt.contains("旧问题需要核销"))
        XCTAssertTrue(prompt.contains("resolved_from_last"))
    }

    func testPublishAssetsResultDecodesFlexibleTags() throws {
        let data = """
        {
          "summary": "摘要",
          "cover_text": "封面",
          "moments_text": "朋友圈",
          "tags": "写作，公众号、个人表达",
          "xiaohongshu_text": "小红书",
          "cover_image_prompt": "封面图提示词"
        }
        """.data(using: .utf8)!

        let assets = try JSONDecoder().decode(PublishAssetsResult.self, from: data)

        XCTAssertEqual(assets.summary, "摘要")
        XCTAssertEqual(assets.tags, ["写作", "公众号", "个人表达"])
        XCTAssertEqual(assets.cover_image_prompt, "封面图提示词")
    }

    func testRewriteResultDecodesReplacement() throws {
        let data = """
        {
          "replacement": "改写后的片段",
          "note": "更自然"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(RewriteResult.self, from: data)

        XCTAssertEqual(result.replacement, "改写后的片段")
        XCTAssertEqual(result.note, "更自然")
    }

    func testRewriteFallbackCanShortenSelectedText() {
        let result = NativeFallbacks.rewriteSelection(
            selectedText: "第一句需要保留。第二句也很重要。第三句可以先删掉。",
            mode: .shorten
        )

        XCTAssertEqual(result.replacement, "第一句需要保留。第二句也很重要。")
        XCTAssertEqual(result.note, "删去重复和铺垫，保留主干意思。")
    }

    func testRewriteSelectionPromptReadsContextPackage() {
        let style = StyleProfile(
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
        var context = ContextPackage(
            stage: "局部改写阶段",
            title: "上下文标题",
            summary: "上下文摘要",
            idea: "上下文想法",
            direction: "情感文学",
            outline_excerpt: "上下文大纲",
            content_excerpt: "上下文正文",
            materials_excerpt: "上下文素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 20,
            paragraph_count: 1,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        context.learned_preferences = ["少用宏大判断"]

        let prompt = NativePrompts.rewriteSelection(
            context: context,
            selectedText: "需要改写的片段",
            surroundingText: "片段前后的上下文",
            mode: .natural,
            style: style
        ).last?.content ?? ""

        XCTAssertTrue(prompt.contains("上下文标题"))
        XCTAssertTrue(prompt.contains("上下文正文"))
        XCTAssertTrue(prompt.contains("上下文素材"))
        XCTAssertTrue(prompt.contains("少用宏大判断"))
        XCTAssertTrue(prompt.contains("需要改写的片段"))
        XCTAssertTrue(prompt.contains("片段前后的上下文"))
    }

    func testTextDiffReportsAddedAndRemovedLines() {
        let before = """
        第一段
        第二段旧
        第三段
        """
        let after = """
        第一段
        第二段新
        第三段
        第四段
        """

        let summary = TextDiff.summary(before: before, after: after)
        let lines = TextDiff.lines(before: before, after: after)

        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.removed, 1)
        XCTAssertTrue(lines.contains { $0.kind == .removed && $0.text == "第二段旧" })
        XCTAssertTrue(lines.contains { $0.kind == .added && $0.text == "第四段" })
    }

    func testWritingAdvisorResultDecodesSuggestedActions() throws {
        let data = """
        {
          "stage": "初稿阶段",
          "main_problem": "正文还缺少具体场景。",
          "next_action": "先做写作诊断。",
          "reason": "短稿不适合直接润色。",
          "suggested_actions": ["writing_review", "rewrite_selection_expand"],
          "focus_area": "场景化表达",
          "context_findings": ["已有正文但缺少具体场景"],
          "execution_plan": ["先诊断", "再扩写关键段落"],
          "risk_notes": ["直接润色会掩盖内容不足"]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(WritingAdvisorResult.self, from: data)

        XCTAssertEqual(result.stage, "初稿阶段")
        XCTAssertEqual(result.suggested_actions, ["writing_review", "rewrite_selection_expand"])
        XCTAssertEqual(result.context_findings, ["已有正文但缺少具体场景"])
        XCTAssertEqual(result.execution_plan?.last, "再扩写关键段落")
        XCTAssertEqual(result.risk_notes, ["直接润色会掩盖内容不足"])
        XCTAssertEqual(AdvisorAction(rawValue: result.suggested_actions?.first ?? ""), .writingReview)
    }

    func testWritingContextBuilderInfersOutlineStage() {
        let context = WritingContextBuilder().build(
            title: "一个标题",
            summary: "",
            content: "",
            outline: "## 开头\n从一个场景开始。",
            idea: "一个想法",
            direction: "情感文学",
            materials: "素材",
            style: StyleProfile(
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
            ),
            selectedTopic: nil,
            recentArticles: [],
            recentReviews: [],
            ideas: []
        )

        XCTAssertEqual(context.stage, "大纲阶段")
        XCTAssertEqual(context.paragraph_count, 0)
        XCTAssertTrue(context.style_brief.contains("克制"))
    }

    /// 回归：素材是逐条累加的，此前按 1000 字掐尾截断——作者最后加进来的素材最先消失，
    /// 且界面无提示。现在保留头尾并显式写明省略了多少字。
    func testWritingContextBuilderKeepsTailOfLongMaterials() {
        let head = String(repeating: "头", count: 2_000)
        let tail = String(repeating: "尾", count: 2_000)
        let context = WritingContextBuilder().build(
            title: "标题",
            summary: "",
            content: "",
            outline: "",
            idea: "想法",
            direction: "情感文学",
            materials: head + tail,
            style: StyleProfile(
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
            ),
            selectedTopic: nil,
            recentArticles: [],
            recentReviews: [],
            ideas: []
        )

        XCTAssertTrue(context.materials_excerpt.hasPrefix("头"), "开头素材应保留")
        XCTAssertTrue(context.materials_excerpt.hasSuffix("尾"), "结尾素材不能再被掐掉")
        XCTAssertTrue(context.materials_excerpt.contains("此处省略中间"), "省略应显式标注，不能静默丢弃")
    }

    func testWritingAdvisorFallbackSuggestsDraftFromOutline() {
        let context = ContextPackage(
            stage: "大纲阶段",
            title: "标题",
            summary: "",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "## 开头",
            content_excerpt: "",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let result = NativeFallbacks.writingAdvisor(context: context)

        XCTAssertEqual(result.suggested_actions, ["draft_from_outline"])
        XCTAssertEqual(result.focus_area, "从结构进入完整表达")
        XCTAssertFalse(result.context_findings?.isEmpty ?? true)
        XCTAssertFalse(result.execution_plan?.isEmpty ?? true)
        XCTAssertFalse(result.risk_notes?.isEmpty ?? true)
    }

    func testPromptTemplatePathReceivesAgentDiscipline() {
        let style = StyleProfile(
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
        let template = PromptTemplate(
            id: 1,
            key: PromptTemplateKey.draft.rawValue,
            name: "自定义大纲成稿",
            system_prompt: "system {{style_name}}",
            user_template: "draft {{topic_title}} {{outline}} {{materials}}",
            is_default: 1,
            updated_at: nil,
            created_at: nil
        )
        let topic = TopicPayload(
            title: "测试选题",
            direction: "情感文学",
            core_viewpoint: nil,
            target_reader: nil,
            description: nil,
            angle: nil,
            emotion: nil,
            score: nil,
            status: nil,
            tags: nil
        )
        let context = ContextPackage(
            stage: "大纲阶段",
            title: "",
            summary: "",
            idea: "",
            direction: "情感文学",
            outline_excerpt: "大纲",
            content_excerpt: "",
            materials_excerpt: "一个素材",
            selected_topic_title: topic.title,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let messages = NativePrompts.draft(
            topic: topic,
            context: context,
            style: style,
            template: template
        )

        XCTAssertEqual(messages.first?.content, "system 测试风格")
        XCTAssertTrue(messages.last?.content.contains("代理式工作纪律") == true)
        XCTAssertTrue(messages.last?.content.contains("本轮模式：完整初稿") == true)
        XCTAssertTrue(messages.last?.content.contains("JSON 纪律") == true)
    }

    func testPlanningPromptsReadContextPackage() {
        let style = StyleProfile(
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
        let topic = TopicPayload(
            title: "上下文选题",
            direction: "情感文学",
            core_viewpoint: "核心观点",
            target_reader: "目标读者",
            description: "一句话说明",
            angle: "推荐角度",
            emotion: nil,
            score: nil,
            status: nil,
            tags: nil
        )
        var context = ContextPackage(
            stage: "构思阶段",
            title: "",
            summary: "",
            idea: "上下文想法",
            direction: "情感文学",
            outline_excerpt: "上下文大纲",
            content_excerpt: "",
            materials_excerpt: "上下文素材",
            selected_topic_title: topic.title,
            selected_topic_summary: topic.description,
            style_name: "测试风格",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        context.learned_preferences = ["少用宏大判断"]

        let topicsPrompt = NativePrompts.topics(context: context, style: style).last?.content ?? ""
        let outlinePrompt = NativePrompts.outline(topic: topic, context: context, style: style).last?.content ?? ""
        let draftPrompt = NativePrompts.draft(topic: topic, context: context, style: style).last?.content ?? ""
        let brief = WritingBriefResult(
            working_title: "工作标题",
            core_question: "核心问题",
            thesis: "核心主张",
            target_reader: nil,
            emotional_center: nil,
            material_strategy: nil,
            structure_plan: nil,
            must_keep: nil,
            avoid: nil,
            raw_output: nil
        )
        let argument = ArgumentCheckResult(
            thesis_strength: "可写",
            weak_points: [],
            missing_evidence: [],
            revision_directives: [],
            ready_to_draft: true,
            raw_output: nil
        )
        let sections = SectionDraftResult(
            title: "分段标题",
            sections: [DraftSection(heading: "开头", content: "分段内容", self_check: nil)],
            raw_output: nil
        )
        let briefPrompt = NativePrompts.writingBrief(context: context, style: style).last?.content ?? ""
        let argumentPrompt = NativePrompts.argumentCheck(brief: brief, context: context, style: style).last?.content ?? ""
        let critiquePrompt = NativePrompts.draftCritique(brief: brief, argumentCheck: argument, sectionDraft: sections, context: context, style: style).last?.content ?? ""

        XCTAssertTrue(topicsPrompt.contains("上下文想法"))
        XCTAssertTrue(topicsPrompt.contains("上下文素材"))
        XCTAssertTrue(outlinePrompt.contains("上下文素材"))
        XCTAssertTrue(outlinePrompt.contains("上下文选题"))
        XCTAssertTrue(draftPrompt.contains("上下文大纲"))
        XCTAssertTrue(draftPrompt.contains("上下文素材"))
        XCTAssertTrue(briefPrompt.contains("上下文想法"))
        XCTAssertTrue(briefPrompt.contains("少用宏大判断"))
        XCTAssertTrue(argumentPrompt.contains("上下文素材"))
        XCTAssertTrue(argumentPrompt.contains("少用宏大判断"))
        XCTAssertTrue(critiquePrompt.contains("上下文素材"))
        XCTAssertTrue(critiquePrompt.contains("少用宏大判断"))
    }

    func testAdvisorTemplateKeepsOutputContractAndAgentDiscipline() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "初稿阶段",
            title: "标题",
            summary: "",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "",
            word_count: 200,
            paragraph_count: 3,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        let template = PromptTemplate(
            id: 2,
            key: PromptTemplateKey.writingAdvisor.rawValue,
            name: "自定义智能下一步",
            system_prompt: "advisor",
            user_template: "context {{context_json}}",
            is_default: 1,
            updated_at: nil,
            created_at: nil
        )

        let messages = NativePrompts.writingAdvisor(context: context, style: style, template: template)
        let userPrompt = messages.last?.content ?? ""

        XCTAssertTrue(userPrompt.contains("context_findings"))
        XCTAssertTrue(userPrompt.contains("execution_plan"))
        XCTAssertTrue(userPrompt.contains("risk_notes"))
        XCTAssertTrue(userPrompt.contains("代理式工作纪律"))
        XCTAssertTrue(userPrompt.contains("本轮模式：智能下一步"))
    }

    func testReaderPerspectivePromptReadsContextPackage() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "初稿阶段",
            title: "上下文里的标题",
            summary: "上下文里的摘要",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "上下文里的正文段落",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 10,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let messages = NativePrompts.readerPerspective(context: context, style: style)
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("上下文里的标题"))
        XCTAssertTrue(prompt.contains("上下文里的摘要"))
        XCTAssertTrue(prompt.contains("上下文里的正文段落"))
        XCTAssertTrue(prompt.contains("本轮模式：读者模拟"))
    }

    func testDraftSelfCheckPromptReadsContextPackage() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "初稿阶段",
            title: "自检标题",
            summary: "",
            idea: "自检想法",
            direction: "情感文学",
            outline_excerpt: "自检大纲",
            content_excerpt: "自检正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 4,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let messages = NativePrompts.draftSelfCheck(context: context, style: style)
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("自检标题"))
        XCTAssertTrue(prompt.contains("自检想法"))
        XCTAssertTrue(prompt.contains("自检大纲"))
        XCTAssertTrue(prompt.contains("自检正文"))
        XCTAssertTrue(prompt.contains("本轮模式：生成后自检"))
    }

    func testPrePublishAuditPromptReadsContextPackage() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "发表前终审",
            title: "终审标题",
            summary: "终审摘要",
            idea: "",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "终审正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 4,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let messages = NativePrompts.prePublishAudit(context: context, style: style)
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("终审标题"))
        XCTAssertTrue(prompt.contains("终审摘要"))
        XCTAssertTrue(prompt.contains("终审正文"))
        XCTAssertTrue(prompt.contains("本轮模式：发表前终审"))
    }

    func testPublishAssetsPromptReadsContextPackage() {
        let style = StyleProfile(
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
        let context = ContextPackage(
            stage: "发布准备",
            title: "发布标题",
            summary: "发布摘要",
            idea: "",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "发布正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 4,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let messages = NativePrompts.publishAssets(context: context, style: style)
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("发布标题"))
        XCTAssertTrue(prompt.contains("发布摘要"))
        XCTAssertTrue(prompt.contains("发布正文"))
        XCTAssertTrue(prompt.contains("本轮模式：发布物料"))
    }

    func testAgentDraftResultsDecodeAndFallbackPipelineProducesDraft() throws {
        let briefData = """
        {
          "working_title": "从一个真实问题写起",
          "core_question": "为什么这件事值得写？",
          "thesis": "文章要先回答真实问题，而不是先追求完整。",
          "target_reader": "正在写公众号的人",
          "emotional_center": "克制",
          "material_strategy": ["素材先放在开头"],
          "structure_plan": [
            {"heading": "开头", "purpose": "提出问题", "key_points": ["场景"], "material_hint": "素材"}
          ],
          "must_keep": ["真实表达"],
          "avoid": ["标题党"]
        }
        """.data(using: .utf8)!

        let brief = try JSONDecoder().decode(WritingBriefResult.self, from: briefData)
        let check = NativeFallbacks.argumentCheck(brief: brief, materials: "一个素材")
        let context = ContextPackage(
            stage: "想法阶段",
            title: "",
            summary: "",
            idea: "一个想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "",
            materials_excerpt: "一个素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        let sections = NativeFallbacks.sectionDraft(brief: brief, argumentCheck: check, context: context)
        let critique = NativeFallbacks.draftCritique(brief: brief, argumentCheck: check, sectionDraft: sections, direction: "情感文学")
        let draft = critique.draftResult(fallbackTitle: "备用标题", fallbackContent: sections.markdown)

        XCTAssertEqual(brief.structure_plan?.first?.heading, "开头")
        XCTAssertFalse(check.revision_directives?.isEmpty ?? true)
        XCTAssertTrue(sections.markdown.contains("开头"))
        XCTAssertFalse(critique.critique_notes?.isEmpty ?? true)
        XCTAssertEqual(draft.title, "从一个真实问题写起")
    }

    /// 22.2.1：unresolved_gaps 是新增的可选字段，旧版模型/兜底返回的 JSON 里没有这个 key 也必须能正常解码。
    func testWritingBriefResultDecodesWithoutUnresolvedGapsForBackwardCompatibility() throws {
        let legacyData = """
        {
          "working_title": "旧版 brief",
          "core_question": "旧问题"
        }
        """.data(using: .utf8)!

        let brief = try JSONDecoder().decode(WritingBriefResult.self, from: legacyData)

        XCTAssertEqual(brief.working_title, "旧版 brief")
        XCTAssertNil(brief.unresolved_gaps)
    }

    func testWritingBriefResultDecodesUnresolvedGapsWhenPresent() throws {
        let data = """
        {
          "working_title": "修订后的 brief",
          "unresolved_gaps": ["缺一段亲历的具体场景"]
        }
        """.data(using: .utf8)!

        let brief = try JSONDecoder().decode(WritingBriefResult.self, from: data)

        XCTAssertEqual(brief.unresolved_gaps, ["缺一段亲历的具体场景"])
    }

    func testNativeFallbackBriefRevisionKeepsBriefAndFillsUnresolvedGaps() {
        let brief = WritingBriefResult(
            working_title: "原标题",
            core_question: "原问题",
            thesis: "原主张",
            target_reader: nil,
            emotional_center: nil,
            material_strategy: nil,
            structure_plan: nil,
            must_keep: nil,
            avoid: nil,
            raw_output: nil
        )
        let check = ArgumentCheckResult(
            thesis_strength: "偏弱",
            weak_points: [],
            missing_evidence: ["缺一段亲历的具体场景"],
            revision_directives: [],
            ready_to_draft: false,
            raw_output: nil
        )

        let revised = NativeFallbacks.briefRevision(brief: brief, argumentCheck: check)

        XCTAssertEqual(revised.working_title, "原标题")
        XCTAssertEqual(revised.core_question, "原问题")
        XCTAssertEqual(revised.unresolved_gaps, ["缺一段亲历的具体场景"])
    }

    func testSectionFragmentContextsFollowBriefSections() {
        let brief = WritingBriefResult(
            working_title: "成都的慢",
            core_question: nil,
            thesis: nil,
            target_reader: nil,
            emotional_center: nil,
            material_strategy: nil,
            structure_plan: [
                WritingBriefSection(
                    heading: "茶馆里的慢",
                    purpose: "用成都茶馆场景打开文章",
                    key_points: ["慢下来", "具体场景"],
                    material_hint: "喝茶聊天"
                )
            ],
            must_keep: nil,
            avoid: nil,
            raw_output: nil
        )
        let fragments = [
            Fragment(
                id: 1,
                source_type: "idea",
                source_id: 10,
                title: "成都茶馆",
                content: "在成都第一次被陌生人邀着喝茶聊天，才发现关系不是马上交换资源。",
                keywords: FragmentRetriever.keywords(for: "成都 茶馆 喝茶 聊天 慢下来"),
                created_at: nil,
                updated_at: nil
            )
        ]

        let contexts = FragmentRetriever.sectionContexts(for: brief, fragments: fragments)

        XCTAssertEqual(contexts.first?.section_index, 1)
        XCTAssertEqual(contexts.first?.heading, "茶馆里的慢")
        XCTAssertEqual(contexts.first?.fragments.first?.citationTitle, "成都茶馆")
    }

    func testSectionDraftPromptIncludesSectionFragments() {
        let style = StyleProfile(
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
        let brief = WritingBriefResult(
            working_title: "成都的慢",
            core_question: nil,
            thesis: nil,
            target_reader: nil,
            emotional_center: nil,
            material_strategy: nil,
            structure_plan: [
                WritingBriefSection(
                    heading: "茶馆里的慢",
                    purpose: "用真实场景打开文章",
                    key_points: ["成都", "慢下来"],
                    material_hint: nil
                )
            ],
            must_keep: nil,
            avoid: nil,
            raw_output: nil
        )
        var context = ContextPackage(
            stage: "想法阶段",
            title: "",
            summary: "",
            idea: "写成都",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "",
            materials_excerpt: "已有材料",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        context.section_fragment_contexts = [
            SectionFragmentContext(
                section_index: 1,
                heading: "茶馆里的慢",
                query: "茶馆 慢下来",
                fragments: [
                    RetrievedFragment(
                        fragment_id: 1,
                        source_type: "idea",
                        source_id: 10,
                        title: "成都茶馆",
                        content: "在成都第一次被陌生人邀着喝茶聊天。",
                        score: 0.8
                    )
                ]
            )
        ]

        let messages = NativePrompts.sectionDraft(
            brief: brief,
            argumentCheck: ArgumentCheckResult(thesis_strength: "可写", weak_points: [], missing_evidence: [], revision_directives: [], ready_to_draft: true, raw_output: nil),
            context: context,
            style: style
        )
        let prompt = messages.last?.content ?? ""

        XCTAssertTrue(prompt.contains("按段检索到的个人素材"))
        XCTAssertTrue(prompt.contains("在成都第一次被陌生人邀着喝茶聊天"))
        XCTAssertTrue(prompt.contains("不要把 A 段素材挪作 B 段经历"))
    }

    func testPrePublishLocalVerifierFlagsUnmatchedQuotes() {
        let report = PrePublishAuditReport(
            passed: true,
            summary: "模型终审通过。",
            typo_issues: [],
            quote_issues: [],
            consistency_issues: [],
            pitfall_issues: [],
            raw_output: nil
        )
        let verified = PrePublishAuditLocalVerifier.verifyQuotes(
            in: report,
            content: "文中引用：“花谢花飞花满天，红消香断有谁怜。”",
            fragments: []
        )

        XCTAssertEqual(verified.passed, false)
        XCTAssertEqual(verified.quote_issues?.first?.excerpt, "花谢花飞花满天，红消香断有谁怜。")
        XCTAssertTrue(verified.summary?.contains("本地引文核对新增 1 条") ?? false)
    }

    func testPrePublishLocalVerifierAcceptsQuotesFoundInCorpus() {
        let report = PrePublishAuditReport(
            passed: true,
            summary: "模型终审通过。",
            typo_issues: [],
            quote_issues: [],
            consistency_issues: [],
            pitfall_issues: [],
            raw_output: nil
        )
        let fragments = [
            Fragment(
                id: 1,
                source_type: "article",
                source_id: 1,
                title: "红楼梦笔记",
                content: "原文摘录：花谢花飞花满天，红消香断有谁怜。",
                keywords: [],
                created_at: nil,
                updated_at: nil
            )
        ]

        let verified = PrePublishAuditLocalVerifier.verifyQuotes(
            in: report,
            content: "文中引用：“花谢花飞花满天，红消香断有谁怜。”",
            fragments: fragments
        )

        XCTAssertEqual(verified.passed, true)
        XCTAssertTrue(verified.quote_issues?.isEmpty ?? true)
    }

    /// 两段、每段远超 300 字下限、以句末标点收尾、不含套话的合格正文，供质量门测试复用。
    private func wellFormedDraftContent() -> String {
        let openingBody = String(repeating: "这是一段用于验证长度完整性检查的示例正文内容。", count: 20)
        let mainBody = String(repeating: "这里继续补充更多素材以确保超过长度下限的要求。", count: 20)
        return "## 开头\n\(openingBody)\n\n## 主体\n\(mainBody)"
    }

    func testAgentDraftQualityGatePassesCompleteTrace() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent()
        )

        XCTAssertEqual(gate?.items.count, 9)
        XCTAssertEqual(gate?.reviewCount, 0)
        XCTAssertTrue(gate?.summary.contains("通过") == true)
    }

    func testAgentDraftQualityGateFlagsWeakTrace() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "",
            thesis: "",
            targetReader: "目标读者",
            argumentDirectives: [],
            missingEvidence: ["缺少亲历场景"],
            sectionSummaries: ["只有一段"],
            critiqueNotes: []
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(
                has_concerns: true,
                flagged_excerpts: [FlaggedExcerpt(excerpt: "空泛表达", concern: "缺少证据")],
                raw_output: nil
            )
        )

        // 原有 5 项复核 + 未提供正文触发的“长度完整性”复核。
        XCTAssertEqual(gate?.items.count, 9)
        XCTAssertEqual(gate?.reviewCount, 6)
        XCTAssertTrue(gate?.summary.contains("建议复核") == true)
    }

    func testAgentDraftQualityGateFlagsUnresolvedGaps() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            unresolvedGaps: ["缺一段亲历的具体场景"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent()
        )

        XCTAssertEqual(gate?.items.count, 9)
        XCTAssertEqual(gate?.items.first { $0.title == "素材缺口" }?.status, .review)
        XCTAssertEqual(gate?.reviewCount, 1)
    }

    func testAgentDraftQualityGateStructureDeviationFlagsLargeGap() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 5
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent()
        )

        let item = gate?.items.first { $0.title == "结构偏差" }
        XCTAssertEqual(item?.status, .review)
        XCTAssertTrue(item?.detail.contains("偏差") == true)
    }

    func testAgentDraftQualityGateStructureDeviationPassesSmallGap() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent()
        )

        let item = gate?.items.first { $0.title == "结构偏差" }
        XCTAssertEqual(item?.status, .passed)
    }

    func testAgentDraftQualityGateLengthIntegrityFlagsShortOrTruncatedContent() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: "太短了，还没写完"
        )

        let item = gate?.items.first { $0.title == "长度完整性" }
        XCTAssertEqual(item?.status, .review)
        XCTAssertTrue(item?.detail.contains("下限") == true)
    }

    func testAgentDraftQualityGateLengthIntegrityPassesFullLengthProperlyEndedContent() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent()
        )

        let item = gate?.items.first { $0.title == "长度完整性" }
        XCTAssertEqual(item?.status, .passed)
    }

    func testAgentDraftQualityGatePitfallScanFlagsKnownPitfallAndCannedEnding() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let content = wellFormedDraftContent() + "\n\n愿我们都能被生活温柔以待。"

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: content,
            knownPitfalls: ["总喜欢用反问句强行升华"]
        )

        let item = gate?.items.first { $0.title == "雷区特征扫描" }
        XCTAssertEqual(item?.status, .review)
        XCTAssertTrue(item?.detail.contains("愿我们都") == true)
    }

    func testAgentDraftQualityGatePitfallScanPassesCleanContent() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 2
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: wellFormedDraftContent(),
            knownPitfalls: ["总喜欢用反问句强行升华"]
        )

        let item = gate?.items.first { $0.title == "雷区特征扫描" }
        XCTAssertEqual(item?.status, .passed)
    }

    /// PRD 22.2.2 回归测试：字段全填但正文只有两句话的劣质 trace，质量门必须出现 review 项。
    func testAgentDraftQualityGateFlagsShallowContentDespiteFullFields() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "核心问题",
            thesis: "核心主张",
            targetReader: "目标读者",
            argumentDirectives: ["开头落到场景"],
            missingEvidence: [],
            sectionSummaries: ["开头：完成", "主体：完成", "结尾：完成"],
            critiqueNotes: ["中段已收紧"],
            plannedSectionCount: 3
        )

        let gate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil),
            content: "今天天气不错。我出门散步了。"
        )

        XCTAssertEqual(gate?.reviewCount, 1)
        let lengthItem = gate?.items.first { $0.title == "长度完整性" }
        XCTAssertEqual(lengthItem?.status, .review)
    }

    func testReviewDrivenFallbackProducesFullDraftResult() {
        let context = ContextPackage(
            stage: "修改阶段",
            title: "一篇文章",
            summary: "",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "旧正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "",
            word_count: 20,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        let review = WritingReview(
            id: 1,
            article_id: nil,
            title_snapshot: "一篇文章",
            summary: "缺少场景",
            overall_score: 70,
            strengths: [],
            issues: [
                WritingReviewIssue(
                    dimension: "素材",
                    severity: "中",
                    excerpt: nil,
                    problem: "缺少具体场景",
                    suggestion: "补一个亲历场景"
                )
            ],
            revision_plan: ["先补场景"],
            training_focus: ["场景化表达"],
            style_notes: []
        )

        let result = NativeFallbacks.improveDraftFromReview(context: context, content: "旧正文", review: review)

        XCTAssertEqual(result.title, "一篇文章")
        XCTAssertTrue((result.content ?? "").contains("补一个亲历场景"))
        XCTAssertEqual(result.tags, ["情感文学", "诊断改稿"])
    }

    func testEditPreferenceFallbackFindsRepeatedEditPatterns() {
        let records = [
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
            ),
            EditRecord(
                id: 2,
                article_id: 2,
                draft_version_id: 2,
                title_snapshot: "第二篇",
                added_characters: 12,
                removed_characters: 90,
                base_characters: 700,
                edit_ratio: 0.14,
                edit_level: "heavy",
                diff_summary: "removed_examples=- 这就是生活给我们的启示",
                created_at: nil
            )
        ]

        let result = NativeFallbacks.summarizeEditPreferences(records: records)

        XCTAssertTrue((result.candidates ?? []).contains { $0.description.contains("删减") })
        XCTAssertEqual(result.candidates?.first?.source_edit_record_ids?.isEmpty, false)
        XCTAssertTrue(result.monthly_summary?.contains("轻改") == true)
    }

    func testCandidateJudgeFallbackSelectsMostCompleteCandidate() {
        let candidates = [
            DraftCandidate(index: 1, label: "短稿", title: "标题", summary: "", content: "短正文"),
            DraftCandidate(
                index: 2,
                label: "完整稿",
                title: "标题",
                summary: "",
                content: """
                第一段有具体场景。

                第二段推进观点。

                第三段收束。

                第四段补充余味。
                """
            )
        ]

        let result = NativeFallbacks.judgeDraftCandidates(candidates: candidates)

        XCTAssertEqual(result.best_candidate_index, 2)
        XCTAssertEqual(result.rankings.first?.candidate_index, 2)
        XCTAssertTrue(result.summary?.contains("本地评委") == true)
    }

    func testCandidateJudgePromptReadsContextPackage() {
        let style = StyleProfile(
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
        var context = ContextPackage(
            stage: "候选评审阶段",
            title: "候选上下文标题",
            summary: "候选上下文摘要",
            idea: "候选上下文想法",
            direction: "情感文学",
            outline_excerpt: "候选上下文大纲",
            content_excerpt: "候选上下文正文",
            materials_excerpt: "候选上下文素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 30,
            paragraph_count: 2,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        context.known_pitfalls = ["不要鸡汤式收束"]
        let base = DraftSnapshot(title: "原稿标题", summary: "原稿摘要", content: "原稿正文")
        let candidates = [
            DraftCandidate(index: 1, label: "版本一", title: "候选标题", summary: "候选摘要", content: "候选正文")
        ]

        let prompt = NativePrompts.judgeDraftCandidates(
            context: context,
            base: base,
            candidates: candidates,
            style: style
        ).last?.content ?? ""

        XCTAssertTrue(prompt.contains("候选上下文标题"))
        XCTAssertTrue(prompt.contains("候选上下文素材"))
        XCTAssertTrue(prompt.contains("不要鸡汤式收束"))
        XCTAssertTrue(prompt.contains("原稿标题"))
        XCTAssertTrue(prompt.contains("候选正文"))
    }

    func testWorkflowDescriptorOwnsNonJSONDecodeFallback() async {
        let engine = WorkflowEngine(
            runner: AIWorkflowRunner(
                gateway: StaticModelGateway(output: "这是一段模型直接返回的非 JSON 正文")
            )
        )
        let descriptor = WorkflowDescriptor<DraftResult>(
            kind: .draft,
            endpoint: "draft-test",
            buildMessages: {
                [ChatMessage(role: "user", content: "写一篇文章")]
            },
            fallback: {
                DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)
            },
            decode: { content in
                try WorkflowOutputDecoder.decode(content, nonJSONFallback: { cleaned in
                    DraftResult(title: nil, content: nil, summary: nil, tags: nil, raw_output: cleaned)
                })
            }
        )

        let run = await engine.execute(descriptor, config: ModelConfig(), apiKey: "test-key")

        XCTAssertTrue(run.success)
        XCTAssertEqual(run.result.raw_output, "这是一段模型直接返回的非 JSON 正文")
        XCTAssertNil(run.result.content)
    }

    func testAIWorkflowRunnerRetriesOnceOnInvalidJSONThenSucceeds() async {
        let gateway = SequencedModelGateway(steps: [
            .output("这不是合法 JSON"),
            .output(#"{"title":"标题","content":"正文","summary":null,"tags":null,"raw_output":null}"#)
        ])
        let runner = AIWorkflowRunner(gateway: gateway)

        let run = await runner.run(
            endpoint: "retry-test",
            messages: [ChatMessage(role: "user", content: "写一篇文章")],
            config: ModelConfig(),
            apiKey: "test-key",
            fallback: DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)
        ) { content in
            try WorkflowOutputDecoder.decode(content, as: DraftResult.self)
        }

        XCTAssertTrue(run.success)
        XCTAssertEqual(run.result.title, "标题")
        XCTAssertEqual(gateway.callCount, 2)
    }

    func testAIWorkflowRunnerFallsBackWhenRetryOutputStillInvalid() async {
        let gateway = SequencedModelGateway(steps: [
            .output("这不是合法 JSON"),
            .output("这次还是不合法")
        ])
        let runner = AIWorkflowRunner(gateway: gateway)
        let fallback = DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)

        let run = await runner.run(
            endpoint: "retry-test",
            messages: [ChatMessage(role: "user", content: "写一篇文章")],
            config: ModelConfig(),
            apiKey: "test-key",
            fallback: fallback
        ) { content in
            try WorkflowOutputDecoder.decode(content, as: DraftResult.self)
        }

        XCTAssertFalse(run.success)
        XCTAssertEqual(run.result.title, fallback.title)
        XCTAssertEqual(gateway.callCount, 2)
    }

    func testAIWorkflowRunnerDoesNotRetryOnHTTPError() async {
        let gateway = SequencedModelGateway(steps: [
            .failure(NativeAIError.http(status: 500, message: "boom"))
        ])
        let runner = AIWorkflowRunner(gateway: gateway)
        let fallback = DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)

        let run = await runner.run(
            endpoint: "retry-test",
            messages: [ChatMessage(role: "user", content: "写一篇文章")],
            config: ModelConfig(),
            apiKey: "test-key",
            fallback: fallback
        ) { content in
            try WorkflowOutputDecoder.decode(content, as: DraftResult.self)
        }

        XCTAssertFalse(run.success)
        XCTAssertEqual(gateway.callCount, 1)
    }

    func testAIWorkflowRunnerStreamsPartialOutputAndDecodesAccumulatedResult() async {
        let gateway = StaticStreamingModelGateway(steps: [
            .chunks([#"{"title":"标题","#, #""content":"正文","summary":null,"tags":null,"raw_output":null}"#])
        ])
        let runner = AIWorkflowRunner(gateway: gateway)
        let recorder = PartialOutputRecorder()

        let run = await runner.run(
            endpoint: "stream-test",
            messages: [ChatMessage(role: "user", content: "写一篇文章")],
            config: ModelConfig(),
            apiKey: "test-key",
            fallback: DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)
        ) { content in
            try WorkflowOutputDecoder.decode(content, as: DraftResult.self)
        } onPartialOutput: { text in
            recorder.record(text)
        }

        XCTAssertTrue(run.success)
        XCTAssertEqual(run.result.title, "标题")
        XCTAssertEqual(run.result.content, "正文")
        XCTAssertEqual(gateway.callCount, 1)
        XCTAssertEqual(recorder.snapshots, [
            #"{"title":"标题","#,
            #"{"title":"标题","content":"正文","summary":null,"tags":null,"raw_output":null}"#
        ])
    }

    func testAIWorkflowRunnerStreamingRetriesOnceOnInvalidJSONThenSucceeds() async {
        let gateway = StaticStreamingModelGateway(steps: [
            .chunks(["这不是合法 JSON"]),
            .chunks([#"{"title":"标题","content":"正文","summary":null,"tags":null,"raw_output":null}"#])
        ])
        let runner = AIWorkflowRunner(gateway: gateway)
        let recorder = PartialOutputRecorder()

        let run = await runner.run(
            endpoint: "stream-retry-test",
            messages: [ChatMessage(role: "user", content: "写一篇文章")],
            config: ModelConfig(),
            apiKey: "test-key",
            fallback: DraftResult(title: "兜底", content: "本地兜底正文", summary: nil, tags: nil, raw_output: nil)
        ) { content in
            try WorkflowOutputDecoder.decode(content, as: DraftResult.self)
        } onPartialOutput: { text in
            recorder.record(text)
        }

        XCTAssertTrue(run.success)
        XCTAssertEqual(run.result.title, "标题")
        XCTAssertEqual(gateway.callCount, 2)
    }

    func testNativeWorkflowCatalogOwnsDescriptorDeclaration() throws {
        let style = StyleProfile(
            id: 1,
            name: "Catalog 测试风格",
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
        let context = ContextPackage(
            stage: "自检阶段",
            title: "Catalog 标题",
            summary: "Catalog 摘要",
            idea: "Catalog 想法",
            direction: "情感文学",
            outline_excerpt: "Catalog 大纲",
            content_excerpt: "Catalog 正文",
            materials_excerpt: "Catalog 素材",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "Catalog 测试风格",
            style_brief: "",
            word_count: 8,
            paragraph_count: 1,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let selfCheck = NativeWorkflowCatalog.draftSelfCheck(context: context, style: style, template: nil)

        XCTAssertEqual(selfCheck.kind, .draftSelfCheck)
        XCTAssertEqual(selfCheck.endpoint, "draft-self-check-native")
        XCTAssertEqual(selfCheck.templateKey, .draftSelfCheck)
        XCTAssertTrue(selfCheck.buildMessages().last?.content.contains("Catalog 标题") == true)
        XCTAssertEqual(selfCheck.fallback().has_concerns, false)

        let rewrite = NativeWorkflowCatalog.rewriteSelection(
            context: context,
            selectedText: "原句",
            surroundingText: "前文 原句 后文",
            mode: .natural,
            customInstruction: nil,
            style: style,
            template: nil
        )
        let decoded = try rewrite.decode("非 JSON 改写")

        XCTAssertEqual(rewrite.kind, .rewriteSelection)
        XCTAssertEqual(rewrite.endpoint, "rewrite-selection-natural-native")
        XCTAssertEqual(decoded.replacement, "非 JSON 改写")
    }

    func testWorkflowEngineRecordsAICallWithResolvedWorkflowModel() async {
        let recorder = RecordingWorkflowRecorder()
        let engine = WorkflowEngine(
            runner: AIWorkflowRunner(
                gateway: StaticModelGateway(output: #"{"best_candidate_index":1,"rankings":[{"candidate_index":1,"score":88,"reason":"完整"}],"summary":"ok"}"#)
            ),
            recorder: recorder
        )
        let descriptor = WorkflowDescriptor<CandidateJudgeResult>(
            kind: .candidateJudge,
            endpoint: "candidate-judge-test",
            buildMessages: {
                [ChatMessage(role: "user", content: "评估候选")]
            },
            fallback: {
                CandidateJudgeResult(best_candidate_index: nil, rankings: [], summary: nil, raw_output: nil)
            }
        )
        let config = ModelConfig(
            baseURL: "https://api.example.com",
            model: "default-model",
            workflowOverrides: [
                AIWorkflowKind.candidateJudge.rawValue: ModelRouteConfig(
                    baseURL: nil,
                    model: "judge-model",
                    temperature: nil,
                    timeoutSeconds: nil
                )
            ]
        )

        let run = await engine.execute(descriptor, config: config, apiKey: "test-key")

        XCTAssertTrue(run.success)
        XCTAssertEqual(recorder.records.count, 1)
        XCTAssertEqual(recorder.records.first?.endpoint, "candidate-judge-test")
        XCTAssertEqual(recorder.records.first?.model, "judge-model")
        XCTAssertEqual(recorder.records.first?.success, true)
    }

    func testModelGatewayExposesStreamingPlaceholder() async {
        let gateway = StaticModelGateway(output: "ok")
        let stream = gateway.stream(
            ModelGatewayRequest(
                messages: [ChatMessage(role: "user", content: "测试流式接口")],
                config: ModelConfig(),
                workflow: .draft,
                apiKey: "test-key"
            )
        )

        do {
            for try await _ in stream {
                XCTFail("流式占位接口在实现前不应产生分片。")
            }
            XCTFail("流式占位接口应明确抛出未实现错误。")
        } catch {
            guard let gatewayError = error as? ModelGatewayError else {
                XCTFail("期待 ModelGatewayError，实际得到 \(error)")
                return
            }
            XCTAssertEqual(gatewayError, .streamingNotImplemented)
        }
    }

    func testSSELineParserHandlesDataDoneAndIgnorableLines() {
        XCTAssertEqual(
            SSELineParser.parse(#"data: {"choices":[{"delta":{"content":"你好"}}]}"#),
            .delta("你好")
        )
        XCTAssertEqual(SSELineParser.parse("data: [DONE]"), .done)
        XCTAssertEqual(SSELineParser.parse(""), .ignored)
        XCTAssertEqual(SSELineParser.parse(": keep-alive"), .ignored)
        XCTAssertEqual(SSELineParser.parse("data: 不是合法JSON"), .ignored)
        XCTAssertEqual(
            SSELineParser.parse(#"data: {"choices":[{"delta":{}}]}"#),
            .ignored
        )
        XCTAssertEqual(
            SSELineParser.parse(#"data: {"choices":[{"delta":{"content":""}}]}"#),
            .ignored
        )
    }

    func testContextPackageEncodingExcludesFragmentCorpusRegardlessOfSize() throws {
        func makeContext(fragmentCount: Int) -> ContextPackage {
            var context = ContextPackage(
                stage: "初稿阶段",
                title: "标题",
                summary: "摘要",
                idea: "想法",
                direction: "情感文学",
                outline_excerpt: "",
                content_excerpt: "",
                materials_excerpt: "素材摘录",
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: "默认",
                style_brief: "",
                word_count: 10,
                paragraph_count: 1,
                material_count: 1,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: []
            )
            context.fragment_corpus = (0..<fragmentCount).map { index in
                Fragment(
                    id: index,
                    source_type: "idea",
                    source_id: index,
                    title: "素材标题\(index)",
                    content: "AGENT_LEAK_MARKER_全量语料库片段正文_\(index)",
                    keywords: [],
                    created_at: nil,
                    updated_at: nil
                )
            }
            return context
        }

        let encoder = JSONEncoder()
        let emptyJSON = try encoder.encode(makeContext(fragmentCount: 0))
        let largeJSON = try encoder.encode(makeContext(fragmentCount: 50))
        let largeText = String(data: largeJSON, encoding: .utf8) ?? ""

        XCTAssertFalse(largeText.contains("AGENT_LEAK_MARKER"))
        XCTAssertEqual(
            largeJSON.count,
            emptyJSON.count,
            "fragment_corpus 不应参与 ContextPackage 编码，JSON 长度不应随片段数量变化"
        )
    }

    func testAgentPromptsExcludeFragmentCorpusContentFromContextJSON() {
        let style = StyleProfile(
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
        var context = ContextPackage(
            stage: "写作阶段",
            title: "标题",
            summary: "摘要",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "",
            materials_excerpt: "素材摘录",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 10,
            paragraph_count: 1,
            material_count: 1,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )
        let marker = "AGENT_LEAK_MARKER_全量语料库正文"
        context.fragment_corpus = [
            Fragment(
                id: 1,
                source_type: "idea",
                source_id: 1,
                title: "素材标题",
                content: marker,
                keywords: [],
                created_at: nil,
                updated_at: nil
            )
        ]

        let brief = WritingBriefResult(
            working_title: nil,
            core_question: nil,
            thesis: nil,
            target_reader: nil,
            emotional_center: nil,
            material_strategy: nil,
            structure_plan: nil,
            must_keep: nil,
            avoid: nil,
            raw_output: nil
        )
        let argumentCheckResult = ArgumentCheckResult(
            thesis_strength: nil,
            weak_points: nil,
            missing_evidence: nil,
            revision_directives: nil,
            ready_to_draft: nil,
            raw_output: nil
        )
        let sectionDraft = SectionDraftResult(title: nil, sections: nil, raw_output: nil)

        let briefPrompt = NativePrompts.writingBrief(context: context, style: style).last?.content ?? ""
        let argumentPrompt = NativePrompts.argumentCheck(brief: brief, context: context, style: style).last?.content ?? ""
        let critiquePrompt = NativePrompts.draftCritique(
            brief: brief,
            argumentCheck: argumentCheckResult,
            sectionDraft: sectionDraft,
            context: context,
            style: style
        ).last?.content ?? ""

        XCTAssertFalse(briefPrompt.contains(marker))
        XCTAssertFalse(argumentPrompt.contains(marker))
        XCTAssertFalse(critiquePrompt.contains(marker))
    }

    func testWritingReviewUsesLowTemperatureDefaultWithoutOverride() {
        let request = ModelGatewayRequest(
            messages: [],
            config: ModelConfig(),
            workflow: .writingReview,
            apiKey: "test-key"
        )

        XCTAssertEqual(request.resolvedTemperature, 0.2)
        XCTAssertEqual(request.resolvedMaxTokens, 4096)
        XCTAssertEqual(request.resolvedTimeoutSeconds, 120)
    }

    func testDraftUsesHighTimeoutAndMaxTokensDefaultWithoutOverride() {
        let request = ModelGatewayRequest(
            messages: [],
            config: ModelConfig(),
            workflow: .draft,
            apiKey: "test-key"
        )

        XCTAssertEqual(request.resolvedTemperature, 0.75)
        XCTAssertEqual(request.resolvedMaxTokens, 8192)
        XCTAssertEqual(request.resolvedTimeoutSeconds, 240)
    }

    func testWorkflowOverrideWinsOverCodeLevelDefault() {
        let config = ModelConfig(
            workflowOverrides: [
                AIWorkflowKind.writingReview.rawValue: ModelRouteConfig(
                    temperature: 0.9,
                    timeoutSeconds: 30,
                    maxTokens: 2048
                )
            ]
        )
        let request = ModelGatewayRequest(
            messages: [],
            config: config,
            workflow: .writingReview,
            apiKey: "test-key"
        )

        XCTAssertEqual(request.resolvedTemperature, 0.9)
        XCTAssertEqual(request.resolvedMaxTokens, 2048)
        XCTAssertEqual(request.resolvedTimeoutSeconds, 30)
    }

    func testNoWorkflowFallsBackToExistingGlobalDefault() {
        let request = ModelGatewayRequest(
            messages: [],
            config: ModelConfig(),
            workflow: nil,
            apiKey: "test-key"
        )

        XCTAssertEqual(request.resolvedTemperature, 0.75)
        XCTAssertNil(request.resolvedMaxTokens)
        XCTAssertEqual(request.resolvedTimeoutSeconds, 90)
    }

    func testChatCompletionRequestOmitsMaxTokensKeyWhenNil() throws {
        let body = ChatCompletionRequest(
            model: "test-model",
            messages: [ChatMessage(role: "user", content: "hi")],
            temperature: 0.2,
            maxTokens: nil,
            stream: false
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNil(json?["max_tokens"])
    }

    func testChatCompletionRequestEncodesMaxTokensWhenPresent() throws {
        let body = ChatCompletionRequest(
            model: "test-model",
            messages: [ChatMessage(role: "user", content: "hi")],
            temperature: 0.75,
            maxTokens: 8192,
            stream: false
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["max_tokens"] as? Int, 8192)
    }

    /// PRD 24.6：超长风格样本取头尾时，省略处必须显式写明丢了多少字。
    /// 旧实现只在头尾之间放一个空行，模型读到的是一篇结构断裂却看不出断口的"作者范文"
    /// （作者库里 2615 字的《鸳鸯》已经过线）。
    func testLongStyleSampleKeepsHeadAndTailWithExplicitOmissionNote() {
        let head = String(repeating: "头", count: 900)
        let tail = String(repeating: "尾", count: 900)
        let middle = String(repeating: "中", count: 700)
        let style = StyleProfile(
            id: 1,
            name: "测试风格",
            language_style: "中文",
            tone: "克制",
            structure_preference: "先场景后观察",
            favorite_expressions: "",
            forbidden_expressions: "",
            sample_texts: [head + middle + tail],
            title_style_like: nil,
            title_style_dislike: nil,
            is_default: 1
        )
        let context = ContextPackage(
            stage: "构思阶段",
            title: "",
            summary: "",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "测试风格",
            style_brief: "",
            word_count: 0,
            paragraph_count: 0,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: [],
            recent_issues: []
        )

        let prompt = NativePrompts.writingBrief(context: context, style: style).last?.content ?? ""

        XCTAssertTrue(prompt.contains("（此处省略中间 900 字）"), "省略处必须写明丢了多少字")
        XCTAssertTrue(prompt.contains(String(repeating: "头", count: 800)), "开头应保留")
        XCTAssertTrue(prompt.contains(String(repeating: "尾", count: 800)), "结尾应保留——否则样本读起来像被掐了尾")
    }
}

private struct StaticModelGateway: ModelGateway {
    var output: String

    func complete(_ request: ModelGatewayRequest) async throws -> String {
        output
    }
}

private final class SequencedModelGateway: ModelGateway {
    enum Step {
        case output(String)
        case failure(Error)
    }

    private var steps: [Step]
    private(set) var callCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func complete(_ request: ModelGatewayRequest) async throws -> String {
        callCount += 1
        guard !steps.isEmpty else {
            throw NativeAIError.invalidResponse
        }
        switch steps.removeFirst() {
        case let .output(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

private final class StaticStreamingModelGateway: ModelGateway {
    enum Step {
        case chunks([String])
        case failure(Error)
    }

    private var steps: [Step]
    private(set) var callCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func complete(_ request: ModelGatewayRequest) async throws -> String {
        throw NativeAIError.invalidResponse
    }

    func stream(_ request: ModelGatewayRequest) -> AsyncThrowingStream<String, Error> {
        callCount += 1
        guard !steps.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: NativeAIError.invalidResponse) }
        }
        let step = steps.removeFirst()
        return AsyncThrowingStream { continuation in
            switch step {
            case let .chunks(parts):
                for part in parts {
                    continuation.yield(part)
                }
                continuation.finish()
            case let .failure(error):
                continuation.finish(throwing: error)
            }
        }
    }
}

/// 仅用于单测里以 `@Sendable` 闭包记录流式分片；测试单线程串行调用，`@unchecked Sendable` 足够安全。
private final class PartialOutputRecorder: @unchecked Sendable {
    private(set) var snapshots: [String] = []

    func record(_ text: String) {
        snapshots.append(text)
    }
}

private final class RecordingWorkflowRecorder: AIWorkflowRecording {
    struct Record {
        var endpoint: String
        var model: String
        var elapsedMS: Int
        var success: Bool
        var error: String
        var inputSummary: String
        var outputSummary: String
    }

    private(set) var records: [Record] = []

    func recordAICall(
        endpoint: String,
        model: String,
        elapsedMS: Int,
        success: Bool,
        error: String,
        inputSummary: String,
        outputSummary: String
    ) {
        records.append(
            Record(
                endpoint: endpoint,
                model: model,
                elapsedMS: elapsedMS,
                success: success,
                error: error,
                inputSummary: inputSummary,
                outputSummary: outputSummary
            )
        )
    }
}
