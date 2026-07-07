import Foundation

package enum PrePublishAuditLocalVerifier {
    package static func verifyQuotes(
        in report: PrePublishAuditReport,
        content: String,
        fragments: [Fragment]
    ) -> PrePublishAuditReport {
        let quotes = quotedSegments(in: content)
        guard !quotes.isEmpty else { return report }

        let corpus = fragments.map(\.content)
        let existingExcerpts = Set((report.quote_issues ?? []).compactMap { issue in
            issue.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let missingIssues = quotes
            .filter { quote in
                !existingExcerpts.contains(quote) && !corpus.contains { $0.contains(quote) }
            }
            .map { quote in
                AuditIssue(
                    category: "引文核对",
                    severity: "中",
                    excerpt: quote,
                    problem: "本地素材库和已发布/归档正文中未找到完全匹配的引文来源。",
                    suggestion: "发布前人工核对原文；确认无误后可保留。"
                )
            }

        guard !missingIssues.isEmpty else { return report }
        var updated = report
        updated.quote_issues = (updated.quote_issues ?? []) + missingIssues
        updated.passed = false
        let suffix = "本地引文核对新增 \(missingIssues.count) 条建议复核项。"
        let summary = updated.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated.summary = summary.isEmpty ? suffix : "\(summary) \(suffix)"
        return updated
    }

    package static func quotedSegments(in text: String) -> [String] {
        let pairs: [(Character, Character)] = [
            ("“", "”"),
            ("「", "」"),
            ("『", "』"),
            ("\"", "\"")
        ]
        var output: [String] = []
        for pair in pairs {
            output.append(contentsOf: quotedSegments(in: text, open: pair.0, close: pair.1))
        }
        var seen: Set<String> = []
        return output.filter { quote in
            guard !seen.contains(quote) else { return false }
            seen.insert(quote)
            return true
        }
    }

    private static func quotedSegments(in text: String, open: Character, close: Character) -> [String] {
        if open == close {
            return symmetricalQuotedSegments(in: text, quote: open)
        }
        var segments: [String] = []
        var currentStart: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == open {
                currentStart = text.index(after: index)
            } else if char == close, let start = currentStart {
                let quote = String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                if quote.count >= 4, quote.count <= 160, !quote.contains("\n") {
                    segments.append(quote)
                }
                currentStart = nil
            }
            index = text.index(after: index)
        }
        return segments
    }

    private static func symmetricalQuotedSegments(in text: String, quote: Character) -> [String] {
        var segments: [String] = []
        var currentStart: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == quote {
                if let start = currentStart {
                    let segment = String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if segment.count >= 4, segment.count <= 160, !segment.contains("\n") {
                        segments.append(segment)
                    }
                    currentStart = nil
                } else {
                    currentStart = text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return segments
    }
}
