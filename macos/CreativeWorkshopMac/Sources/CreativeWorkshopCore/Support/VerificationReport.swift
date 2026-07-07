import Foundation

/// 统一验证信号的来源（PRD 23.7）：质量门、生成后自检、生成时生效的作者雷区、发表前终审。
package enum VerificationSource: String, Hashable, Codable {
    case gate
    case selfCheck
    case pitfall
    case audit
}

/// 统一验证信号的等级。质量门/自检只有 passed/review 二元判断，发表前终审用 高/中/低——
/// 两套词汇并存，合并成一个枚举，靠 `sortRank` 决定 compactLines 截断时的优先级。
package enum VerificationLevel: String, Hashable, Codable {
    case high
    case review
    case medium
    case low
    case passed

    package var sortRank: Int {
        switch self {
        case .high: return 0
        case .review: return 1
        case .medium: return 2
        case .low: return 3
        case .passed: return 4
        }
    }

    package var label: String {
        switch self {
        case .high: return "高"
        case .review: return "待复核"
        case .medium: return "中"
        case .low: return "低"
        case .passed: return "通过"
        }
    }

    package init(auditSeverity: String) {
        switch auditSeverity {
        case "高": self = .high
        case "中": self = .medium
        case "低": self = .low
        default: self = .medium
        }
    }
}

package struct VerificationEntry: Identifiable, Hashable, Codable {
    package var source: VerificationSource
    package var level: VerificationLevel
    package var title: String
    package var detail: String

    package init(source: VerificationSource, level: VerificationLevel, title: String, detail: String) {
        self.source = source
        self.level = level
        self.title = title
        self.detail = detail
    }

    package var id: String {
        "\(source.rawValue)|\(level.rawValue)|\(title)|\(detail)"
    }

    /// 供 compactLines 使用的单行渲染，形如 "[高] 标题：detail"。
    package var line: String {
        "[\(level.label)] \(title)：\(detail)"
    }
}

/// 四路验证信号（质量门/自检/雷区/终审）统一后的报告，供待复核卡片、eval 报告
/// 与后续决策上下文（任务 14）共用同一份数据。
package struct VerificationReport: Hashable, Codable {
    package var entries: [VerificationEntry]

    package init(entries: [VerificationEntry]) {
        self.entries = entries
    }

    package func entries(source: VerificationSource) -> [VerificationEntry] {
        entries.filter { $0.source == source }
    }

    package var reviewCount: Int {
        entries.filter { $0.level != .passed }.count
    }

    /// 一行总结，供 eval 报告等文本场景使用。
    package var summaryLine: String {
        guard !entries.isEmpty else {
            return "验证：暂无可用信号。"
        }
        let attention = reviewCount
        if attention == 0 {
            return "验证通过：\(entries.count) 项检查全部通过。"
        }
        let highCount = entries.filter { $0.level == .high }.count
        if highCount > 0 {
            return "验证：\(entries.count) 项中有 \(attention) 项待复核（含 \(highCount) 项高风险）。"
        }
        return "验证：\(entries.count) 项中有 \(attention) 项待复核。"
    }

    /// 供决策上下文压缩使用：按严重程度排序，最多 `limit` 行，超限时最后一行收尾为"另有 N 项"。
    package func compactLines(limit: Int = 6) -> [String] {
        guard limit > 0 else { return [] }
        let sorted = entries.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.level.sortRank != rhs.element.level.sortRank {
                    return lhs.element.level.sortRank < rhs.element.level.sortRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        guard sorted.count > limit else {
            return sorted.map(\.line)
        }

        let shown = sorted.prefix(limit - 1)
        let remaining = sorted.count - shown.count
        return shown.map(\.line) + ["另有 \(remaining) 项"]
    }

    package static func build(
        gate: AgentDraftQualityGate? = nil,
        selfCheck: DraftSelfCheckResult? = nil,
        pitfalls: [AuthorPitfall]? = nil,
        audit: PrePublishAudit? = nil
    ) -> VerificationReport {
        var entries: [VerificationEntry] = []

        if let gate {
            entries += gate.items.map { item in
                VerificationEntry(
                    source: .gate,
                    level: item.status == .passed ? .passed : .review,
                    title: item.title,
                    detail: item.detail
                )
            }
        }

        if let selfCheck, selfCheck.has_concerns == true {
            entries += (selfCheck.flagged_excerpts ?? []).map { excerpt in
                VerificationEntry(
                    source: .selfCheck,
                    level: .review,
                    title: "生成后自检",
                    detail: "\(excerpt.excerpt)\n\(excerpt.concern)"
                )
            }
        }

        if let pitfalls {
            entries += pitfalls.map { pitfall in
                VerificationEntry(
                    source: .pitfall,
                    level: .review,
                    title: "作者雷区",
                    detail: pitfall.description
                )
            }
        }

        if let audit {
            entries += audit.issues.map { issue in
                VerificationEntry(
                    source: .audit,
                    level: VerificationLevel(auditSeverity: issue.severity),
                    title: issue.category,
                    detail: [issue.excerpt, issue.problem, issue.suggestion]
                        .compactMap { $0 }
                        .joined(separator: " — ")
                )
            }
        }

        return VerificationReport(entries: entries)
    }
}
