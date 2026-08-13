import SwiftUI
import CreativeWorkshopCore

/// 「我的文章」工作区页面（24.13 新增）。
///
/// 此前文章列表没有自己的屏幕，只以「最近文章」的形式挤在侧栏导航项下面，
/// 既看不到全部，也和导航抢位置。两列结构下它成为一个正经目的地，
/// 侧栏只保留折叠的「最近」快捷入口。
struct ArticlesView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var selection: WorkspaceDestination

    private let statuses = ["全部", "草稿", "已发布", "已归档"]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "工作区", title: "我的文章") {
                HStack(spacing: WorkshopMetrics.controlSpacing) {
                    Picker("状态", selection: $store.articleStatusFilter) {
                        ForEach(statuses, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()

                    Button {
                        store.newDraft()
                        navigateAfterSessionSwitch(to: .process)
                    } label: {
                        Label("新建文章", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if store.filteredArticles.isEmpty {
                emptyState
            } else {
                articleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WorkshopMetrics.controlSpacing) {
                ForEach(store.filteredArticles) { article in
                    articleRow(article)
                }
            }
            .frame(maxWidth: 1_060, alignment: .leading)
            .padding(WorkshopMetrics.pagePadding)
        }
    }

    private func articleRow(_ article: Article) -> some View {
        let status = article.status ?? "草稿"
        let isCurrent = article.id == store.selectedArticleID

        return Button {
            store.openArticle(article)
            navigateAfterSessionSwitch(to: .article)
        } label: {
            HStack(alignment: .top, spacing: WorkshopMetrics.stackSpacing) {
                VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
                    Text(article.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if let summary = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: WorkshopMetrics.controlSpacing) {
                        if let genre = article.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !genre.isEmpty {
                            Text(genre)
                        }
                        if let updatedAt = article.updated_at {
                            Text(updatedAt)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(WorkshopPalette.textTertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: WorkshopMetrics.stackSpacing)

                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkshopPalette.statusColor(status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        Capsule()
                            .stroke(WorkshopPalette.statusColor(status).opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(WorkshopMetrics.stackSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: WorkshopMetrics.controlCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: WorkshopMetrics.controlCornerRadius)
                    .stroke(
                        isCurrent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(article.displayTitle)，\(status)")
        .accessibilityHint("打开这篇文章的正文")
    }

    /// 切换被挂起（有未保存修改待确认）时不导航，理由同 `SidebarView`。
    private func navigateAfterSessionSwitch(to destination: WorkspaceDestination) {
        guard store.pendingSessionSwitch == nil else { return }
        selection = destination
    }

    private var emptyState: some View {
        VStack(spacing: WorkshopMetrics.controlSpacing) {
            Image(systemName: "doc.on.doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(store.articles.isEmpty ? "还没有文章" : "没有「\(store.articleStatusFilter)」状态的文章")
                .font(.headline)

            Text("在「创作过程」写下一个想法并生成初稿，保存后会出现在这里。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("去创作过程") {
                selection = .process
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(WorkshopMetrics.pagePadding)
    }
}
