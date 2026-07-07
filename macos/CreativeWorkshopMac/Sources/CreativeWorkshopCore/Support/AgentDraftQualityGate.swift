import Foundation

package enum QualityGateStatus: String, Hashable {
    case passed
    case review
}

package struct QualityGateItem: Identifiable, Hashable {
    package var title: String
    package var detail: String
    package var status: QualityGateStatus

    package var id: String {
        "\(title)|\(detail)|\(status.rawValue)"
    }
}

package struct AgentDraftQualityGate: Hashable {
    package var items: [QualityGateItem]

    package var reviewCount: Int {
        items.filter { $0.status == .review }.count
    }

    package var passedCount: Int {
        items.filter { $0.status == .passed }.count
    }

    package var summary: String {
        reviewCount == 0
            ? "质量门通过：核心问题、论点、分段与自检均已给出。"
            : "质量门提示：还有 \(reviewCount) 项建议复核。"
    }
}

package enum AgentDraftQualityGateEvaluator {
    /// 结尾套话正则：常见公众号收尾模式，命中即视为疑似套路化结尾（PRD 22.2.2）。
    private static let cannedEndingPatterns: [String] = [
        "愿我们都",
        "与君共勉",
        "你学会了吗",
        "点个赞",
        "关注我"
    ]

    private static let sentenceEndingCharacters = CharacterSet(charactersIn: "。！？…\"”」』")

    package static func evaluate(
        trace: AgentDraftTrace?,
        selfCheck: DraftSelfCheckResult?,
        content: String = "",
        knownPitfalls: [String] = []
    ) -> AgentDraftQualityGate? {
        guard let trace else {
            return nil
        }

        let items = [
            briefItem(trace),
            argumentItem(trace),
            sectionItem(trace),
            critiqueItem(trace),
            selfCheckItem(selfCheck),
            unresolvedGapsItem(trace),
            structureDeviationItem(trace, content: content),
            lengthIntegrityItem(trace, content: content),
            pitfallScanItem(content: content, knownPitfalls: knownPitfalls)
        ]

        return AgentDraftQualityGate(items: items)
    }

    private static func briefItem(_ trace: AgentDraftTrace) -> QualityGateItem {
        let missing = [
            trace.coreQuestion.trimmedNonEmpty == nil ? "核心问题" : nil,
            trace.thesis.trimmedNonEmpty == nil ? "核心主张" : nil,
            trace.targetReader.trimmedNonEmpty == nil ? "目标读者" : nil
        ].compactMap { $0 }

        if missing.isEmpty {
            return QualityGateItem(
                title: "写作 Brief",
                detail: "已明确核心问题、主张和目标读者。",
                status: .passed
            )
        }
        return QualityGateItem(
            title: "写作 Brief",
            detail: "缺少：\(missing.joined(separator: "、"))。",
            status: .review
        )
    }

    private static func argumentItem(_ trace: AgentDraftTrace) -> QualityGateItem {
        let hasDirectives = trace.argumentDirectives.contains { $0.trimmedNonEmpty != nil }
        let missingEvidenceCount = trace.missingEvidence.filter { $0.trimmedNonEmpty != nil }.count

        if hasDirectives && missingEvidenceCount == 0 {
            return QualityGateItem(
                title: "论点检查",
                detail: "已有修订指令，未标出明显缺证据项。",
                status: .passed
            )
        }
        if hasDirectives {
            return QualityGateItem(
                title: "论点检查",
                detail: "已有修订指令，但仍有 \(missingEvidenceCount) 个证据/场景缺口。",
                status: .review
            )
        }
        return QualityGateItem(
            title: "论点检查",
            detail: "缺少明确的论点修订指令。",
            status: .review
        )
    }

    private static func sectionItem(_ trace: AgentDraftTrace) -> QualityGateItem {
        let sectionCount = trace.sectionSummaries.filter { $0.trimmedNonEmpty != nil }.count
        if sectionCount >= 2 {
            return QualityGateItem(
                title: "分段成稿",
                detail: "已生成 \(sectionCount) 个段落自检。",
                status: .passed
            )
        }
        return QualityGateItem(
            title: "分段成稿",
            detail: "段落自检不足，建议确认结构是否过薄。",
            status: .review
        )
    }

    private static func critiqueItem(_ trace: AgentDraftTrace) -> QualityGateItem {
        let critiqueCount = trace.critiqueNotes.filter { $0.trimmedNonEmpty != nil }.count
        if critiqueCount > 0 {
            return QualityGateItem(
                title: "自我批评",
                detail: "已给出 \(critiqueCount) 条自我批评。",
                status: .passed
            )
        }
        return QualityGateItem(
            title: "自我批评",
            detail: "缺少自我批评，建议人工重点复核中段和结尾。",
            status: .review
        )
    }

    private static func unresolvedGapsItem(_ trace: AgentDraftTrace) -> QualityGateItem {
        let gapCount = trace.unresolvedGaps.filter { $0.trimmedNonEmpty != nil }.count
        if gapCount > 0 {
            return QualityGateItem(
                title: "素材缺口",
                detail: "Brief 修订后仍有 \(gapCount) 个证据/场景缺口未覆盖。",
                status: .review
            )
        }
        return QualityGateItem(
            title: "素材缺口",
            detail: "未标出无法覆盖的证据/场景缺口。",
            status: .passed
        )
    }

    private static func selfCheckItem(_ selfCheck: DraftSelfCheckResult?) -> QualityGateItem {
        guard let selfCheck else {
            return QualityGateItem(
                title: "生成后自检",
                detail: "未拿到自检结果。",
                status: .review
            )
        }

        let flags = selfCheck.flagged_excerpts ?? []
        if selfCheck.has_concerns == true, !flags.isEmpty {
            return QualityGateItem(
                title: "生成后自检",
                detail: "发现 \(flags.count) 处建议复查片段。",
                status: .review
            )
        }
        return QualityGateItem(
            title: "生成后自检",
            detail: "未发现高风险片段。",
            status: .passed
        )
    }

    private static func structureDeviationItem(_ trace: AgentDraftTrace, content: String) -> QualityGateItem {
        guard trace.plannedSectionCount > 0 else {
            return QualityGateItem(
                title: "结构偏差",
                detail: "未提供 brief 结构规划，跳过结构偏差比对。",
                status: .passed
            )
        }

        let sectionSummaryCount = trace.sectionSummaries.filter { $0.trimmedNonEmpty != nil }.count
        // 与 sectionSummaries 交叉取较大值：避免正文未使用 Markdown 二级标题时被误判为结构偏差。
        let actualSectionCount = max(estimatedSectionCount(in: content), sectionSummaryCount)
        let deviation = abs(actualSectionCount - trace.plannedSectionCount)

        if deviation >= 2 {
            return QualityGateItem(
                title: "结构偏差",
                detail: "计划 \(trace.plannedSectionCount) 段，正文实际约 \(actualSectionCount) 段，偏差 \(deviation) 段。",
                status: .review
            )
        }
        return QualityGateItem(
            title: "结构偏差",
            detail: "计划 \(trace.plannedSectionCount) 段，正文实际约 \(actualSectionCount) 段，偏差 \(deviation) 段。",
            status: .passed
        )
    }

    private static func estimatedSectionCount(in content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        let headingCount = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }.count
        if headingCount > 0 {
            return headingCount
        }

        let paragraphs = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.count
    }

    private static func lengthIntegrityItem(_ trace: AgentDraftTrace, content: String) -> QualityGateItem {
        let sectionSummaryCount = trace.sectionSummaries.filter { $0.trimmedNonEmpty != nil }.count
        let planCount = trace.plannedSectionCount > 0 ? trace.plannedSectionCount : max(sectionSummaryCount, 1)
        let minLength = planCount * 300
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let actualLength = trimmed.count

        var problems: [String] = []
        if actualLength < minLength {
            problems.append("正文 \(actualLength) 字，低于计划 \(planCount) 段 × 300 字的下限 \(minLength) 字")
        }
        if let lastScalar = trimmed.unicodeScalars.last, !sentenceEndingCharacters.contains(lastScalar) {
            problems.append("结尾字符「\(trimmed.suffix(1))」不是句末标点，疑似截断")
        } else if trimmed.isEmpty {
            problems.append("正文为空")
        }

        if problems.isEmpty {
            return QualityGateItem(
                title: "长度完整性",
                detail: "正文 \(actualLength) 字，达到下限 \(minLength) 字，结尾标点正常。",
                status: .passed
            )
        }
        return QualityGateItem(
            title: "长度完整性",
            detail: problems.joined(separator: "；"),
            status: .review
        )
    }

    private static func pitfallScanItem(content: String, knownPitfalls: [String]) -> QualityGateItem {
        var hits: [String] = []

        for pitfall in knownPitfalls {
            let trimmed = pitfall.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, content.localizedStandardContains(trimmed) else { continue }
            hits.append("作者雷区「\(trimmed)」")
        }

        for pattern in cannedEndingPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            if regex.firstMatch(in: content, range: range) != nil {
                hits.append("结尾套话「\(pattern)」")
            }
        }

        if hits.isEmpty {
            return QualityGateItem(
                title: "雷区特征扫描",
                detail: "未命中作者雷区或常见套话结尾。",
                status: .passed
            )
        }
        return QualityGateItem(
            title: "雷区特征扫描",
            detail: "命中：\(hits.joined(separator: "、"))。",
            status: .review
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
