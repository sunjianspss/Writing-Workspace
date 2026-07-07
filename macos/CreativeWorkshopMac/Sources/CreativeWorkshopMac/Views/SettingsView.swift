import SwiftUI
import CreativeWorkshopCore

struct SettingsView: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Form {
                settingsSections
            }
            .padding(24)
        }
        .frame(width: 760, height: 680)
    }

    private var settingsSections: some View {
        Group {
            Section("模型") {
                TextField("API Base URL", text: $store.modelBaseURLText)
                    .frame(width: 380)
                TextField("模型", text: $store.modelName)
                    .frame(width: 380)
                SecureField("API Key", text: $store.apiKeyInput)
                    .frame(width: 380)
                VStack(alignment: .leading, spacing: 6) {
                    Text("工作流模型路由 JSON")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.modelWorkflowOverridesText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 620)
                        .frame(minHeight: 90)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                    Text("示例：{\"candidate_judge\":{\"model\":\"deepseek-v4-pro\",\"temperature\":0.4},\"draft_self_check\":{\"model\":\"cheap-model\",\"timeoutSeconds\":45}}")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("保存模型设置") {
                        Task { await store.saveModelSettings() }
                    }
                    Button("清除 API Key") {
                        Task { await store.clearAPIKey() }
                    }
                    Text(store.runtimeStatus?.model ?? store.statusText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("本地数据") {
                Text(store.databasePathText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("风格库") {
                Picker("风格", selection: styleSelection) {
                    ForEach(store.styleProfiles) { profile in
                        Text(verbatim: styleTitle(profile))
                            .tag(profile.id)
                    }
                    if store.styleProfiles.isEmpty {
                        Text("暂无风格")
                            .tag(-1)
                    }
                }
                .frame(width: 420)

                HStack {
                    Button("新建风格") {
                        store.newStyleProfile()
                    }
                    Button("保存风格") {
                        Task { await store.saveStyleProfile() }
                    }
                    Button("设为默认") {
                        Task { await store.setSelectedStyleAsDefault() }
                    }
                    .disabled(store.selectedStyleProfileID == nil || store.selectedStyleProfile?.is_default == 1)
                }

                TextField("风格名称", text: $store.styleName)
                    .frame(width: 420)
                TextField("体裁标签（如：情感文学随笔、经典文本再解读）", text: $store.styleGenre)
                    .frame(width: 420)
                    .help("按写作方向匹配风格档案，需与「写作方向」输入一致才能命中（18.3.4）。")
                TextField("语言", text: $store.styleLanguage)
                    .frame(width: 620)
                TextField("语气", text: $store.styleTone)
                    .frame(width: 620)
                TextField("结构偏好", text: $store.styleStructure)
                    .frame(width: 620)
                TextField("常用表达", text: $store.styleFavorites)
                    .frame(width: 620)
                TextField("禁忌表达", text: $store.styleForbidden)
                    .frame(width: 620)
                TextField("喜欢的标题", text: $store.styleTitleLike)
                    .frame(width: 620)
                TextField("不喜欢的标题", text: $store.styleTitleDislike)
                    .frame(width: 620)

                VStack(alignment: .leading, spacing: 6) {
                    Text("体裁评价重点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.styleGenreFocus)
                        .font(.callout)
                        .frame(width: 620)
                        .frame(minHeight: 70)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                    Text("会拼入写作诊断和生成类提示词，例如「细节是否具体、情绪是否悬浮」（18.3.4）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("样本文本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.styleSamplesText)
                        .font(.callout)
                        .frame(width: 620)
                        .frame(minHeight: 140)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                    Text("多篇样本可用单独一行 --- 分隔。生成时会优先额外参考同体裁的近期文章。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                pitfallsSection
                editPreferencesSection
            }

            Section("提示词模板") {
                Picker("模板", selection: promptTemplateSelection) {
                    ForEach(store.promptTemplates) { template in
                        Text(verbatim: promptTemplateTitle(template))
                            .tag(template.id)
                    }
                    if store.promptTemplates.isEmpty {
                        Text("暂无模板")
                            .tag(-1)
                    }
                }
                .frame(width: 420)

                TextField("模板名称", text: $store.promptTemplateName)
                    .frame(width: 420)

                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.promptTemplateSystemPrompt)
                        .font(.callout)
                        .frame(width: 620)
                        .frame(minHeight: 80)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("User Template")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.promptTemplateUserTemplate)
                        .font(.callout)
                        .frame(width: 620)
                        .frame(minHeight: 220)
                        .overlay(.separator, in: RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 0.5)))
                    Text("可用占位符会按工作流不同逐步扩展。全文润色当前支持：{{style_description}}、{{style_samples}}、{{context_json}}、{{content}}、{{polish_goal}}。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("保存提示词模板") {
                    Task { await store.savePromptTemplate() }
                }
                .disabled(store.selectedPromptTemplateID == nil || store.isLoading)
            }

            Section("实验室") {
                Toggle("代理会话（实验室）", isOn: Binding(
                    get: { store.agentLabEnabled },
                    set: { store.setAgentLabEnabled($0) }
                ))
                Text("代理会话：模型在预算内自主决定写作步骤，产物仍需你确认。评测放行前默认关闭。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("作者雷区清单")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("从历史诊断归纳") {
                    Task { await store.summarizeAuthorPitfalls() }
                }
                .controlSize(.small)
                .disabled(store.selectedStyleProfileID == nil || store.isLoading)
            }

            let confirmed = store.selectedStyleProfile?.known_pitfalls ?? []
            if confirmed.isEmpty {
                Text("暂无已确认的雷区。归纳结果需要人工确认后才会出现在这里。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(confirmed) { pitfall in
                    HStack(alignment: .top, spacing: 8) {
                        Text("· \(pitfall.description)")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("删除") {
                            Task { await store.deleteConfirmedPitfall(pitfall) }
                        }
                        .controlSize(.mini)
                    }
                }
            }

            if !store.pitfallCandidates.isEmpty {
                Divider()
                Text("待确认候选")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.pitfallCandidates, id: \.description) { candidate in
                    HStack(alignment: .top, spacing: 8) {
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
        .frame(width: 620)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var editPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("编辑偏好校准")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("从发布修改归纳") {
                    Task { await store.summarizeEditPreferences() }
                }
                .controlSize(.small)
                .disabled(store.selectedStyleProfileID == nil || store.isLoading)
            }

            if !store.editRecordMonthlySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(store.editRecordMonthlySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let confirmed = store.selectedStyleProfile?.learned_preferences ?? []
            if confirmed.isEmpty {
                Text("暂无已确认编辑偏好。发布后的人工修改会先形成候选规则，确认后才会影响生成。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(confirmed) { preference in
                    HStack(alignment: .top, spacing: 8) {
                        Text("· \(preference.description)")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("删除") {
                            Task { await store.deleteConfirmedEditPreference(preference) }
                        }
                        .controlSize(.mini)
                    }
                }
            }

            if !store.editPreferenceCandidates.isEmpty {
                Divider()
                Text("待确认候选")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.editPreferenceCandidates, id: \.description) { candidate in
                    HStack(alignment: .top, spacing: 8) {
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
        .frame(width: 620)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
