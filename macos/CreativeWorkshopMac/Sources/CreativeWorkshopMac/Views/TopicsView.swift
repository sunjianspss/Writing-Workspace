import SwiftUI
import CreativeWorkshopCore

/// 「待写选题」工作区页面：展示全部选题储备，选用后跳回创作画布。
struct TopicsView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var sidebarSelection: SidebarItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if store.topics.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.topics) { topic in
                            topicCard(topic)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("待写选题")
                .font(.title2.bold())
            Text("共 \(store.topics.count) 条选题储备。选用后自动带入标题、想法和大纲草案，并回到创作画布。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无选题")
                .font(.headline)
            Text("在创作画布输入一个想法并点击「生成选题」，结果会存到这里。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("去创作画布") {
                sidebarSelection = .articles
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func topicCard(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.title)
                .font(.headline)
                .lineLimit(2)
            Text(topic.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let description = topic.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let viewpoint = topic.core_viewpoint, !viewpoint.isEmpty {
                Text("核心观点：\(viewpoint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Button("选用并开始写") {
                    store.useTopic(topic)
                    sidebarSelection = .articles
                }
                .buttonStyle(.borderedProminent)

                Button("选用并生成大纲") {
                    store.useTopic(topic)
                    sidebarSelection = .articles
                    Task { await store.generateOutline() }
                }
                .disabled(store.isLoading)

                Spacer()

                Button("删除选题", role: .destructive) {
                    Task { await store.deleteTopic(topic) }
                }
                .disabled(store.isLoading)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            topic.id == store.selectedTopicID ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
