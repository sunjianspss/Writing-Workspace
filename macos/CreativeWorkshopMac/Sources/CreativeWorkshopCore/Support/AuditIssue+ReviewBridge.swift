import Foundation

package extension AuditIssue {
    var writingReviewIssue: WritingReviewIssue {
        WritingReviewIssue(
            dimension: category,
            severity: severity,
            excerpt: excerpt,
            problem: problem,
            suggestion: suggestion ?? "请根据终审问题修正这一处，并保持作者原有语气。"
        )
    }
}
