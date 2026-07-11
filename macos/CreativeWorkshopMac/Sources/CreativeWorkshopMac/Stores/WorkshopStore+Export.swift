import AppKit
import Foundation
import UniformTypeIdentifiers
import CreativeWorkshopCore

/// R5 瘦身·任务 23：复制与导出。文本组装早已下沉 `ArticleExportFormatter`（Core），
/// 这里只剩剪贴板 / 存储面板等 AppKit 转发。
extension WorkshopStore {
    func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusText = "已复制"
    }

    func copyArticleContent(format: ArticleCopyFormat) {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            statusText = "正文为空，无法复制"
            return
        }

        copyToClipboard(
            ArticleExportFormatter.articleContent(
                format: format,
                title: title,
                summary: summary,
                content: content
            )
        )
        statusText = "已复制正文（\(format.statusName)）"
    }

    func copyLatestWritingReview() {
        guard let review = latestReview else {
            statusText = "暂无可复制的诊断"
            return
        }

        copyToClipboard(ArticleExportFormatter.writingReview(review, fallbackTitle: title))
        statusText = "已复制写作教练诊断"
    }

    func copyThirtyDayReviewReport() {
        do {
            copyToClipboard(try thirtyDayReviewReport())
            statusText = "已复制 30 天写作教练报告"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func exportThirtyDayReviewReport() {
        do {
            let report = try thirtyDayReviewReport()
            let panel = NSSavePanel()
            panel.title = "导出 30 天写作教练报告"
            panel.nameFieldStringValue = "创作工坊-30天写作教练报告.md"
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else {
                statusText = "已取消导出报告"
                return
            }
            try report.write(to: url, atomically: true, encoding: .utf8)
            statusText = "已导出 30 天写作教练报告"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func thirtyDayReviewReport() throws -> String {
        try ArticleExportFormatter.thirtyDayReviewReport(
            reviews: database.listWritingReviews(limit: 50),
            generatedAt: Self.nowString()
        )
    }
}
