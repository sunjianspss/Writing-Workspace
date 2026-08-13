import Foundation

/// 把工作流结果翻译成人类可读文本的纯映射（24.15 从 `WorkshopStore` 抽出）。
///
/// 两类去处：运行记录里的说明与可复盘轨迹（进数据库），以及大纲的 Markdown
/// 渲染（进编辑器，见文件末尾的 `OutlineResult` 扩展）。
///
/// 同样的输入必须产出同样的文本。留在 Store 里时它们只能连着 `@MainActor` 的
/// 整个对象才测得到，而截断规则（只取前 N 条）和渲染拼装本身都是会出错的逻辑。
package enum WorkflowNarration {
    /// 代理初稿的过程说明。空字段整条略去，不留「未返回」占位。
    package static func agentDraftNote(_ response: AgentDraftResponse) -> String {
        [
            "代理初稿流程：writing brief → 论点检查 → 分段成稿 → 自我批评。",
            response.brief.core_question.map { "Brief 核心问题：\($0)" },
            response.brief.thesis.map { "Brief 主张：\($0)" },
            joinedIfPresent("论点检查指令", response.argumentCheck.revision_directives, limit: 3),
            joinedIfPresent("自我批评", response.critique.critique_notes, limit: 3)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    /// 诊断后全文修订的说明。
    package static func reviewRevisionNote(_ review: WritingReview) -> String {
        [
            "根据写作教练诊断进行全文修订。",
            "诊断摘要：\(review.summary)",
            joinedIfPresent("修改顺序", review.revision_plan, limit: 4),
            joinedIfPresent("训练重点", review.training_focus, limit: 3)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    /// 代理初稿的结构化轨迹。缺字段用明确的「未返回」占位，便于复盘时区分
    /// 「模型没给」和「给了空值」。
    package static func agentDraftTrace(_ response: AgentDraftResponse) -> AgentDraftTrace {
        AgentDraftTrace(
            workingTitle: response.brief.working_title ?? response.result.title ?? "未命名代理初稿",
            coreQuestion: response.brief.core_question ?? "未返回核心问题",
            thesis: response.brief.thesis ?? "未返回核心主张",
            targetReader: response.brief.target_reader ?? "未返回目标读者",
            argumentDirectives: response.argumentCheck.revision_directives ?? [],
            missingEvidence: response.argumentCheck.missing_evidence ?? [],
            sectionSummaries: (response.sectionDraft.sections ?? []).map(sectionSummary),
            critiqueNotes: response.critique.critique_notes ?? [],
            unresolvedGaps: response.brief.unresolved_gaps ?? [],
            plannedSectionCount: response.brief.structure_plan?.count ?? 0
        )
    }

    /// 段落摘要：有自检就用「标题：自检」，否则退回标题，标题也空才截正文。
    private static func sectionSummary(_ section: DraftSection) -> String {
        let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = section.self_check?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let check, !check.isEmpty {
            return "\(heading.isEmpty ? "未命名段落" : heading)：\(check)"
        }
        return heading.isEmpty ? String(section.content.prefix(40)) : heading
    }

    private static func joinedIfPresent(_ label: String, _ items: [String]?, limit: Int) -> String? {
        guard let items, !items.isEmpty else { return nil }
        return "\(label)：\(items.prefix(limit).joined(separator: "；"))"
    }
}

package extension TopicPayload {
    /// 已有选题原样转成写入载荷。
    init(topic: Topic) {
        self.init(
            title: topic.title,
            direction: topic.direction,
            core_viewpoint: topic.core_viewpoint,
            target_reader: topic.target_reader,
            description: topic.description,
            angle: topic.angle,
            emotion: topic.emotion,
            score: topic.score,
            status: topic.status,
            tags: topic.tags
        )
    }

    /// 从当前草稿现场攒一条选题。标题和想法都为空时没有可记录的东西，返回 nil。
    init?(draftTitle: String, idea: String, summary: String, direction: String) {
        let resolvedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty || !resolvedIdea.isEmpty else {
            return nil
        }

        let resolvedAngle = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            title: resolvedTitle.isEmpty ? String(resolvedIdea.prefix(32)) : resolvedTitle,
            direction: direction,
            core_viewpoint: resolvedIdea.isEmpty ? nil : resolvedIdea,
            target_reader: nil,
            description: resolvedIdea.isEmpty ? summary : resolvedIdea,
            angle: resolvedAngle.isEmpty ? nil : summary,
            emotion: nil,
            score: 3,
            status: "待写",
            tags: [direction]
        )
    }
}

package extension OutlineResult {
    /// 结构化大纲渲染成编辑器里的 Markdown（24.17 从两处私有扩展收拢）。
    ///
    /// 此前 `WorkshopStore` 和 `WritingAgentCoordinator` 各有一份逐字相同的实现，
    /// 靠注释提醒人工同步。渲染规则是领域逻辑，不该按 target 复制。
    ///
    /// 模型给了原始输出就直接用；否则按"标题→开头→各段（含素材位置）→结尾"拼装。
    var markdown: String {
        if let raw_output, !raw_output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw_output
        }

        var lines: [String] = []
        if let title, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }
        if let opening, !opening.isEmpty {
            lines.append("## 开头")
            lines.append(opening)
            lines.append("")
        }
        for section in sections ?? [] {
            if let heading = section.heading, !heading.isEmpty {
                lines.append("## \(heading)")
            }
            for point in section.points ?? [] where !point.isEmpty {
                lines.append("- \(point)")
            }
            if let hint = section.material_hint, !hint.isEmpty {
                lines.append("素材位置：\(hint)")
            }
            lines.append("")
        }
        if let ending, !ending.isEmpty {
            lines.append("## 结尾")
            lines.append(ending)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
