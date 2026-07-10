import Foundation
import SQLite3

package final class NativeDatabase {
    package let databaseURL: URL
    private var db: OpaquePointer?

    package init(databaseURL: URL? = nil) throws {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            self.databaseURL = try NativePaths.databaseURL
        }
        if sqlite3_open(self.databaseURL.path, &db) != SQLITE_OK {
            throw NativeDatabaseError.open(message: lastErrorMessage)
        }
        try execute("PRAGMA foreign_keys = ON")
        try initialize()
    }

    deinit {
        sqlite3_close(db)
    }

    package func runtimeStatus(model: String) -> RuntimeStatus {
        RuntimeStatus(model: model, backend: "native-sqlite")
    }

    package func schemaVersion() throws -> Int {
        try scalarInt("PRAGMA user_version")
    }

    package func modelConfig() throws -> ModelConfig {
        ModelConfig(
            baseURL: try setting("model_base_url") ?? "https://api.deepseek.com",
            model: try setting("model_name") ?? "deepseek-v4-pro",
            workflowOverrides: decodeJSON(try setting("model_workflow_overrides"), fallback: [String: ModelRouteConfig]())
        )
    }

    package func saveModelConfig(baseURL: String, model: String) throws {
        let existingOverrides = (try? modelConfig().workflowOverrides) ?? [:]
        try saveModelConfig(
            ModelConfig(
                baseURL: baseURL,
                model: model,
                workflowOverrides: existingOverrides
            )
        )
    }

    package func saveModelConfig(_ config: ModelConfig) throws {
        try saveSetting(key: "model_base_url", value: config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        try saveSetting(key: "model_name", value: config.model.trimmingCharacters(in: .whitespacesAndNewlines))
        try saveSetting(key: "model_workflow_overrides", value: encodeJSON(config.workflowOverrides))
    }

    /// 23.6 有界代理循环每会话模型调用上限，默认 12（决策步计入）。
    package func agentCallBudget() throws -> Int {
        Int(try setting("agent_call_budget") ?? "") ?? 12
    }

    package func saveAgentCallBudget(_ budget: Int) throws {
        try saveSetting(key: "agent_call_budget", value: "\(budget)")
    }

    /// 23.6.6 实验室开关：默认关闭，"深度成稿"保持默认入口。
    package func agentLabEnabled() throws -> Bool {
        try setting("agent_lab_enabled") == "1"
    }

    package func saveAgentLabEnabled(_ enabled: Bool) throws {
        try saveSetting(key: "agent_lab_enabled", value: enabled ? "1" : "0")
    }

    package func listArticles(status: String? = nil) throws -> [Article] {
        let trimmedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedStatus.isEmpty || trimmedStatus == "全部" {
            return try rows("\(articleSelectSQL) ORDER BY updated_at DESC", mapper: article)
        }
        return try rows(
            "\(articleSelectSQL) WHERE status = ? ORDER BY updated_at DESC",
            [trimmedStatus],
            mapper: article
        )
    }

    package func listTopics(status: String? = nil) throws -> [Topic] {
        let trimmedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedStatus.isEmpty {
            return try rows("\(topicSelectSQL) ORDER BY updated_at DESC", mapper: topic)
        }
        return try rows("\(topicSelectSQL) WHERE status = ? ORDER BY updated_at DESC", [trimmedStatus], mapper: topic)
    }

    package func listIdeas(search: String = "", type: String = "", tag: String = "") throws -> [Idea] {
        var clauses: [String] = []
        var values: [Any?] = []
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            clauses.append("(title LIKE ? OR content LIKE ?)")
            values.append("%\(trimmedSearch)%")
            values.append("%\(trimmedSearch)%")
        }
        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedType.isEmpty, trimmedType != "全部" {
            clauses.append("type = ?")
            values.append(trimmedType)
        }
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty {
            clauses.append("tags LIKE ?")
            values.append("%\(trimmedTag)%")
        }
        let whereClause = clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))"
        return try rows("\(ideaSelectSQL)\(whereClause) ORDER BY updated_at DESC", values, mapper: idea)
    }

    package func overviewStats() throws -> OverviewStats {
        let articleTotal = try scalarInt("SELECT COUNT(*) FROM articles")
        let publishedTotal = try scalarInt("SELECT COUNT(*) FROM articles WHERE status IN ('已发布', '已归档')")
        let topicPending = try scalarInt("SELECT COUNT(*) FROM topics WHERE status = '待写'")
        let topicTotal = try scalarInt("SELECT COUNT(*) FROM topics")
        let topDirection = try scalarText(
            """
            SELECT direction FROM topics
            WHERE direction IS NOT NULL AND direction != ''
            GROUP BY direction
            ORDER BY COUNT(*) DESC
            LIMIT 1
            """
        )

        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let weekArticleTotal = try scalarInt(
            "SELECT COUNT(*) FROM articles WHERE substr(created_at, 1, 10) >= ?",
            [dateOnly(weekStart)]
        )
        let monthArticleTotal = try scalarInt(
            "SELECT COUNT(*) FROM articles WHERE substr(created_at, 1, 10) >= ?",
            [dateOnly(monthStart)]
        )

        return OverviewStats(
            article_total: articleTotal,
            published_total: publishedTotal,
            week_article_total: weekArticleTotal,
            month_article_total: monthArticleTotal,
            week_published_total: nil,
            month_published_total: nil,
            idea_total: try scalarInt("SELECT COUNT(*) FROM ideas"),
            idea_used: try scalarInt("SELECT COUNT(*) FROM ideas WHERE used = 1"),
            topic_pending: topicPending,
            topic_total: topicTotal,
            top_direction: topDirection,
            current_streak: try writingStreak()
        )
    }

    package func defaultStyle() throws -> StyleProfile {
        if let style = try rows(
            "\(styleSelectSQL) WHERE is_default = 1 ORDER BY id LIMIT 1",
            mapper: style
        ).first {
            return style
        }
        return try rows("\(styleSelectSQL) ORDER BY id LIMIT 1", mapper: style).first ?? defaultStyleProfile
    }

    package func listStyleProfiles() throws -> [StyleProfile] {
        try rows("\(styleSelectSQL) ORDER BY is_default DESC, updated_at DESC, id", mapper: style)
    }

    package func saveStyleProfile(id: Int?, profile: StyleProfile) throws -> StyleProfile {
        let now = utcNow()
        let sampleTexts = encodeStringArray(profile.sample_texts ?? [])
        let knownPitfalls = encodePitfalls(profile.known_pitfalls ?? [])
        let learnedPreferences = encodeJSON(profile.learned_preferences ?? [])
        if let id {
            try execute(
                """
                UPDATE style_profiles
                SET name = ?, language_style = ?, tone = ?, structure_preference = ?,
                    favorite_expressions = ?, forbidden_expressions = ?, sample_texts = ?,
                    title_style_like = ?, title_style_dislike = ?, genre = ?, genre_focus = ?,
                    known_pitfalls = ?, learned_preferences = ?, updated_at = ?
                WHERE id = ?
                """,
                [
                    profile.name,
                    profile.language_style,
                    profile.tone,
                    profile.structure_preference,
                    profile.favorite_expressions,
                    profile.forbidden_expressions,
                    sampleTexts,
                    profile.title_style_like,
                    profile.title_style_dislike,
                    profile.genre,
                    profile.genre_focus,
                    knownPitfalls,
                    learnedPreferences,
                    now,
                    id
                ]
            )
            return try getStyleProfile(id)
        }

        try execute(
            """
            INSERT INTO style_profiles
                (name, language_style, tone, structure_preference, favorite_expressions,
                 forbidden_expressions, sample_texts, title_style_like, title_style_dislike,
                 genre, genre_focus, known_pitfalls, learned_preferences, is_default, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            """,
            [
                profile.name,
                profile.language_style,
                profile.tone,
                profile.structure_preference,
                profile.favorite_expressions,
                profile.forbidden_expressions,
                sampleTexts,
                profile.title_style_like,
                profile.title_style_dislike,
                profile.genre,
                profile.genre_focus,
                knownPitfalls,
                learnedPreferences,
                now,
                now
            ]
        )
        return try getStyleProfile(Int(sqlite3_last_insert_rowid(db)))
    }

    /// 按写作方向匹配体裁化风格档案（18.3.4）：优先精确匹配 `genre`，否则回退到默认风格。
    package func styleProfile(forDirection direction: String) throws -> StyleProfile {
        let trimmed = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try defaultStyle()
        }
        if let matched = try rows(
            "\(styleSelectSQL) WHERE genre = ? ORDER BY updated_at DESC LIMIT 1",
            [trimmed],
            mapper: style
        ).first {
            return matched
        }
        return try defaultStyle()
    }

    /// 供体裁化 few-shot 样本抽取：最近同体裁、已完成/已发布/已归档的文章正文（18.3.4）。
    package func recentArticlesForSamples(genre: String, excludingArticleID: Int? = nil, limit: Int = 3) throws -> [Article] {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        let safeLimit = max(1, min(limit, 10))
        if let excludingArticleID {
            return try rows(
                """
                \(articleSelectSQL)
                WHERE genre = ? AND id != ? AND status IN ('已发布', '已归档', '草稿')
                      AND content IS NOT NULL AND trim(content) != ''
                ORDER BY updated_at DESC LIMIT ?
                """,
                [trimmed, excludingArticleID, safeLimit],
                mapper: article
            )
        }
        return try rows(
            """
            \(articleSelectSQL)
            WHERE genre = ? AND status IN ('已发布', '已归档', '草稿')
                  AND content IS NOT NULL AND trim(content) != ''
            ORDER BY updated_at DESC LIMIT ?
            """,
            [trimmed, safeLimit],
            mapper: article
        )
    }

    package func setDefaultStyleProfile(id: Int) throws -> StyleProfile {
        try execute("UPDATE style_profiles SET is_default = 0")
        try execute(
            "UPDATE style_profiles SET is_default = 1, updated_at = ? WHERE id = ?",
            [utcNow(), id]
        )
        return try getStyleProfile(id)
    }

    package func listPromptTemplates() throws -> [PromptTemplate] {
        try rows("\(promptTemplateSelectSQL) ORDER BY id", mapper: promptTemplate)
    }

    package func promptTemplate(key: PromptTemplateKey) throws -> PromptTemplate? {
        try rows(
            "\(promptTemplateSelectSQL) WHERE key = ? LIMIT 1",
            [key.rawValue],
            mapper: promptTemplate
        ).first
    }

    package func savePromptTemplate(
        id: Int,
        name: String,
        systemPrompt: String,
        userTemplate: String
    ) throws -> PromptTemplate {
        try execute(
            """
            UPDATE prompt_templates
            SET name = ?, system_prompt = ?, user_template = ?, is_default = 0, updated_at = ?
            WHERE id = ?
            """,
            [name, systemPrompt, userTemplate, utcNow(), id]
        )
        return try getPromptTemplate(id)
    }

    package func saveArticle(id: Int?, payload: ArticleSaveRequest) throws -> Article {
        let now = utcNow()
        let tagsJSON = encodeStringArray(payload.tags)
        if let id {
            try execute(
                """
                UPDATE articles
                SET title = ?, content = ?, summary = ?, status = ?, tags = ?,
                    related_topic_id = ?, genre = ?, audit_report = NULL, updated_at = ?
                WHERE id = ?
                """,
                [
                    payload.title,
                    payload.content,
                    payload.summary,
                    payload.status,
                    tagsJSON,
                    payload.related_topic_id,
                    payload.genre,
                    now,
                    id
                ]
            )
            return try getArticle(id)
        }

        try execute(
            """
            INSERT INTO articles
                (title, content, summary, status, type, tags, related_topic_id, genre, created_at, updated_at)
            VALUES (?, ?, ?, ?, '', ?, ?, ?, ?, ?)
            """,
            [
                payload.title,
                payload.content,
                payload.summary,
                payload.status,
                tagsJSON,
                payload.related_topic_id,
                payload.genre,
                now,
                now
            ]
        )
        return try getArticle(Int(sqlite3_last_insert_rowid(db)))
    }

    package func updateArticleStatus(id: Int, status: String) throws -> Article {
        try execute(
            "UPDATE articles SET status = ?, updated_at = ? WHERE id = ?",
            [status, utcNow(), id]
        )
        return try getArticle(id)
    }

    package func saveIdea(id: Int?, payload: IdeaSaveRequest) throws -> Idea {
        let now = utcNow()
        let tagsJSON = encodeStringArray(payload.tags)
        if let id {
            try execute(
                """
                UPDATE ideas
                SET title = ?, content = ?, type = ?, tags = ?, used = ?,
                    related_article_id = ?, updated_at = ?
                WHERE id = ?
                """,
                [
                    payload.title,
                    payload.content,
                    payload.type,
                    tagsJSON,
                    payload.used,
                    payload.related_article_id,
                    now,
                    id
                ]
            )
            return try getIdea(id)
        }

        try execute(
            """
            INSERT INTO ideas
                (title, content, type, tags, used, related_article_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                payload.title,
                payload.content,
                payload.type,
                tagsJSON,
                payload.used,
                payload.related_article_id,
                now,
                now
            ]
        )
        return try getIdea(Int(sqlite3_last_insert_rowid(db)))
    }

    package func markIdeaUsed(id: Int, used: Bool) throws -> Idea {
        try execute(
            "UPDATE ideas SET used = ?, updated_at = ? WHERE id = ?",
            [used ? 1 : 0, utcNow(), id]
        )
        return try getIdea(id)
    }

    package func deleteIdea(id: Int) throws {
        try execute("DELETE FROM ideas WHERE id = ?", [id])
    }

    package func deleteTopic(id: Int) throws {
        try execute("DELETE FROM topics WHERE id = ?", [id])
    }

    package func createTopics(_ payloads: [TopicPayload]) throws -> [Topic] {
        try payloads.map { payload in
            let now = utcNow()
            try execute(
                """
                INSERT INTO topics
                    (title, direction, core_viewpoint, target_reader, description, angle,
                     emotion, score, status, tags, related_material_ids, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?)
                """,
                [
                    payload.title,
                    payload.direction,
                    payload.core_viewpoint,
                    payload.target_reader,
                    payload.description,
                    payload.angle,
                    payload.emotion,
                    payload.score ?? 3,
                    payload.status ?? "待写",
                    encodeStringArray(payload.tags ?? []),
                    now,
                    now
                ]
            )
            return try getTopic(Int(sqlite3_last_insert_rowid(db)))
        }
    }

    package func listWritingReviews(articleID: Int? = nil, limit: Int = 8) throws -> [WritingReview] {
        let safeLimit = max(1, min(limit, 50))
        if let articleID {
            return try rows(
                "\(writingReviewSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, safeLimit],
                mapper: writingReview
            )
        }
        return try rows(
            "\(writingReviewSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [safeLimit],
            mapper: writingReview
        )
    }

    package func listPublishAssets(articleID: Int? = nil, limit: Int = 8) throws -> [PublishAssets] {
        let safeLimit = max(1, min(limit, 50))
        if let articleID {
            return try rows(
                "\(publishAssetsSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, safeLimit],
                mapper: publishAssets
            )
        }
        return try rows(
            "\(publishAssetsSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [safeLimit],
            mapper: publishAssets
        )
    }

    package func listWritingAdvisorRuns(articleID: Int? = nil, limit: Int = 8) throws -> [WritingAdvisorRun] {
        let safeLimit = max(1, min(limit, 50))
        if let articleID {
            return try rows(
                "\(writingAdvisorSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, safeLimit],
                mapper: writingAdvisorRun
            )
        }
        return try rows(
            "\(writingAdvisorSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [safeLimit],
            mapper: writingAdvisorRun
        )
    }

    package func listDraftVersions(articleID: Int? = nil, limit: Int = 8) throws -> [DraftVersion] {
        let safeLimit = max(1, min(limit, 50))
        if let articleID {
            return try rows(
                "\(draftVersionSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, safeLimit],
                mapper: draftVersion
            )
        }
        return try rows(
            "\(draftVersionSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [safeLimit],
            mapper: draftVersion
        )
    }

    package func listAICalls(limit: Int = 20) throws -> [AICallRecord] {
        let safeLimit = max(1, min(limit, 100))
        return try rows(
            "\(aiCallSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [safeLimit],
            mapper: aiCallRecord
        )
    }

    package func listAgentRuns(articleID: Int? = nil, limit: Int = 8) throws -> [AgentRun] {
        let safeLimit = max(1, min(limit, 50))
        let runs: [AgentRun]
        if let articleID {
            runs = try rows(
                "\(agentRunSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, safeLimit],
                mapper: agentRun
            )
        } else {
            runs = try rows(
                "\(agentRunSelectSQL) ORDER BY created_at DESC LIMIT ?",
                [safeLimit],
                mapper: agentRun
            )
        }
        return try runs.map { run in
            var enriched = run
            enriched.steps = try listAgentSteps(runID: run.id)
            return enriched
        }
    }

    package func listAgentSteps(runID: Int) throws -> [AgentStep] {
        try rows(
            "\(agentStepSelectSQL) WHERE run_id = ? ORDER BY step_index, id",
            [runID],
            mapper: agentStep
        )
    }

    package func listFragments(limit: Int = 500) throws -> [Fragment] {
        try rows(
            "\(fragmentSelectSQL) ORDER BY updated_at DESC, id DESC LIMIT ?",
            [max(1, min(limit, 5_000))],
            mapper: fragment
        )
    }

    @discardableResult
    package func rebuildFragments() throws -> [Fragment] {
        try execute("DELETE FROM fragments")
        let ideas = try listIdeas()
        for idea in ideas {
            try replaceFragments(sourceType: "idea", sourceID: idea.id, title: idea.displayTitle, text: idea.content)
        }
        let articles = try rows(
            """
            \(articleSelectSQL)
            WHERE status IN ('已发布', '已归档') AND content IS NOT NULL AND trim(content) != ''
            ORDER BY updated_at DESC
            """,
            mapper: article
        )
        for article in articles {
            try replaceFragments(sourceType: "article", sourceID: article.id, title: article.title, text: article.content ?? "")
        }
        return try listFragments()
    }

    package func replaceFragments(sourceType: String, sourceID: Int, title: String?, text: String) throws {
        try execute(
            "DELETE FROM fragments WHERE source_type = ? AND source_id = ?",
            [sourceType, sourceID]
        )
        let now = utcNow()
        for fragmentText in FragmentRetriever.split(text: text) {
            try execute(
                """
                INSERT INTO fragments
                    (source_type, source_id, title, content, keywords, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    sourceType,
                    sourceID,
                    title,
                    fragmentText,
                    encodeStringArray(FragmentRetriever.keywords(for: fragmentText)),
                    now,
                    now
                ]
            )
        }
    }

    package func latestConfirmedDraftVersion(articleID: Int) throws -> DraftVersion? {
        try rows(
            """
            \(draftVersionSelectSQL)
            WHERE article_id = ? AND review_status = 'confirmed'
            ORDER BY created_at DESC LIMIT 1
            """,
            [articleID],
            mapper: draftVersion
        ).first
    }

    @discardableResult
    package func saveEditRecord(article: Article, draftVersion: DraftVersion?) throws -> EditRecord {
        let before = draftVersion?.after_content ?? ""
        let after = article.content ?? ""
        let diff = TextDiff.characterSummary(before: before, after: after)
        let baseCharacters = max(1, before.count)
        let changed = diff.added + diff.removed
        let ratio = Double(changed) / Double(baseCharacters)
        let level: String
        if ratio <= 0.01 {
            level = "zero"
        } else if ratio <= 0.10 {
            level = "light"
        } else {
            level = "heavy"
        }
        try execute(
            """
            INSERT INTO edit_records
                (article_id, draft_version_id, title_snapshot, added_characters,
                 removed_characters, base_characters, edit_ratio, edit_level,
                 diff_summary, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                article.id,
                draftVersion?.id,
                article.title,
                diff.added,
                diff.removed,
                baseCharacters,
                ratio,
                level,
                editDiffSummary(before: before, after: after, diff: diff),
                utcNow()
            ]
        )
        return try getEditRecord(Int(sqlite3_last_insert_rowid(db)))
    }

    package func listEditRecords(limit: Int = 50) throws -> [EditRecord] {
        try rows(
            "\(editRecordSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [max(1, min(limit, 500))],
            mapper: editRecord
        )
    }

    package func editRecordStats(since dateText: String? = nil) throws -> EditRecordStats {
        let records: [EditRecord]
        if let dateText {
            records = try rows(
                "\(editRecordSelectSQL) WHERE substr(created_at, 1, 10) >= ? ORDER BY created_at DESC",
                [dateText],
                mapper: editRecord
            )
        } else {
            records = try listEditRecords(limit: 500)
        }
        guard !records.isEmpty else {
            return EditRecordStats(total: 0, zeroEditRate: 0, lightEditRate: 0, averageEditRatio: 0)
        }
        let zeroCount = records.filter { $0.edit_ratio <= 0.01 }.count
        let lightCount = records.filter { $0.edit_ratio <= 0.10 }.count
        let average = records.map(\.edit_ratio).reduce(0, +) / Double(records.count)
        return EditRecordStats(
            total: records.count,
            zeroEditRate: Double(zeroCount) / Double(records.count),
            lightEditRate: Double(lightCount) / Double(records.count),
            averageEditRatio: average
        )
    }

    private func editDiffSummary(before: String, after: String, diff: TextDiffSummary) -> String {
        let changedLines = TextDiff.lines(before: before, after: after)
            .filter { $0.kind != .equal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let removed = changedLines
            .filter { $0.kind == .removed }
            .prefix(3)
            .map { "- \($0.text.prefix(80))" }
        let added = changedLines
            .filter { $0.kind == .added }
            .prefix(3)
            .map { "+ \($0.text.prefix(80))" }
        return ([
            "added=\(diff.added), removed=\(diff.removed), unchanged=\(diff.unchanged)",
            removed.isEmpty ? nil : "removed_examples=\(removed.joined(separator: " | "))",
            added.isEmpty ? nil : "added_examples=\(added.joined(separator: " | "))"
        ] as [String?])
            .compactMap { $0 }
            .joined(separator: "; ")
    }

    @discardableResult
    package func savePrePublishAudit(
        result: PrePublishAuditReport,
        articleID: Int?,
        titleSnapshot: String?,
        model: String
    ) throws -> PrePublishAudit {
        let issues = result.allIssues
        let now = utcNow()
        let rawReport = encodeJSON(result)
        try execute(
            """
            INSERT INTO pre_publish_audits
                (article_id, title_snapshot, passed, summary, issues, raw_output, model, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                result.passed == true ? 1 : 0,
                result.summary,
                encodeJSON(issues),
                result.raw_output,
                model,
                now
            ]
        )
        if let articleID {
            try execute(
                "UPDATE articles SET audit_report = ?, updated_at = ? WHERE id = ?",
                [rawReport, now, articleID]
            )
        }
        return try getPrePublishAudit(Int(sqlite3_last_insert_rowid(db)))
    }

    package func listPrePublishAudits(articleID: Int? = nil, limit: Int = 8) throws -> [PrePublishAudit] {
        if let articleID {
            return try rows(
                "\(prePublishAuditSelectSQL) WHERE article_id = ? ORDER BY created_at DESC LIMIT ?",
                [articleID, max(1, min(limit, 50))],
                mapper: prePublishAudit
            )
        }
        return try rows(
            "\(prePublishAuditSelectSQL) ORDER BY created_at DESC LIMIT ?",
            [max(1, min(limit, 50))],
            mapper: prePublishAudit
        )
    }

    package func saveWritingReview(
        result: WritingReviewResult,
        articleID: Int?,
        titleSnapshot: String,
        model: String,
        reviewedSnapshot: String
    ) throws -> WritingReview {
        let now = utcNow()
        let normalizedSummary = result.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = normalizedSummary?.isEmpty == false
            ? normalizedSummary!
            : "已完成一次写作诊断。"
        try execute(
            """
            INSERT INTO writing_reviews
                (article_id, title_snapshot, summary, overall_score, strengths, issues,
                 revision_plan, training_focus, style_notes, raw_output, model, created_at,
                 resolved_from_last, reviewed_snapshot, pitfall_hits)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                summary,
                result.overall_score,
                encodeStringArray(result.strengths ?? []),
                encodeWritingIssues(result.issues ?? []),
                encodeStringArray(result.revision_plan ?? []),
                encodeStringArray(result.training_focus ?? []),
                encodeStringArray(result.style_notes ?? []),
                result.raw_output,
                model,
                now,
                encodeStringArray(result.resolved_from_last ?? []),
                reviewedSnapshot,
                encodeStringArray(result.pitfall_hits ?? [])
            ]
        )
        return try getWritingReview(Int(sqlite3_last_insert_rowid(db)))
    }

    package func savePublishAssets(
        result: PublishAssetsResult,
        articleID: Int?,
        titleSnapshot: String,
        model: String
    ) throws -> PublishAssets {
        try execute(
            """
            INSERT INTO publish_assets
                (article_id, title_snapshot, summary, cover_text, moments_text, tags,
                 xiaohongshu_text, cover_image_prompt, raw_output, model, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                result.summary,
                result.cover_text,
                result.moments_text,
                encodeStringArray(result.tags ?? []),
                result.xiaohongshu_text,
                result.cover_image_prompt,
                result.raw_output,
                model,
                utcNow()
            ]
        )
        return try getPublishAssets(Int(sqlite3_last_insert_rowid(db)))
    }

    package func saveWritingAdvisorRun(
        result: WritingAdvisorResult,
        context: ContextPackage,
        articleID: Int?,
        titleSnapshot: String,
        model: String
    ) throws -> WritingAdvisorRun {
        let stage = normalized(result.stage, fallback: context.stage)
        let mainProblem = normalized(result.main_problem, fallback: "已完成一次写作判断。")
        let nextAction = normalized(result.next_action, fallback: "先运行写作诊断。")
        let reason = normalized(result.reason, fallback: "根据当前上下文给出的本地建议。")
        try execute(
            """
            INSERT INTO writing_advisor_runs
                (article_id, title_snapshot, stage, main_problem, next_action, reason,
                 suggested_actions, focus_area, context_findings, execution_plan, risk_notes,
                 context_summary, raw_output, model, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                stage,
                mainProblem,
                nextAction,
                reason,
                encodeStringArray(result.suggested_actions ?? []),
                result.focus_area,
                encodeStringArray(result.context_findings ?? []),
                encodeStringArray(result.execution_plan ?? []),
                encodeStringArray(result.risk_notes ?? []),
                context.summaryText,
                result.raw_output,
                model,
                utcNow()
            ]
        )
        return try getWritingAdvisorRun(Int(sqlite3_last_insert_rowid(db)))
    }

    package func saveDraftVersion(
        articleID: Int?,
        titleSnapshot: String,
        action: String,
        note: String?,
        before: DraftSnapshot,
        after: DraftSnapshot,
        reviewStatus: String = "confirmed"
    ) throws -> DraftVersion {
        try execute(
            """
            INSERT INTO draft_versions
                (article_id, title_snapshot, action, note, before_title, before_summary,
                 before_content, after_title, after_summary, after_content, created_at, review_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                action,
                note,
                before.title,
                before.summary,
                before.content,
                after.title,
                after.summary,
                after.content,
                utcNow(),
                reviewStatus
            ]
        )
        return try getDraftVersion(Int(sqlite3_last_insert_rowid(db)))
    }

    /// 复核确认/放弃（18.4.1）：把某个"待复核"版本标记为 `confirmed`。
    package func confirmDraftVersion(id: Int) throws -> DraftVersion {
        try execute(
            "UPDATE draft_versions SET review_status = 'confirmed' WHERE id = ?",
            [id]
        )
        return try getDraftVersion(id)
    }

    /// 放弃一个从未落地为正文的"待复核"版本，直接从历史中移除，避免留下永远悬空的记录。
    package func deleteDraftVersion(id: Int) throws {
        try execute("DELETE FROM draft_versions WHERE id = ?", [id])
    }

    package func attachDraftVersionsToArticle(articleID: Int, titleSnapshot: String) throws {
        try execute(
            """
            UPDATE draft_versions
            SET article_id = ?
            WHERE article_id IS NULL AND title_snapshot = ?
            """,
            [articleID, titleSnapshot]
        )
    }

    package func recordAICall(
        endpoint: String,
        model: String,
        elapsedMS: Int,
        success: Bool,
        error: String,
        inputSummary: String = "",
        outputSummary: String = ""
    ) {
        try? execute(
            """
            INSERT INTO ai_calls
                (endpoint, style_profile_id, material_ids, model, elapsed_ms, success, error,
                 input_summary, output_summary, created_at)
            VALUES (?, NULL, '[]', ?, ?, ?, ?, ?, ?, ?)
            """,
            [endpoint, model, elapsedMS, success ? 1 : 0, error, inputSummary, outputSummary, utcNow()]
        )
    }

    package func saveAgentRun(
        runType: String,
        articleID: Int?,
        titleSnapshot: String,
        status: String,
        summary: String?,
        model: String,
        elapsedMS: Int,
        inputSummary: String,
        outputSummary: String,
        error: String,
        steps: [AgentStepPayload],
        sessionKind: String? = nil,
        budgetSummary: String? = nil
    ) throws -> AgentRun {
        let now = utcNow()
        try execute(
            """
            INSERT INTO agent_runs
                (article_id, title_snapshot, run_type, status, summary, model, elapsed_ms,
                 input_summary, output_summary, error, session_kind, budget_summary, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                articleID,
                titleSnapshot,
                runType,
                status,
                summary,
                model,
                elapsedMS,
                inputSummary,
                outputSummary,
                error,
                sessionKind,
                budgetSummary,
                now
            ]
        )
        let runID = Int(sqlite3_last_insert_rowid(db))
        for step in steps.sorted(by: { $0.step_index < $1.step_index }) {
            try execute(
                """
                INSERT INTO agent_steps
                    (run_id, step_index, name, status, input_summary, output_summary,
                     elapsed_ms, error, step_type, decision_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    runID,
                    step.step_index,
                    step.name,
                    step.status,
                    step.input_summary,
                    step.output_summary,
                    step.elapsed_ms,
                    step.error,
                    step.step_type,
                    step.decision_json,
                    now
                ]
            )
        }
        var run = try getAgentRun(runID)
        run.steps = try listAgentSteps(runID: runID)
        return run
    }

    private func initialize() throws {
        try executeScript(
            """
            CREATE TABLE IF NOT EXISTS style_profiles (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                language_style TEXT,
                tone TEXT,
                structure_preference TEXT,
                favorite_expressions TEXT,
                forbidden_expressions TEXT,
                sample_texts TEXT,
                title_style_like TEXT,
                title_style_dislike TEXT,
                is_default INTEGER DEFAULT 0,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS articles (
                id INTEGER PRIMARY KEY,
                title TEXT,
                content TEXT,
                summary TEXT,
                status TEXT DEFAULT '草稿',
                type TEXT,
                tags TEXT,
                self_score INTEGER,
                published_at TEXT,
                read_count INTEGER DEFAULT 0,
                like_count INTEGER DEFAULT 0,
                wow_count INTEGER DEFAULT 0,
                share_count INTEGER DEFAULT 0,
                comment_count INTEGER DEFAULT 0,
                related_material_ids TEXT,
                related_topic_id INTEGER,
                audit_report TEXT,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS ideas (
                id INTEGER PRIMARY KEY,
                title TEXT,
                content TEXT NOT NULL,
                type TEXT DEFAULT '灵感',
                tags TEXT,
                used INTEGER DEFAULT 0,
                related_article_id INTEGER,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS topics (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                direction TEXT,
                core_viewpoint TEXT,
                target_reader TEXT,
                description TEXT,
                angle TEXT,
                emotion TEXT,
                score INTEGER DEFAULT 3,
                status TEXT DEFAULT '待写',
                tags TEXT,
                related_material_ids TEXT,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS settings (
                id INTEGER PRIMARY KEY,
                key TEXT UNIQUE,
                value TEXT,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS prompt_templates (
                id INTEGER PRIMARY KEY,
                key TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                system_prompt TEXT NOT NULL,
                user_template TEXT NOT NULL,
                is_default INTEGER DEFAULT 1,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS ai_calls (
                id INTEGER PRIMARY KEY,
                endpoint TEXT,
                style_profile_id INTEGER,
                material_ids TEXT,
                model TEXT,
                elapsed_ms INTEGER,
                success INTEGER,
                error TEXT,
                input_summary TEXT,
                output_summary TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS writing_reviews (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                summary TEXT,
                overall_score INTEGER,
                strengths TEXT,
                issues TEXT,
                revision_plan TEXT,
                training_focus TEXT,
                style_notes TEXT,
                raw_output TEXT,
                model TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS publish_assets (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                summary TEXT,
                cover_text TEXT,
                moments_text TEXT,
                tags TEXT,
                xiaohongshu_text TEXT,
                cover_image_prompt TEXT,
                raw_output TEXT,
                model TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS writing_advisor_runs (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                stage TEXT,
                main_problem TEXT,
                next_action TEXT,
                reason TEXT,
                suggested_actions TEXT,
                focus_area TEXT,
                context_findings TEXT,
                execution_plan TEXT,
                risk_notes TEXT,
                context_summary TEXT,
                raw_output TEXT,
                model TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS draft_versions (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                action TEXT,
                note TEXT,
                before_title TEXT,
                before_summary TEXT,
                before_content TEXT,
                after_title TEXT,
                after_summary TEXT,
                after_content TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS agent_runs (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                run_type TEXT,
                status TEXT,
                summary TEXT,
                model TEXT,
                elapsed_ms INTEGER,
                input_summary TEXT,
                output_summary TEXT,
                error TEXT,
                session_kind TEXT,
                budget_summary TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS agent_steps (
                id INTEGER PRIMARY KEY,
                run_id INTEGER,
                step_index INTEGER,
                name TEXT,
                status TEXT,
                input_summary TEXT,
                output_summary TEXT,
                elapsed_ms INTEGER,
                error TEXT,
                step_type TEXT DEFAULT 'action',
                decision_json TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS fragments (
                id INTEGER PRIMARY KEY,
                source_type TEXT NOT NULL,
                source_id INTEGER NOT NULL,
                title TEXT,
                content TEXT NOT NULL,
                keywords TEXT,
                created_at TEXT,
                updated_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_fragments_source ON fragments(source_type, source_id);

            CREATE TABLE IF NOT EXISTS edit_records (
                id INTEGER PRIMARY KEY,
                article_id INTEGER NOT NULL,
                draft_version_id INTEGER,
                title_snapshot TEXT,
                added_characters INTEGER,
                removed_characters INTEGER,
                base_characters INTEGER,
                edit_ratio REAL,
                edit_level TEXT,
                diff_summary TEXT,
                created_at TEXT
            );

            CREATE TABLE IF NOT EXISTS pre_publish_audits (
                id INTEGER PRIMARY KEY,
                article_id INTEGER,
                title_snapshot TEXT,
                passed INTEGER,
                summary TEXT,
                issues TEXT,
                raw_output TEXT,
                model TEXT,
                created_at TEXT
            );
            """
        )
        try ensureColumns()
        try ensureSchemaVersion()
        try seedDefaultsIfNeeded()
        try seedPromptTemplatesIfNeeded()
    }

    private func ensureColumns() throws {
        try ensureColumn(table: "style_profiles", name: "favorite_expressions", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "sample_texts", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "title_style_like", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "title_style_dislike", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "is_default", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "style_profiles", name: "genre", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "genre_focus", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "known_pitfalls", definition: "TEXT")
        try ensureColumn(table: "style_profiles", name: "learned_preferences", definition: "TEXT")
        try ensureColumn(table: "articles", name: "read_count", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "articles", name: "like_count", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "articles", name: "wow_count", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "articles", name: "share_count", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "articles", name: "comment_count", definition: "INTEGER DEFAULT 0")
        try ensureColumn(table: "articles", name: "related_material_ids", definition: "TEXT")
        try ensureColumn(table: "articles", name: "related_topic_id", definition: "INTEGER")
        try ensureColumn(table: "articles", name: "genre", definition: "TEXT")
        try ensureColumn(table: "articles", name: "audit_report", definition: "TEXT")
        try ensureColumn(table: "topics", name: "related_material_ids", definition: "TEXT")
        try ensureColumn(table: "ai_calls", name: "input_summary", definition: "TEXT")
        try ensureColumn(table: "ai_calls", name: "output_summary", definition: "TEXT")
        try ensureColumn(table: "prompt_templates", name: "is_default", definition: "INTEGER DEFAULT 1")
        try ensureColumn(table: "writing_reviews", name: "resolved_from_last", definition: "TEXT")
        try ensureColumn(table: "writing_reviews", name: "reviewed_snapshot", definition: "TEXT")
        try ensureColumn(table: "writing_reviews", name: "pitfall_hits", definition: "TEXT")
        try ensureColumn(table: "writing_advisor_runs", name: "context_findings", definition: "TEXT")
        try ensureColumn(table: "writing_advisor_runs", name: "execution_plan", definition: "TEXT")
        try ensureColumn(table: "writing_advisor_runs", name: "risk_notes", definition: "TEXT")
        try ensureColumn(table: "draft_versions", name: "review_status", definition: "TEXT DEFAULT 'confirmed'")
        try ensureColumn(table: "agent_runs", name: "session_kind", definition: "TEXT")
        try ensureColumn(table: "agent_runs", name: "budget_summary", definition: "TEXT")
        try ensureColumn(table: "agent_steps", name: "step_type", definition: "TEXT DEFAULT 'action'")
        try ensureColumn(table: "agent_steps", name: "decision_json", definition: "TEXT")
    }

    private func ensureSchemaVersion() throws {
        let currentVersion = try schemaVersion()
        guard currentVersion < nativeDatabaseSchemaVersion else {
            try saveSetting(key: "database_schema_version", value: "\(currentVersion)")
            return
        }
        try execute("PRAGMA user_version = \(nativeDatabaseSchemaVersion)")
        try saveSetting(key: "database_schema_version", value: "\(nativeDatabaseSchemaVersion)")
    }

    private func ensureColumn(table: String, name: String, definition: String) throws {
        let existing = Set(try rows("PRAGMA table_info(\(table))") { statement in
            text(statement, 1) ?? ""
        })
        guard !existing.contains(name) else {
            return
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func seedDefaultsIfNeeded() throws {
        guard try scalarInt("SELECT COUNT(*) FROM style_profiles") == 0 else {
            return
        }
        let now = utcNow()
        try execute(
            """
            INSERT INTO style_profiles
                (name, language_style, tone, structure_preference, favorite_expressions,
                 forbidden_expressions, sample_texts, title_style_like, title_style_dislike,
                 known_pitfalls, learned_preferences, is_default, created_at, updated_at)
            VALUES (?, ?, ?, ?, '', ?, '[]', ?, ?, '[]', '[]', 1, ?, ?)
            """,
            [
                defaultStyleProfile.name,
                defaultStyleProfile.language_style,
                defaultStyleProfile.tone,
                defaultStyleProfile.structure_preference,
                defaultStyleProfile.forbidden_expressions,
                defaultStyleProfile.title_style_like,
                defaultStyleProfile.title_style_dislike,
                now,
                now
            ]
        )
    }

    /// 逐个补种缺失的模板 key，而不是"表为空才整体写入一次"。
    /// 这样在改造后新增 `draftSelfCheck`/`pitfallSummary`/`readerPerspective` 等工作流时，
    /// 已经在用的旧数据库也能补上新模板，且不会覆盖作者已经自定义过的旧模板。
    private func seedPromptTemplatesIfNeeded() throws {
        let existingKeys = Set(try rows("SELECT key FROM prompt_templates", mapper: { text($0, 0) ?? "" }))
        let now = utcNow()
        for template in NativePrompts.defaultPromptTemplates() {
            if existingKeys.contains(template.key.rawValue) {
                // 内置默认模板随版本更新：只刷新用户从未保存过的行（保存会置 is_default = 0 并推进 updated_at）
                try execute(
                    """
                    UPDATE prompt_templates
                    SET name = ?, system_prompt = ?, user_template = ?
                    WHERE key = ? AND is_default = 1 AND updated_at = created_at
                    """,
                    [
                        template.name,
                        template.system_prompt,
                        template.user_template,
                        template.key.rawValue
                    ]
                )
            } else {
                try execute(
                    """
                    INSERT INTO prompt_templates
                        (key, name, system_prompt, user_template, is_default, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 1, ?, ?)
                    """,
                    [
                        template.key.rawValue,
                        template.name,
                        template.system_prompt,
                        template.user_template,
                        now,
                        now
                    ]
                )
            }
        }
    }

    private func getArticle(_ id: Int) throws -> Article {
        guard let article = try rows("\(articleSelectSQL) WHERE id = ?", [id], mapper: article).first else {
            throw NativeDatabaseError.notFound("article \(id)")
        }
        return article
    }

    private func getStyleProfile(_ id: Int) throws -> StyleProfile {
        guard let style = try rows("\(styleSelectSQL) WHERE id = ?", [id], mapper: style).first else {
            throw NativeDatabaseError.notFound("style profile \(id)")
        }
        return style
    }

    private func getTopic(_ id: Int) throws -> Topic {
        guard let found = try rows("\(topicSelectSQL) WHERE id = ?", [id], mapper: topic).first else {
            throw NativeDatabaseError.notFound("topic \(id)")
        }
        return found
    }

    private func getIdea(_ id: Int) throws -> Idea {
        guard let found = try rows("\(ideaSelectSQL) WHERE id = ?", [id], mapper: idea).first else {
            throw NativeDatabaseError.notFound("idea \(id)")
        }
        return found
    }

    private func getWritingReview(_ id: Int) throws -> WritingReview {
        guard let review = try rows("\(writingReviewSelectSQL) WHERE id = ?", [id], mapper: writingReview).first else {
            throw NativeDatabaseError.notFound("writing review \(id)")
        }
        return review
    }

    private func getPublishAssets(_ id: Int) throws -> PublishAssets {
        guard let assets = try rows("\(publishAssetsSelectSQL) WHERE id = ?", [id], mapper: publishAssets).first else {
            throw NativeDatabaseError.notFound("publish assets \(id)")
        }
        return assets
    }

    private func getWritingAdvisorRun(_ id: Int) throws -> WritingAdvisorRun {
        guard let run = try rows("\(writingAdvisorSelectSQL) WHERE id = ?", [id], mapper: writingAdvisorRun).first else {
            throw NativeDatabaseError.notFound("writing advisor run \(id)")
        }
        return run
    }

    private func getDraftVersion(_ id: Int) throws -> DraftVersion {
        guard let version = try rows("\(draftVersionSelectSQL) WHERE id = ?", [id], mapper: draftVersion).first else {
            throw NativeDatabaseError.notFound("draft version \(id)")
        }
        return version
    }

    private func getAgentRun(_ id: Int) throws -> AgentRun {
        guard var run = try rows("\(agentRunSelectSQL) WHERE id = ?", [id], mapper: agentRun).first else {
            throw NativeDatabaseError.notFound("agent run \(id)")
        }
        run.steps = try listAgentSteps(runID: id)
        return run
    }

    private func getEditRecord(_ id: Int) throws -> EditRecord {
        guard let record = try rows("\(editRecordSelectSQL) WHERE id = ?", [id], mapper: editRecord).first else {
            throw NativeDatabaseError.notFound("edit record \(id)")
        }
        return record
    }

    private func getPrePublishAudit(_ id: Int) throws -> PrePublishAudit {
        guard let audit = try rows("\(prePublishAuditSelectSQL) WHERE id = ?", [id], mapper: prePublishAudit).first else {
            throw NativeDatabaseError.notFound("pre-publish audit \(id)")
        }
        return audit
    }

    private func getPromptTemplate(_ id: Int) throws -> PromptTemplate {
        guard let template = try rows("\(promptTemplateSelectSQL) WHERE id = ?", [id], mapper: promptTemplate).first else {
            throw NativeDatabaseError.notFound("prompt template \(id)")
        }
        return template
    }

    private func topic(_ statement: OpaquePointer?) -> Topic {
        Topic(
            id: int(statement, 0),
            title: text(statement, 1) ?? "未命名选题",
            direction: text(statement, 2),
            core_viewpoint: text(statement, 3),
            target_reader: text(statement, 4),
            description: text(statement, 5),
            angle: text(statement, 6),
            emotion: text(statement, 7),
            score: optionalInt(statement, 8),
            status: text(statement, 9),
            tags: decodeStringArray(text(statement, 10)),
            updated_at: text(statement, 13),
            created_at: text(statement, 12)
        )
    }

    private func article(_ statement: OpaquePointer?) -> Article {
        Article(
            id: int(statement, 0),
            title: text(statement, 1),
            content: text(statement, 2),
            summary: text(statement, 3),
            status: text(statement, 4),
            type: text(statement, 5),
            tags: decodeStringArray(text(statement, 6)),
            updated_at: text(statement, 9),
            created_at: text(statement, 8),
            related_topic_id: optionalInt(statement, 7),
            genre: text(statement, 10),
            audit_report: decodeJSON(text(statement, 11), fallback: nil as PrePublishAuditReport?)
        )
    }

    private func idea(_ statement: OpaquePointer?) -> Idea {
        Idea(
            id: int(statement, 0),
            title: text(statement, 1),
            content: text(statement, 2) ?? "",
            type: text(statement, 3),
            tags: decodeStringArray(text(statement, 4)),
            used: optionalInt(statement, 5),
            related_article_id: optionalInt(statement, 6),
            updated_at: text(statement, 8),
            created_at: text(statement, 7)
        )
    }

    private func style(_ statement: OpaquePointer?) -> StyleProfile {
        StyleProfile(
            id: int(statement, 0),
            name: text(statement, 1) ?? "默认公众号风格",
            language_style: text(statement, 2),
            tone: text(statement, 3),
            structure_preference: text(statement, 4),
            favorite_expressions: text(statement, 5),
            forbidden_expressions: text(statement, 6),
            sample_texts: decodeStringArray(text(statement, 7)),
            title_style_like: text(statement, 8),
            title_style_dislike: text(statement, 9),
            is_default: optionalInt(statement, 10),
            genre: text(statement, 11),
            genre_focus: text(statement, 12),
            known_pitfalls: decodePitfalls(text(statement, 13)),
            learned_preferences: decodeJSON(text(statement, 14), fallback: [LearnedPreference]())
        )
    }

    private func writingReview(_ statement: OpaquePointer?) -> WritingReview {
        WritingReview(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            summary: text(statement, 3) ?? "",
            overall_score: optionalInt(statement, 4),
            strengths: decodeStringArray(text(statement, 5)),
            issues: decodeWritingIssues(text(statement, 6)),
            revision_plan: decodeStringArray(text(statement, 7)),
            training_focus: decodeStringArray(text(statement, 8)),
            style_notes: decodeStringArray(text(statement, 9)),
            raw_output: text(statement, 10),
            model: text(statement, 11),
            created_at: text(statement, 12),
            resolved_from_last: decodeStringArray(text(statement, 13)),
            reviewed_snapshot: text(statement, 14),
            pitfall_hits: decodeStringArray(text(statement, 15))
        )
    }

    private func publishAssets(_ statement: OpaquePointer?) -> PublishAssets {
        PublishAssets(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            summary: text(statement, 3),
            cover_text: text(statement, 4),
            moments_text: text(statement, 5),
            tags: decodeStringArray(text(statement, 6)),
            xiaohongshu_text: text(statement, 7),
            cover_image_prompt: text(statement, 8),
            raw_output: text(statement, 9),
            model: text(statement, 10),
            created_at: text(statement, 11)
        )
    }

    private func writingAdvisorRun(_ statement: OpaquePointer?) -> WritingAdvisorRun {
        WritingAdvisorRun(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            stage: text(statement, 3) ?? "",
            main_problem: text(statement, 4) ?? "",
            next_action: text(statement, 5) ?? "",
            reason: text(statement, 6) ?? "",
            suggested_actions: decodeStringArray(text(statement, 7)),
            focus_area: text(statement, 8),
            context_findings: decodeStringArray(text(statement, 9)),
            execution_plan: decodeStringArray(text(statement, 10)),
            risk_notes: decodeStringArray(text(statement, 11)),
            context_summary: text(statement, 12),
            raw_output: text(statement, 13),
            model: text(statement, 14),
            created_at: text(statement, 15)
        )
    }

    private func draftVersion(_ statement: OpaquePointer?) -> DraftVersion {
        DraftVersion(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            action: text(statement, 3) ?? "",
            note: text(statement, 4),
            before_title: text(statement, 5) ?? "",
            before_summary: text(statement, 6) ?? "",
            before_content: text(statement, 7) ?? "",
            after_title: text(statement, 8) ?? "",
            after_summary: text(statement, 9) ?? "",
            after_content: text(statement, 10) ?? "",
            created_at: text(statement, 11),
            review_status: text(statement, 12) ?? "confirmed"
        )
    }

    private func aiCallRecord(_ statement: OpaquePointer?) -> AICallRecord {
        AICallRecord(
            id: int(statement, 0),
            endpoint: text(statement, 1),
            model: text(statement, 2),
            elapsed_ms: optionalInt(statement, 3),
            success: optionalInt(statement, 4),
            error: text(statement, 5),
            input_summary: text(statement, 6),
            output_summary: text(statement, 7),
            created_at: text(statement, 8)
        )
    }

    private func agentRun(_ statement: OpaquePointer?) -> AgentRun {
        AgentRun(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            run_type: text(statement, 3) ?? "",
            status: text(statement, 4) ?? "",
            summary: text(statement, 5),
            model: text(statement, 6),
            elapsed_ms: optionalInt(statement, 7),
            input_summary: text(statement, 8),
            output_summary: text(statement, 9),
            error: text(statement, 10),
            session_kind: text(statement, 11),
            budget_summary: text(statement, 12),
            created_at: text(statement, 13),
            steps: []
        )
    }

    private func agentStep(_ statement: OpaquePointer?) -> AgentStep {
        AgentStep(
            id: int(statement, 0),
            run_id: int(statement, 1),
            step_index: int(statement, 2),
            name: text(statement, 3) ?? "",
            status: text(statement, 4) ?? "",
            input_summary: text(statement, 5),
            output_summary: text(statement, 6),
            elapsed_ms: optionalInt(statement, 7),
            error: text(statement, 8),
            step_type: text(statement, 9) ?? "action",
            decision_json: text(statement, 10),
            created_at: text(statement, 11)
        )
    }

    private func fragment(_ statement: OpaquePointer?) -> Fragment {
        Fragment(
            id: int(statement, 0),
            source_type: text(statement, 1) ?? "",
            source_id: int(statement, 2),
            title: text(statement, 3),
            content: text(statement, 4) ?? "",
            keywords: decodeStringArray(text(statement, 5)),
            created_at: text(statement, 6),
            updated_at: text(statement, 7)
        )
    }

    private func editRecord(_ statement: OpaquePointer?) -> EditRecord {
        EditRecord(
            id: int(statement, 0),
            article_id: int(statement, 1),
            draft_version_id: optionalInt(statement, 2),
            title_snapshot: text(statement, 3),
            added_characters: int(statement, 4),
            removed_characters: int(statement, 5),
            base_characters: int(statement, 6),
            edit_ratio: optionalDouble(statement, 7) ?? 0,
            edit_level: text(statement, 8) ?? "",
            diff_summary: text(statement, 9),
            created_at: text(statement, 10)
        )
    }

    private func prePublishAudit(_ statement: OpaquePointer?) -> PrePublishAudit {
        PrePublishAudit(
            id: int(statement, 0),
            article_id: optionalInt(statement, 1),
            title_snapshot: text(statement, 2),
            passed: int(statement, 3),
            summary: text(statement, 4),
            issues: decodeJSON(text(statement, 5), fallback: [AuditIssue]()),
            raw_output: text(statement, 6),
            model: text(statement, 7),
            created_at: text(statement, 8)
        )
    }

    private func promptTemplate(_ statement: OpaquePointer?) -> PromptTemplate {
        PromptTemplate(
            id: int(statement, 0),
            key: text(statement, 1) ?? "",
            name: text(statement, 2) ?? "",
            system_prompt: text(statement, 3) ?? "",
            user_template: text(statement, 4) ?? "",
            is_default: optionalInt(statement, 5),
            updated_at: text(statement, 7),
            created_at: text(statement, 6)
        )
    }

    private func writingStreak() throws -> Int {
        let dates = Set(try rows(
            "SELECT DISTINCT substr(created_at, 1, 10) FROM articles WHERE created_at IS NOT NULL",
            mapper: { statement in
                text(statement, 0) ?? ""
            }
        ).filter { !$0.isEmpty })
        var cursor = Date()
        var streak = 0
        let calendar = Calendar.current
        while dates.contains(dateOnly(cursor)) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    private func setting(_ key: String) throws -> String? {
        try scalarText("SELECT value FROM settings WHERE key = ? LIMIT 1", [key])
    }

    private func normalized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func saveSetting(key: String, value: String) throws {
        let now = utcNow()
        try execute(
            """
            INSERT INTO settings (key, value, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            [key, value, now, now]
        )
    }

    private func scalarInt(_ sql: String, _ values: [Any?] = []) throws -> Int {
        try rows(sql, values) { statement in
            int(statement, 0)
        }.first ?? 0
    }

    private func scalarText(_ sql: String, _ values: [Any?] = []) throws -> String? {
        try rows(sql, values) { statement in
            text(statement, 0)
        }.first ?? nil
    }

    private func execute(_ sql: String, _ values: [Any?] = []) throws {
        try withStatement(sql, values) { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw NativeDatabaseError.statement(message: lastErrorMessage)
            }
        }
    }

    private func executeScript(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if let error {
            let message = String(cString: error)
            sqlite3_free(error)
            throw NativeDatabaseError.statement(message: message)
        }
        guard result == SQLITE_OK else {
            throw NativeDatabaseError.statement(message: lastErrorMessage)
        }
    }

    private func rows<T>(_ sql: String, _ values: [Any?] = [], mapper: (OpaquePointer?) -> T) throws -> [T] {
        try withStatement(sql, values) { statement in
            var output: [T] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    output.append(mapper(statement))
                } else if result == SQLITE_DONE {
                    return output
                } else {
                    throw NativeDatabaseError.statement(message: lastErrorMessage)
                }
            }
        }
    }

    private func withStatement<T>(_ sql: String, _ values: [Any?], body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NativeDatabaseError.statement(message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            try bind(value, to: statement, index: Int32(offset + 1))
        }
        return try body(statement)
    }

    private func bind(_ value: Any?, to statement: OpaquePointer?, index: Int32) throws {
        let result: Int32
        switch value {
        case nil:
            result = sqlite3_bind_null(statement, index)
        case let value as Int:
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as Int64:
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as Double:
            result = sqlite3_bind_double(statement, index, value)
        case let value as Bool:
            result = sqlite3_bind_int64(statement, index, value ? 1 : 0)
        case let value as String:
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        default:
            result = sqlite3_bind_text(statement, index, "\(value!)", -1, sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw NativeDatabaseError.statement(message: lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "unknown SQLite error"
    }
}

private let nativeDatabaseSchemaVersion = 10
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private let topicSelectSQL = """
SELECT id, title, direction, core_viewpoint, target_reader, description, angle,
       emotion, score, status, tags, related_material_ids, created_at, updated_at
FROM topics
"""

private let articleSelectSQL = """
SELECT id, title, content, summary, status, type, tags, related_topic_id, created_at, updated_at, genre, audit_report
FROM articles
"""

private let ideaSelectSQL = """
SELECT id, title, content, type, tags, used, related_article_id, created_at, updated_at
FROM ideas
"""

private let styleSelectSQL = """
SELECT id, name, language_style, tone, structure_preference, favorite_expressions,
       forbidden_expressions, sample_texts, title_style_like, title_style_dislike, is_default,
       genre, genre_focus, known_pitfalls, learned_preferences
FROM style_profiles
"""

private let writingReviewSelectSQL = """
SELECT id, article_id, title_snapshot, summary, overall_score, strengths, issues,
       revision_plan, training_focus, style_notes, raw_output, model, created_at,
       resolved_from_last, reviewed_snapshot, pitfall_hits
FROM writing_reviews
"""

private let publishAssetsSelectSQL = """
SELECT id, article_id, title_snapshot, summary, cover_text, moments_text, tags,
       xiaohongshu_text, cover_image_prompt, raw_output, model, created_at
FROM publish_assets
"""

private let writingAdvisorSelectSQL = """
SELECT id, article_id, title_snapshot, stage, main_problem, next_action, reason,
       suggested_actions, focus_area, context_findings, execution_plan, risk_notes,
       context_summary, raw_output, model, created_at
FROM writing_advisor_runs
"""

private let draftVersionSelectSQL = """
SELECT id, article_id, title_snapshot, action, note, before_title, before_summary,
       before_content, after_title, after_summary, after_content, created_at, review_status
FROM draft_versions
"""

private let aiCallSelectSQL = """
SELECT id, endpoint, model, elapsed_ms, success, error, input_summary, output_summary, created_at
FROM ai_calls
"""

private let agentRunSelectSQL = """
SELECT id, article_id, title_snapshot, run_type, status, summary, model, elapsed_ms,
       input_summary, output_summary, error, session_kind, budget_summary, created_at
FROM agent_runs
"""

private let agentStepSelectSQL = """
SELECT id, run_id, step_index, name, status, input_summary, output_summary,
       elapsed_ms, error, step_type, decision_json, created_at
FROM agent_steps
"""

private let fragmentSelectSQL = """
SELECT id, source_type, source_id, title, content, keywords, created_at, updated_at
FROM fragments
"""

private let editRecordSelectSQL = """
SELECT id, article_id, draft_version_id, title_snapshot, added_characters,
       removed_characters, base_characters, edit_ratio, edit_level, diff_summary, created_at
FROM edit_records
"""

private let prePublishAuditSelectSQL = """
SELECT id, article_id, title_snapshot, passed, summary, issues, raw_output, model, created_at
FROM pre_publish_audits
"""

private let promptTemplateSelectSQL = """
SELECT id, key, name, system_prompt, user_template, is_default, created_at, updated_at
FROM prompt_templates
"""

private let defaultStyleProfile = StyleProfile(
    id: 1,
    name: "默认公众号风格",
    language_style: "中文，通俗易懂，有个人表达感",
    tone: "真诚、克制、略带感慨，但不鸡汤",
    structure_preference: "从现实痛点切入，再讲观察，再给方法或感悟",
    favorite_expressions: "",
    forbidden_expressions: "不要标题党，不要培训腔，不要营销腔，不要堆砌概念",
    sample_texts: [],
    title_style_like: "自然、克制、有思考感",
    title_style_dislike: "夸张、焦虑、低俗、过度反差",
    is_default: 1,
    genre: nil,
    genre_focus: nil,
    known_pitfalls: [],
    learned_preferences: []
)

private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: value)
}

private func int(_ statement: OpaquePointer?, _ index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return int(statement, index)
}

private func double(_ statement: OpaquePointer?, _ index: Int32) -> Double {
    sqlite3_column_double(statement, index)
}

private func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return double(statement, index)
}

private func decodeStringArray(_ text: String?) -> [String] {
    guard let text, let data = text.data(using: .utf8) else {
        return []
    }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}

private func encodeStringArray(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let text = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return text
}

private func decodeWritingIssues(_ text: String?) -> [WritingReviewIssue] {
    guard let text, let data = text.data(using: .utf8) else {
        return []
    }
    return (try? JSONDecoder().decode([WritingReviewIssue].self, from: data)) ?? []
}

private func encodeWritingIssues(_ values: [WritingReviewIssue]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let text = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return text
}

private func decodePitfalls(_ text: String?) -> [AuthorPitfall] {
    guard let text, let data = text.data(using: .utf8) else {
        return []
    }
    return (try? JSONDecoder().decode([AuthorPitfall].self, from: data)) ?? []
}

private func encodePitfalls(_ values: [AuthorPitfall]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let text = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return text
}

private func decodeJSON<T: Decodable>(_ text: String?, fallback: T) -> T {
    guard let text, let data = text.data(using: .utf8) else {
        return fallback
    }
    return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
}

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return ""
    }
    return text
}

private func utcNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func dateOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

extension NativeDatabase: AIWorkflowRecording {}

package enum NativeDatabaseError: LocalizedError {
    case open(message: String)
    case statement(message: String)
    case notFound(String)

    package var errorDescription: String? {
        switch self {
        case let .open(message):
            return "无法打开本地 SQLite 数据库：\(message)"
        case let .statement(message):
            return "SQLite 操作失败：\(message)"
        case let .notFound(value):
            return "未找到数据：\(value)"
        }
    }
}
