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

                seriesMenu
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
                    // 系列排在平铺列表之前：「下一篇写谁」在有限清单里是查表，不该淹在
                    // 一百多条储备里让人重新挑一遍。
                    if !store.seriesProgress.isEmpty {
                        seriesSection
                        Divider()
                    }

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

    /// 哪些标签算系列由作者勾选：标签里大部分是「书评」「AI 工具」这种普通分类，
    /// 机器分不出哪个是系列。列出已有标签让他点，而不是手敲——手敲会敲出
    /// 「红楼梦 」这种带空格的孪生标签。
    private var seriesMenu: some View {
        Menu {
            if store.seriesCandidateTags.isEmpty {
                Text("还没有任何标签")
            } else {
                ForEach(store.seriesCandidateTags, id: \.self) { tag in
                    Button {
                        store.toggleSeriesTag(tag)
                    } label: {
                        if isSeries(tag) {
                            Label(tag, systemImage: "checkmark")
                        } else {
                            Text(tag)
                        }
                    }
                }
            }
        } label: {
            Label("系列", systemImage: "square.stack.3d.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func isSeries(_ tag: String) -> Bool {
        store.seriesTags.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: WorkshopMetrics.controlSpacing) {
            ForEach(store.seriesProgress) { series in
                seriesCard(series)
            }
        }
    }

    private func seriesCard(_ series: SeriesProgress.Series) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.tag)
                    .font(.headline)
                Text("已写 \(series.written.count) / 共 \(series.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if series.pending.isEmpty, series.total > 0 {
                    Text("这个系列写完了")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if series.total > 0 {
                ProgressView(value: series.completion)
                    .progressViewStyle(.linear)
            }

            if !series.written.isEmpty {
                Text("已写：" + series.written.compactMap(\.title).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 待写的直接可点开写——「下一篇写谁」的答案就该一步之内可执行。
            if !series.pending.isEmpty {
                Text("还剩 \(series.pending.count) 篇")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(series.pending) { topic in
                    HStack {
                        Text(topic.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Button("开始写") {
                            store.useTopic(topic)
                            selection = .process
                        }
                        .controlSize(.small)
                    }
                }
            } else if series.total == 0 {
                Text("还没有文章或选题带这个标签。给它们打上「\(series.tag)」标签，这里就会显示进度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 10))
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
