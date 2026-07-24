import Foundation

package enum NativePrompts {
    package static func writingBrief(context: ContextPackage, style: StyleProfile) -> [ChatMessage] {
        let prompt = """
        你是我的中文长文写作代理。先不要写正文，只生成一份写作 brief，用来约束后续成稿。

        【作者风格说明】
        \(styleDescription(style))

        【作者样本】
        \(samplesBlock(style))

        【今天的想法】
        \(context.idea)

        【写作方向】
        \(context.direction)

        【可用素材】
        \(context.materials_excerpt)

        【当前写作上下文 JSON】
        \(contextJSON(context))

        要求：
        1. 把模糊想法压成一个清楚的核心问题
        2. 给出文章真正要证明或展开的主张，不要空泛
        3. 明确目标读者和情绪中心
        4. 列出素材使用策略：哪些素材应该放进正文，哪些只作为背景
        5. 给出分段结构计划，每段说明功能，不要直接写正文
        6. 列出必须保留的个人表达和必须避免的写法

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "working_title": "工作标题",
          "core_question": "这篇文章真正要回答的问题",
          "thesis": "文章的核心主张",
          "target_reader": "目标读者",
          "emotional_center": "情绪中心",
          "material_strategy": ["素材如何使用"],
          "structure_plan": [
            {"heading": "段落标题", "purpose": "这一段的功能", "key_points": ["要点"], "material_hint": "可使用素材"}
          ],
          "must_keep": ["必须保留的个人表达或事实"],
          "avoid": ["必须避免的写法"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作代理，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .planning)
    }

    package static func argumentCheck(
        brief: WritingBriefResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> [ChatMessage] {
        let prompt = """
        你是我的中文长文论点编辑。请检查这份 writing brief 是否足够支撑一篇有深度的文章。不要写正文。

        【原始想法】\(context.idea)
        【写作方向】\(context.direction)
        【可用素材】
        \(context.materials_excerpt)

        【当前写作上下文 JSON】
        \(contextJSON(context))

        【作者风格说明】
        \(styleDescription(style))

        【writing brief JSON】
        \(encodedJSON(brief))

        请检查：
        1. 核心主张是否具体、可展开、非套话
        2. 有没有缺证据、缺场景的位置；仅当体裁适合个人叙事时，再检查是否缺个人经验
        3. 哪些段落最容易写成泛泛议论
        4. 成稿前必须遵守哪些修改指令

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "thesis_strength": "论点强度判断",
          "weak_points": ["薄弱处"],
          "missing_evidence": ["缺少的证据/场景；仅个人叙事类体裁才列缺失的个人经验"],
          "revision_directives": ["成稿前必须遵守的指令"],
          "ready_to_draft": true
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文论点编辑，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .argumentAudit)
    }

    package static func briefRevision(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> [ChatMessage] {
        let prompt = """
        你是我的中文长文写作代理。论点编辑判断当前 writing brief 还不足以支撑成稿。请只修订 brief，不要写正文。

        【原 writing brief JSON】
        \(encodedJSON(brief))

        【论点检查 JSON】
        \(encodedJSON(argumentCheck))

        【可用素材】
        \(context.materials_excerpt)

        修订要求：
        1. 逐条回应论点检查中的 revision_directives，能用现有素材补上的缺口，直接写进 material_strategy 和 structure_plan
        2. missing_evidence 中现有素材无法覆盖的项，原样放进 unresolved_gaps，不要编造经历或案例去填补
        3. 不要扩大文章野心，宁可收窄核心问题，也不要留下撑不起来的主张

        请只输出 JSON，不要输出 Markdown 代码块：结构与原 brief 完全相同，另加一个字段 "unresolved_gaps": ["现有素材仍无法覆盖的证据/场景缺口"]
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作代理，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .briefRevision)
    }

    package static func sectionDraft(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> [ChatMessage] {
        let prompt = """
        你是我的中文长文写作代理。现在根据 brief 和论点检查结果分段成稿。

        【作者风格说明】
        \(styleDescription(style))

        【作者样本】
        \(samplesBlock(style))

        【原始想法】\(context.idea)
        【写作方向】\(context.direction)
        【可用素材】
        \(context.materials_excerpt)

        【按段检索到的个人素材】
        \(sectionFragmentsBlock(context.section_fragment_contexts ?? []))

        【writing brief JSON】
        \(encodedJSON(brief))

        【论点检查 JSON】
        \(encodedJSON(argumentCheck))

        分段成稿要求：
        1. 严格按 brief 的结构计划逐段写，不要跳段
        2. 每段只承担一个功能，段与段之间要有承接
        3. 主动吸收论点检查中的 revision_directives
        4. 能用具体场景就不用抽象判断；个人表达与感悟只在体裁适合时使用，解读、评述类体裁以贴合原作和事实为先
        5. 写每段时优先使用该段下方的真实素材，不要把 A 段素材挪作 B 段经历；未命中素材时不要编造
        6. 不要输出整篇最终稿，只输出分段草稿数组，下一步还会自我批评和整合

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "title": "标题建议",
          "sections": [
            {"heading": "段落标题", "content": "这一段正文 Markdown", "self_check": "这一段是否完成了它的功能"}
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文长文写作代理，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .sectionDraft)
    }

    package static func draftCritique(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        sectionDraft: SectionDraftResult,
        context: ContextPackage,
        style: StyleProfile
    ) -> [ChatMessage] {
        let prompt = """
        你是我的中文长文主编。请对分段草稿做一次自我批评，然后整合成最终初稿。

        【作者风格说明】
        \(styleDescription(style))

        【原始想法】\(context.idea)
        【写作方向】\(context.direction)
        【可用素材】
        \(context.materials_excerpt)

        【当前写作上下文 JSON】
        \(contextJSON(context))

        【writing brief JSON】
        \(encodedJSON(brief))

        【论点检查 JSON】
        \(encodedJSON(argumentCheck))

        【分段草稿 JSON】
        \(encodedJSON(sectionDraft))

        自我批评要求：
        1. 检查是否偏离 brief 的核心问题和主张
        2. 检查是否还有泛泛议论、鸡汤腔、培训腔、营销腔
        3. 检查段落之间是否有真实推进，而不是并列堆砌
        4. 只把关键批评写进 critique_notes，不要暴露冗长思考过程
        5. 根据批评直接修订并输出一版完整正文

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "critique_notes": ["自我批评摘要"],
          "title": "最终标题",
          "content": "完整正文 Markdown",
          "summary": "80 字以内摘要",
          "tags": ["标签1", "标签2", "标签3"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文长文主编，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .critiqueRevision)
    }

    package static func topics(context: ContextPackage, style: StyleProfile, template: PromptTemplate? = nil) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "input": context.idea,
                    "direction": context.direction,
                    "materials": context.materials_excerpt
                ]) { _, new in new }
            ), mode: .planning)
        }

        let prompt = """
        你是我的公众号选题策划助手。

        我的写作方向：\(context.direction)
        今天的关键词或想法：\(context.idea)
        可用素材：
        \(context.materials_excerpt)

        我的写作风格：
        \(styleDescription(style))

        请生成 8 个公众号选题。
        要求：标题自然不标题党；适合公众号读者；有真实痛点；有个人表达空间；推荐指数为 1-5。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "topics": [
            {
              "title": "标题",
              "description": "一句话说明",
              "core_viewpoint": "这篇文章最想讲清楚的核心观点",
              "target_reader": "适合阅读这篇文章的人群",
              "angle": "推荐角度",
              "emotion": "情绪强度",
              "score": 4,
              "direction": "\(context.direction)",
              "status": "待写",
              "tags": ["标签1", "标签2"]
            }
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文公众号选题策划助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .planning)
    }

    package static func outline(topic: TopicPayload, context: ContextPackage, style: StyleProfile, template: PromptTemplate? = nil) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging(topicVariables(topic).merging([
                    "materials": context.materials_excerpt
                ]) { _, new in new }) { _, new in new }
            ), mode: .planning)
        }

        let prompt = """
        你是我的公众号文章大纲助手。

        文章选题：\(topic.title)
        一句话说明：\(topic.description ?? "")
        推荐角度：\(topic.angle ?? "")
        核心观点：\(topic.core_viewpoint ?? "")
        目标读者：\(topic.target_reader ?? "")
        可用素材：
        \(context.materials_excerpt)

        我的写作风格：
        \(styleDescription(style))

        请生成文章大纲。
        要求：开头从现实痛点切入；层次清晰；标注可插入素材位置；结尾有余味不喊口号。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "title": "标题建议",
          "opening": "开头设计",
          "sections": [
            {
              "heading": "第一部分",
              "points": ["要点1", "要点2"],
              "material_hint": "可插入素材"
            }
          ],
          "ending": "结尾设计"
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文公众号大纲助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .planning)
    }

    package static func draft(topic: TopicPayload, context: ContextPackage, style: StyleProfile, template: PromptTemplate? = nil) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging(topicVariables(topic).merging([
                    "outline": context.outline_excerpt,
                    "materials": context.materials_excerpt
                ]) { _, new in new }) { _, new in new }
            ), mode: .fullDraft)
        }

        let prompt = """
        你是我的公众号写作助手。

        【作者风格样本】
        \(samplesBlock(style))

        【风格说明】
        \(styleDescription(style))

        文章选题：\(topic.title)
        选题说明：\(topic.description ?? "")
        推荐角度：\(topic.angle ?? "")

        文章大纲：
        \(context.outline_excerpt)

        可用素材：
        \(context.materials_excerpt)

        写作要求：
        1. 严格沿着大纲展开，不要跳跃
        2. 语言通俗自然，像真实作者写的
        3. 段落不要太长
        4. 开头能让读者读下去
        5. 结尾有回味，不喊口号
        6. 技术概念必须解释清楚定义、价值、例子和边界

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "title": "标题建议",
          "content": "完整正文 Markdown",
          "summary": "80 字以内摘要",
          "tags": ["标签1", "标签2", "标签3"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文公众号写作助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .fullDraft)
    }

    package static func polishDraft(
        context: ContextPackage,
        content: String,
        mode: PolishMode,
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: [
                    "style_description": styleDescription(style),
                    "style_samples": samplesBlock(style),
                    "context_json": contextJSON(context),
                    "content": content,
                    "polish_goal": mode.promptInstruction
                ]
            ), mode: .revision)
        }

        let prompt = """
        你是我的中文长文编辑。请对当前整篇文章做一次全文改写，不要只改选中片段。

        【作者风格说明】
        \(styleDescription(style))

        【作者风格样本】
        \(samplesBlock(style))

        【当前写作上下文 JSON】
        \(contextJSON(context))

        【当前正文】
        \(content)

        【本次全文改写目标】
        \(mode.promptInstruction)

        要求：
        1. 保留文章的核心观点、事实关系、人称和作者个人表达
        2. 可以调整段落顺序、删重复、补承接，但不要虚构新事实
        3. 不要改成营销腔、培训腔、鸡汤腔或标题党
        4. 摘要控制在 80 字以内
        5. 正文使用 Markdown
        6. 不要输出解释、寒暄或多个版本

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "title": "保留或优化后的标题",
          "content": "改写后的完整正文 Markdown",
          "summary": "80 字以内摘要",
          "tags": ["标签1", "标签2", "标签3"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文长文编辑，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .revision)
    }

    package static func improveDraftFromReview(
        context: ContextPackage,
        content: String,
        review: WritingReview,
        style: StyleProfile
    ) -> [ChatMessage] {
        // 完整正文在下方单独给出，上下文 JSON 里再带一份 1000+800 截断副本（中间挖成 "..."）
        // 只会与完整正文互相干扰，这里清空它。
        var contextForPrompt = context
        contextForPrompt.content_excerpt = ""
        let prompt = """
        你是我的中文长文主编。请根据写作教练诊断，对整篇文章做一次全文修订。

        【作者风格说明】
        \(styleDescription(style))

        【作者样本】
        \(samplesBlock(style))

        【当前写作上下文 JSON】
        \(contextJSON(contextForPrompt))

        【当前完整正文】
        \(content)

        【写作教练诊断 JSON】
        \(encodedJSON(review))

        修订要求：
        1. 这是全文修改，不是局部改写；要处理诊断里的 issues、revision_plan、training_focus
        2. 优先解决高严重度问题，再处理结构承接和语言自然度
        3. 保留原文的核心观点、事实关系、人称和作者个人表达
        4. 可以调整段落顺序、删重复、补承接、加必要的场景，但不要虚构具体事实
        5. 不要把文章改成营销腔、培训腔、鸡汤腔或标题党
        6. 如果诊断建议与原文风格冲突，以保留作者个人表达为先
        7. 输出一版可直接进入待复核的完整稿

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "title": "修订后的标题",
          "content": "修订后的完整正文 Markdown",
          "summary": "80 字以内摘要",
          "tags": ["标签1", "标签2", "标签3"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文长文主编，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .reviewDrivenRevision)
    }

    /// 写作诊断评分锚点。不给锚点时模型评分会向 70 分档塌缩、且与 issues 清单脱钩——
    /// 实测同一份逐字节相同的正文，三次诊断给出 58/72/73，极差 15 分。
    /// 内联 prompt 与 seed 模板共用这一份文案，避免两条路径再次漂移（本次修复的根因）。
    static let scoreAnchorBlock = """
    评分锚点（必须落到锚点上，不要给 70 分档的"安全分"）：
    - 90–100：可直接发表。结构完整推进、细节具体真实、无任何高危问题、无腔调问题
    - 80–89：小修可发。主线清楚有推进，只有 1–2 处中低危问题
    - 70–79：中修。存在 1 处高危问题，或 3 处以上中危问题，或细节明显单薄
    - 60–69：大修。偏题、结构断裂、大段空泛议论或多处高危问题
    - 0–59：需重写。跑题、明显截断、大量套话或腔调失控
    分数必须与 issues 清单一致：有高危问题不得进入 80 档；没有任何问题不应停留在 70 档。
    """

    package static func writingReview(
        context: ContextPackage,
        style: StyleProfile,
        previousReview: WritingReview? = nil,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "title": context.title,
                    "summary": context.summary,
                    "content": context.content_excerpt,
                    "outline": context.outline_excerpt,
                    "idea": context.idea,
                    "direction": context.direction,
                    "previous_review": previousReviewBlock(previousReview)
                ]) { _, new in new }
            ), mode: .review)
        }

        let prompt = """
        你是我的私人中文写作教练和资深编辑。请诊断当前文章，目标不是代写，而是帮助作者提高写作能力。

        【作者风格说明】
        \(styleDescription(style))

        【作者风格样本】
        \(samplesBlock(style))

        【写作方向】
        \(context.direction)

        【原始想法】
        \(context.idea)

        【标题】
        \(context.title)

        【摘要】
        \(context.summary)

        【大纲】
        \(context.outline_excerpt)

        【正文】
        \(context.content_excerpt)

        【上一次诊断】
        \(previousReviewBlock(previousReview))

        诊断要求：
        1. 先判断这篇文章最核心的问题，不要泛泛夸奖
        2. 指出会影响读者读下去的问题，维度不限于开头/结构/观点/素材/表达/节奏/风格这些通用维度，
           如果文章是文学写作方向，优先考虑并可直接使用这些更具体的文学向维度：
           人称视角、意象与细节、留白与节奏、情感真实度、文本引用关系（经典/素材引用是否服务于个人表达）、
           语言腔调（是否滑向文艺腔/鸡汤腔/营销腔）
        3. 每个问题都要给出可执行修改建议
        4. 如果正文很少，也要基于标题、想法和大纲判断下一步该补什么
        5. 保留作者个人表达，不要建议改成营销腔、培训腔或标题党
        6. 依据体裁给建议：只在个人叙事、情感随笔类体裁才建议补充个人感悟或生活体验；
           原著解读、书评、科普等体裁以忠实原文、准确清晰为评价标准，不要建议加入个人体验
        7. 不要直接重写全文
        8. 如果存在"上一次诊断"，先判断其中的问题这次是否已经解决：已解决的问题写入 resolved_from_last，
           不要在 issues 里重复列出；issues 只列仍未解决的问题和新出现的问题
        9. 如果作者风格说明中列出了"作者常见雷区"，重点检查这些问题是否再次出现
        10. 如果作者风格说明列出了"作者常见雷区"，逐条判断本文是否再次命中：
           命中的雷区写入 pitfall_hits（原样抄写雷区描述），未命中不要写。

        \(scoreAnchorBlock)

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "summary": "对当前稿件的一句话诊断",
          "overall_score": 72,
          "strengths": ["已经做得比较好的地方"],
          "issues": [
            {
              "dimension": "开头/结构/观点/素材/表达/节奏/风格，或人称视角/意象与细节/留白与节奏/情感真实度/文本引用关系/语言腔调",
              "severity": "高/中/低",
              "excerpt": "可选，引用一小段原文",
              "problem": "问题是什么",
              "suggestion": "下一步怎么改"
            }
          ],
          "revision_plan": ["第一步怎么改", "第二步怎么改", "第三步怎么改"],
          "training_focus": ["接下来最该训练的写作能力"],
          "style_notes": ["与作者个人风格有关的观察"],
          "resolved_from_last": ["上一次诊断中这次已经解决的问题，没有历史或没有解决的留空数组"],
          "pitfall_hits": ["命中的雷区原文描述，未命中留空数组"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作教练，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .review)
    }

    private static func resolvedRewriteInstruction(mode: RewriteMode, customInstruction: String?) -> String {
        let trimmed = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? mode.promptInstruction : trimmed
    }

    private static func previousReviewBlock(_ review: WritingReview?) -> String {
        guard let review else {
            return "（这是第一次诊断，没有历史记录。）"
        }
        let issuesText = review.issues.prefix(6).map { "- [\($0.dimension)] \($0.problem)" }.joined(separator: "\n")
        let planText = review.revision_plan.prefix(6).map { "- \($0)" }.joined(separator: "\n")
        return """
        上一次诊断评分：\(review.overall_score.map(String.init) ?? "无")
        上一次诊断指出的问题：
        \(issuesText.isEmpty ? "（无记录）" : issuesText)
        上一次给出的修改计划：
        \(planText.isEmpty ? "（无记录）" : planText)
        """
    }

    package static func publishAssets(context: ContextPackage, style: StyleProfile, template: PromptTemplate? = nil) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "title": context.title,
                    "summary": context.summary,
                    "content": context.content_excerpt
                ]) { _, new in new }
            ), mode: .publish)
        }

        let prompt = """
        你是我的公众号发布助手。

        【作者风格说明】
        \(styleDescription(style))

        文章标题：\(context.title)
        文章摘要：\(context.summary)
        文章正文：
        \(context.content_excerpt)

        请生成以下发布物料：
        1. 公众号摘要（50～120 字）
        2. 公众号封面文案（20 字以内）
        3. 朋友圈转发文案（100 字以内，像作者自己写的推荐语，不要硬广）
        4. 文章标签（5～8 个）
        5. 小红书版本（200 字以内）
        6. 封面图提示词（适合给绘图模型或设计工具使用）

        要求：保持作者个人表达感；不要硬广；不要夸张标题党；不要输出解释。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "summary": "公众号摘要",
          "cover_text": "公众号封面文案",
          "moments_text": "朋友圈转发文案",
          "tags": ["标签1", "标签2", "标签3"],
          "xiaohongshu_text": "小红书版本",
          "cover_image_prompt": "封面图提示词"
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的公众号发布助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .publish)
    }

    package static func rewriteSelection(
        context: ContextPackage,
        selectedText: String,
        surroundingText: String,
        mode: RewriteMode,
        customInstruction: String? = nil,
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        let goal = resolvedRewriteInstruction(mode: mode, customInstruction: customInstruction)
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "context_json": contextJSON(context),
                    "selected_text": selectedText,
                    "title": context.title,
                    "surrounding_text": surroundingText,
                    "rewrite_goal": goal
                ]) { _, new in new }
            ), mode: .selectionRewrite)
        }

        let prompt = """
        你是我的中文长文编辑。请只改写用户选中的片段，不要重写全文。

        【作者风格说明】
        \(styleDescription(style))

        【作者风格样本】
        \(samplesBlock(style))

        【当前文章标题】
        \(context.title.isEmpty ? "未填写" : context.title)

        【当前写作上下文 JSON】
        \(contextJSON(context))

        【上下文】
        \(surroundingText)

        【选中片段】
        \(selectedText)

        【本次改写目标】
        \(goal)

        要求：
        1. 只输出可以直接替换选中片段的内容
        2. 保留选中片段的核心意思、事实关系和人称
        3. 不要添加与上下文冲突的新事实
        4. 如果选中片段含 Markdown 标记，尽量保持格式兼容
        5. 不要输出解释、寒暄或多个版本

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "replacement": "替换后的片段",
          "note": "一句话说明这次改动的重点"
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文编辑，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .selectionRewrite)
    }

    package static func writingAdvisor(context: ContextPackage, style: StyleProfile, template: PromptTemplate? = nil) -> [ChatMessage] {
        if let template {
            let messages = render(
                template,
                variables: commonVariables(style: style).merging([
                    "context_json": contextJSON(context)
                ]) { _, new in new }
            )
            return appendAgentDiscipline(to: appendAdvisorOutputContract(to: messages), mode: .advisor)
        }

        let prompt = """
        你是我的私人中文写作代理，工作方式参考 Claude Code / Codex 的代理循环：先读上下文，列证据，再做计划，最后给出可执行动作。你的任务不是代写，而是判断当前稿件最应该做的下一步。

        【作者风格说明】
        \(styleDescription(style))

        【作者风格样本】
        \(samplesBlock(style))

        【当前写作上下文 JSON】
        \(contextJSON(context))

        请按这个顺序判断：
        1. 先列出 3～5 条上下文观察：当前稿件有什么、缺什么、最近诊断或作者雷区提示了什么
        2. 再给出 2～5 步执行计划：先处理结构、观点、素材还是语言，为什么
        3. 标出 1～3 条风险：如果直接生成或直接润色，最可能损失什么
        4. 判断当前处于哪个写作阶段
        5. 判断最大问题是什么
        6. 判断现在最值得做的下一步是什么
        7. 解释为什么不是先做其他事
        8. 推荐 1～3 个可执行动作

        可用动作 id 只能从下面选择：
        - quick_draft
        - generate_topics
        - generate_outline
        - draft_from_outline
        - writing_review
        - rewrite_selection_natural
        - rewrite_selection_expand
        - polish_natural
        - polish_tighten
        - publish_assets
        - save_article

        要求：不要泛泛鼓励，不要直接重写正文；建议要具体、克制、适合当前阶段。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "stage": "构思阶段/大纲阶段/初稿阶段/修改阶段/发布阶段",
          "main_problem": "当前最大问题",
          "next_action": "最推荐的下一步",
          "reason": "为什么此时应先做这一步",
          "suggested_actions": ["generate_outline", "writing_review"],
          "focus_area": "这次最该训练的能力",
          "context_findings": ["基于上下文得到的观察，不要编造上下文里没有的信息"],
          "execution_plan": ["第一步", "第二步", "第三步"],
          "risk_notes": ["本轮需要避免的风险"]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作编辑，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .advisor)
    }

    /// 生成后轻量自检（18.3.5）：只标记高风险信号，用小 prompt、低输出长度，失败时由调用方静默跳过。
    package static func draftSelfCheck(
        context: ContextPackage,
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "title": context.title,
                    "outline": context.outline_excerpt,
                    "idea": context.idea,
                    "content": context.content_excerpt
                ]) { _, new in new }
            ), mode: .selfCheck)
        }

        let prompt = """
        你是一名快速复查的编辑助手。只做轻量自检，不做完整诊断，也不改写正文。

        【标题】\(context.title)
        【想法/大纲】
        \(context.idea.isEmpty ? context.outline_excerpt : context.idea + "\n" + context.outline_excerpt)

        【本次生成正文】
        \(context.content_excerpt)

        请只检查以下高风险信号：
        1. 正文是否明显偏离大纲或想法
        2. 结尾是否落入套话、口号或培训腔
        3. 是否存在明显的语句不连贯、重复或前后矛盾（长文本尤其容易在中段出现这类问题）
        4. 字数是否与正文应有的完整度明显不符（例如明显被截断）

        最多给出 3 条需要作者复查的片段，每条引用一小段原文并说明具体问题。没有问题就返回空数组，不要为了凑数量而勉强找问题。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "has_concerns": false,
          "flagged_excerpts": [
            {"excerpt": "引用的原文片段", "concern": "具体问题是什么"}
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文编辑助手，只输出用户要求的 JSON，不输出解释。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .selfCheck)
    }

    /// 从历史诊断归纳候选作者雷区（18.3.3）：只生成候选，是否采纳由作者手动确认。
    package static func summarizePitfalls(
        issues: [(reviewID: Int, dimension: String, problem: String)],
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        let issuesText = issues
            .map { "- [review_id=\($0.reviewID)] [\($0.dimension)] \($0.problem)" }
            .joined(separator: "\n")

        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "issues_history": issuesText
                ]) { _, new in new }
            ), mode: .memory)
        }

        let prompt = """
        你是我的写作复盘助手。下面是这位作者近期多次写作诊断中出现过的问题记录，请归纳出反复出现的"作者雷区"。

        【历史诊断问题】
        \(issuesText)

        要求：
        1. 把语义相近、反复出现的问题聚成同一条雷区，不要逐条罗列原始问题
        2. 只保留真正反复出现（至少 2 次不同诊断中出现类似问题）的雷区，偶发的一次性问题不要归纳进来
        3. 每条雷区用一句话描述这位作者具体会踩的坑，而不是泛泛的写作建议
        4. 最多输出 6 条
        5. 每条雷区列出支持它的 review_id

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "candidates": [
            {"description": "具体的雷区描述", "supporting_review_ids": [12, 9]}
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作复盘助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .memory)
    }

    /// 从发布前人工修改记录归纳候选编辑偏好（20.4）：只生成候选，是否生效由作者手动确认。
    package static func summarizeEditPreferences(
        records: [EditRecord],
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        let recordsText = records
            .map { record in
                let ratio = String(format: "%.1f%%", record.edit_ratio * 100)
                return """
                - [edit_record_id=\(record.id)] \(record.title_snapshot ?? "未命名文章")：\(record.edit_level)，编辑比例 \(ratio)，增 \(record.added_characters) / 删 \(record.removed_characters)，摘要：\(record.diff_summary ?? "")
                """
            }
            .joined(separator: "\n")

        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "edit_records": recordsText
                ]) { _, new in new }
            ), mode: .memory)
        }

        let prompt = """
        你是我的写作复盘助手。下面是这位作者发布前对 AI 确认稿做过的人工修改记录，请归纳出候选"编辑偏好校准规则"。

        【编辑记录】
        \(recordsText)

        【当前已确认编辑偏好】
        \(learnedPreferencesInline(style).isEmpty ? "（暂无）" : learnedPreferencesInline(style))

        要求：
        1. 只归纳反复出现、可操作、能指导下一次生成的偏好，不要写成泛泛建议
        2. 规则要描述"以后生成时应该主动怎么做/避免什么"，例如"少用总结式金句收束，多保留个人场景"
        3. 不要把单篇文章的个别修改上升为长期偏好
        4. 最多输出 6 条，每条附支持它的 edit_record_id
        5. 规则必须等待作者确认后才会生效

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "monthly_summary": "本月编辑行为的一句话趋势",
          "candidates": [
            {"description": "具体编辑偏好规则", "source_edit_record_ids": [3, 7]}
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作复盘助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .memory)
    }

    /// 读者视角模拟（18.4.3）：补充诊断视角，不计入 overall_score，不替代编辑视角诊断。
    package static func readerPerspective(
        context: ContextPackage,
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "title": context.title,
                    "summary": context.summary,
                    "content": context.content_excerpt
                ]) { _, new in new }
            ), mode: .readerSimulation)
        }

        let prompt = """
        你现在不是编辑，而是扮演这篇文章的一位典型读者，模拟真实阅读体验中的兴趣变化。

        【标题】\(context.title)
        【摘要】\(context.summary)
        【正文】
        \(context.content_excerpt)

        请说明：
        1. 这位读者是谁（一句话画像，例如"平时刷公众号但不常读长文的人"）
        2. 读者最可能在哪一段或哪一句失去兴趣，为什么
        3. 哪一句或哪一段最可能被记住或转发，为什么
        4. 一句话补充说明，供作者参考（不是评分，不是修改指令）

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "reader_persona": "读者画像",
          "drop_off_point": "最可能失去兴趣的位置和原因",
          "most_memorable_point": "最可能被记住或转发的位置和原因",
          "note": "一句话补充"
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的读者视角模拟助手，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .readerSimulation)
    }

    package static func prePublishAudit(
        context: ContextPackage,
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "title": context.title,
                    "summary": context.summary,
                    "content": context.content_excerpt
                ]) { _, new in new }
            ), mode: .prePublishAudit)
        }

        let prompt = """
        你是发表前终审编辑。只做发布安全初审，不改写全文，也不阻止作者发布。

        【标题】\(context.title)
        【摘要】\(context.summary)
        【正文】
        \(context.content_excerpt)

        【作者已确认雷区】
        \(pitfallsInline(style).isEmpty ? "（暂无）" : pitfallsInline(style))

        请逐项检查：
        1. 明显错别字、病句、重复或断裂表达，必须给出原文片段
        2. 引文或书名号内容是否需要人工核对，不要假装你能联网查证
        3. 标题、摘要、正文主线是否一致
        4. 是否再次命中作者已确认雷区

        注意：引文准确性只做"建议复核"，不要擅自改写；没有证据的问题不要硬凑。

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "passed": false,
          "summary": "一句话终审结论",
          "typo_issues": [{"category":"错字/病句","severity":"高/中/低","excerpt":"原文片段","problem":"问题","suggestion":"建议"}],
          "quote_issues": [{"category":"引文核对","severity":"高/中/低","excerpt":"引文片段","problem":"为什么需要核对","suggestion":"建议"}],
          "consistency_issues": [{"category":"一致性","severity":"高/中/低","excerpt":"原文片段","problem":"问题","suggestion":"建议"}],
          "pitfall_issues": [{"category":"作者雷区","severity":"高/中/低","excerpt":"原文片段","problem":"命中的雷区","suggestion":"建议"}]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文发表前终审编辑，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .prePublishAudit)
    }

    package static func judgeDraftCandidates(
        context: ContextPackage,
        base: DraftSnapshot,
        candidates: [DraftCandidate],
        style: StyleProfile,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        let candidatesJSON = encodedJSON(candidates, fallback: candidates.map { "\($0.index). \($0.label)：\($0.title)" }.joined(separator: "\n"))
        let baseJSON = encodedJSON(base, fallback: "\(base.title)\n\(base.summary)\n\(base.content)")

        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: commonVariables(style: style).merging([
                    "context_json": contextJSON(context),
                    "base_draft_json": baseJSON,
                    "candidate_drafts_json": candidatesJSON
                ]) { _, new in new }
            ), mode: .candidateJudge)
        }

        let prompt = """
        你是候选稿评委。请比较多个全文改写候选，选出最值得进入"深度成稿"自动迭代的一版。

        【原稿 JSON】
        \(baseJSON)

        【当前写作上下文 JSON】
        \(contextJSON(context))

        【候选稿 JSON】
        \(candidatesJSON)

        【作者风格与评价重点】
        \(styleDescription(style))

        评分维度：
        1. 是否保留原稿真实经验和作者视角
        2. 是否符合体裁评价重点
        3. 是否避开作者雷区和已确认编辑偏好
        4. 结构推进是否更清楚，语言是否更自然
        5. 是否有新增虚构、过度鸡汤、营销腔、标题党风险

        请只输出 JSON，不要输出 Markdown 代码块：
        {
          "best_candidate_index": 1,
          "summary": "一句话说明为什么选它",
          "rankings": [
            {"candidate_index": 1, "score": 86, "reason": "排序理由", "strengths": ["优点"], "risks": ["风险"]}
          ]
        }
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文长文候选评委，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .candidateJudge)
    }

    /// 23.6.3 决策工作流：判别类、低温、小输出，本章唯一新增 prompt，文案逐字取自 PRD 23.6.3。
    package static func agentDecision(
        state: AgentSessionState,
        availableActions: [AgentSessionAction],
        correctionNote: String? = nil,
        template: PromptTemplate? = nil
    ) -> [ChatMessage] {
        if let template {
            return appendAgentDiscipline(to: render(
                template,
                variables: [
                    "goal": agentSessionGoalBlock(state),
                    "draft_status": agentSessionDraftStatusBlock(state),
                    "action_history": agentSessionActionHistoryBlock(state),
                    "budget": agentSessionBudgetBlock(state),
                    "available_actions": agentSessionAvailableActionsBlock(availableActions)
                ]
            ), mode: .decision)
        }

        let correctionBlock = correctionNote.map { "\n【纠正观察】\n\($0)\n" } ?? ""
        let prompt = """
        你是我的中文写作代理调度器。你的职责不是写作，而是根据当前会话状态，
        决定下一步执行哪一个动作，或者停下来。

        【写作目标】
        \(agentSessionGoalBlock(state))

        【当前稿件状态】
        \(agentSessionDraftStatusBlock(state))

        【已执行动作历史】
        \(agentSessionActionHistoryBlock(state))

        【剩余预算】
        \(agentSessionBudgetBlock(state))
        \(correctionBlock)
        【可用动作】（只能从中选择，且必须满足括号内前置条件）
        \(agentSessionAvailableActionsBlock(availableActions))

        决策纪律：
        1. 每次只选一个动作；优先解决验证信号里的高严重度问题
        2. 同一动作连续使用不得超过 2 次；上一动作没有改善验证信号时，必须换路径或选 ask_author / finish
        3. 预算剩余不足 3 次时，只允许 writing_review、ask_author 或 finish
        4. 缺证据时用 search_materials 或 ask_author，不得让生成动作编造经历
        5. 不确定时倾向 finish——把判断交还作者永远是合法选择

        请只输出 JSON，不要输出 Markdown 代码块：
        {"action":"动作 id","arguments":{"query":"仅 search_materials / ask_author 需要"},
         "reason":"选择这一步的原因","expected_gain":"预计改善哪个验证信号","stop":false}
        """
        return appendAgentDiscipline(to: [
            ChatMessage(role: "system", content: "你是严谨的中文写作代理调度器，只输出用户要求的 JSON。"),
            ChatMessage(role: "user", content: prompt)
        ], mode: .decision)
    }

    private static func agentSessionGoalBlock(_ state: AgentSessionState) -> String {
        [
            "想法：\(state.idea.isEmpty ? "（未填写）" : state.idea)",
            "方向：\(state.direction.isEmpty ? "（未填写）" : state.direction)",
            state.selectedTopicTitle.map { "选题：\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func agentSessionDraftStatusBlock(_ state: AgentSessionState) -> String {
        let review = state.latestReview
        let reviewLine = review.map { r in
            let high = r.issues.filter { $0.severity == "高" }.count
            let medium = r.issues.filter { $0.severity == "中" }.count
            let pitfalls = r.pitfall_hits.isEmpty ? "无" : r.pitfall_hits.joined(separator: "、")
            return "最近诊断：评分 \(r.overall_score.map(String.init) ?? "无")，高问题 \(high) 个，中问题 \(medium) 个，命中雷区：\(pitfalls)"
        } ?? "最近诊断：（本会话尚未诊断过）"

        let gateLine = state.latestGate.map { "质量门摘要：\($0.summary)" } ?? "质量门摘要：（本会话尚未生成过草稿）"
        let selfCheckLine = state.latestSelfCheck.map { check -> String in
            let count = check.flagged_excerpts?.count ?? 0
            return check.has_concerns == true ? "自检摘要：发现 \(count) 处建议复查片段" : "自检摘要：未发现高风险片段"
        } ?? "自检摘要：（本会话尚未自检过）"

        return """
        阶段：\(state.outline.isEmpty && state.content.isEmpty ? "构思阶段" : (state.content.isEmpty ? "大纲阶段" : "初稿/修改阶段"))
        字数：\(state.content.count)
        大纲：\(state.outline.isEmpty ? "无" : "已有")
        \(reviewLine)
        \(gateLine)
        \(selfCheckLine)
        """
    }

    private static func agentSessionActionHistoryBlock(_ state: AgentSessionState) -> String {
        state.actionHistoryLines.isEmpty ? "（本会话尚未执行任何动作）" : state.actionHistoryLines.joined(separator: "\n")
    }

    private static func agentSessionBudgetBlock(_ state: AgentSessionState) -> String {
        "剩余 \(state.remainingCalls) 次；本会话已用 \(state.usedCalls) 次，总预算 \(state.callBudget) 次"
    }

    private static func agentSessionAvailableActionsBlock(_ actions: [AgentSessionAction]) -> String {
        actions.map { "- \($0.rawValue)（\($0.title)，\($0.preconditionNote)）" }.joined(separator: "\n")
    }

    package static func defaultPromptTemplates() -> [PromptTemplateSeed] {
        [
            PromptTemplateSeed(
                key: .topics,
                name: PromptTemplateKey.topics.title,
                system_prompt: "你是严谨的中文公众号选题策划助手，只输出用户要求的 JSON。",
                user_template: """
                请生成 8 个公众号选题。

                【写作方向】{{direction}}
                【关键词或想法】{{input}}
                【素材】{{materials}}
                【作者风格】{{style_description}}

                要求：标题自然不标题党；有真实痛点；有个人表达空间；推荐指数 1-5。
                请只输出 JSON：
                {"topics":[{"title":"标题","description":"一句话说明","core_viewpoint":"核心观点","target_reader":"目标读者","angle":"推荐角度","emotion":"情绪强度","score":4,"direction":"{{direction}}","status":"待写","tags":["标签1"]}]}
                """
            ),
            PromptTemplateSeed(
                key: .outline,
                name: PromptTemplateKey.outline.title,
                system_prompt: "你是严谨的中文公众号大纲助手，只输出用户要求的 JSON。",
                user_template: """
                请生成可直接成稿的公众号文章大纲。

                【选题】{{topic_title}}
                【说明】{{topic_description}}
                【核心观点】{{topic_core_viewpoint}}
                【目标读者】{{topic_target_reader}}
                【推荐角度】{{topic_angle}}
                【素材】{{materials}}
                【作者风格】{{style_description}}

                要求：开头从现实痛点切入；层次清楚；标注素材插入位置；结尾有余味。
                请只输出 JSON：
                {"title":"标题建议","opening":"开头设计","sections":[{"heading":"第一部分","points":["要点1"],"material_hint":"可插入素材"}],"ending":"结尾设计"}
                """
            ),
            PromptTemplateSeed(
                key: .draft,
                name: PromptTemplateKey.draft.title,
                system_prompt: "你是严谨的中文公众号写作助手，只输出用户要求的 JSON。",
                user_template: """
                请根据大纲生成完整公众号文章。

                【选题】{{topic_title}}
                【选题说明】{{topic_description}}
                【推荐角度】{{topic_angle}}
                【大纲】{{outline}}
                【素材】{{materials}}
                【作者风格】{{style_description}}
                【样本】{{style_samples}}

                要求：严格沿大纲展开；段落自然；保留个人表达；结尾有回味；不要输出解释。
                请只输出 JSON：
                {"title":"标题建议","content":"完整正文 Markdown","summary":"80 字以内摘要","tags":["标签1","标签2","标签3"]}
                """
            ),
            PromptTemplateSeed(
                key: .polishDraft,
                name: PromptTemplateKey.polishDraft.title,
                system_prompt: "你是严谨的中文长文编辑，只输出用户要求的 JSON。",
                user_template: """
                你是我的中文长文编辑。请对当前整篇文章做一次全文改写，不要只改选中片段。

                【作者风格说明】
                {{style_description}}

                【作者风格样本】
                {{style_samples}}

                【当前写作上下文 JSON】
                {{context_json}}

                【当前正文】
                {{content}}

                【本次全文改写目标】
                {{polish_goal}}

                要求：
                1. 保留文章的核心观点、事实关系、人称和作者个人表达
                2. 可以调整段落顺序、删重复、补承接，但不要虚构新事实
                3. 不要改成营销腔、培训腔、鸡汤腔或标题党
                4. 摘要控制在 80 字以内
                5. 正文使用 Markdown
                6. 不要输出解释、寒暄或多个版本

                请只输出 JSON，不要输出 Markdown 代码块：
                {
                  "title": "保留或优化后的标题",
                  "content": "改写后的完整正文 Markdown",
                  "summary": "80 字以内摘要",
                  "tags": ["标签1", "标签2", "标签3"]
                }
                """
            ),
            PromptTemplateSeed(
                key: .writingReview,
                name: PromptTemplateKey.writingReview.title,
                system_prompt: "你是严谨的中文写作教练，只输出用户要求的 JSON。",
                user_template: """
                请诊断当前文章，目标是帮助作者提高写作能力，不要代写、不要重写全文。

                【方向】{{direction}}
                【想法】{{idea}}
                【标题】{{title}}
                【摘要】{{summary}}
                【大纲】{{outline}}
                【正文】{{content}}
                【作者风格】{{style_description}}

                【上一次诊断】
                {{previous_review}}

                诊断要求：
                1. 先判断这篇文章最核心的问题，不要泛泛夸奖
                2. 维度不限于开头/结构/观点/素材/表达/节奏/风格；如果是文学写作方向，
                   优先使用这些更具体的文学向维度：人称视角、意象与细节、留白与节奏、情感真实度、
                   文本引用关系（经典/素材引用是否服务于个人表达）、语言腔调（是否滑向文艺腔/鸡汤腔/营销腔）
                3. 每个问题都要引用原文片段并给出可执行的修改建议
                4. 先判断文章体裁：只在个人叙事、情感随笔类体裁才建议加入个人感悟或生活体验；
                   原著解读、书评、科普等体裁以忠实原文为先，不要建议加入个人体验
                5. 保留作者个人表达，不要建议改成营销腔、培训腔或标题党
                6. 如果存在"上一次诊断"，先逐条判断其中的问题这次是否已经解决：
                   已解决的写入 resolved_from_last，不要在 issues 里重复列出；
                   issues 只列仍未解决的问题和新出现的问题
                7. 如果作者风格说明列出了"作者常见雷区"，逐条判断本文是否再次命中：
                   命中的雷区写入 pitfall_hits（原样抄写雷区描述），未命中不要写

                \(scoreAnchorBlock)

                请只输出 JSON：
                {"summary":"一句话诊断","overall_score":72,"strengths":["优点"],"issues":[{"dimension":"维度","severity":"高/中/低","excerpt":"原文片段","problem":"问题","suggestion":"建议"}],"revision_plan":["修改步骤"],"training_focus":["训练重点"],"style_notes":["风格观察"],"resolved_from_last":["上一次诊断中这次已解决的问题，没有历史或没有解决的留空数组"],"pitfall_hits":["命中的雷区原文描述，未命中留空数组"]}
                """
            ),
            PromptTemplateSeed(
                key: .publishAssets,
                name: PromptTemplateKey.publishAssets.title,
                system_prompt: "你是严谨的公众号发布助手，只输出用户要求的 JSON。",
                user_template: """
                请为文章生成发布物料。

                【标题】{{title}}
                【摘要】{{summary}}
                【正文】{{content}}
                【作者风格】{{style_description}}

                要求：不要硬广，不夸张，不标题党，保持作者个人表达感。
                请只输出 JSON：
                {"summary":"公众号摘要","cover_text":"20字以内封面文案","moments_text":"朋友圈文案","tags":["标签1"],"xiaohongshu_text":"小红书版本","cover_image_prompt":"封面图提示词"}
                """
            ),
            PromptTemplateSeed(
                key: .rewriteSelection,
                name: PromptTemplateKey.rewriteSelection.title,
                system_prompt: "你是严谨的中文编辑，只输出用户要求的 JSON。",
                user_template: """
                只改写用户选中的片段，不要重写全文。

                【标题】{{title}}
                【上下文】{{surrounding_text}}
                【选中片段】{{selected_text}}
                【改写目标】{{rewrite_goal}}
                【作者风格】{{style_description}}

                要求：保留原意、事实关系、人称和 Markdown 兼容性；不要输出解释。
                请只输出 JSON：
                {"replacement":"替换后的片段","note":"一句话说明改动重点"}
                """
            ),
            PromptTemplateSeed(
                key: .writingAdvisor,
                name: PromptTemplateKey.writingAdvisor.title,
                system_prompt: "你是严谨的中文写作编辑，只输出用户要求的 JSON。",
                user_template: """
                请判断当前稿件最应该做的下一步。

                【当前写作上下文 JSON】
                {{context_json}}
                【作者风格】
                {{style_description}}

                可用动作 id：quick_draft, generate_topics, generate_outline, draft_from_outline, writing_review, rewrite_selection_natural, rewrite_selection_expand, polish_natural, polish_tighten, publish_assets, save_article。
                要求：像 Claude Code / Codex 那样先列上下文观察，再给执行计划和风险提示；不要泛泛鼓励，不要直接重写正文；建议要具体、克制、适合当前阶段。
                请只输出 JSON：
                {"stage":"阶段","main_problem":"当前最大问题","next_action":"最推荐的下一步","reason":"原因","suggested_actions":["writing_review"],"focus_area":"训练能力","context_findings":["观察1"],"execution_plan":["步骤1"],"risk_notes":["风险1"]}
                """
            ),
            PromptTemplateSeed(
                key: .draftSelfCheck,
                name: PromptTemplateKey.draftSelfCheck.title,
                system_prompt: "你是严谨的中文编辑助手，只输出用户要求的 JSON，不输出解释。",
                user_template: """
                只做轻量自检，不做完整诊断，也不改写正文。

                【标题】{{title}}
                【想法/大纲】{{idea}} {{outline}}
                【本次生成正文】{{content}}

                检查：是否偏离大纲/想法；结尾是否落套话或口号；是否语句不连贯或重复；字数是否明显不符预期。
                最多给出 3 条需要复查的片段，没问题就返回空数组。
                请只输出 JSON：
                {"has_concerns":false,"flagged_excerpts":[{"excerpt":"原文片段","concern":"具体问题"}]}
                """
            ),
            PromptTemplateSeed(
                key: .pitfallSummary,
                name: PromptTemplateKey.pitfallSummary.title,
                system_prompt: "你是严谨的中文写作复盘助手，只输出用户要求的 JSON。",
                user_template: """
                归纳这位作者反复出现的"作者雷区"。

                【历史诊断问题】
                {{issues_history}}

                要求：聚类相近问题；只保留至少出现 2 次的反复问题；每条给出具体描述和支持它的 review_id；最多 6 条。
                请只输出 JSON：
                {"candidates":[{"description":"具体雷区描述","supporting_review_ids":[12,9]}]}
                """
            ),
            PromptTemplateSeed(
                key: .editPreferenceSummary,
                name: PromptTemplateKey.editPreferenceSummary.title,
                system_prompt: "你是严谨的中文写作复盘助手，只输出用户要求的 JSON。",
                user_template: """
                从发布前人工修改记录中归纳候选"编辑偏好校准规则"。

                【编辑记录】
                {{edit_records}}
                【已确认编辑偏好】
                {{learned_preferences}}

                要求：只保留反复出现、可指导下一次生成的偏好；不要把单篇文章修改当长期规则；每条附支持它的 edit_record_id；最多 6 条。
                请只输出 JSON：
                {"monthly_summary":"本月编辑行为趋势","candidates":[{"description":"具体编辑偏好规则","source_edit_record_ids":[3,7]}]}
                """
            ),
            PromptTemplateSeed(
                key: .readerPerspective,
                name: PromptTemplateKey.readerPerspective.title,
                system_prompt: "你是严谨的读者视角模拟助手，只输出用户要求的 JSON。",
                user_template: """
                扮演这篇文章的一位典型读者，模拟真实阅读体验。

                【标题】{{title}}
                【摘要】{{summary}}
                【正文】{{content}}

                说明：读者是谁；最可能在哪失去兴趣；哪一句最可能被记住或转发；一句话补充。
                请只输出 JSON：
                {"reader_persona":"读者画像","drop_off_point":"失去兴趣的位置和原因","most_memorable_point":"被记住或转发的位置和原因","note":"一句话补充"}
                """
            ),
            PromptTemplateSeed(
                key: .prePublishAudit,
                name: PromptTemplateKey.prePublishAudit.title,
                system_prompt: "你是严谨的中文发表前终审编辑，只输出用户要求的 JSON。",
                user_template: """
                请做发表前终审，只提示风险，不改写全文，不阻止作者发布。

                【标题】{{title}}
                【摘要】{{summary}}
                【正文】{{content}}
                【作者风格】{{style_description}}
                【作者雷区】{{known_pitfalls}}

                检查：错别字/病句；引文或书名号内容是否需要人工核对；标题-摘要-正文一致性；作者雷区最终扫描。
                请只输出 JSON：
                {"passed":false,"summary":"一句话终审结论","typo_issues":[{"category":"错字/病句","severity":"高/中/低","excerpt":"原文片段","problem":"问题","suggestion":"建议"}],"quote_issues":[],"consistency_issues":[],"pitfall_issues":[]}
                """
            ),
            PromptTemplateSeed(
                key: .candidateJudge,
                name: PromptTemplateKey.candidateJudge.title,
                system_prompt: "你是严谨的中文长文候选评委，只输出用户要求的 JSON。",
                user_template: """
                比较多个全文改写候选，选出最值得进入深度成稿的一版。

                【原稿 JSON】{{base_draft_json}}
                【候选稿 JSON】{{candidate_drafts_json}}
                【作者风格】{{style_description}}

                请按真实经验保留、体裁评价重点、作者雷区、编辑偏好、结构推进和虚构风险排序。
                请只输出 JSON：
                {"best_candidate_index":1,"summary":"选择理由","rankings":[{"candidate_index":1,"score":86,"reason":"排序理由","strengths":["优点"],"risks":["风险"]}]}
                """
            ),
            PromptTemplateSeed(
                key: .agentDecision,
                name: PromptTemplateKey.agentDecision.title,
                system_prompt: "你是严谨的中文写作代理调度器，只输出用户要求的 JSON。",
                user_template: """
                你是我的中文写作代理调度器。你的职责不是写作，而是根据当前会话状态，
                决定下一步执行哪一个动作，或者停下来。

                【写作目标】
                {{goal}}

                【当前稿件状态】
                {{draft_status}}

                【已执行动作历史】
                {{action_history}}

                【剩余预算】
                {{budget}}

                【可用动作】（只能从中选择，且必须满足括号内前置条件）
                {{available_actions}}

                决策纪律：
                1. 每次只选一个动作；优先解决验证信号里的高严重度问题
                2. 同一动作连续使用不得超过 2 次；上一动作没有改善验证信号时，必须换路径或选 ask_author / finish
                3. 预算剩余不足 3 次时，只允许 writing_review、ask_author 或 finish
                4. 缺证据时用 search_materials 或 ask_author，不得让生成动作编造经历
                5. 不确定时倾向 finish——把判断交还作者永远是合法选择

                请只输出 JSON，不要输出 Markdown 代码块：
                {"action":"动作 id","arguments":{"query":"仅 search_materials / ask_author 需要"},"reason":"选择这一步的原因","expected_gain":"预计改善哪个验证信号","stop":false}
                """
            )
        ]
    }

    private enum AgentPromptMode {
        case planning
        case argumentAudit
        case briefRevision
        case sectionDraft
        case fullDraft
        case critiqueRevision
        case revision
        case reviewDrivenRevision
        case review
        case advisor
        case selectionRewrite
        case publish
        case selfCheck
        case memory
        case readerSimulation
        case prePublishAudit
        case candidateJudge
        case decision
    }

    private static func appendAgentDiscipline(to messages: [ChatMessage], mode: AgentPromptMode) -> [ChatMessage] {
        guard let lastIndex = messages.indices.last else {
            return messages
        }
        var updated = messages
        updated[lastIndex] = ChatMessage(
            role: updated[lastIndex].role,
            content: updated[lastIndex].content + "\n\n" + agentDiscipline(mode: mode)
        )
        return updated
    }

    private static func agentDiscipline(mode: AgentPromptMode) -> String {
        let modeFocus: String
        switch mode {
        case .planning:
            modeFocus = "规划：把模糊输入拆成可执行写作路径，先限定问题、读者、证据和结构。"
        case .argumentAudit:
            modeFocus = "论证审计：找出主张、证据与场景之间的缺口，个人经验缺口只在体裁适合个人叙事时提出；宁可指出不足，不要假装充分。"
        case .briefRevision:
            modeFocus = "Brief 修订：只依论点检查的缺口修订 brief，不写正文，无法用现有素材覆盖的缺口原样进 unresolved_gaps，不编造经历去填补。"
        case .sectionDraft:
            modeFocus = "分段成稿：每段只完成一个功能，先推进结构，再照顾语言。"
        case .fullDraft:
            modeFocus = "完整初稿：先遵守素材和结构边界，再生成可被复核的全文。"
        case .critiqueRevision:
            modeFocus = "自我批评后整合：先找偏题、空泛、断裂和腔调问题，再合成一版更稳的初稿。"
        case .revision:
            modeFocus = "全文改写：保留作者事实、视角和核心表达，只修真正影响阅读的问题。"
        case .reviewDrivenRevision:
            modeFocus = "诊断驱动改稿：按诊断优先级改，先处理高严重度结构和素材问题，再处理句子。"
        case .review:
            modeFocus = "写作诊断：像编辑一样挑关键问题，给出可执行修改顺序，而不是泛泛评价。"
        case .advisor:
            modeFocus = "智能下一步：先判断当前阶段和最大阻塞，再推荐动作。"
        case .selectionRewrite:
            modeFocus = "局部改写：只动选中片段，维护上下文一致性和作者语气。"
        case .publish:
            modeFocus = "发布物料：把正文转成发布表达，但不夸张、不硬广、不制造正文没有的卖点。"
        case .selfCheck:
            modeFocus = "生成后自检：只标出高风险问题，不做完整诊断，不凑数量。"
        case .memory:
            modeFocus = "复盘记忆：从历史问题里提炼反复模式，只保留有证据支撑的作者雷区。"
        case .readerSimulation:
            modeFocus = "读者模拟：站在真实读者耐心和记忆点上判断，不替编辑评分。"
        case .prePublishAudit:
            modeFocus = "发表前终审：只做错字、引文、一致性和作者雷区的安全初审，提示风险，不替作者发布。"
        case .candidateJudge:
            modeFocus = "候选评委：比较候选稿的真实细节、体裁适配、雷区风险和编辑偏好，只选最值得继续迭代的一版。"
        case .decision:
            modeFocus = "决策调度：每次只选一个动作；证据与验证信号优先；在预算内行动；把不确定交还作者永远是合法选择。"
        }

        return """
        【代理式工作纪律】
        本轮模式：\(modeFocus)
        - 上下文盘点：先区分已知输入、可用素材、作者风格、历史诊断和仍然缺失的信息。
        - 计划先行：内部先确定 2～4 步执行顺序，再生成结果；不要输出你的思考过程。
        - 证据优先：每个关键判断尽量来自当前想法、素材、正文、样本或历史诊断；缺证据时用谨慎表达，不能替作者编造具体经历。
        - 体裁适配：先依据体裁、写作方向和正文判断文章类型再给建议；个人经验、个人感悟只在个人叙事、情感随笔类体裁中作为要求或缺口提出；原著解读、书评影评、科普、资讯类体裁以忠实原文和事实准确为先，不要建议加入个人生活体验。
        - 质量门：输出前自检是否跑题、是否空泛、是否滑向标题党/营销腔/培训腔/鸡汤腔、是否破坏作者原本人称和语气。
        - JSON 纪律：只输出当前任务要求的 JSON；不要输出 Markdown 代码块、寒暄、解释、多个版本或额外字段。
        """
    }

    private static func samplesBlock(_ style: StyleProfile) -> String {
        let samples = (style.sample_texts ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !samples.isEmpty else {
            return "（暂无样本文章，请主要参考风格补充说明。）"
        }
        return samples.prefix(3).enumerated().map { index, sample in
            "【样本文章 \(index + 1)】\n\(truncate(sample))"
        }.joined(separator: "\n\n")
    }

    private static func sectionFragmentsBlock(_ contexts: [SectionFragmentContext]) -> String {
        guard !contexts.isEmpty else {
            return "无按段命中的个人素材。若缺少真实素材，请保留空白或写出作者的真实不确定，不要编造经历。"
        }
        return contexts.map { context in
            let fragments = context.fragments.enumerated().map { index, fragment in
                "\(index + 1). \(fragment.citationTitle)：\(truncate(fragment.content, chunkSize: 220))"
            }.joined(separator: "\n")
            return """
            第 \(context.section_index) 段：\(context.heading)
            检索问题：\(context.query)
            可用真实片段：
            \(fragments)
            """
        }
        .joined(separator: "\n\n")
    }

    private static func styleDescription(_ style: StyleProfile) -> String {
        [
            "体裁：\(style.genre ?? "")",
            "语言：\(style.language_style ?? "")",
            "语气：\(style.tone ?? "")",
            "结构：\(style.structure_preference ?? "")",
            "常用表达：\(style.favorite_expressions ?? "")",
            "禁忌：\(style.forbidden_expressions ?? "")",
            "喜欢的标题：\(style.title_style_like ?? "")",
            "不喜欢的标题：\(style.title_style_dislike ?? "")",
            "体裁评价重点：\(style.genre_focus ?? "")",
            "作者常见雷区（重点检查是否再次出现）：\(pitfallsInline(style))",
            "已确认编辑偏好（生成时主动遵守）：\(learnedPreferencesInline(style))"
        ]
        .filter { !$0.hasSuffix("：") }
        .joined(separator: "\n")
    }

    private static func pitfallsInline(_ style: StyleProfile) -> String {
        let pitfalls = (style.known_pitfalls ?? [])
            .map(\.description)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pitfalls.isEmpty else {
            return ""
        }
        return pitfalls.prefix(8).joined(separator: "；")
    }

    private static func learnedPreferencesInline(_ style: StyleProfile) -> String {
        let preferences = (style.learned_preferences ?? [])
            .map(\.description)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !preferences.isEmpty else {
            return ""
        }
        return preferences.prefix(8).joined(separator: "；")
    }

    private static func truncate(_ text: String, chunkSize: Int = 800) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > chunkSize * 3 else {
            return trimmed
        }
        let prefix = String(trimmed.prefix(chunkSize))
        let suffix = String(trimmed.suffix(chunkSize))
        return "\(prefix)\n\n\(suffix)"
    }

    private static func contextJSON(_ context: ContextPackage) -> String {
        encodedJSON(context, fallback: context.summaryText)
    }

    private static func encodedJSON<T: Encodable>(_ value: T, fallback: String? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return fallback ?? String(describing: value)
        }
        return text
    }

    private static func commonVariables(style: StyleProfile) -> [String: String] {
        [
            "style_description": styleDescription(style),
            "style_samples": samplesBlock(style),
            "style_name": style.name,
            "style_language": style.language_style ?? "",
            "style_tone": style.tone ?? "",
            "style_structure": style.structure_preference ?? "",
            "style_favorites": style.favorite_expressions ?? "",
            "style_forbidden": style.forbidden_expressions ?? "",
            "title_style_like": style.title_style_like ?? "",
            "title_style_dislike": style.title_style_dislike ?? "",
            "style_genre": style.genre ?? "",
            "style_genre_focus": style.genre_focus ?? "",
            "known_pitfalls": pitfallsInline(style).isEmpty ? "（暂无已确认的作者雷区）" : pitfallsInline(style),
            "learned_preferences": learnedPreferencesInline(style).isEmpty ? "（暂无已确认的编辑偏好）" : learnedPreferencesInline(style)
        ]
    }

    private static func topicVariables(_ topic: TopicPayload) -> [String: String] {
        [
            "topic_title": topic.title,
            "topic_direction": topic.direction ?? "",
            "topic_description": topic.description ?? "",
            "topic_core_viewpoint": topic.core_viewpoint ?? "",
            "topic_target_reader": topic.target_reader ?? "",
            "topic_angle": topic.angle ?? "",
            "topic_emotion": topic.emotion ?? "",
            "topic_tags": (topic.tags ?? []).joined(separator: "，")
        ]
    }

    private static func render(_ template: PromptTemplate, variables: [String: String]) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: replacePlaceholders(template.system_prompt, variables: variables)),
            ChatMessage(role: "user", content: replacePlaceholders(template.user_template, variables: variables))
        ]
    }

    private static func appendAdvisorOutputContract(to messages: [ChatMessage]) -> [ChatMessage] {
        guard let lastIndex = messages.indices.last else {
            return messages
        }
        var updated = messages
        let contract = """

        【代理式输出补充】
        为了让本次判断像 Claude Code / Codex 的任务推进一样可复核，请在 JSON 中额外返回：
        - context_findings: 3～5 条上下文观察，只能依据当前稿件、素材、风格、历史诊断和作者雷区
        - execution_plan: 2～5 步执行计划，说明接下来按什么顺序推进
        - risk_notes: 1～3 条风险，说明当前直接生成、直接润色或直接发布可能损失什么
        """
        updated[lastIndex] = ChatMessage(
            role: updated[lastIndex].role,
            content: updated[lastIndex].content + contract
        )
        return updated
    }

    private static func replacePlaceholders(_ template: String, variables: [String: String]) -> String {
        variables.reduce(template) { partial, item in
            partial.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }
}
