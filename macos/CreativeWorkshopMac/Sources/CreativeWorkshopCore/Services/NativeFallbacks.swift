import Foundation

package enum NativeFallbacks {
    package static func plainDraftFallback(input: String, direction: String, materials: String) -> DraftResult {
        let topic = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "今天的写作想法" : input
        let directionText = direction.isEmpty ? "日常观察" : direction
        let materialBlock = materials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\n\n可用素材里最值得保留的一点是：\(materials.trimmingCharacters(in: .whitespacesAndNewlines))"
        return DraftResult(
            title: "\(topic)：先把事情做小一点",
            content: """
            ## \(topic)：先把事情做小一点

            很多时候，我们卡住不是因为完全没有想法，而是因为一开始就想把它写得太完整。

            今天这个方向是「\(directionText)」。如果只把它当成一篇文章，它会显得有点重；但如果先把它当成一次整理，事情就轻了很多。\(materialBlock)

            我更愿意从一个很小的问题开始：这件事到底触动了我什么？是一个工具带来的效率变化，还是一个普通人重新获得掌控感的瞬间？

            当这个问题被看清楚，文章的结构也会自然出现：先写真实处境，再写观察，再写一个可以被别人带走的小方法。这样的文章不一定惊天动地，但它更像一个人在认真说话。

            所以今天先不用追求完美。先写下来，留下可以修改的东西。很多稳定的表达，就是从这样一个不那么郑重的开始里长出来的。
            """,
            summary: "围绕「\(topic)」整理一个可继续修改的公众号初稿，从现实处境切入，给出观察和行动建议。",
            tags: [directionText, "写作", "个人表达"],
            raw_output: nil
        )
    }

    package static func writingBrief(input: String, direction: String, materials: String) -> WritingBriefResult {
        let topic = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "今天的写作想法" : input
        let directionText = direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "日常观察" : direction
        return WritingBriefResult(
            working_title: "\(topic)：先从一个真实问题写起",
            core_question: "这件事到底触动了作者什么，又为什么值得读者读完？",
            thesis: "好文章不是把概念说大，而是把一个真实处境说清楚。",
            target_reader: "对「\(directionText)」有兴趣，但更希望读到真实经验而不是空泛建议的人",
            emotional_center: "克制、真诚、有一点自我追问",
            material_strategy: [
                materials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "当前素材较少，优先补一个亲历场景。"
                    : "从素材中挑一个最具体的场景放在开头或第二段。",
                "抽象判断只作为段落收束，不作为正文主体。"
            ],
            structure_plan: [
                WritingBriefSection(
                    heading: "具体场景",
                    purpose: "让读者知道这不是凭空议论。",
                    key_points: ["写一个发生过的瞬间", "提出核心问题"],
                    material_hint: String(materials.prefix(100))
                ),
                WritingBriefSection(
                    heading: "核心观察",
                    purpose: "把个人感受压成可讨论的判断。",
                    key_points: ["说明为什么这件事值得写", "避免直接拔高"],
                    material_hint: "用想法本身作为主线"
                ),
                WritingBriefSection(
                    heading: "展开与回收",
                    purpose: "补充例子、边界和余味。",
                    key_points: ["补一个例子", "说明边界", "结尾回到核心观点或原文"],
                    material_hint: "如果素材不足，保留空白感，不硬编事实"
                )
            ],
            must_keep: ["真实处境", "作者个人表达", "克制语气"],
            avoid: ["标题党", "培训腔", "空泛鸡汤", "虚构事实"],
            raw_output: nil
        )
    }

    package static func argumentCheck(brief: WritingBriefResult, materials: String) -> ArgumentCheckResult {
        ArgumentCheckResult(
            thesis_strength: "主张可以成立，但必须依靠具体场景和可靠证据支撑。",
            weak_points: [
                "如果只围绕「\(brief.thesis ?? "核心主张")」展开，容易变成抽象议论。",
                "素材不足时，中段最容易松散。"
            ],
            missing_evidence: materials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ["需要补一个亲历场景或具体例子。"]
                : ["需要明确哪些素材直接进入正文，哪些只作为背景。"],
            revision_directives: [
                "开头必须落在具体场景，不要先下结论。",
                "每个抽象判断后面至少跟一个事实、动作或感受。",
                "结尾不要喊口号，回到一个可感的细节。"
            ],
            ready_to_draft: true,
            raw_output: nil
        )
    }

    /// 论点检查判定 brief 不足以支撑成稿时的本地兜底：原样保留 brief，只把缺证据项透传为 unresolved_gaps，
    /// 不替作者编造经历去填补缺口（PRD 22.2.1）。
    package static func briefRevision(brief: WritingBriefResult, argumentCheck: ArgumentCheckResult) -> WritingBriefResult {
        var revised = brief
        revised.unresolved_gaps = argumentCheck.missing_evidence ?? []
        return revised
    }

    package static func sectionDraft(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        context: ContextPackage
    ) -> SectionDraftResult {
        let sections = (brief.structure_plan ?? []).enumerated().map { index, planned in
            let points = (planned.key_points ?? []).joined(separator: "；")
            let directive = argumentCheck.revision_directives?.first ?? "从具体处境写起。"
            let matched = context.section_fragment_contexts?.first { $0.section_index == index + 1 }?.fragments.first
            let materialLine = matched.map { "可用真实片段：\($0.content)" }
                ?? (planned.material_hint?.isEmpty == false ? "可用素材：\(planned.material_hint!)" : "如果暂时没有素材，就保留作者真实的犹豫，不要硬编例子。")
            return DraftSection(
                heading: planned.heading,
                content: """
                \(planned.purpose)

                这一段先处理：\(points.isEmpty ? planned.purpose : points)。\(directive)

                \(materialLine)
                """,
                self_check: "已按 brief 的段落功能生成一版可继续修订的段落。"
            )
        }
        return SectionDraftResult(
            title: brief.working_title,
            sections: sections,
            raw_output: nil
        )
    }

    package static func draftCritique(
        brief: WritingBriefResult,
        argumentCheck: ArgumentCheckResult,
        sectionDraft: SectionDraftResult,
        direction: String
    ) -> DraftCritiqueResult {
        let title = brief.working_title ?? "从一个真实问题写起"
        let body = sectionDraft.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = body.isEmpty ? plainDraftFallback(input: brief.core_question ?? title, direction: direction, materials: "").content ?? "" : body
        return DraftCritiqueResult(
            critique_notes: [
                "当前为本地代理兜底稿，已按上下文盘点、论点检查、分段成稿、自我批评的顺序生成。",
                "质量门提醒：兜底稿不会编造亲历细节，具体场景和段落承接仍需要模型或作者继续补足。"
            ],
            title: title,
            content: content,
            summary: "围绕「\(title)」生成一版可复核初稿，从具体处境进入核心观察。",
            tags: [direction.isEmpty ? "写作" : direction, "代理初稿", "个人表达"],
            raw_output: nil
        )
    }

    package static func improveDraftFromReview(context: ContextPackage, content: String, review: WritingReview) -> DraftResult {
        let title = context.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名文章" : context.title
        let issues = review.issues.prefix(3).map { "- [\($0.dimension)] \($0.suggestion)" }.joined(separator: "\n")
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedContent.isEmpty ? "请先补充正文，再按诊断改全文。" : trimmedContent
        let improved = """
        \(base)

        ---

        本轮根据写作教练诊断，优先处理以下修改方向：
        \(issues.isEmpty ? "- 保留核心观点，补足结构承接和具体场景。" : issues)

        本地兜底只执行"诊断优先级整理"，不会虚构新事实。请先确认这些问题是否真是当前最大阻塞，再继续让模型做全文修订。
        """
        return DraftResult(
            title: title,
            content: improved,
            summary: context.summary.isEmpty ? review.summary : context.summary,
            tags: [context.direction, "诊断改稿"].filter { !$0.isEmpty },
            raw_output: nil
        )
    }

    package static func topics(context: ContextPackage) -> [TopicPayload] {
        let direction = context.direction
        let seed = context.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "今天这个想法" : context.idea
        return [
            TopicPayload(
                title: "\(seed)，为什么值得认真写一次",
                direction: direction,
                core_viewpoint: "\(seed)的价值不在概念本身，而在它能不能帮普通人解决一个具体问题。",
                target_reader: "有类似经历、但还没整理清楚的人",
                description: "从一个具体问题切入，讲清它背后的真实处境。",
                angle: "现实痛点 + 个人观察 + 可执行方法",
                emotion: "克制",
                score: 4,
                status: "待写",
                tags: [direction, "公众号选题"]
            ),
            TopicPayload(
                title: "普通人理解\(seed)的最小入口",
                direction: direction,
                core_viewpoint: "复杂话题要先落到一个可以尝试的小入口，理解才会真正发生。",
                target_reader: "想把想法写成文章、但不想被概念劝退的读者",
                description: "用一个笨办法解释复杂感受或概念。",
                angle: "降低理解门槛，避免术语堆砌",
                emotion: "平实",
                score: 5,
                status: "待写",
                tags: [direction, "解释型文章"]
            ),
            TopicPayload(
                title: "我重新看待\(seed)之后，发现它并不遥远",
                direction: direction,
                core_viewpoint: "真正改变人的不是宏大的叙事，而是某一次具体经验带来的掌控感。",
                target_reader: "关注个人经验如何变成稳定表达的人",
                description: "把抽象话题落回个人使用体验。",
                angle: "个人经历 + 认知转变",
                emotion: "轻微感慨",
                score: 3,
                status: "待写",
                tags: [direction, "个人表达"]
            )
        ]
    }

    package static func outline(topic: TopicPayload, context: ContextPackage) -> OutlineResult {
        OutlineResult(
            title: topic.title,
            opening: "从一个普通人会遇到的具体场景切入，提出读者心里的疑问。",
            sections: [
                OutlineSection(
                    heading: "先把问题说清楚",
                    points: ["这个想法出现之前，读者卡在哪里", "为什么原来的方式不够顺"],
                    material_hint: String(context.materials_excerpt.prefix(80))
                ),
                OutlineSection(
                    heading: "再解释真正值得写的部分",
                    points: ["用一句话说清核心观点", "拆成几个具体场景", "避免空泛抒情"],
                    material_hint: "可插入与体裁匹配的例子或素材"
                ),
                OutlineSection(
                    heading: "最后讲它的边界",
                    points: ["它能解决什么", "它不能自动解决什么", "写作时要避免什么"],
                    material_hint: "可插入自己的犹豫和判断"
                )
            ],
            ending: "回到普通人的现实选择：先解决一个小问题，再慢慢理解更大的变化。",
            raw_output: nil
        )
    }

    package static func draft(topic: TopicPayload, context: ContextPackage) -> DraftResult {
        let title = topic.title.isEmpty ? "从一个小问题开始" : topic.title
        return DraftResult(
            title: title,
            content: """
            # \(title)

            很多文章写不下去，是因为一开始就想把所有问题都讲完整。

            更稳的办法，是先抓住一个具体场景：读者为什么会在这里卡住？这个问题如果不解决，会给他带来什么麻烦？

            这篇文章可以沿着下面的大纲展开：

            \(context.outline_excerpt)

            可用素材里有一部分值得保留：\(String(context.materials_excerpt.prefix(160)))

            等这些部分被放到同一条线上，文章就不只是解释一个概念，而是在帮读者穿过一个具体问题。
            """,
            summary: "围绕「\(title)」展开，从具体问题切入，解释概念价值和使用边界。",
            tags: topic.tags ?? ["公众号", "写作"],
            raw_output: nil
        )
    }

    package static func polishDraft(title: String, summary: String, content: String, mode: PolishMode) -> DraftResult {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名文章"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackContent = trimmedContent.isEmpty ? "请先写下一版正文，再进行全文润色。" : trimmedContent
        let polished: String
        switch mode {
        case .natural:
            polished = naturalized(fallbackContent)
        case .tighten:
            polished = fallbackContent
                .components(separatedBy: "\n\n")
                .map { paragraph in
                    let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count > 120 else { return text }
                    return shortened(text)
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .deepen:
            polished = """
            \(fallbackContent)

            回头看，真正需要被保留下来的，不只是一个判断，而是这个判断从哪里长出来。它来自具体经历、反复确认后的选择，也来自那些说不清但一直没有消失的感受。把这一层写清楚，文章就不只是顺滑了一点，而是多了一点能站住的东西。
            """
        case .conversational:
            polished = "说得直白一点，" + naturalized(fallbackContent)
        }
        let resolvedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "对「\(resolvedTitle)」完成一次全文润色，保留原意并改善表达节奏。"
            : summary
        return DraftResult(
            title: resolvedTitle,
            content: polished,
            summary: resolvedSummary,
            tags: fallbackTags(title: resolvedTitle, content: polished),
            raw_output: nil
        )
    }

    package static func writingReview(
        context: ContextPackage
    ) -> WritingReviewResult {
        let trimmedTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = context.content_excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutline = context.outline_excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphCount = trimmedContent
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        var score = 68
        var strengths: [String] = []
        var issues: [WritingReviewIssue] = []
        var revisionPlan: [String] = []
        var trainingFocus: [String] = []
        var styleNotes: [String] = []

        if !trimmedTitle.isEmpty {
            strengths.append("标题已经给出明确方向，适合作为后续修改的锚点。")
            score += 4
        } else {
            issues.append(WritingReviewIssue(
                dimension: "标题",
                severity: "中",
                excerpt: nil,
                problem: "当前稿件还没有明确标题，读者进入文章前缺少预期。",
                suggestion: "先用一句朴素的话写清这篇文章真正要讨论的问题，再考虑文采。"
            ))
            revisionPlan.append("先补一个临时标题，用来限定文章的核心问题。")
        }

        if trimmedContent.count >= 800 {
            strengths.append("正文已经有一定体量，可以进入结构和句子层面的精修。")
            score += 8
        } else if trimmedContent.isEmpty {
            issues.append(WritingReviewIssue(
                dimension: "正文",
                severity: "高",
                excerpt: nil,
                problem: "正文为空，目前还不能判断文章的真实表达效果。",
                suggestion: "先沿着大纲写出一个不追求完美的完整版本，再做诊断会更有效。"
            ))
            revisionPlan.append("把想法或大纲先扩成 5 到 8 个自然段。")
            score -= 14
        } else {
            issues.append(WritingReviewIssue(
                dimension: "展开",
                severity: "中",
                excerpt: String(trimmedContent.prefix(60)),
                problem: "正文还偏短，观点可能没有足够的场景和论证支撑。",
                suggestion: "为每个关键判断补一个具体例子，优先写亲历场景，不急着拔高。"
            ))
            revisionPlan.append("逐段检查：每个判断后面至少补一个事实、场景或小故事。")
            score -= 6
        }

        if paragraphCount >= 5 {
            strengths.append("段落数量足够，适合继续调整段落之间的承接关系。")
        } else {
            issues.append(WritingReviewIssue(
                dimension: "结构",
                severity: "中",
                excerpt: nil,
                problem: "段落层次还不够清楚，读者可能难以感到文章在推进。",
                suggestion: "把文章拆成开头、核心观察、展开论证、呼应核心观点、结尾五个部分。"
            ))
            trainingFocus.append("训练段落推进：每一段只承担一个功能。")
        }

        if !trimmedOutline.isEmpty {
            strengths.append("已有大纲，说明文章不是完全散写，可以用它来做改稿清单。")
        } else {
            issues.append(WritingReviewIssue(
                dimension: "大纲",
                severity: "低",
                excerpt: nil,
                problem: "缺少大纲会让修改时容易陷入逐句打磨，而忽略整体结构。",
                suggestion: "先写一个四段式大纲，再判断每段是否服务核心观点。"
            ))
        }

        let abstractWords = ["价值", "认知", "底层逻辑", "长期主义", "本质", "能力"]
        let matchedAbstractWords = abstractWords.filter {
            trimmedContent.contains($0)
                || context.summary.contains($0)
                || context.idea.contains($0)
        }
        if !matchedAbstractWords.isEmpty {
            issues.append(WritingReviewIssue(
                dimension: "表达",
                severity: "低",
                excerpt: matchedAbstractWords.prefix(3).joined(separator: "、"),
                problem: "稿件里出现了一些抽象词，如果缺少具体场景，容易显得像结论先行。",
                suggestion: "每出现一个抽象判断，就追问一次：这个判断发生在哪个具体人、事、场景里？"
            ))
            trainingFocus.append("训练把抽象判断落回具体场景。")
        }

        if revisionPlan.isEmpty {
            revisionPlan = [
                "先确认开头是否用一个具体场景把读者带进来。",
                "再检查每个小标题或段落是否都在服务同一个核心观点。",
                "最后删掉解释不清的抽象句，换成具体经历或动作。"
            ]
        }
        if trainingFocus.isEmpty {
            trainingFocus = ["训练开头场景化", "训练段落承接", "训练结尾不喊口号"]
        }
        styleNotes.append("当前诊断来自本地规则，只做保底参考；配置 API Key 后会得到更细的编辑反馈。")

        let clampedScore = min(95, max(35, score))
        return WritingReviewResult(
            summary: trimmedContent.isEmpty ? "当前更像一个写作准备稿，下一步应先完成可修改的正文。" : "当前稿件已有方向，接下来要把结构推进和具体素材补实。",
            overall_score: clampedScore,
            strengths: Array(strengths.prefix(4)),
            issues: Array(issues.prefix(5)),
            revision_plan: Array(revisionPlan.prefix(5)),
            training_focus: Array(trainingFocus.prefix(4)),
            style_notes: styleNotes,
            raw_output: nil
        )
    }

    package static func rewriteSelection(selectedText: String, mode: RewriteMode, customInstruction: String? = nil) -> RewriteResult {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return RewriteResult(replacement: selectedText, note: "没有选中可改写的正文。", raw_output: nil)
        }

        let trimmedInstruction = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedInstruction.isEmpty {
            return RewriteResult(
                replacement: naturalized(text),
                note: "本地环境暂时无法按具体建议改写，已返回轻度调整版本，请人工核对是否解决了「\(trimmedInstruction.prefix(30))」这个问题。",
                raw_output: nil
            )
        }

        let replacement: String
        let note: String
        switch mode {
        case .natural:
            replacement = naturalized(text)
            note = "弱化模板感，让句子更像真实作者的表达。"
        case .expand:
            replacement = """
            \(text)

            更具体地说，这里真正值得展开的，不是一个漂亮结论，而是它发生在什么场景里、对人造成了什么影响，以及为什么这个感受会一直留在那里。
            """
            note = "补充一个可继续展开的解释层。"
        case .shorten:
            replacement = shortened(text)
            note = "删去重复和铺垫，保留主干意思。"
        case .deepen:
            replacement = """
            \(text)

            真正值得留意的是，这件事表面上只是一个选择，背后其实是在重新确认：什么东西只是暂时有用，什么东西会在更长时间里继续影响一个人。
            """
            note = "增加一层观察，但不改变原意。"
        case .vivid:
            replacement = """
            如果把它落到一个具体场景里，大概就是一个人停在原地，手里还攥着没来得及处理的事情，心里却已经知道，有些东西不能再像过去那样含混带过了。\(text)
            """
            note = "用场景入口增强画面感。"
        case .conversational:
            replacement = "说得直白一点，\(naturalized(text))"
            note = "改成更接近日常说话的口吻。"
        case .custom:
            replacement = naturalized(text)
            note = "本地环境下的默认调整，请人工核对。"
        }
        return RewriteResult(replacement: replacement, note: note, raw_output: nil)
    }

    /// 生成后自检的本地兜底：不调用模型，只用简单规则标一个"建议复查"信号，不判定为确定问题。
    package static func draftSelfCheck(context: ContextPackage) -> DraftSelfCheckResult {
        let trimmed = context.content_excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil)
        }
        var flagged: [FlaggedExcerpt] = []
        if trimmed.count > 1_500 {
            let mid = trimmed.index(trimmed.startIndex, offsetBy: trimmed.count / 2)
            let windowStart = trimmed.index(mid, offsetBy: -20, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
            let windowEnd = trimmed.index(mid, offsetBy: 20, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            flagged.append(
                FlaggedExcerpt(
                    excerpt: String(trimmed[windowStart..<windowEnd]),
                    concern: "本地自检未接入模型，长文本中段容易出现连贯性下滑，建议人工重点复查这一段。"
                )
            )
        }
        return DraftSelfCheckResult(has_concerns: !flagged.isEmpty, flagged_excerpts: flagged, raw_output: nil)
    }

    /// 归纳雷区的本地兜底：按 dimension 做频次统计，没有模型时也能给出一个保底候选。
    package static func summarizePitfalls(issues: [(reviewID: Int, dimension: String, problem: String)]) -> PitfallSummaryResult {
        guard !issues.isEmpty else {
            return PitfallSummaryResult(candidates: [], raw_output: nil)
        }
        var grouped: [String: [(reviewID: Int, problem: String)]] = [:]
        for issue in issues {
            grouped[issue.dimension, default: []].append((issue.reviewID, issue.problem))
        }
        let candidates = grouped
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(6)
            .map { dimension, occurrences in
                PitfallCandidate(
                    description: "「\(dimension)」问题反复出现（\(occurrences.count) 次），例如：\(occurrences.last?.problem ?? "")",
                    supporting_review_ids: occurrences.map(\.reviewID)
                )
            }
        return PitfallSummaryResult(candidates: Array(candidates), raw_output: nil)
    }

    package static func summarizeEditPreferences(records: [EditRecord]) -> EditPreferenceSummaryResult {
        guard !records.isEmpty else {
            return EditPreferenceSummaryResult(candidates: [], monthly_summary: "暂无发布编辑记录。", raw_output: nil)
        }

        var candidates: [EditPreferenceCandidate] = []
        let heavyRecords = records.filter { $0.edit_ratio > 0.10 }
        if heavyRecords.count >= 2 {
            candidates.append(
                EditPreferenceCandidate(
                    description: "AI 初稿与最终发布稿差异较大时，下一次生成应先收紧结构和段落功能，避免把问题留给发布前重写。",
                    source_edit_record_ids: heavyRecords.prefix(6).map(\.id)
                )
            )
        }

        let deletionHeavy = records.filter { $0.removed_characters > $0.added_characters }
        if deletionHeavy.count >= 2 {
            candidates.append(
                EditPreferenceCandidate(
                    description: "作者发布前常做删减，生成时应减少重复解释和总结式铺垫，保留更直接的个人观察。",
                    source_edit_record_ids: deletionHeavy.prefix(6).map(\.id)
                )
            )
        }

        let additionHeavy = records.filter { $0.added_characters > $0.removed_characters }
        if additionHeavy.count >= 2 {
            candidates.append(
                EditPreferenceCandidate(
                    description: "作者发布前常补内容，生成时应主动补足具体场景、承接和论证细节，不只给顺滑表达。",
                    source_edit_record_ids: additionHeavy.prefix(6).map(\.id)
                )
            )
        }

        if candidates.isEmpty, let record = records.first {
            candidates.append(
                EditPreferenceCandidate(
                    description: "样本仍少，先观察发布前编辑比例；暂不把单篇修改升级为长期偏好。",
                    source_edit_record_ids: [record.id]
                )
            )
        }

        let zeroCount = records.filter { $0.edit_ratio <= 0.01 }.count
        let lightCount = records.filter { $0.edit_ratio <= 0.10 }.count
        let summary = "最近 \(records.count) 篇中，零改 \(zeroCount) 篇，轻改 \(lightCount) 篇。"
        return EditPreferenceSummaryResult(candidates: Array(candidates.prefix(6)), monthly_summary: summary, raw_output: nil)
    }

    package static func judgeDraftCandidates(candidates: [DraftCandidate]) -> CandidateJudgeResult {
        let rankings = candidates
            .map { candidate -> CandidateScore in
                let paragraphCount = candidate.content.components(separatedBy: "\n\n")
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .count
                let score = min(90, 65 + min(paragraphCount * 3, 15) + min(candidate.content.count / 400, 10))
                return CandidateScore(
                    candidate_index: candidate.index,
                    score: score,
                    reason: "本地评委按段落完整度、正文体量和标题可用性做保底排序。",
                    strengths: ["结构相对完整"],
                    risks: ["本地兜底无法判断细腻度、真实素材使用和作者雷区"]
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidate_index < rhs.candidate_index
                }
                return lhs.score > rhs.score
            }
        return CandidateJudgeResult(
            best_candidate_index: rankings.first?.candidate_index ?? candidates.first?.index,
            rankings: rankings,
            summary: "本地评委已选择当前看起来最完整的一版，建议仍人工核对。",
            raw_output: nil
        )
    }

    package static func readerPerspective(context: ContextPackage) -> ReaderPerspectiveResult {
        let resolvedTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "这篇文章" : context.title
        let trimmedContent = context.content_excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReaderPerspectiveResult(
            reader_persona: "平时刷公众号、耐心有限的普通读者",
            drop_off_point: trimmedContent.count > 1_200
                ? "正文偏长，读者最可能在中段失去耐心，如果那一段没有具体场景或例子。"
                : "本地兜底未接入模型，无法准确判断具体位置，建议配置 API Key 后重试。",
            most_memorable_point: "开头如果有一个具体场景或反差，最可能被记住；「\(resolvedTitle)」本身是否有记忆点也值得留意。",
            note: "当前为本地规则生成的保底参考，配置 API Key 后可获得更准确的读者视角模拟。",
            raw_output: nil
        )
    }

    package static func writingAdvisor(context: ContextPackage) -> WritingAdvisorResult {
        let contentIsEmpty = context.word_count == 0
        let outlineIsEmpty = context.outline_excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let ideaIsEmpty = context.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelectionAction = context.word_count > 0

        if contentIsEmpty && outlineIsEmpty && ideaIsEmpty {
            return WritingAdvisorResult(
                stage: "空白阶段",
                main_problem: "当前还缺少一个可以推进的写作入口。",
                next_action: "先写下一句真实想法，或者从素材箱选择一个素材。",
                reason: "没有想法、标题或大纲时，直接生成容易变成泛泛模板。",
                suggested_actions: ["generate_topics"],
                focus_area: "把模糊念头变成可写问题",
                context_findings: [
                    "当前没有可复用的想法、标题或大纲。",
                    "没有足够上下文时，系统无法判断读者、主张和素材边界。",
                    "缺少明确问题时，直接成稿会滑向模板化表达。",
                    "更适合先把模糊念头变成几个可判断的选题。"
                ],
                execution_plan: [
                    "先补一句真实想法或选择一个素材。",
                    "再生成选题，筛出最有个人表达空间的一条。",
                    "选定选题后再进入大纲。"
                ],
                risk_notes: ["此时直接生成正文，最容易得到没有具体素材支撑的空泛文章。"],
                raw_output: nil
            )
        }

        if contentIsEmpty && outlineIsEmpty {
            return WritingAdvisorResult(
                stage: context.stage,
                main_problem: "已有想法，但文章还没有结构。",
                next_action: "先生成大纲，确定开头、核心观察和结尾。",
                reason: "此时直接润色没有对象，直接成稿也容易偏离原始想法。",
                suggested_actions: ["generate_outline", "generate_topics"],
                focus_area: "把想法组织成结构",
                context_findings: [
                    "当前已有想法，但还没有稳定结构。",
                    "下一步应先限定核心问题、目标读者和可用素材位置。",
                    "正文为空，语言层面的润色暂时没有对象。",
                    "先确定开头、核心观察和结尾，能降低后续跑偏概率。"
                ],
                execution_plan: [
                    "先生成或手写大纲。",
                    "检查大纲里是否有现实场景、核心观点和收束。",
                    "确认结构后再大纲成稿。"
                ],
                risk_notes: ["跳过大纲直接成稿，可能会把原始想法稀释成通用议论文。"],
                raw_output: nil
            )
        }

        if contentIsEmpty {
            return WritingAdvisorResult(
                stage: context.stage,
                main_problem: "大纲已经存在，但还没有可修改的正文。",
                next_action: "用大纲成稿，先得到一版可以编辑的草稿。",
                reason: "写作训练需要具体文本，空大纲阶段不适合进入诊断。",
                suggested_actions: ["draft_from_outline"],
                focus_area: "从结构进入完整表达",
                context_findings: [
                    "当前已有大纲，但没有正文。",
                    "此阶段最缺的是可被诊断和修改的完整文本。",
                    "大纲成稿时应优先保持结构推进，不急着追求句子漂亮。",
                    "大纲已经足够作为第一版正文的约束。"
                ],
                execution_plan: [
                    "先按大纲生成一版完整草稿。",
                    "生成后检查是否偏离大纲和原始想法。",
                    "再用写作诊断决定优先修改结构还是表达。"
                ],
                risk_notes: ["在没有正文时反复调整大纲，容易拖延进入真正写作。"],
                raw_output: nil
            )
        }

        if context.word_count < 800 {
            return WritingAdvisorResult(
                stage: context.stage,
                main_problem: "正文还偏短，观点可能缺少场景和论证支撑。",
                next_action: "先做写作诊断，找出最该补的段落。",
                reason: "短稿最容易误把润色当修改，先判断缺什么更稳。",
                suggested_actions: hasSelectionAction ? ["writing_review", "rewrite_selection_expand"] : ["writing_review"],
                focus_area: "补具体场景和段落推进",
                context_findings: [
                    "正文已经存在，但篇幅还偏短。",
                    "短稿常见问题不是句子不够漂亮，而是场景、转折或论证不足。",
                    "当前更需要定点补证据，而不是整体润色。",
                    "先诊断能判断应该扩哪里，而不是平均用力润色。"
                ],
                execution_plan: [
                    "先运行写作诊断，找到最影响阅读的问题。",
                    "对能定位的片段做定点扩写或加深。",
                    "补完结构缺口后再做全文自然化。"
                ],
                risk_notes: ["直接全文润色可能让短稿更顺，但不会补足真正缺失的内容。"],
                raw_output: nil
            )
        }

        if context.recent_issues.contains(where: { $0.contains("开头") || $0.contains("结构") }) {
            return WritingAdvisorResult(
                stage: context.stage,
                main_problem: "历史诊断提示开头或结构问题反复出现。",
                next_action: "先运行写作诊断，再按优先修改项处理。",
                reason: "这能把修改顺序固定下来，避免陷入逐句打磨。",
                suggested_actions: ["writing_review"],
                focus_area: "开头场景化和结构推进",
                context_findings: [
                    "历史诊断里反复出现开头或结构问题。",
                    "当前稿件已有正文，适合先判断旧问题是否复发。",
                    "如果旧问题未解决，应先处理复发点，再进入语言层面。",
                    "修改顺序需要先定下来，避免只修句子。"
                ],
                execution_plan: [
                    "先运行写作诊断，对照历史问题。",
                    "优先处理仍未解决的结构或开头问题。",
                    "确认主要问题解决后，再做全文润色。"
                ],
                risk_notes: ["如果直接润色，可能会掩盖结构问题，让文章看似顺滑但仍缺推进。"],
                raw_output: nil
            )
        }

        return WritingAdvisorResult(
            stage: context.stage,
            main_problem: "正文已有基础，可以进入编辑判断。",
            next_action: "先做写作诊断，再尝试一次全文自然润色。",
            reason: "诊断能帮助区分结构问题和句子问题，全文润色会留下可恢复版本，适合进入正式改稿。",
            suggested_actions: ["writing_review", "polish_natural", "publish_assets"],
            focus_area: "从完整草稿进入编辑复盘",
            context_findings: [
                "正文已有基础，可以进入编辑判断。",
                "当前最需要区分结构问题和语言问题。",
                "先诊断再润色，能避免把深层问题盖成表面顺滑。",
                "已有版本管理，适合做可恢复的改稿尝试。"
            ],
            execution_plan: [
                "先运行写作诊断，确认最大问题。",
                "按诊断优先处理结构或关键段落。",
                "再做全文自然润色并复核差异。",
                "定稿后生成发布物料。"
            ],
            risk_notes: ["如果跳过诊断直接发布，可能遗漏中段松散、结尾口号化等深层问题。"],
            raw_output: nil
        )
    }

    package static func publishAssets(context: ContextPackage) -> PublishAssetsResult {
        let resolvedTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "今天的想法"
            : context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSummary = context.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "这篇文章围绕「\(resolvedTitle)」展开，整理真实处境、个人观察和可继续修改的表达方向。"
            : context.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = fallbackTags(title: resolvedTitle, content: context.content_excerpt)
        return PublishAssetsResult(
            summary: resolvedSummary,
            cover_text: "先写下来",
            moments_text: "今天这篇更像一次整理：不追求宏大结论，只把一个真实想法说清楚。",
            tags: tags,
            xiaohongshu_text: "最近在整理「\(resolvedTitle)」。比起追求复杂结论，我更想把它讲成普通人也能靠近的小入口。适合想稳定写作、慢慢理清自己表达的人看看。",
            cover_image_prompt: "简洁公众号封面，一张安静书桌，笔记本电脑与手写笔记，温暖自然光，克制、干净、有思考感",
            raw_output: nil
        )
    }

    package static func prePublishAudit(context: ContextPackage, style: StyleProfile) -> PrePublishAuditReport {
        let title = context.title
        let summary = context.summary
        let trimmedContent = context.content_excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        var typoIssues: [AuditIssue] = []
        if title.contains("葬花呤") || trimmedContent.contains("葬花呤") {
            typoIssues.append(
                AuditIssue(
                    category: "错字",
                    severity: "中",
                    excerpt: "葬花呤",
                    problem: "疑似错字，应为《葬花吟》。",
                    suggestion: "确认是否为《葬花吟》，如是则统一修正。"
                )
            )
        }

        var consistencyIssues: [AuditIssue] = []
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !trimmedContent.contains(String(title.prefix(min(8, title.count)))) {
            consistencyIssues.append(
                AuditIssue(
                    category: "一致性",
                    severity: "低",
                    excerpt: title,
                    problem: "标题关键词在正文中没有明显回收。",
                    suggestion: "发布前快速确认标题、摘要和正文主线是否一致。"
                )
            )
        }

        let pitfallIssues = (style.known_pitfalls ?? []).compactMap { pitfall -> AuditIssue? in
            let description = pitfall.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty,
                  trimmedContent.localizedStandardContains(description) else {
                return nil
            }
            return AuditIssue(
                category: "作者雷区",
                severity: "中",
                excerpt: description,
                problem: "正文疑似再次命中已确认的作者雷区。",
                suggestion: "发布前人工确认这不是旧问题复发。"
            )
        }

        let issues = typoIssues + consistencyIssues + pitfallIssues
        return PrePublishAuditReport(
            passed: issues.isEmpty,
            summary: issues.isEmpty ? "本地终审未发现明显风险，可进入人工确认发布。" : "本地终审发现 \(issues.count) 条建议复核项。",
            typo_issues: typoIssues,
            quote_issues: [],
            consistency_issues: consistencyIssues,
            pitfall_issues: pitfallIssues,
            raw_output: nil
        )
    }

    private static func fallbackTags(title: String, content: String) -> [String] {
        let text = "\(title)\n\(content)"
        var tags = ["写作", "公众号", "个人表达"]
        if text.contains("AI") || text.contains("API") || text.contains("模型") {
            tags.append("AI 工具")
        }
        if text.contains("成都") {
            tags.append("成都")
        }
        if text.contains("红楼梦") || text.contains("林黛玉") {
            tags.append("读书随笔")
        }
        return Array(tags.prefix(6))
    }

    private static func naturalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "毋庸置疑", with: "说到底")
            .replacingOccurrences(of: "不可否认的是", with: "我慢慢觉得")
            .replacingOccurrences(of: "本质上", with: "往深处看")
            .replacingOccurrences(of: "我们必须", with: "也许我们得")
            .replacingOccurrences(of: "赋能", with: "帮到")
            .replacingOccurrences(of: "打造", with: "做出")
            .replacingOccurrences(of: "闭环", with: "完整过程")
    }

    private static func shortened(_ text: String) -> String {
        let pieces = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if pieces.count > 1 {
            return pieces.prefix(2).joined(separator: "。") + "。"
        }
        let target = max(24, text.count / 2)
        guard text.count > target else {
            return text
        }
        return String(text.prefix(target)).trimmingCharacters(in: .whitespacesAndNewlines) + "……"
    }
}
