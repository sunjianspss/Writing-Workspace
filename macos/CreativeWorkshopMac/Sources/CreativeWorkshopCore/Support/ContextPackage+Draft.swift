import Foundation

package extension ContextPackage {
    mutating func applyDraftSnapshot(_ snapshot: DraftSnapshot) {
        title = snapshot.title
        summary = snapshot.summary
        content_excerpt = snapshot.content
        word_count = snapshot.content.count
        paragraph_count = snapshot.content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    func replacingTitle(_ fallbackTitle: String) -> ContextPackage {
        var copy = self
        copy.title = fallbackTitle
        return copy
    }
}
