import Foundation
import SwiftUI
import CreativeWorkshopCore

private enum WorkshopSettingsTab: String, CaseIterable, Identifiable, Hashable {
    case model
    case style
    case prompts
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: "模型"
        case .style: "风格"
        case .prompts: "提示词"
        case .advanced: "高级"
        }
    }

    var symbol: String {
        switch self {
        case .model: "cpu"
        case .style: "text.quote"
        case .prompts: "text.bubble"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// 24.14：设置从独立的偏好设置窗口搬进右列，成为左列底部的一个目的地。
/// 四个分类保持不变，只是不再由 `TabView` 的窗口式工具栏承载——改用右列统一的
/// 面包屑顶栏，和其他屏一致。状态栏由 `ContentView` 提供，这里不再自带一条。
struct SettingsView: View {
    @ObservedObject var store: WorkshopStore
    @State private var selectedTab: WorkshopSettingsTab = .model
    @State private var isShowingClearAPIKeyConfirmation = false
    @AppStorage("workshopAppearance") private var appearance = WorkshopAppearance.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "设置", title: selectedTab.title) {
                Picker("设置分类", selection: $selectedTab) {
                    ForEach(WorkshopSettingsTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            selectedSettingsPage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "清除 API Key？",
            isPresented: $isShowingClearAPIKeyConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除 API Key", role: .destructive) {
                Task { await store.clearAPIKey() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会从钥匙串移除当前凭据。之后仍可重新填写并保存。")
        }
    }

    @ViewBuilder
    private var selectedSettingsPage: some View {
        switch selectedTab {
        case .model: modelSettingsPage
        case .style: styleSettingsPage
        case .prompts: promptSettingsPage
        case .advanced: advancedSettingsPage
        }
    }

    private var modelSettingsPage: some View {
        settingsPage(
            title: "模型",
            subtitle: "配置默认模型与凭据；单个工作流的覆盖规则收纳在高级选项中。"
        ) {
            Section("连接") {
                TextField("API Base URL", text: $store.modelBaseURLText)
                TextField("默认模型", text: $store.modelName)
                SecureField("API Key", text: $store.apiKeyInput)

                LabeledContent("钥匙串状态") {
                    Label(
                        store.isAPIKeyConfigured ? "已保存" : "未保存",
                        systemImage: store.isAPIKeyConfigured ? "key.fill" : "key"
                    )
                    .foregroundStyle(.secondary)
                }

                if let model = store.runtimeStatus?.model {
                    LabeledContent("当前运行模型") {
                        Text(model)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                HStack(spacing: WorkshopMetrics.controlSpacing) {
                    Button("清除 API Key", role: .destructive) {
                        isShowingClearAPIKeyConfirmation = true
                    }
                    .disabled(!store.isAPIKeyConfigured || store.isLoading)

                    Spacer()

                    Button("保存模型设置") {
                        Task { await store.saveModelSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)
                }
            }

            Section("工作流模型路由") {
                DisclosureGroup("按工作流覆盖默认模型") {
                    WorkshopLabeledEditor(
                        "路由规则（JSON）",
                        text: $store.modelWorkflowOverridesText,
                        minimumHeight: 120,
                        hint: "示例：{\"candidate_judge\":{\"model\":\"deepseek-v4-pro\",\"temperature\":0.4}}",
                        style: .code
                    )
                    .padding(.top, WorkshopMetrics.controlSpacing)
                }
            }
        }
    }

    private var styleSettingsPage: some View {
        settingsPage(
            title: "风格",
            subtitle: "把稳定偏好记录为可审阅的风格档案；自动归纳的规则必须人工确认。"
        ) {
            Section("风格档案") {
                Picker("当前风格", selection: styleSelection) {
                    ForEach(store.styleProfiles) { profile in
                        Text(verbatim: styleTitle(profile))
                            .tag(profile.id)
                    }
                    if store.styleProfiles.isEmpty {
                        Text("暂无风格")
                            .tag(-1)
                    }
                }

                TextField("风格名称", text: $store.styleName)
                TextField("体裁标签", text: $store.styleGenre)
                    .help("需与写作方向一致，才能命中对应风格档案。")

                HStack(spacing: WorkshopMetrics.controlSpacing) {
                    Button("新建风格") {
                        store.newStyleProfile()
                    }

                    Button("设为默认") {
                        Task { await store.setSelectedStyleAsDefault() }
                    }
                    .disabled(
                        store.selectedStyleProfileID == nil
                            || store.selectedStyleProfile?.is_default == 1
                            || store.isLoading
                    )

                    Spacer()

                    Button("保存风格") {
                        Task { await store.saveStyleProfile() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)
                }
            }

            Section("语言与结构") {
                TextField("语言", text: $store.styleLanguage)
                TextField("语气", text: $store.styleTone)
                TextField("结构偏好", text: $store.styleStructure)
                TextField("常用表达", text: $store.styleFavorites)
                TextField("禁忌表达", text: $store.styleForbidden)
            }

            Section("标题偏好") {
                TextField("喜欢的标题", text: $store.styleTitleLike)
                TextField("不喜欢的标题", text: $store.styleTitleDislike)
            }

            Section("写作参考") {
                WorkshopLabeledEditor(
                    "体裁评价重点",
                    text: $store.styleGenreFocus,
                    minimumHeight: 90,
                    hint: "会用于写作诊断与生成，例如：细节是否具体、情绪是否悬浮。"
                )

                WorkshopLabeledEditor(
                    "样本文本",
                    text: $store.styleSamplesText,
                    minimumHeight: 160,
                    hint: "多篇样本用单独一行 --- 分隔；生成时还会参考同体裁的近期文章。"
                )
            }

            Section("学习与校准") {
                pitfallsSection
                editPreferencesSection
            }
        }
    }

    private var promptSettingsPage: some View {
        settingsPage(
            title: "提示词",
            subtitle: "按工作流维护模板。保存前可直接审阅系统指令、用户模板与占位符。"
        ) {
            Section("模板") {
                Picker("当前模板", selection: promptTemplateSelection) {
                    ForEach(store.promptTemplates) { template in
                        Text(verbatim: promptTemplateTitle(template))
                            .tag(template.id)
                    }
                    if store.promptTemplates.isEmpty {
                        Text("暂无模板")
                            .tag(-1)
                    }
                }

                TextField("模板名称", text: $store.promptTemplateName)
            }

            Section("指令") {
                WorkshopLabeledEditor(
                    "System Prompt",
                    text: $store.promptTemplateSystemPrompt,
                    minimumHeight: 110
                )

                WorkshopLabeledEditor(
                    "User Template",
                    text: $store.promptTemplateUserTemplate,
                    minimumHeight: 250,
                    hint: "全文润色支持：{{style_description}}、{{style_samples}}、{{context_json}}、{{content}}、{{polish_goal}}。"
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button("保存提示词模板") {
                        Task { await store.savePromptTemplate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedPromptTemplateID == nil || store.isLoading)
                }
            }
        }
    }

    private var advancedSettingsPage: some View {
        settingsPage(
            title: "高级",
            subtitle: "外观、本地数据位置，以及尚未进入稳定工作流的实验功能。"
        ) {
            Section("外观") {
                Picker("界面外观", selection: $appearance) {
                    ForEach(WorkshopAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("「跟随系统」随 macOS 的浅色/深色切换；选定浅色或深色则始终固定。左列底部也可以快速切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("本地数据") {
                VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
                    Text("数据库路径")
                        .font(.caption.weight(.semibold))
                    Text(store.databasePathText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("实验室") {
                Toggle(
                    "代理会话",
                    isOn: Binding(
                        get: { store.agentLabEnabled },
                        set: { store.setAgentLabEnabled($0) }
                    )
                )

                Text("模型会在预算内自行安排写作步骤，但所有产物仍需你确认。评测放行前默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, WorkshopMetrics.pagePadding)
            .padding(.top, WorkshopMetrics.sectionSpacing)
            .padding(.bottom, WorkshopMetrics.controlSpacing)

            Form {
                content()
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: WorkshopMetrics.settingsContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var pitfallsSection: some View {
        GroupBox("作者雷区清单") {
            VStack(alignment: .leading, spacing: WorkshopMetrics.controlSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("从历史诊断生成候选，确认后才会影响写作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("归纳") {
                        Task { await store.summarizeAuthorPitfalls() }
                    }
                    .controlSize(.small)
                    .disabled(store.selectedStyleProfileID == nil || store.isLoading)
                }

                let confirmed = store.selectedStyleProfile?.known_pitfalls ?? []
                if confirmed.isEmpty {
                    Text("暂无已确认的雷区。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(confirmed) { pitfall in
                        HStack(alignment: .top, spacing: WorkshopMetrics.controlSpacing) {
                            Text("• \(pitfall.description)")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("删除", role: .destructive) {
                                Task { await store.deleteConfirmedPitfall(pitfall) }
                            }
                            .controlSize(.mini)
                        }
                    }
                }

                if !store.pitfallCandidates.isEmpty {
                    Divider()
                    Text("待确认候选")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.pitfallCandidates, id: \.description) { candidate in
                        HStack(alignment: .top, spacing: WorkshopMetrics.controlSpacing) {
                            Text(candidate.description)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("确认加入") {
                                Task { await store.confirmPitfallCandidate(candidate) }
                            }
                            .controlSize(.mini)
                            Button("忽略") {
                                store.dismissPitfallCandidate(candidate)
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var editPreferencesSection: some View {
        GroupBox("编辑偏好校准") {
            VStack(alignment: .leading, spacing: WorkshopMetrics.controlSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("从发布前后的人工修改生成候选规则。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("归纳") {
                        Task { await store.summarizeEditPreferences() }
                    }
                    .controlSize(.small)
                    .disabled(store.selectedStyleProfileID == nil || store.isLoading)
                }

                if !store.editRecordMonthlySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(store.editRecordMonthlySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let confirmed = store.selectedStyleProfile?.learned_preferences ?? []
                if confirmed.isEmpty {
                    Text("暂无已确认的编辑偏好。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(confirmed) { preference in
                        HStack(alignment: .top, spacing: WorkshopMetrics.controlSpacing) {
                            Text("• \(preference.description)")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("删除", role: .destructive) {
                                Task { await store.deleteConfirmedEditPreference(preference) }
                            }
                            .controlSize(.mini)
                        }
                    }
                }

                if !store.editPreferenceCandidates.isEmpty {
                    Divider()
                    Text("待确认候选")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.editPreferenceCandidates, id: \.description) { candidate in
                        HStack(alignment: .top, spacing: WorkshopMetrics.controlSpacing) {
                            Text(candidate.description)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("确认加入") {
                                Task { await store.confirmEditPreferenceCandidate(candidate) }
                            }
                            .controlSize(.mini)
                            Button("忽略") {
                                store.dismissEditPreferenceCandidate(candidate)
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func promptTemplateTitle(_ template: PromptTemplate) -> String {
        template.templateKey?.title ?? template.name
    }

    private var promptTemplateSelection: Binding<Int> {
        Binding(
            get: { store.selectedPromptTemplateID ?? store.promptTemplates.first?.id ?? -1 },
            set: { templateID in
                store.editPromptTemplate(store.promptTemplates.first { $0.id == templateID })
            }
        )
    }

    private func styleTitle(_ profile: StyleProfile) -> String {
        profile.is_default == 1 ? "\(profile.name) · 默认" : profile.name
    }

    private var styleSelection: Binding<Int> {
        Binding(
            get: { store.selectedStyleProfileID ?? store.styleProfiles.first?.id ?? -1 },
            set: { profileID in
                store.editStyleProfile(store.styleProfiles.first { $0.id == profileID })
            }
        )
    }
}
