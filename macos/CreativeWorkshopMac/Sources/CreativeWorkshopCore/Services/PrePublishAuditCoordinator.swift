import Foundation

package struct PrePublishAuditInput {
    package var articleID: Int
    package var title: String
    package var summary: String
    package var content: String
    package var style: StyleProfile
    package var template: PromptTemplate?
    package var config: ModelConfig
    package var apiKey: String
    package var model: String

    package init(
        articleID: Int,
        title: String,
        summary: String,
        content: String,
        style: StyleProfile,
        template: PromptTemplate? = nil,
        config: ModelConfig,
        apiKey: String,
        model: String
    ) {
        self.articleID = articleID
        self.title = title
        self.summary = summary
        self.content = content
        self.style = style
        self.template = template
        self.config = config
        self.apiKey = apiKey
        self.model = model
    }
}

package struct PrePublishAuditOutput {
    package var audit: PrePublishAudit?
    package var note: String
}

package struct PrePublishAuditCoordinator {
    package var aiClient: AIWorkflowExecuting
    package var database: NativeDatabase

    package init(aiClient: AIWorkflowExecuting, database: NativeDatabase) {
        self.aiClient = aiClient
        self.database = database
    }

    package func run(_ input: PrePublishAuditInput) async throws -> PrePublishAuditOutput {
        do {
            let context = ContextPackage(
                stage: "发表前终审",
                title: input.title,
                summary: input.summary,
                idea: "",
                direction: input.style.genre ?? "",
                outline_excerpt: "",
                content_excerpt: input.content,
                materials_excerpt: "",
                selected_topic_title: nil,
                selected_topic_summary: nil,
                style_name: input.style.name,
                style_brief: input.style.tone ?? "",
                word_count: input.content.count,
                paragraph_count: input.content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                material_count: 0,
                recent_article_titles: [],
                recent_training_focus: [],
                recent_issues: [],
                genre: input.style.genre,
                known_pitfalls: (input.style.known_pitfalls ?? []).map(\.description),
                learned_preferences: (input.style.learned_preferences ?? []).map(\.description)
            )
            let response = await aiClient.execute(
                NativeWorkflowCatalog.prePublishAudit(
                    context: context,
                    style: input.style,
                    template: input.template
                ),
                config: input.config,
                apiKey: input.apiKey
            ).prePublishAuditResponse
            try Task.checkCancellation()
            let fragments = (try? database.rebuildFragments()) ?? []
            let auditedResult = PrePublishAuditLocalVerifier.verifyQuotes(
                in: response.result,
                content: input.content,
                fragments: fragments
            )
            let audit = try database.savePrePublishAudit(
                result: auditedResult,
                articleID: input.articleID,
                titleSnapshot: input.title,
                model: input.model
            )
            if auditedResult.passed == true {
                return PrePublishAuditOutput(audit: audit, note: "终审通过")
            }
            let issueCount = auditedResult.allIssues.count
            let note = issueCount > 0 ? "终审提示 \(issueCount) 项需复核" : "终审未完全通过，请人工复核"
            return PrePublishAuditOutput(audit: audit, note: note)
        } catch {
            if isCancellation(error) {
                throw error
            }
            return PrePublishAuditOutput(audit: nil, note: "终审未完成：\(error.localizedDescription)")
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as NSError).code == NSURLErrorCancelled
    }
}
