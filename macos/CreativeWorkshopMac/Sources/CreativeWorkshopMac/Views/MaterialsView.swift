import SwiftUI
import CreativeWorkshopCore

struct MaterialsView: View {
    @ObservedObject var store: WorkshopStore

    private let materialTypes = ["全部", "灵感", "金句", "文章片段"]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "工作区", title: "素材箱") {
                // 放不下就退成纯图标。加了「粘贴为素材」之后这一行有两个按钮，窄窗口下
                // 带文字放不下——而页头的 HStack 不裁剪、只溢出，「新素材」会被挤出可视区。
                ViewThatFits(in: .horizontal) {
                    headerActions(iconOnly: false)
                    headerActions(iconOnly: true)
                }
            }

            // 列表与编辑器在右列内部左右分栏——两列结构下这是「列表 + 详情」的落法。
            HSplitView {
                materialList
                    .frame(minWidth: 240, idealWidth: 320)

                materialEditor
                    .frame(minWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 粘贴即存排在「新素材」之前，因为它才是常用路径：作者的素材两个来源（微信收藏、
    /// Obsidian）都以复制收尾，手打录入是少数。
    ///
    /// 用 ⇧⌘V 而不是 ⌘V：⌘V 会在整个窗口内被劫持，标题和正文输入框里就粘不了了。
    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.pasteMaterialFromClipboard()
            } label: {
                Label("粘贴为素材", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .help("把剪贴板里的文字直接存成一条素材（⇧⌘V）")

            Button {
                store.newMaterial()
            } label: {
                Label("新素材", systemImage: "plus")
            }
            .help("新素材")
        }
    }

    /// macOS 13 没有 `AnyLabelStyle`，所以用两个分支而不是把样式当值传。
    @ViewBuilder
    private func headerActions(iconOnly: Bool) -> some View {
        if iconOnly {
            headerButtons.labelStyle(.iconOnly)
        } else {
            headerButtons.labelStyle(.titleAndIcon)
        }
    }

    private var materialList: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索素材", text: $store.materialSearchText)
                .textFieldStyle(.roundedBorder)

            // 分段选择器是这一页最"硬"的元素：它不会压缩到内容宽度以下。带着自己的
            // 标签就更宽——而 LabeledContent 已经给了一个标签，于是界面上"类型"出现两次。
            Picker("类型", selection: $store.materialTypeFilter) {
                ForEach(materialTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .labelsHidden()
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
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    ViewThatFits(in: .horizontal) {
                        saveButton(iconOnly: false)
                        saveButton(iconOnly: true)
                    }
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
                    .labelsHidden()
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
                        // TextEditor 的固有宽度很大，不封顶它会把整个右列顶宽，
                        // 分栏总宽超出窗口后左右一起溢出。
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                }

                // 这一排三个按钮是编辑区最"硬"的元素：带文字时约 350pt，比这一栏的
                // 最小宽度还宽，于是把整个右列顶出窗口——左右两侧一起被切。放不下就退成纯图标。
                ViewThatFits(in: .horizontal) {
                    editorActions(iconOnly: false)
                    editorActions(iconOnly: true)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func saveButton(iconOnly: Bool) -> some View {
        let button = Button {
            Task { await store.saveIdea() }
        } label: {
            Label("保存素材", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canSaveMaterial || store.isLoading)
        .help("保存素材")

        if iconOnly {
            button.labelStyle(.iconOnly)
        } else {
            button.labelStyle(.titleAndIcon)
        }
    }

    private var editorButtons: some View {
        HStack(spacing: 8) {
            Button {
                if let idea = store.selectedIdea {
                    store.useIdeaInSession(idea)
                }
            } label: {
                Label("加入当前写作", systemImage: "text.badge.plus")
            }
            .disabled(store.selectedIdea == nil)
            .help("加入当前写作")

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
            .help("从素材生成选题")
            .fixedSize()

            Spacer(minLength: 8)

            Button(role: .destructive) {
                Task { await store.deleteSelectedIdea() }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(store.selectedIdea == nil || store.isLoading)
            .help("删除")
        }
    }

    @ViewBuilder
    private func editorActions(iconOnly: Bool) -> some View {
        if iconOnly {
            editorButtons.labelStyle(.iconOnly)
        } else {
            editorButtons.labelStyle(.titleAndIcon)
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
