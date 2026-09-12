import SwiftUI
import CreativeWorkshopCore

struct MaterialsView: View {
    @ObservedObject var store: WorkshopStore

    private let materialTypes = ["全部", "灵感", "金句", "文章片段"]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "工作区", title: "素材箱") {
                Button {
                    store.newMaterial()
                } label: {
                    Label("新素材", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            // 列表与编辑器在右列内部左右分栏——两列结构下这是「列表 + 详情」的落法。
            HSplitView {
                materialList
                    .frame(minWidth: 260, idealWidth: 320)

                materialEditor
                    .frame(minWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var materialList: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索素材", text: $store.materialSearchText)
                .textFieldStyle(.roundedBorder)

            Picker("类型", selection: $store.materialTypeFilter) {
                ForEach(materialTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if filteredIdeas.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无素材")
                        .font(.headline)
                    Text("先记录一个灵感、金句或文章片段。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredIdeas) { idea in
                        Button {
                            store.editIdea(idea)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(idea.displayTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    if idea.used == 1 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(idea.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(idea.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(idea.id == store.selectedIdeaID ? Color.accentColor.opacity(0.12) : Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(20)
    }

    private var materialEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selectedIdeaID == nil ? "新素材" : "编辑素材")
                            .font(.title2.bold())
                        Text("素材可以直接加入当前写作，也可以用来生成选题。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.saveIdea() }
                    } label: {
                        Label("保存素材", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canSaveMaterial || store.isLoading)
                }

                LabeledContent("标题") {
                    TextField("可选，用一句话概括素材", text: $store.materialTitle)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("类型") {
                    Picker("类型", selection: $store.materialType) {
                        ForEach(materialTypes.dropFirst(), id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LabeledContent("标签") {
                    TextField("用逗号分隔，例如：成都，长期主义", text: $store.materialTagsText)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.materialContent)
                        .font(.body)
                        .frame(minHeight: 260)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                }

                HStack {
                    Button {
                        if let idea = store.selectedIdea {
                            store.useIdeaInSession(idea)
                        }
                    } label: {
                        Label("加入当前写作", systemImage: "text.badge.plus")
                    }
                    .disabled(store.selectedIdea == nil)

                    // 方向在这里选，而不是沿用创作页那一个：素材箱攒的东西和手上正在写的
                    // 那篇常常不是一个方向，沉默继承会生成一批方向错的选题。
                    Menu {
                        if !store.normalizedDirection.isEmpty {
                            Button("沿用当前方向（\(store.normalizedDirection)）") {
                                if let idea = store.selectedIdea {
                                    Task { await store.generateTopicsFromIdea(idea) }
                                }
                            }
                            Divider()
                        }
                        ForEach(store.knownDirections, id: \.self) { direction in
                            Button(direction) {
                                if let idea = store.selectedIdea {
                                    Task { await store.generateTopicsFromIdea(idea, direction: direction) }
                                }
                            }
                        }
                    } label: {
                        Label("从素材生成选题", systemImage: "sparkles")
                    }
                    .disabled(store.selectedIdea == nil || store.isLoading)

                    Spacer()

                    Button(role: .destructive) {
                        Task { await store.deleteSelectedIdea() }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(store.selectedIdea == nil || store.isLoading)
                }
            }
            .padding(20)
        }
    }

    private var filteredIdeas: [Idea] {
        let query = store.materialSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.ideas.filter { idea in
            let matchesType = store.materialTypeFilter == "全部" || idea.type == store.materialTypeFilter
            let matchesQuery = query.isEmpty
                || idea.displayTitle.localizedCaseInsensitiveContains(query)
                || idea.content.localizedCaseInsensitiveContains(query)
                || idea.tags.joined(separator: " ").localizedCaseInsensitiveContains(query)
            return matchesType && matchesQuery
        }
    }
}
