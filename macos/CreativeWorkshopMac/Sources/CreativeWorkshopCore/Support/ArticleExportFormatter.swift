import Foundation

package enum ArticleExportFormatter {
    package static func articleContent(
        format: ArticleCopyFormat,
        title: String,
        summary: String,
        content: String
    ) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        switch format {
        case .plainText:
            return cleanContent
        case .markdown:
            return markdownArticle(title: cleanTitle, summary: cleanSummary, content: cleanContent)
        case .html:
            return htmlArticle(title: cleanTitle, summary: cleanSummary, content: cleanContent)
        }
    }

    package static func writingReview(_ review: WritingReview, fallbackTitle: String) -> String {
        var parts: [String] = ["# 写作教练诊断"]

        let reviewTitle = (review.title_snapshot ?? fallbackTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        if !reviewTitle.isEmpty {
            parts.append("文章：\(reviewTitle)")
        }
        if let createdAt = review.created_at, !createdAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("时间：\(createdAt)")
        }
        if let score = review.overall_score {
            parts.append("评分：\(score)")
        }

        parts.append(markdownSection(title: "一句话诊断", body: review.summary))
        appendMarkdownListSection(title: "优点", values: review.strengths, to: &parts)

        if !review.issues.isEmpty {
            var issueLines: [String] = []
            for (index, issue) in review.issues.enumerated() {
                issueLines.append("\(index + 1). [\(issue.severity)] \(issue.dimension)")
                if let excerpt = issue.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
                    issueLines.append("   原文：\(excerpt)")
                }
                issueLines.append("   问题：\(issue.problem)")
                issueLines.append("   建议：\(issue.suggestion)")
            }
            parts.append("## 优先修改项\n\(issueLines.joined(separator: "\n"))")
        }

        appendMarkdownNumberedSection(title: "修改顺序", values: review.revision_plan, to: &parts)
        appendMarkdownListSection(title: "训练重点", values: review.training_focus, to: &parts)
        appendMarkdownListSection(title: "风格观察", values: review.style_notes, to: &parts)
        appendMarkdownListSection(title: "较上次已解决", values: review.resolved_from_last, to: &parts)

        if let rawOutput = review.raw_output?.trimmingCharacters(in: .whitespacesAndNewlines), !rawOutput.isEmpty {
            parts.append(markdownSection(title: "模型原始诊断", body: rawOutput))
        }

        return parts.joined(separator: "\n\n")
    }

    package static func thirtyDayReviewReport(reviews: [WritingReview], generatedAt: String, days: Int = 30) throws -> String {
        let recentReviews = recentReviews(reviews, days: days)
        guard !recentReviews.isEmpty else {
            throw NativeDatabaseError.notFound("最近 30 天写作教练记录")
        }

        let scores = recentReviews.compactMap(\.overall_score)
        let averageScore = scores.isEmpty ? nil : Int(Double(scores.reduce(0, +)) / Double(scores.count))
        let focusCounts = countValues(recentReviews.flatMap(\.training_focus))
        let issueCounts = countValues(recentReviews.flatMap { $0.issues.map(\.dimension) })

        var parts: [String] = ["# 30 天写作教练报告"]
        parts.append("生成时间：\(generatedAt)")
        parts.append("诊断次数：\(recentReviews.count)")
        if let averageScore {
            parts.append("平均评分：\(averageScore)")
        }

        appendMarkdownListSection(
            title: "高频训练重点",
            values: focusCounts.prefix(8).map { "\($0.value)（\($0.count) 次）" },
            to: &parts
        )
        appendMarkdownListSection(
            title: "高频问题维度",
            values: issueCounts.prefix(8).map { "\($0.value)（\($0.count) 次）" },
            to: &parts
        )

        let weeklyPlan = focusCounts.prefix(3).map(\.value)
        if !weeklyPlan.isEmpty {
            parts.append(
                """
                ## 本周写作训练计划
                1. 每篇文章先检查「\(weeklyPlan[0])」。
                \(weeklyPlan.dropFirst().enumerated().map { "\($0.offset + 2). 修改时重点复核「\($0.element)」。" }.joined(separator: "\n"))
                """
            )
        }

        parts.append("## 最近诊断摘要")
        for review in recentReviews.prefix(12) {
            var lines: [String] = []
            lines.append("### \(review.title_snapshot ?? "未命名文章")")
            if let createdAt = review.created_at {
                lines.append("- 时间：\(createdAt)")
            }
            if let score = review.overall_score {
                lines.append("- 评分：\(score)")
            }
            lines.append("- 诊断：\(review.summary)")
            if !review.issues.isEmpty {
                lines.append("- 主要问题：\(review.issues.prefix(3).map { "[\($0.severity)] \($0.dimension)：\($0.problem)" }.joined(separator: "；"))")
            }
            if !review.revision_plan.isEmpty {
                lines.append("- 修改顺序：\(review.revision_plan.prefix(3).joined(separator: "；"))")
            }
            parts.append(lines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }

    private static func markdownArticle(title: String, summary: String, content: String) -> String {
        var parts: [String] = []
        if !title.isEmpty {
            parts.append("# \(title)")
        }
        if !summary.isEmpty {
            parts.append("> \(summary)")
        }
        parts.append(content)
        return parts.joined(separator: "\n\n")
    }

    private static func recentReviews(_ reviews: [WritingReview], days: Int) -> [WritingReview] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -max(1, days), to: Date()) ?? Date()
        return reviews.filter { review in
            guard let createdAt = review.created_at,
                  let date = parseISODate(createdAt) else {
                return true
            }
            return date >= cutoff
        }
    }

    private static func countValues(_ values: [String]) -> [(value: String, count: Int)] {
        Dictionary(grouping: values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, by: { $0 })
            .map { (value: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.value < $1.value
                }
                return $0.count > $1.count
            }
    }

    private static func parseISODate(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private static func markdownSection(title: String, body: String) -> String {
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "## \(title)\n\(cleanBody.isEmpty ? "无" : cleanBody)"
    }

    private static func appendMarkdownListSection(title: String, values: [String], to parts: inout [String]) {
        let lines = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
        guard !lines.isEmpty else { return }
        parts.append("## \(title)\n\(lines.joined(separator: "\n"))")
    }

    private static func appendMarkdownNumberedSection(title: String, values: [String], to parts: inout [String]) {
        let lines = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
        guard !lines.isEmpty else { return }
        parts.append("## \(title)\n\(lines.joined(separator: "\n"))")
    }

    private static func htmlArticle(title: String, summary: String, content: String) -> String {
        var parts: [String] = ["<article>"]
        if !title.isEmpty {
            parts.append("<h1>\(escapeHTML(title))</h1>")
        }
        if !summary.isEmpty {
            parts.append("<p><strong>摘要：</strong>\(escapeHTML(summary))</p>")
        }
        parts.append(markdownishBodyHTML(content))
        parts.append("</article>")
        return parts.joined(separator: "\n")
    }

    private static func markdownishBodyHTML(_ content: String) -> String {
        content
            .components(separatedBy: "\n\n")
            .map { block in
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("### ") {
                    return "<h3>\(escapeHTML(String(trimmed.dropFirst(4))))</h3>"
                }
                if trimmed.hasPrefix("## ") {
                    return "<h2>\(escapeHTML(String(trimmed.dropFirst(3))))</h2>"
                }
                if trimmed.hasPrefix("# ") {
                    return "<h1>\(escapeHTML(String(trimmed.dropFirst(2))))</h1>"
                }
                return "<p>\(escapeHTML(trimmed).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            }
            .filter { $0 != "<p></p>" }
            .joined(separator: "\n")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
