import SwiftUI
import CreativeWorkshopCore

/// 「当前稿件」组里的三个视角：创作过程、正文、发布物料。
///
/// 24.13：这三个视角原本是本视图内部的一个分段 Picker，现在由左列导航直接选中，
/// 所以 `selection` 是外部状态——本视图只负责渲染被选中的那一个，并在需要时跳转。
struct ComposerView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var selection: WorkspaceDestination
    @SceneStorage("isFocusWritingMode") private var isFocusWritingMode = false
    @State private var isWeChatFormatterPresented = false
    private let articleStatuses = ["草稿", "已发布", "已归档"]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "当前稿件", title: selection.title) {
                topActionBar
            }

            selectedComposerContent
                .padding(.horizontal, WorkshopMetrics.sectionSpacing)
                .padding(.top, WorkshopMetrics.stackSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectPreferredViewForCurrentDraft()
        }
        .onChange(of: store.selectedArticleID) { _ in
            selectPreferredViewForCurrentDraft()
        }
        // 18.3.2 防空转：内容自上次诊断后未变化时，必须先提示后才允许发起新的模型调用。
        // 24.1 发布流程护栏：未经"已发布"直接归档会缺失终审与编辑量记录（北极星指标）。
        .confirmationDialog(
            "这篇文章尚未标记\u{201C}已发布\u{201D}。直接归档将跳过发表前终审与编辑量记录。",
            isPresented: $store.showArchiveWithoutPublishPrompt,
            titleVisibility: .visible
        ) {
            Button("先发布再归档") {
                Task { await store.archiveAfterPublishing() }
            }
            Button("仍然归档", role: .destructive) {
                Task { await store.archiveWithoutPublishing() }
            }
            Button("取消", role: .cancel) {
                store.cancelArchivePrompt()
            }
        }
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
                selection = .article
            }
            Button("丢弃", role: .destructive) {
                store.discardAutosavedDraft()
            }
            Button("稍后再说", role: .cancel) {}
        } message: {
            Text("系统保存了上次未正式保存的标题、摘要、正文、想法、大纲、素材和待复核状态。")
        }
        .sheet(isPresented: $isWeChatFormatterPresented) {
            WeChatFormatterView(
                title: store.title,
                summary: store.summary,
                content: store.content
            )
        }
    }

    @ViewBuilder
    private var selectedComposerContent: some View {
        switch selection {
        case .article:
            articleEditorSection
        case .community:
            communitySection
        default:
            processSection
        }
    }

    private var communitySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PublishAssetsCard(store: store)
                    .frame(maxWidth: 1_060, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
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
                            directionField
                        }
                        .frame(width: 220)

                        processIdeaEditor
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldCaption("写作方向")
                            directionField
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

    /// 写作方向：可直接输入，也可从已有体裁中选（保证与风格档案、同体裁样本的匹配键一致）。
    private var directionField: some View {
        HStack(spacing: 6) {
            TextField("例如：情感文学", text: $store.writingDirection)
                .textFieldStyle(.roundedBorder)
            Menu {
                ForEach(store.knownDirections, id: \.self) { direction in
                    Button(direction) {
                        store.writingDirection = direction
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("从已有体裁中选择，保证与风格档案和同体裁样本精确匹配；也可直接输入新体裁。")
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
                selection = .article
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
            topActionsFull
            topActionsCompact
        }
    }

    private var topActionsFull: some View {
        HStack(spacing: 8) {
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
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var topActionsCompact: some View {
        HStack(spacing: 8) {
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
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 24.1 发布流程指示条：让"已发布"作为数据链必经站自解释。
    private var publishFlowIndicator: some View {
        HStack(spacing: 4) {
            ForEach(Array(WorkshopStore.publishFlowStages.enumerated()), id: \.offset) { index, stage in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Text(stage)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        index == store.publishFlowStageIndex ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(index == store.publishFlowStageIndex ? Color.accentColor : .secondary)
            }
            Text("发布时记录终审与编辑量")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

                publishFlowIndicator
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
                Task { await store.requestArticleStatusChange(store.articleStatus) }
            } label: {
                Label("更新状态", systemImage: "checkmark.circle")
            }
            .disabled(store.isLoading)

            Button {
                Task { await store.requestArticleStatusChange("已归档") }
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
    }

    /// 打开一篇已有内容的稿件时直接落到正文；新稿回到创作过程。
    /// 只在「当前稿件」的三个视角之间调整，不会把作者从诊断或工作区页面拽走。
    private func selectPreferredViewForCurrentDraft() {
        if store.selectedArticleID == nil {
            selection = .process
            return
        }

        if !store.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selection = .article
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
                selection = .article
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

            Button {
                isWeChatFormatterPresented = true
            } label: {
                Label("公众号排版", systemImage: "doc.richtext")
            }
            .disabled(store.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("预览公众号主题，并复制带内联样式的微信富文本。")

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

    private func fieldCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct PublishAssetsCard: View {
    @ObservedObject var store: WorkshopStore
    @State private var selectedChannel: PublishChannel = .xiaohongshu
    @State private var copiedAssetID: String?
    @State private var isPromptExpanded = true
    @State private var isRawOutputExpanded = false

    var body: some View {
        let assets = store.latestPublishAssets
        let hasAssets = assets.map(hasUsableContent) ?? false

        return VStack(alignment: .leading, spacing: 16) {
            publicationHeader(hasAssets: hasAssets)

            if let assets, hasAssets {
                publishWorkbench(assets)
                promptPanel(assets)
                rawOutputPanel(assets)
            } else {
                emptyState
                if let assets {
                    rawOutputPanel(assets)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            selectPreferredChannel()
        }
        .onChange(of: store.latestPublishAssets?.id) { _ in
            selectPreferredChannel()
        }
    }

    private func publicationHeader(hasAssets: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                publicationIdentity(hasAssets: hasAssets)
                Spacer(minLength: 20)
                generateButton(hasAssets: hasAssets)
            }

            VStack(alignment: .leading, spacing: 12) {
                publicationIdentity(hasAssets: hasAssets)
                generateButton(hasAssets: hasAssets)
            }
        }
        .padding(.vertical, 4)
    }

    private func publicationIdentity(hasAssets: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "megaphone")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text("社群发布")
                    .font(.title3.weight(.semibold))

                Text("为不同渠道准备内容，快速预览并一键复制发布。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Image(systemName: hasAssets ? "checkmark.circle" : "clock")
                    Text(hasAssets ? "已有发布物料" : "等待生成发布物料")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(hasAssets ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func generateButton(hasAssets: Bool) -> some View {
        Button {
            Task { await store.generatePublishAssets() }
        } label: {
            if isGeneratingAssets {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("生成中")
                }
            } else {
                Label(hasAssets ? "重新生成" : "生成发布物料", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(!store.canGeneratePublishAssets)
        .help(hasAssets ? "基于当前文章重新生成所有发布物料" : "基于当前文章生成发布物料")
    }

    private func publishWorkbench(_ assets: PublishAssets) -> some View {
        PublishWorkbenchLayout(
            supportColumnWidth: 300,
            minimumChannelWidth: 380,
            spacing: 14
        ) {
            supportingAssetsColumn(assets)
            channelPanel(assets)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func supportingAssetsColumn(_ assets: PublishAssets) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shortAssetPanel(
                title: "摘要",
                systemImage: "text.alignleft",
                value: assets.summary,
                assetID: "summary",
                minimumHeight: 132
            )

            shortAssetPanel(
                title: "封面文案",
                systemImage: "character.cursor.ibeam",
                value: assets.cover_text,
                assetID: "cover-text",
                minimumHeight: 108
            )

            tagsPanel(assets.tags)
        }
    }

    private func shortAssetPanel(
        title: String,
        systemImage: String,
        value: String?,
        assetID: String,
        minimumHeight: CGFloat
    ) -> some View {
        let content = trimmed(value)

        return publishSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    if let content {
                        compactCopyButton(value: content, assetID: assetID, label: title)
                    }
                }

                if let content {
                    Text(content)
                        .font(.callout)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    missingContentLabel("暂未生成\(title)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        }
    }

    private func tagsPanel(_ tags: [String]) -> some View {
        publishSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("标签", systemImage: "tag")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)

                    if !tags.isEmpty {
                        compactCopyButton(
                            value: tags.joined(separator: "，"),
                            assetID: "tags",
                            label: "标签"
                        )
                    }
                }

                if tags.isEmpty {
                    missingContentLabel("暂未生成标签")
                } else {
                    PublishTagFlowLayout(spacing: 7) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 220, alignment: .leading)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                                .help(tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        }
    }

    private func channelPanel(_ assets: PublishAssets) -> some View {
        let channelText = trimmed(selectedChannel.value(in: assets))
        let assetID = selectedChannel.rawValue

        return publishSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    channelSelector
                    Spacer(minLength: 12)
                    Text(channelText.map { "\($0.count) 字" } ?? "暂无内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.top, 12)

                Group {
                    if let channelText {
                        Text(channelText)
                            .font(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        missingContentLabel("暂未生成\(selectedChannel.title)文案")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 318, alignment: .topLeading)
                .padding(.vertical, 16)

                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        if let channelText {
                            copy(channelText, assetID: assetID)
                        }
                    } label: {
                        Label(
                            copiedAssetID == assetID ? "已复制正文" : "复制正文",
                            systemImage: copiedAssetID == assetID ? "checkmark" : "doc.on.doc"
                        )
                        .frame(minWidth: 78)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(copiedAssetID == assetID ? .green : .accentColor)
                    .disabled(channelText == nil)
                    .help("复制\(selectedChannel.title)文案")
                }
            }
        }
    }

    private var channelSelector: some View {
        HStack(spacing: 22) {
            ForEach(PublishChannel.allCases) { channel in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedChannel = channel
                    }
                } label: {
                    Text(channel.title)
                        .font(.subheadline.weight(selectedChannel == channel ? .semibold : .regular))
                        .foregroundStyle(selectedChannel == channel ? Color.accentColor : Color.secondary)
                        .padding(.vertical, 2)
                        .overlay(alignment: .bottom) {
                            if selectedChannel == channel {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: 9)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedChannel == channel ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func promptPanel(_ assets: PublishAssets) -> some View {
        if let prompt = trimmed(assets.cover_image_prompt) {
            publishSurface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("封面图提示词", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))

                        Spacer(minLength: 8)
                        compactCopyButton(value: prompt, assetID: "cover-prompt", label: "封面图提示词")

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isPromptExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(isPromptExpanded ? 180 : 0))
                        }
                        .buttonStyle(.borderless)
                        .help(isPromptExpanded ? "收起封面图提示词" : "展开封面图提示词")
                    }

                    if isPromptExpanded {
                        Text(prompt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rawOutputPanel(_ assets: PublishAssets) -> some View {
        if let rawOutput = trimmed(assets.raw_output) {
            DisclosureGroup("模型原始物料", isExpanded: $isRawOutputExpanded) {
                Text(rawOutput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var emptyState: some View {
        publishSurface {
            VStack(spacing: 14) {
                Image(systemName: "paperplane")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 15))

                VStack(spacing: 6) {
                    Text("把成稿变成可发布的内容")
                        .font(.headline)
                    Text("一次生成摘要、封面文案、朋友圈、小红书、标签和封面图提示词。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            .frame(maxWidth: .infinity, minHeight: 330)
        }
    }

    private func compactCopyButton(value: String, assetID: String, label: String) -> some View {
        Button {
            copy(value, assetID: assetID)
        } label: {
            Label(
                copiedAssetID == assetID ? "已复制" : "复制",
                systemImage: copiedAssetID == assetID ? "checkmark" : "doc.on.doc"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(copiedAssetID == assetID ? Color.green : Color.secondary)
            .frame(width: 56, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("复制\(label)")
        .accessibilityLabel(copiedAssetID == assetID ? "\(label)已复制" : "复制\(label)")
    }

    private func missingContentLabel(_ text: String) -> some View {
        Label(text, systemImage: "minus.circle")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func publishSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
    }

    private var isGeneratingAssets: Bool {
        store.isLoading && store.statusText.contains("生成发布物料")
    }

    private func hasUsableContent(_ assets: PublishAssets) -> Bool {
        [
            assets.summary,
            assets.cover_text,
            assets.moments_text,
            assets.xiaohongshu_text,
            assets.cover_image_prompt
        ].contains { trimmed($0) != nil } || !assets.tags.isEmpty
    }

    private func selectPreferredChannel() {
        guard let assets = store.latestPublishAssets else {
            selectedChannel = .xiaohongshu
            return
        }

        if trimmed(assets.xiaohongshu_text) != nil {
            selectedChannel = .xiaohongshu
        } else if trimmed(assets.moments_text) != nil {
            selectedChannel = .moments
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func copy(_ value: String, assetID: String) {
        store.copyToClipboard(value)
        withAnimation(.easeOut(duration: 0.16)) {
            copiedAssetID = assetID
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard copiedAssetID == assetID else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                copiedAssetID = nil
            }
        }
    }
}

private enum PublishChannel: String, CaseIterable, Identifiable {
    case xiaohongshu
    case moments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xiaohongshu:
            return "小红书"
        case .moments:
            return "朋友圈"
        }
    }

    func value(in assets: PublishAssets) -> String? {
        switch self {
        case .xiaohongshu:
            return assets.xiaohongshu_text
        case .moments:
            return assets.moments_text
        }
    }
}

private struct PublishWorkbenchLayout: Layout {
    let supportColumnWidth: CGFloat
    let minimumChannelWidth: CGFloat
    let spacing: CGFloat

    private var wideLayoutMinimumWidth: CGFloat {
        supportColumnWidth + spacing + minimumChannelWidth
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }

        let availableWidth = proposal.width ?? wideLayoutMinimumWidth
        if availableWidth >= wideLayoutMinimumWidth {
            let channelWidth = availableWidth - supportColumnWidth - spacing
            let supportSize = subviews[0].sizeThatFits(
                ProposedViewSize(width: supportColumnWidth, height: nil)
            )
            let channelSize = subviews[1].sizeThatFits(
                ProposedViewSize(width: channelWidth, height: nil)
            )
            return CGSize(
                width: availableWidth,
                height: max(supportSize.height, channelSize.height)
            )
        }

        let stackedProposal = ProposedViewSize(width: availableWidth, height: nil)
        let supportSize = subviews[0].sizeThatFits(stackedProposal)
        let channelSize = subviews[1].sizeThatFits(stackedProposal)
        return CGSize(
            width: availableWidth,
            height: supportSize.height + spacing + channelSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }

        if bounds.width >= wideLayoutMinimumWidth {
            let channelWidth = bounds.width - supportColumnWidth - spacing
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: supportColumnWidth, height: nil)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + supportColumnWidth + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: channelWidth, height: nil)
            )
            return
        }

        let stackedProposal = ProposedViewSize(width: bounds.width, height: nil)
        let supportSize = subviews[0].sizeThatFits(stackedProposal)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: stackedProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + supportSize.height + spacing),
            anchor: .topLeading,
            proposal: stackedProposal
        )
    }
}

private struct PublishTagFlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > availableWidth {
                widestRow = max(widestRow, currentX - spacing)
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, max(0, currentX - spacing))
        let width = proposal.width ?? widestRow
        return CGSize(width: width, height: currentY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
