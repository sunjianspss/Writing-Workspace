import SwiftUI
import CreativeWorkshopCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case articles
    case topics
    case materials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .articles: "文章"
        case .topics: "待写选题"
        case .materials: "素材箱"
        }
    }

    var symbol: String {
        switch self {
        case .articles: "doc.text"
        case .topics: "sparkles"
        case .materials: "tray.full"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @ObservedObject var store: WorkshopStore
    private let articleStatuses = ["全部", "草稿", "已发布", "已归档"]

    var body: some View {
        List(selection: $selection) {
            Section("工作区") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }

            Section("最近文章") {
                Picker("筛选", selection: $store.articleStatusFilter) {
                    ForEach(articleStatuses, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                ForEach(store.filteredArticles.prefix(8)) { article in
                    Button {
                        store.openArticle(article)
                        selection = .articles
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.displayTitle)
                                .lineLimit(1)
                            Text(article.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
