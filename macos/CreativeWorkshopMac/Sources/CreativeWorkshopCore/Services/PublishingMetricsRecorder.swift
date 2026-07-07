import Foundation

package struct PublishingMetricsSnapshot {
    package var stats: EditRecordStats
    package var monthlySummary: String
}

package struct PublishingMetricsRecorder {
    package var database: NativeDatabase

    package init(database: NativeDatabase) {
        self.database = database
    }

    package func recordPublishedArticle(_ article: Article) -> PublishingMetricsSnapshot? {
        do {
            if let version = try database.latestConfirmedDraftVersion(articleID: article.id) {
                _ = try database.saveEditRecord(article: article, draftVersion: version)
            }
            return try snapshot()
        } catch {
            return try? snapshot()
        }
    }

    package func snapshot() throws -> PublishingMetricsSnapshot {
        let stats = try database.editRecordStats()
        let records = try database.listEditRecords(limit: 500)
        return PublishingMetricsSnapshot(
            stats: stats,
            monthlySummary: EditRecordAnalytics.monthlySummary(
                records: records,
                cumulativeLightEditRate: stats.lightEditRate
            )
        )
    }
}
