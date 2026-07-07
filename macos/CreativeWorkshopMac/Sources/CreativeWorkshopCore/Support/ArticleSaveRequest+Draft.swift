import Foundation

package extension ArticleSaveRequest {
    static func draft(
        title: String,
        content: String,
        summary: String,
        status: String,
        tags: [String],
        topicID: Int?,
        genre: String
    ) -> ArticleSaveRequest {
        ArticleSaveRequest(title: title, content: content, summary: summary, status: status, tags: tags, related_topic_id: topicID, genre: genre)
    }
}
