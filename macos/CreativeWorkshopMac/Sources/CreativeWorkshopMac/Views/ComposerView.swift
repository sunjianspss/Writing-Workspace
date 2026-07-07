import SwiftUI
import CreativeWorkshopCore

struct ComposerView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var isInspectorVisible: Bool
    @SceneStorage("selectedComposerTab") private var selectedComposerTab: ComposerTab = .process
    @SceneStorage("isFocusWritingMode") private var isFocusWritingMode = false
    private let articleStatuses = ["草稿", "已发布", "已归档"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topActionBar
            composerTabPicker
            selectedComposerContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectPreferredTabForCurrentDraft()
        }
        .onChange(of: store.selectedArticleID) { _ in
            selectPreferredTabForCurrentDraft()
        }
        .onChange(of: store.title) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.summary) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.content) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.outline) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.ideaInput) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.writingDirection) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.materials) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.articleStatus) { _ in store.scheduleAutosaveSnapshot() }
        .onChange(of: store.pendingDraftReview?.draftVersionID) { _ in store.scheduleAutosaveSnapshot() }
        // 18.3.2 防空转：内容自上次诊断后未变化时，必须先提示后才允许发起新的模型调用。
        .confirmationDialog(
            "内容与上次诊断时相同，仍要重新诊断吗？",
            isPresented: $store.showUnchangedReviewPrompt,
            titleVisibility: .visible
        ) {
            Button("仍要诊断") {
                Task { await store.confirmReviewDespiteNoChange() }
            }
            Button("取消", role: .cancel) {
                store.cancelUnchangedReviewPrompt()
            }
        }
        .confirmationDialog(
            "发现未保存草稿，要恢复吗？",
            isPresented: $store.showAutosaveRestorePrompt,
            titleVisibility: .visible
        ) {
            Button("恢复草稿") {
                store.restoreAutosavedDraft()
                selectedComposerTab = .article
            }
            Button("丢弃", role: .destructive) {
                store.discardAutosavedDraft()
            }
            Button("稍后再说", role: .cancel) {}
        } message: {
            Text("系统保存了上次未正式保存的标题、摘要、正文、想法、大纲、素材和待复核状态。")
        }
    }

    private var composerTabPicker: some View {
        Picker("工作区视图", selection: $selectedComposerTab) {
            ForEach(ComposerTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 260)
        .controlSize(.small)
    }

    @ViewBuilder
    private var selectedComposerContent: some View {
        switch selectedComposerTab {
        case .process:
            processSection
        case .article:
            articleEditorSection
        }
    }

    private var processSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                processHero

                if store.pendingDraftReview != nil {
                    pendingDraftReviewBar
                }

                if store.agentSessionAskAuthor != nil {
                    agentAskAuthorBar
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        processInputPanel
                            .layoutPriority(2)
                        processAdvisorPanel
                            .frame(width: 280)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        processInputPanel
                        processAdvisorPanel
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        processOutlinePanel
                        processMaterialsPanel
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        processOutlinePanel
                        processMaterialsPanel
                    }
                }

                processCurrentTopicPanel
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }

    private var processHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                processHeroTitle
                Spacer(minLength: 20)
                processMetric(title: "正文", value: "\(store.content.count) 字")
                processMetric(title: "选题", value: store.selectedTopic?.status ?? "准备中")
                processMetric(title: "诊断", value: store.latestReview?.overall_score.map { "\($0) 分" } ?? "待开始")
            }

            VStack(alignment: .leading, spacing: 12) {
                processHeroTitle
                HStack(spacing: 10) {
                    processMetric(title: "正文", value: "\(store.content.count) 字")
                    processMetric(title: "选题", value: store.selectedTopic?.status ?? "准备中")
                    processMetric(title: "诊断", value: store.latestReview?.overall_score.map { "\($0) 分" } ?? "待开始")
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var processHeroTitle: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("把想法搭成一篇文章")
                    .font(.title3.weight(.semibold))
                Text("先沉淀方向、选题、大纲和素材；正文成熟后再进入文章编辑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var processInputPanel: some View {
        processPanel {
            VStack(alignment: .leading, spacing: 12) {
                processPanelHeader(
                    title: "创作会话",
                    subtitle: "一句想法也可以开始，系统会帮你扩展成选题、大纲或初稿。",
                    systemImage: "quote.opening"
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldCaption("写作方向")
                            TextField("例如：情感文学", text: $store.writingDirection)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(width: 220)

                        processIdeaEditor
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldCaption("写作方向")
                            TextField("例如：情感文学", text: $store.writingDirection)
                                .textFieldStyle(.roundedBorder)
                        }
                        processIdeaEditor
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await store.quickDraft() }
                    } label: {
                        Label("生成初稿", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

                    Button {
                        Task { await store.generateTopics() }
                    } label: {
                        Label("拓展选题", systemImage: "sparkles")
                    }
                    .disabled(store.ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

                    Button {
                        Task { await store.generateOutline() }
                    } label: {
                        Label("生成大纲", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(store.isLoading)
                }
                .controlSize(.regular)
            }
        }
    }

    private var processIdeaEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldCaption("想法")
            TextEditor(text: $store.ideaInput)
                .font(.callout)
                .frame(minHeight: 104)
                .overlay(.separator, in: RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.5)))
        }
    }

    private var processAdvisorPanel: some View {
        processPanel {
            VStack(alignment: .leading, spacing: 12) {
                processPanelHeader(
                    title: "智能下一步",
                    subtitle: "让系统判断当前最该推进的动作。",
                    systemImage: "wand.and.stars"
                )

                if let run = store.latestAdvisorRun {
                    Text(run.stage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(run.next_action)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(run.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }

                    if !run.actions.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(Array(run.actions.prefix(4))) { action in
                                Button {
                                    store.performAdvisorAction(action)
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                }
                                .disabled(store.isLoading)
                            }
                        }
                        .controlSize(.small)
                    }
                } else {
                    Text("还没有判断记录。可以先补充想法、大纲或正文，再让系统给出下一步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await store.runWritingAdvisor() }
                } label: {
                    Label("判断下一步", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.canRunAdvisor)
            }
        }
    }

    private var processOutlinePanel: some View {
        processTextPanel(
            title: "大纲",
            subtitle: "控制正文结构，生成后可以继续手改。",
            systemImage: "list.bullet.rectangle",
            text: $store.outline,
            minHeight: 170
        ) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.generateOutline() }
                } label: {
                    Label("生成大纲", systemImage: "list.bullet.rectangle")
                }
                .disabled(store.isLoading)

                Button {
                    Task { await store.draftFromOutline() }
                } label: {
                    Label("大纲成稿", systemImage: "square.and.pencil")
                }
                .disabled(store.outline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
            }
            .controlSize(.small)
        }
    }

    private var processMaterialsPanel: some View {
        processTextPanel(
            title: "素材",
            subtitle: "放事实、例子、金句或原始笔记。",
            systemImage: "tray.full",
            text: $store.materials,
            minHeight: 170
        ) {
            Button {
                selectedComposerTab = .article
            } label: {
                Label("进入编辑", systemImage: "doc.text")
            }
            .controlSize(.small)
        }
    }

    private var processCurrentTopicPanel: some View {
        processPanel {
            VStack(alignment: .leading, spacing: 12) {
                processPanelHeader(
                    title: "当前选题",
                    subtitle: "过程页只放正在推进的一条；完整选题库继续放在右侧资料栏。",
                    systemImage: "target"
                )

                if let topic = store.selectedTopic {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(topic.title)
                                .font(.title3.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            Text(topic.subtitle.isEmpty ? "待推进" : topic.subtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }

                        if let description = topic.description,
                           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                topicDetail("核心观点", topic.core_viewpoint)
                                topicDetail("目标读者", topic.target_reader)
                                topicDetail("情绪", topic.emotion)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                topicDetail("核心观点", topic.core_viewpoint)
                                topicDetail("目标读者", topic.target_reader)
                                topicDetail("情绪", topic.emotion)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                store.useTopic(topic)
                            } label: {
                                Label("同步到文章", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Button {
                                store.useTopic(topic)
                                Task { await store.generateOutline() }
                            } label: {
                                Label("生成大纲", systemImage: "list.bullet.rectangle")
                            }
                            .disabled(store.isLoading)

                            Button {
                                Task { await store.generateTopics() }
                            } label: {
                                Label("再拓展选题", systemImage: "sparkles")
                            }
                            .disabled(store.ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
                        }
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("还没有当前选题。先写下一个想法，或从右侧资料栏选择一条待写选题。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await store.generateTopics() }
                        } label: {
                            Label("根据想法拓展选题", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.ideaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
                    }
                }
            }
        }
    }

    private var topActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Spacer(minLength: 0)
                topActionsFull
            }

            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 0)
                topActionsCompact
            }

            HStack {
                Spacer(minLength: 0)
                topActionsCompact
            }
        }
    }

    private var topActionsFull: some View {
        HStack(spacing: 8) {
            statusLabel

            if store.canCancelCurrentOperation {
                Button(role: .cancel) {
                    store.cancelCurrentOperation()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button {
                store.newDraft()
            } label: {
                Label("新稿", systemImage: "plus")
            }

            Button {
                Task { await store.runWritingAdvisor() }
            } label: {
                Label("智能下一步", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canRunAdvisor)

            Button {
                Task { await store.reviewCurrentDraft() }
            } label: {
                Label("写作诊断", systemImage: "text.magnifyingglass")
            }
            .disabled(!store.canRunWritingCoach)

            if store.agentLabEnabled {
                Button {
                    Task { await store.startAgentSession() }
                } label: {
                    Label("代理会话", systemImage: "brain.head.profile")
                }
                .disabled(!store.canStartAgentSession)
                .help("代理会话（实验室）：模型在预算内自主决定写作步骤，产物仍需你确认。")
            }

            Button {
                Task { await store.saveArticle() }
            } label: {
                Label("保存", systemImage: "tray.and.arrow.down")
            }
            .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

            Button {
                isInspectorVisible.toggle()
            } label: {
                Label(isInspectorVisible ? "隐藏上下文" : "显示上下文", systemImage: "sidebar.right")
            }
            .help(isInspectorVisible ? "隐藏右侧上下文" : "显示右侧上下文")
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var topActionsCompact: some View {
        HStack(spacing: 8) {
            statusLabel

            if store.canCancelCurrentOperation {
                Button(role: .cancel) {
                    store.cancelCurrentOperation()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
                .help("取消当前生成")
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .help("刷新")

            Button {
                Task { await store.runWritingAdvisor() }
            } label: {
                Label("智能下一步", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canRunAdvisor)
            .help("智能下一步")

            Button {
                Task { await store.reviewCurrentDraft() }
            } label: {
                Label("写作诊断", systemImage: "text.magnifyingglass")
            }
            .disabled(!store.canRunWritingCoach)
            .help("写作诊断")

            if store.agentLabEnabled {
                Button {
                    Task { await store.startAgentSession() }
                } label: {
                    Label("代理会话", systemImage: "brain.head.profile")
                }
                .disabled(!store.canStartAgentSession)
                .help("代理会话（实验室）：模型在预算内自主决定写作步骤，产物仍需你确认。")
            }

            Button {
                Task { await store.saveArticle() }
            } label: {
                Label("保存", systemImage: "tray.and.arrow.down")
            }
            .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
            .help("保存")

            Button {
                store.newDraft()
            } label: {
                Label("新稿", systemImage: "plus")
            }
            .help("新稿")

            Button {
                isInspectorVisible.toggle()
            } label: {
                Label(isInspectorVisible ? "隐藏上下文" : "显示上下文", systemImage: "sidebar.right")
            }
            .help(isInspectorVisible ? "隐藏右侧上下文" : "显示右侧上下文")
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusLabel: some View {
        Text(store.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var articleMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("文章信息")
                    .font(.headline)
                Spacer()
                Text("\(store.content.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                fieldCaption("标题")
                TextField("文章标题", text: $store.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                fieldCaption("摘要")
                TextEditor(text: $store.summary)
                    .font(.callout)
                    .frame(height: 52)
                    .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
            }

            HStack(spacing: 8) {
                Picker("状态", selection: $store.articleStatus) {
                    ForEach(articleStatuses, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Button {
                    Task { await store.updateSelectedArticleStatus(store.articleStatus) }
                } label: {
                    Label("更新状态", systemImage: "checkmark.circle")
                }
                .disabled(store.isLoading)

                Button {
                    Task { await store.updateSelectedArticleStatus("已归档") }
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
                .disabled(store.isLoading || store.articleStatus == "已归档")
            }
            .controlSize(.small)
        }
    }

    private var articleEditorSection: some View {
        Group {
            if isFocusWritingMode {
                focusArticleEditorSection
            } else {
                standardArticleEditorSection
            }
        }
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }

    private var standardArticleEditorSection: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                publicationHeaderPanel

                if store.pendingDraftReview != nil {
                    pendingDraftReviewBar
                }

                if store.agentSessionAskAuthor != nil {
                    agentAskAuthorBar
                }

                publicationBodyPanel
            }
            .frame(maxWidth: 940, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var publicationHeaderPanel: some View {
        articlePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label("发布稿件", systemImage: "doc.text")
                        .font(.headline)
                    publicationStatusPill
                    Spacer()
                    Text("\(store.content.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    fieldCaption("标题")
                    TextField("输入正式标题", text: $store.title)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.22))
                                .frame(height: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 7) {
                    fieldCaption("摘要 / 导语")
                    TextEditor(text: $store.summary)
                        .font(.callout)
                        .frame(minHeight: 68, maxHeight: 96)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.5)))
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        publicationStatusControls
                        Spacer(minLength: 0)
                        publicationSaveControls
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        publicationStatusControls
                        publicationSaveControls
                    }
                }
            }
        }
    }

    private var publicationBodyPanel: some View {
        articlePanel {
            VStack(alignment: .leading, spacing: 10) {
                editorToolbar

                if let excerpts = store.latestSelfCheck?.flagged_excerpts, !excerpts.isEmpty {
                    selfCheckStrip(excerpts)
                }

                SelectedTextEditor(
                    text: $store.content,
                    selectedRange: $store.contentSelection,
                    highlightExcerpts: (store.latestSelfCheck?.flagged_excerpts ?? []).map(\.excerpt)
                )
                    .frame(minHeight: 320, idealHeight: 520, maxHeight: .infinity)
                    .layoutPriority(1)
                    .overlay(.separator, in: RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.5)))
            }
        }
        .layoutPriority(1)
    }

    private var publicationStatusControls: some View {
        HStack(spacing: 8) {
            Text("发布状态")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("状态", selection: $store.articleStatus) {
                ForEach(articleStatuses, id: \.self) { status in
                    Text(status).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        .controlSize(.small)
    }

    private var publicationSaveControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.updateSelectedArticleStatus(store.articleStatus) }
            } label: {
                Label("更新状态", systemImage: "checkmark.circle")
            }
            .disabled(store.isLoading)

            Button {
                Task { await store.updateSelectedArticleStatus("已归档") }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .disabled(store.isLoading || store.articleStatus == "已归档")

            Button {
                Task { await store.saveArticle() }
            } label: {
                Label("保存", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
        }
        .controlSize(.small)
    }

    private var publicationStatusPill: some View {
        Text(store.articleStatus)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch store.articleStatus {
        case "已发布":
            return .green
        case "已归档":
            return .secondary
        default:
            return .accentColor
        }
    }

    private var focusArticleEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("专注写作")
                    .font(.headline)
                Text("\(store.content.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    Task { await store.saveArticle() }
                } label: {
                    Label("保存", systemImage: "tray.and.arrow.down")
                }
                .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)

                Button {
                    isFocusWritingMode = false
                } label: {
                    Label("退出专注", systemImage: "rectangle.compress.vertical")
                }
            }
            .controlSize(.small)

            TextField("文章标题", text: $store.title)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.roundedBorder)

            SelectedTextEditor(
                text: $store.content,
                selectedRange: $store.contentSelection,
                highlightExcerpts: []
            )
            .frame(minHeight: 460, maxHeight: .infinity)
            .layoutPriority(1)
            .overlay(.separator, in: RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.5)))
        }
        .onAppear {
            isInspectorVisible = false
        }
    }

    private func selectPreferredTabForCurrentDraft() {
        if store.selectedArticleID == nil {
            selectedComposerTab = .process
            return
        }

        if !store.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedComposerTab = .article
        }
    }

    /// 18.4.1 待复核：大范围生成动作的产出已经预览在正文里，这里给出不依赖右侧栏的确认/放弃入口。
    private var pendingDraftReviewBar: some View {
        HStack(spacing: 10) {
            Label("「\(store.pendingDraftReview?.actionTitle ?? "本次生成")」待复核", systemImage: "checklist")
                .font(.caption.weight(.semibold))
            Text("确认前不会覆盖已保存的文章")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("确认定稿") {
                Task { await store.confirmPendingDraftReview() }
            }
            .buttonStyle(.borderedProminent)
            Button("放弃") {
                Task { await store.discardPendingDraftReview() }
            }
        }
        .controlSize(.small)
        .padding(8)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 23.6.5 代理会话 ask_author 暂停：列出具体缺口，作者补充「素材」等既有输入框后继续，或直接结束会话。
    private var agentAskAuthorBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("代理提问", systemImage: "questionmark.bubble")
                .font(.caption.weight(.semibold))
            ForEach(store.agentSessionAskAuthor?.questions ?? [], id: \.self) { question in
                Text("· \(question)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("补充「素材」或「写作方向」后点击继续会话，预算继承此前用量。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("继续会话") {
                    Task { await store.resumeAgentSession() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
                Button("就此结束") {
                    Task { await store.finishAgentSessionNow() }
                }
                .disabled(store.isLoading)
            }
        }
        .controlSize(.small)
        .padding(8)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 18.3.5 生成后轻量自检：不弹窗打断，用旁注列出被高亮的片段和具体顾虑，点掉即可。
    private func selfCheckStrip(_ excerpts: [FlaggedExcerpt]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("自检建议复查 \(excerpts.count) 处（已在正文中高亮）", systemImage: "highlighter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("知道了") {
                    store.dismissSelfCheckHighlights()
                }
                .controlSize(.mini)
            }
            ForEach(excerpts) { item in
                Text("「\(item.excerpt)」— \(item.concern)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Text("正文")
                .font(.headline)
            Text(contentStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()

            Button {
                isFocusWritingMode = true
                selectedComposerTab = .article
                isInspectorVisible = false
            } label: {
                Label("专注", systemImage: "rectangle.expand.vertical")
            }
            .help("进入专注写作模式")

            Button {
                Task { await store.deepDraftRevision() }
            } label: {
                Label("深度成稿", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(store.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
            .help("自动执行诊断、修订、复评，结果进入待复核。")

            Menu {
                ForEach(ArticleCopyFormat.allCases) { format in
                    Button {
                        store.copyArticleContent(format: format)
                    } label: {
                        Label(format.title, systemImage: format.systemImage)
                    }
                }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(store.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("复制正文，可选择 TXT、Markdown 或 HTML 格式。")

            Menu {
                ForEach(PolishMode.allCases) { mode in
                    Button {
                        Task { await store.polishDraft(mode) }
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                    .disabled(!store.canPolishDraft)
                }
                Divider()
                Button {
                    Task { await store.generateDraftAlternatives() }
                } label: {
                    Label("生成 3 个候选", systemImage: "square.stack.3d.up")
                }
                .disabled(!store.canPolishDraft)
            } label: {
                Label("全文改写", systemImage: "wand.and.stars")
            }
            .disabled(!store.canPolishDraft)

            Menu {
                ForEach(RewriteMode.menuCases) { mode in
                    Button {
                        Task { await store.rewriteSelectedContent(mode) }
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                    .disabled(!store.canRewriteSelection)
                }
            } label: {
                Label("局部改写", systemImage: "selection.pin.in.out")
            }
            .disabled(!store.canRewriteSelection)
            .help("先在正文中选中一段文字，再使用局部改写。")
        }
        .controlSize(.small)
    }

    private func articlePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func processPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func processPanelHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func processMetric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
    }

    private func topicDetail(_ title: String, _ value: String?) -> some View {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "未填写" : text)
                .font(.caption)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func processTextPanel<Actions: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        text: Binding<String>,
        minHeight: CGFloat,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        processPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    processPanelHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                    Spacer(minLength: 12)
                    actions()
                }

                TextEditor(text: text)
                    .font(.callout)
                    .frame(minHeight: minHeight)
                    .overlay(.separator, in: RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 0.5)))
            }
        }
    }

    private var contentStatusText: String {
        if store.selectedContentCharacterCount > 0 {
            return "已选中 \(store.selectedContentCharacterCount) 字"
        }
        return "\(store.content.count) 字 · 选中一段正文后可局部改写"
    }

    private func compactPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private enum ComposerTab: String, CaseIterable, Identifiable {
    case process
    case article

    var id: String { rawValue }

    var title: String {
        switch self {
        case .process:
            return "写作过程"
        case .article:
            return "文章编辑"
        }
    }

    var systemImage: String {
        switch self {
        case .process:
            return "sparkles"
        case .article:
            return "doc.text"
        }
    }
}
