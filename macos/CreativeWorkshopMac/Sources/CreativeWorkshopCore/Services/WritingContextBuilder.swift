import Foundation

package struct WritingContextBuilder {
    package init() {}

    package func build(
        title: String,
        summary: String,
        content: String,
        outline: String,
        idea: String,
        direction: String,
        materials: String,
        style: StyleProfile,
        selectedTopic: Topic?,
        recentArticles: [Article],
        recentReviews: [WritingReview],
        ideas: [Idea]
    ) -> ContextPackage {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutline = outline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphCount = trimmedContent
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        return ContextPackage(
            stage: inferStage(
                title: title,
                summary: summary,
                content: trimmedContent,
                outline: trimmedOutline,
                idea: trimmedIdea
            ),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            idea: trimmedIdea,
            direction: direction.trimmingCharacters(in: .whitespacesAndNewlines),
            outline_excerpt: truncate(trimmedOutline, limit: 1_200),
            content_excerpt: excerptContent(trimmedContent),
            materials_excerpt: excerptMaterials(materials.trimmingCharacters(in: .whitespacesAndNewlines)),
            selected_topic_title: selectedTopic?.title,
            selected_topic_summary: selectedTopicSummary(selectedTopic),
            style_name: style.name,
            style_brief: styleBrief(style),
            word_count: trimmedContent.count,
            paragraph_count: paragraphCount,
            material_count: ideas.count,
            recent_article_titles: recentArticles.prefix(5).map(\.displayTitle),
            recent_training_focus: Array(recentReviews.flatMap(\.training_focus).prefix(6)),
            recent_issues: Array(
                recentReviews
                    .flatMap(\.issues)
                    .map { "\($0.dimension)：\($0.problem)" }
                    .prefix(6)
            ),
            genre: style.genre,
            known_pitfalls: (style.known_pitfalls ?? []).map(\.description),
            last_review_summary: recentReviews.first?.summary
        )
    }

    private func inferStage(title: String, summary: String, content: String, outline: String, idea: String) -> String {
        if !content.isEmpty {
            if content.count >= 1_200 {
                return "修改阶段"
            }
            return "初稿阶段"
        }
        if !outline.isEmpty {
            return "大纲阶段"
        }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !idea.isEmpty || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "构思阶段"
        }
        return "空白阶段"
    }

    /// 素材是逐条累加的（作者每次「用于本次写作」都会往正文素材块后追加），此前按 1000 字
    /// 掐尾截断，结果是**最后加进来的素材最先消失**，且界面无任何提示。改为放宽上限并保留
    /// 头尾，省略处显式写明丢了多少字，不再让模型和作者都以为素材是完整的（24.3）。
    private func excerptMaterials(_ text: String) -> String {
        guard text.count > 3_000 else {
            return text
        }
        let prefix = text.prefix(1_800)
        let suffix = text.suffix(1_000)
        return "\(prefix)\n\n（此处省略中间 \(text.count - 2_800) 字素材）\n\n\(suffix)"
    }

    private func excerptContent(_ content: String) -> String {
        guard content.count > 2_000 else {
            return content
        }
        let prefix = content.prefix(1_000)
        let suffix = content.suffix(800)
        return "\(prefix)\n\n...\n\n\(suffix)"
    }

    private func selectedTopicSummary(_ topic: Topic?) -> String? {
        guard let topic else {
            return nil
        }
        return [
            topic.description,
            topic.core_viewpoint,
            topic.angle,
            topic.target_reader
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func styleBrief(_ style: StyleProfile) -> String {
        [
            "体裁：\(style.genre.orEmpty)",
            "语言：\(style.language_style.orEmpty)",
            "语气：\(style.tone.orEmpty)",
            "结构：\(style.structure_preference.orEmpty)",
            "禁忌：\(style.forbidden_expressions.orEmpty)"
        ]
        .filter { !$0.hasSuffix("：") }
        .joined(separator: "\n")
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
