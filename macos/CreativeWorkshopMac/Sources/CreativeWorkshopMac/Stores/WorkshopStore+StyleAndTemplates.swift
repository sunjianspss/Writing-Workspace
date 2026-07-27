import Foundation
import CreativeWorkshopCore

/// R5 瘦身·任务 24（PRD 24.11 / P2-9）：提示词模板与风格档案的编辑保存，从 `WorkshopStore`
/// 搬到这里。这一组只由设置页驱动，和写作流程没有耦合，是最干净的一刀。
///
/// 模型设置与 API Key 那一组**没有**跟着搬：它们要读 `private let keychain`，跨文件 extension
/// 取不到，而为了搬家把凭据存储放宽成模块可见不划算——密钥的可见范围不该为了少几行让步。
extension WorkshopStore {
    func editPromptTemplate(_ template: PromptTemplate?) {
        selectedPromptTemplateID = template?.id
        promptTemplateName = template?.name ?? ""
        promptTemplateSystemPrompt = template?.system_prompt ?? ""
        promptTemplateUserTemplate = template?.user_template ?? ""
    }

    func savePromptTemplate() async {
        guard let selectedPromptTemplateID else {
            statusText = "请先选择提示词模板"
            return
        }

        await run("保存提示词模板") {
            let template = try self.database.savePromptTemplate(
                id: selectedPromptTemplateID,
                name: self.promptTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? self.selectedPromptTemplate?.templateKey?.title ?? "未命名模板"
                    : self.promptTemplateName,
                systemPrompt: self.promptTemplateSystemPrompt,
                userTemplate: self.promptTemplateUserTemplate
            )
            self.promptTemplates = try self.database.listPromptTemplates()
            self.editPromptTemplate(template)
            self.statusText = "提示词模板已保存"
        }
    }

    func newStyleProfile() {
        selectedStyleProfileID = nil
        styleName = "新写作风格"
        styleLanguage = ""
        styleTone = ""
        styleStructure = ""
        styleFavorites = ""
        styleForbidden = ""
        styleSamplesText = ""
        styleTitleLike = ""
        styleTitleDislike = ""
        styleGenre = ""
        styleGenreFocus = ""
        statusText = "已新建风格"
    }

    func editStyleProfile(_ profile: StyleProfile?) {
        selectedStyleProfileID = profile?.id
        styleName = profile?.name ?? ""
        styleLanguage = profile?.language_style ?? ""
        styleTone = profile?.tone ?? ""
        styleStructure = profile?.structure_preference ?? ""
        styleFavorites = profile?.favorite_expressions ?? ""
        styleForbidden = profile?.forbidden_expressions ?? ""
        styleSamplesText = (profile?.sample_texts ?? []).joined(separator: "\n---\n")
        styleTitleLike = profile?.title_style_like ?? ""
        styleTitleDislike = profile?.title_style_dislike ?? ""
        styleGenre = profile?.genre ?? ""
        styleGenreFocus = profile?.genre_focus ?? ""
    }

    func saveStyleProfile() async {
        await run("保存风格") {
            let profile = StyleProfile(
                id: self.selectedStyleProfileID ?? 0,
                name: self.styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名风格" : self.styleName,
                language_style: self.styleLanguage,
                tone: self.styleTone,
                structure_preference: self.styleStructure,
                favorite_expressions: self.styleFavorites,
                forbidden_expressions: self.styleForbidden,
                sample_texts: self.styleSamplesFromText(self.styleSamplesText),
                title_style_like: self.styleTitleLike,
                title_style_dislike: self.styleTitleDislike,
                is_default: self.selectedStyleProfile?.is_default,
                genre: self.styleGenre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.styleGenre,
                genre_focus: self.styleGenreFocus,
                known_pitfalls: self.selectedStyleProfile?.known_pitfalls,
                learned_preferences: self.selectedStyleProfile?.learned_preferences
            )
            let saved = try self.database.saveStyleProfile(id: self.selectedStyleProfileID, profile: profile)
            self.styleProfiles = try self.database.listStyleProfiles()
            self.editStyleProfile(saved)
            self.statusText = "风格已保存"
        }
    }

    func setSelectedStyleAsDefault() async {
        guard let selectedStyleProfileID else {
            statusText = "请先选择风格"
            return
        }
        await run("设为默认风格") {
            let style = try self.database.setDefaultStyleProfile(id: selectedStyleProfileID)
            self.styleProfiles = try self.database.listStyleProfiles()
            self.editStyleProfile(style)
            self.statusText = "默认风格已更新"
        }
    }

    private func styleSamplesFromText(_ text: String) -> [String] {
        text
            .components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }}
