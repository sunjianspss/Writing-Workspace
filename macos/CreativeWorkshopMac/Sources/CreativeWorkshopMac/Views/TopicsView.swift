import SwiftUI
import CreativeWorkshopCore

/// 「待写选题」工作区页面：展示全部选题储备，选用后跳回创作画布。
struct TopicsView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var selection: WorkspaceDestination

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "工作区", title: "待写选题") {
                Text("共 \(store.topics.count) 条储备，选用后带入标题、想法和大纲草案")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
                    if store.topics.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: WorkshopMetrics.controlSpacing) {
                            ForEach(store.topics) { topic in
                                topicCard(topic)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1_060, alignment: .leading)
                .padding(WorkshopMetrics.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无选题")
                .font(.headline)
            Text("在「创作过程」输入一个想法并点击「拓展选题」，结果会存到这里。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("去创作过程") {
                selection = .process
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
                    selection = .process
                }
                .buttonStyle(.borderedProminent)

                Button("选用并生成大纲") {
                    store.useTopic(topic)
                    selection = .process
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
            topic.id == store.selectedTopicID ? Color.accentColor.opacity(0.12) : WorkshopPalette.surface,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
