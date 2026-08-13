import XCTest
import SQLite3
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

final class NativeDatabaseTests: XCTestCase {
    func testFreshDatabaseCreatesCoreTablesAndDefaultStyle() throws {
        let database = try makeDatabase()

        XCTAssertEqual(try database.listArticles().count, 0)
        XCTAssertEqual(try database.listTopics().count, 0)
        XCTAssertEqual(try database.defaultStyle().name, "默认公众号风格")

        let stats = try database.overviewStats()
        XCTAssertEqual(stats.article_total, 0)
        XCTAssertEqual(stats.topic_total, 0)
        XCTAssertEqual(try database.schemaVersion(), 11)
    }

    func testVersionedMigrationCreatesBackupThatCanRestorePreMigrationData() throws {
        let (databaseURL, articleID) = try makeVersion10Database(articleTitle: "迁移前标题")
        let backupURL = NativeDatabase.migrationBackupURL(
            for: databaseURL,
            fromVersion: 10,
            toVersion: 11
        )

        var migratedDatabase: NativeDatabase? = try NativeDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try migratedDatabase?.schemaVersion(), 11)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        _ = try migratedDatabase?.saveArticle(
            id: articleID,
            payload: ArticleSaveRequest(
                title: "迁移后被修改",
                content: "正文",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "情感文学"
            )
        )
        migratedDatabase = nil

        try NativeDatabase.restoreMigrationBackup(at: backupURL, to: databaseURL)

        let restoredDatabase = try NativeDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try restoredDatabase.schemaVersion(), 11)
        XCTAssertEqual(try restoredDatabase.listArticles().first?.title, "迁移前标题")
    }

    func testFailedVersionedMigrationRestoresVersion10SnapshotBeforeReportingFailure() throws {
        let (databaseURL, _) = try makeVersion10Database(articleTitle: "失败前仍需保留")
        try executeRawSQL(
            "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY);",
            at: databaseURL
        )

        do {
            _ = try NativeDatabase(databaseURL: databaseURL)
            XCTFail("缺少 name/applied_at 的迁移历史表应让 v11 迁移失败")
        } catch let NativeDatabaseError.migrationFailed(
            fromVersion,
            toVersion,
            backupURL,
            restored,
            _
        ) {
            XCTAssertEqual(fromVersion, 10)
            XCTAssertEqual(toVersion, 11)
            XCTAssertTrue(restored)
            XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        }

        // 故障输入本身属于迁移前快照，自动恢复后仍应存在。移除它，再次打开即可证明
        // 失败尝试没有推进版本、删除文章或留下半迁移状态。
        try executeRawSQL("DROP TABLE schema_migrations;", at: databaseURL)
        let recoveredDatabase = try NativeDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try recoveredDatabase.schemaVersion(), 11)
        XCTAssertEqual(try recoveredDatabase.listArticles().first?.title, "失败前仍需保留")
    }

    func testVersion10LegacyDatabaseNormalizesColumnsBeforeAdvancingToVersion11() throws {
        let (databaseURL, _) = try makeVersion10Database(articleTitle: "真实旧库")
        try executeRawSQL(
            """
            ALTER TABLE draft_versions RENAME TO draft_versions_modern;
            CREATE TABLE draft_versions (
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
            DROP TABLE draft_versions_modern;
            ALTER TABLE agent_runs RENAME TO agent_runs_modern;
            CREATE TABLE agent_runs (
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
                created_at TEXT
            );
            DROP TABLE agent_runs_modern;
            PRAGMA user_version = 10;
            """,
            at: databaseURL
        )

        let database = try NativeDatabase(databaseURL: databaseURL)

        XCTAssertEqual(try database.schemaVersion(), 11)
        let version = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "真实旧库",
            action: "迁移验证",
            note: nil,
            before: DraftSnapshot(title: "旧", summary: "", content: "旧"),
            after: DraftSnapshot(title: "新", summary: "", content: "新"),
            reviewStatus: "pending"
        )
        XCTAssertEqual(version.review_status, "pending")
        XCTAssertNoThrow(try database.listAgentRuns())
    }

    func testSaveArticleCreateTopicsAndStats() throws {
        let database = try makeDatabase()

        let topics = try database.createTopics([
            TopicPayload(
                title: "在成都，慢下来才看清什么更长久",
                direction: "情感文学",
                core_viewpoint: "慢不是懒散，而是一种筛选。",
                target_reader: "在成都生活或创业的人",
                description: "从城市气质切入写长期主义。",
                angle: "城市经验 + 个人观察",
                emotion: "温和",
                score: 5,
                status: "待写",
                tags: ["成都", "长期主义"]
            )
        ])

        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(try database.listTopics(status: "待写").count, 1)

        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "成都教会我的事",
                content: "正文",
                summary: "摘要",
                status: "草稿",
                tags: ["成都"],
                related_topic_id: topics[0].id,
                genre: "情感文学"
            )
        )

        XCTAssertEqual(article.title, "成都教会我的事")
        XCTAssertEqual(article.related_topic_id, topics[0].id)
        XCTAssertNotNil(article.created_at)
        XCTAssertNotNil(article.updated_at)
        XCTAssertEqual(try database.overviewStats().article_total, 1)
    }

    func testDeleteTopicRemovesRow() throws {
        let database = try makeDatabase()

        let topics = try database.createTopics([
            TopicPayload(
                title: "要删除的选题",
                direction: nil,
                core_viewpoint: nil,
                target_reader: nil,
                description: nil,
                angle: nil,
                emotion: nil,
                score: nil,
                status: "待写",
                tags: nil
            ),
            TopicPayload(
                title: "保留的选题",
                direction: nil,
                core_viewpoint: nil,
                target_reader: nil,
                description: nil,
                angle: nil,
                emotion: nil,
                score: nil,
                status: "待写",
                tags: nil
            )
        ])
        XCTAssertEqual(try database.listTopics().count, 2)

        try database.deleteTopic(id: topics[0].id)

        let remaining = try database.listTopics()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "保留的选题")
    }

    func testArticleStatusFilterAndArchive() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "待归档文章",
                content: "正文",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )

        XCTAssertEqual(try database.listArticles(status: "草稿").count, 1)
        XCTAssertEqual(try database.listArticles(status: "已归档").count, 0)

        let archived = try database.updateArticleStatus(id: article.id, status: "已归档")

        XCTAssertEqual(archived.status, "已归档")
        XCTAssertEqual(try database.listArticles(status: "草稿").count, 0)
        XCTAssertEqual(try database.listArticles(status: "已归档").first?.id, article.id)
    }

    func testSaveStyleProfileAndSetDefault() throws {
        let database = try makeDatabase()

        let saved = try database.saveStyleProfile(
            id: nil,
            profile: StyleProfile(
                id: 0,
                name: "读书随笔风格",
                language_style: "中文",
                tone: "克制",
                structure_preference: "先文本后现实",
                favorite_expressions: "慢慢看",
                forbidden_expressions: "不要标题党",
                sample_texts: ["样本一", "样本二"],
                title_style_like: "自然",
                title_style_dislike: "夸张",
                is_default: 0
            )
        )

        XCTAssertEqual(saved.sample_texts, ["样本一", "样本二"])
        XCTAssertEqual(try database.listStyleProfiles().count, 2)

        let defaultStyle = try database.setDefaultStyleProfile(id: saved.id)

        XCTAssertEqual(defaultStyle.is_default, 1)
        XCTAssertEqual(try database.defaultStyle().id, saved.id)
    }

    func testSaveUpdateUseAndDeleteIdeas() throws {
        let database = try makeDatabase()

        let idea = try database.saveIdea(
            id: nil,
            payload: IdeaSaveRequest(
                title: "一个素材",
                content: "素材正文",
                type: "灵感",
                tags: ["写作", "测试"],
                used: 0,
                related_article_id: nil
            )
        )

        XCTAssertEqual(idea.title, "一个素材")
        XCTAssertEqual(try database.listIdeas().count, 1)
        XCTAssertEqual(try database.listIdeas(search: "素材").first?.id, idea.id)

        let updated = try database.saveIdea(
            id: idea.id,
            payload: IdeaSaveRequest(
                title: "更新后的素材",
                content: "新的素材正文",
                type: "金句",
                tags: ["金句"],
                used: 0,
                related_article_id: nil
            )
        )

        XCTAssertEqual(updated.type, "金句")
        XCTAssertEqual(try database.markIdeaUsed(id: idea.id, used: true).used, 1)
        XCTAssertEqual(try database.overviewStats().idea_used, 1)

        try database.deleteIdea(id: idea.id)
        XCTAssertEqual(try database.listIdeas().count, 0)
    }

    func testSaveAndListWritingReviews() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "一篇需要复盘的文章",
                content: "正文",
                summary: "摘要",
                status: "草稿",
                tags: ["写作"],
                related_topic_id: nil,
                genre: nil
            )
        )

        let review = try database.saveWritingReview(
            result: WritingReviewResult(
                summary: "开头还需要更具体。",
                overall_score: 71,
                strengths: ["标题方向明确"],
                issues: [
                    WritingReviewIssue(
                        dimension: "开头",
                        severity: "中",
                        excerpt: "正文",
                        problem: "开头缺少场景。",
                        suggestion: "补一个真实动作。"
                    )
                ],
                revision_plan: ["先补开头", "再理结构"],
                training_focus: ["场景化开头"],
                style_notes: ["保持克制"],
                raw_output: nil,
                resolved_from_last: nil,
                pitfall_hits: ["少用金句收束"]
            ),
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            model: "deepseek-v4-pro",
            reviewedSnapshot: "标题\n摘要\n正文\n大纲\n想法"
        )

        XCTAssertEqual(review.article_id, article.id)
        XCTAssertEqual(review.overall_score, 71)
        XCTAssertEqual(review.issues.first?.dimension, "开头")
        XCTAssertEqual(review.reviewed_snapshot, "标题\n摘要\n正文\n大纲\n想法")
        XCTAssertEqual(review.resolved_from_last, [])
        XCTAssertEqual(review.pitfall_hits, ["少用金句收束"])
        XCTAssertEqual(try database.listWritingReviews(articleID: article.id, limit: 1).first?.pitfall_hits, ["少用金句收束"])
        XCTAssertEqual(try database.listWritingReviews().count, 1)
    }

    func testSaveAndListPublishAssets() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "一篇文章",
                content: "正文",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )

        let assets = try database.savePublishAssets(
            result: PublishAssetsResult(
                summary: "摘要",
                cover_text: "封面",
                moments_text: "朋友圈",
                tags: ["写作", "公众号"],
                xiaohongshu_text: "小红书",
                cover_image_prompt: "封面图提示词",
                raw_output: nil
            ),
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            model: "deepseek-v4-pro"
        )

        XCTAssertEqual(assets.article_id, article.id)
        XCTAssertEqual(assets.tags, ["写作", "公众号"])
        XCTAssertEqual(try database.listPublishAssets(articleID: article.id, limit: 1).first?.id, assets.id)
        XCTAssertEqual(try database.listPublishAssets().count, 1)
    }

    func testSaveAndListWritingAdvisorRuns() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "一篇文章",
                content: "正文",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        let context = ContextPackage(
            stage: "初稿阶段",
            title: article.displayTitle,
            summary: "",
            idea: "想法",
            direction: "情感文学",
            outline_excerpt: "",
            content_excerpt: "正文",
            materials_excerpt: "",
            selected_topic_title: nil,
            selected_topic_summary: nil,
            style_name: "默认",
            style_brief: "克制",
            word_count: 2,
            paragraph_count: 1,
            material_count: 0,
            recent_article_titles: [],
            recent_training_focus: ["场景化表达"],
            recent_issues: []
        )

        let run = try database.saveWritingAdvisorRun(
            result: WritingAdvisorResult(
                stage: "初稿阶段",
                main_problem: "缺少场景",
                next_action: "先诊断",
                reason: "需要判断问题优先级",
                suggested_actions: ["writing_review"],
                focus_area: "场景化表达",
                context_findings: ["正文已有雏形，但缺少场景"],
                execution_plan: ["先诊断", "再补场景"],
                risk_notes: ["直接润色会掩盖内容不足"],
                raw_output: nil
            ),
            context: context,
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            model: "deepseek-v4-pro"
        )

        XCTAssertEqual(run.article_id, article.id)
        XCTAssertEqual(run.actions, [.writingReview])
        XCTAssertEqual(run.context_findings, ["正文已有雏形，但缺少场景"])
        XCTAssertEqual(run.execution_plan, ["先诊断", "再补场景"])
        XCTAssertEqual(run.risk_notes, ["直接润色会掩盖内容不足"])
        XCTAssertEqual(try database.listWritingAdvisorRuns(articleID: article.id, limit: 1).first?.id, run.id)
    }

    func testSaveListAndAttachDraftVersions() throws {
        let database = try makeDatabase()
        let version = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "临时标题",
            action: "选中自然",
            note: "更自然",
            before: DraftSnapshot(title: "临时标题", summary: "", content: "旧正文"),
            after: DraftSnapshot(title: "临时标题", summary: "", content: "新正文")
        )

        XCTAssertEqual(version.before_content, "旧正文")
        XCTAssertEqual(version.after_content, "新正文")
        XCTAssertEqual(try database.listDraftVersions().first?.id, version.id)

        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "临时标题",
                content: "新正文",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        try database.attachDraftVersionsToArticle(articleID: article.id, titleSnapshot: "临时标题")

        XCTAssertEqual(try database.listDraftVersions(articleID: article.id, limit: 1).first?.id, version.id)
    }

    func testAlternativeDraftVersionCanBeConfirmed() throws {
        let database = try makeDatabase()
        let version = try database.saveDraftVersion(
            articleID: nil,
            titleSnapshot: "多版本标题",
            action: "候选·全文自然",
            note: "多版本候选",
            before: DraftSnapshot(title: "多版本标题", summary: "", content: "原正文"),
            after: DraftSnapshot(title: "多版本标题", summary: "", content: "候选正文"),
            reviewStatus: "alternative"
        )

        XCTAssertEqual(version.review_status, "alternative")

        let confirmed = try database.confirmDraftVersion(id: version.id)

        XCTAssertEqual(confirmed.review_status, "confirmed")
        XCTAssertEqual(confirmed.after_content, "候选正文")
    }

    func testRecordAICallStoresInputAndOutputSummaries() throws {
        let database = try makeDatabase()

        database.recordAICall(
            endpoint: "polish-natural-native",
            model: "deepseek-v4-pro",
            elapsedMS: 123,
            success: true,
            error: "",
            inputSummary: "输入摘要",
            outputSummary: "输出摘要"
        )

        let call = try XCTUnwrap(database.listAICalls(limit: 1).first)
        XCTAssertEqual(call.endpoint, "polish-natural-native")
        XCTAssertEqual(call.input_summary, "输入摘要")
        XCTAssertEqual(call.output_summary, "输出摘要")
        XCTAssertEqual(call.success, 1)
    }

    func testSaveAndListAgentRunsWithSteps() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "代理文章",
                content: "正文",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )

        let run = try database.saveAgentRun(
            runType: "代理生成初稿",
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            status: "success",
            summary: "完成代理初稿",
            model: "deepseek-v4-pro",
            elapsedMS: 321,
            inputSummary: "输入",
            outputSummary: "输出",
            error: "",
            steps: [
                AgentStepPayload(
                    step_index: 1,
                    name: "Writing brief",
                    status: "success",
                    input_summary: "brief 输入",
                    output_summary: "brief 输出",
                    elapsed_ms: 100,
                    error: ""
                ),
                AgentStepPayload(
                    step_index: 2,
                    name: "论点检查",
                    status: "success",
                    input_summary: "check 输入",
                    output_summary: "check 输出",
                    elapsed_ms: 221,
                    error: ""
                )
            ]
        )

        XCTAssertEqual(run.article_id, article.id)
        XCTAssertEqual(run.steps.count, 2)
        XCTAssertEqual(run.steps.first?.name, "Writing brief")
        XCTAssertEqual(try database.listAgentRuns(articleID: article.id, limit: 1).first?.steps.last?.name, "论点检查")
        XCTAssertNil(run.session_kind, "单步操作不传 sessionKind 时应保持为空")
    }

    /// 23.5：半自动调度序列写入 session_kind = "plan_execution"，供后续区分单步操作与计划执行。
    func testSaveAgentRunPersistsSessionKindForPlanExecution() throws {
        let database = try makeDatabase()

        let run = try database.saveAgentRun(
            runType: "按计划执行",
            articleID: nil,
            titleSnapshot: "",
            status: "success",
            summary: "计划执行完成",
            model: "deepseek-v4-pro",
            elapsedMS: 12,
            inputSummary: "",
            outputSummary: "",
            error: "",
            steps: [],
            sessionKind: "plan_execution"
        )

        XCTAssertEqual(run.session_kind, "plan_execution")
        XCTAssertEqual(try database.listAgentRuns(limit: 1).first?.session_kind, "plan_execution")
    }

    /// 兼容旧数据（PRD 23.5 验收标准 5）：老版本写入的数据库没有 session_kind 列，
    /// CREATE TABLE IF NOT EXISTS 不会给已存在的表补列，必须靠 ensureColumn 迁移补回来，
    /// 且历史行读出时 session_kind 应为空而不是崩溃。
    func testOpeningLegacyDatabaseWithoutSessionKindColumnMigratesAndStaysUsable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "creative_workshop.sqlite3")

        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE agent_runs (
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
            created_at TEXT
        );
        INSERT INTO agent_runs
            (article_id, title_snapshot, run_type, status, summary, model, elapsed_ms,
             input_summary, output_summary, error, created_at)
        VALUES (NULL, '旧文章', '写作诊断', 'success', '历史记录', 'deepseek-v4-pro', 10, '输入', '输出', '', '2026-01-01T00:00:00Z');
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let database = try NativeDatabase(databaseURL: databaseURL)

        let legacyRun = try XCTUnwrap(database.listAgentRuns(limit: 10).first { $0.run_type == "写作诊断" })
        XCTAssertNil(legacyRun.session_kind)

        let newRun = try database.saveAgentRun(
            runType: "按计划执行",
            articleID: nil,
            titleSnapshot: "",
            status: "success",
            summary: "计划执行完成",
            model: "deepseek-v4-pro",
            elapsedMS: 1,
            inputSummary: "",
            outputSummary: "",
            error: "",
            steps: [],
            sessionKind: "plan_execution"
        )
        XCTAssertEqual(newRun.session_kind, "plan_execution")
        XCTAssertEqual(try database.listAgentRuns(limit: 10).count, 2)
    }

    /// 兼容旧数据（PRD 23.6 验收标准 6）：老版本数据库的 agent_runs 没有 budget_summary，
    /// agent_steps 没有 step_type/decision_json，迁移后历史行必须可读（step_type 默认 "action"），
    /// 且新写入的决策步能正确落库 step_type="decision" 与 decision_json 原文。
    func testOpeningLegacyDatabaseWithoutAgentSessionColumnsMigratesAndStaysUsable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "creative_workshop.sqlite3")

        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &legacyDB), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE agent_runs (
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
            created_at TEXT
        );
        CREATE TABLE agent_steps (
            id INTEGER PRIMARY KEY,
            run_id INTEGER,
            step_index INTEGER,
            name TEXT,
            status TEXT,
            input_summary TEXT,
            output_summary TEXT,
            elapsed_ms INTEGER,
            error TEXT,
            created_at TEXT
        );
        INSERT INTO agent_runs
            (article_id, title_snapshot, run_type, status, summary, model, elapsed_ms,
             input_summary, output_summary, error, session_kind, created_at)
        VALUES (NULL, '旧文章', '写作诊断', 'success', '历史记录', 'deepseek-v4-pro', 10, '输入', '输出', '', NULL, '2026-01-01T00:00:00Z');
        INSERT INTO agent_steps
            (run_id, step_index, name, status, input_summary, output_summary, elapsed_ms, error, created_at)
        VALUES (1, 1, '写作诊断', 'success', '输入', '输出', 10, '', '2026-01-01T00:00:00Z');
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, legacySchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let database = try NativeDatabase(databaseURL: databaseURL)

        let legacyRun = try XCTUnwrap(database.listAgentRuns(limit: 10).first { $0.run_type == "写作诊断" })
        XCTAssertNil(legacyRun.budget_summary)
        let legacyStep = try XCTUnwrap(legacyRun.steps.first)
        XCTAssertEqual(legacyStep.step_type, "action")
        XCTAssertNil(legacyStep.decision_json)

        let decisionStep = AgentStepPayload(
            step_index: 1,
            name: "决策：写作诊断",
            status: "success",
            input_summary: "",
            output_summary: "选择 writing_review",
            elapsed_ms: 5,
            error: "",
            step_type: "decision",
            decision_json: "{\"action\":\"writing_review\",\"stop\":false}"
        )
        let newRun = try database.saveAgentRun(
            runType: "有界代理循环",
            articleID: nil,
            titleSnapshot: "",
            status: "success",
            summary: "会话已完成",
            model: "deepseek-v4-pro",
            elapsedMS: 1,
            inputSummary: "",
            outputSummary: "",
            error: "",
            steps: [decisionStep],
            sessionKind: "agent_session",
            budgetSummary: "已用 1/12 次"
        )
        XCTAssertEqual(newRun.budget_summary, "已用 1/12 次")
        let savedStep = try XCTUnwrap(newRun.steps.first)
        XCTAssertEqual(savedStep.step_type, "decision")
        XCTAssertEqual(savedStep.decision_json, "{\"action\":\"writing_review\",\"stop\":false}")
    }

    func testRebuildFragmentsSupportsLocalRetrieval() throws {
        let database = try makeDatabase()
        let idea = try database.saveIdea(
            id: nil,
            payload: IdeaSaveRequest(
                title: "成都茶馆",
                content: "在成都茶馆里，时间慢下来，人和人的关系不靠饭局，而靠长期信任。",
                type: "素材",
                tags: ["成都"],
                used: 0,
                related_article_id: nil
            )
        )
        _ = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "已发布文章",
                content: "专业能力比短暂关系更经得住时间。",
                summary: "",
                status: "已发布",
                tags: [],
                related_topic_id: nil,
                genre: "情感文学"
            )
        )

        let fragments = try database.rebuildFragments()
        let hits = FragmentRetriever.retrieve(query: "成都 长期 信任", fragments: fragments, limit: 2)

        XCTAssertEqual(fragments.contains { $0.source_type == "idea" && $0.source_id == idea.id }, true)
        XCTAssertEqual(hits.first?.source_type, "idea")
    }

    func testSaveEditRecordComputesPublishingMetrics() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "少改发布文章",
                content: "这是 AI 确认稿，发布前只多加一点点。",
                summary: "",
                status: "已发布",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        let version = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            action: "代理生成初稿",
            note: nil,
            before: DraftSnapshot(title: "", summary: "", content: ""),
            after: DraftSnapshot(title: article.displayTitle, summary: "", content: "这是 AI 确认稿。"),
            reviewStatus: "confirmed"
        )

        let record = try database.saveEditRecord(article: article, draftVersion: version)
        let stats = try database.editRecordStats()

        XCTAssertEqual(record.article_id, article.id)
        XCTAssertEqual(record.draft_version_id, version.id)
        XCTAssertEqual(stats.total, 1)
        XCTAssertGreaterThan(record.edit_ratio, 0)
    }

    func testPublishingMetricsRecorderSnapshotsPublishedEditRecord() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "轻改文章",
                content: "这是发布稿，只改了一点。",
                summary: "",
                status: "已发布",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        _ = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            action: "代理生成初稿",
            note: nil,
            before: DraftSnapshot(title: "", summary: "", content: ""),
            after: DraftSnapshot(title: article.displayTitle, summary: "", content: "这是发布稿。"),
            reviewStatus: "confirmed"
        )

        let snapshot = PublishingMetricsRecorder(database: database).recordPublishedArticle(article)

        XCTAssertEqual(snapshot?.stats.total, 1)
        XCTAssertFalse(snapshot?.monthlySummary.isEmpty ?? true)
        XCTAssertEqual(try database.listEditRecords(limit: 10).first?.article_id, article.id)
    }

    func testSaveAndListPrePublishAudit() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "葬花呤",
                content: "正文里也写了葬花呤。",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        let report = PrePublishAuditReport(
            passed: false,
            summary: "发现错字。",
            typo_issues: [
                AuditIssue(category: "错字", severity: "中", excerpt: "葬花呤", problem: "疑似错字", suggestion: "改为葬花吟")
            ],
            quote_issues: [],
            consistency_issues: [],
            pitfall_issues: [],
            raw_output: nil
        )

        let audit = try database.savePrePublishAudit(
            result: report,
            articleID: article.id,
            titleSnapshot: article.displayTitle,
            model: "deepseek-v4-pro"
        )

        XCTAssertEqual(audit.article_id, article.id)
        XCTAssertEqual(audit.issues.first?.excerpt, "葬花呤")
        XCTAssertEqual(try database.listPrePublishAudits(articleID: article.id, limit: 1).first?.id, audit.id)
        XCTAssertEqual(try database.listArticles().first(where: { $0.id == article.id })?.audit_report?.summary, "发现错字。")

        let editedArticle = try database.saveArticle(
            id: article.id,
            payload: ArticleSaveRequest(
                title: "葬花吟",
                content: "正文已修正。",
                summary: "",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: nil
            )
        )
        XCTAssertNil(editedArticle.audit_report)
    }

    func testModelConfigPersistsWorkflowOverrides() throws {
        let database = try makeDatabase()
        let overrides = [
            AIWorkflowKind.candidateJudge.rawValue: ModelRouteConfig(
                baseURL: nil,
                model: "deepseek-reasoner",
                temperature: 0.35,
                timeoutSeconds: 120
            ),
            AIWorkflowKind.draftSelfCheck.rawValue: ModelRouteConfig(
                baseURL: "https://cheap.example.com",
                model: "fast-check",
                temperature: 0.1,
                timeoutSeconds: 30
            )
        ]

        try database.saveModelConfig(
            ModelConfig(
                baseURL: "https://api.example.com",
                model: "default-model",
                workflowOverrides: overrides
            )
        )

        let config = try database.modelConfig()
        XCTAssertEqual(config.baseURL, "https://api.example.com")
        XCTAssertEqual(config.model, "default-model")
        XCTAssertEqual(config.workflowOverrides[AIWorkflowKind.candidateJudge.rawValue]?.model, "deepseek-reasoner")
        XCTAssertEqual(config.resolved(for: .candidateJudge).model, "deepseek-reasoner")
        XCTAssertEqual(config.resolved(for: .draftSelfCheck).baseURL, "https://cheap.example.com")

        try database.saveModelConfig(baseURL: "https://api.changed.com", model: "changed-default")
        let preserved = try database.modelConfig()
        XCTAssertEqual(preserved.workflowOverrides[AIWorkflowKind.candidateJudge.rawValue]?.model, "deepseek-reasoner")
    }

    func testPromptTemplatesSeedAndSave() throws {
        let database = try makeDatabase()

        let templates = try database.listPromptTemplates()
        XCTAssertEqual(templates.count, PromptTemplateKey.allCases.count)

        let polish = try XCTUnwrap(try database.promptTemplate(key: .polishDraft))
        XCTAssertTrue(polish.user_template.contains("{{content}}"))

        let updated = try database.savePromptTemplate(
            id: polish.id,
            name: "自定义全文润色",
            systemPrompt: "系统提示",
            userTemplate: "用户模板 {{content}}"
        )

        XCTAssertEqual(updated.name, "自定义全文润色")
        XCTAssertEqual(try database.promptTemplate(key: .polishDraft)?.system_prompt, "系统提示")
    }

    func testSeedRefreshKeepsCustomizedTemplateAndUpdatesDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "creative_workshop.sqlite3")

        let first = try NativeDatabase(databaseURL: url)
        let polish = try XCTUnwrap(try first.promptTemplate(key: .polishDraft))
        _ = try first.savePromptTemplate(
            id: polish.id,
            name: "自定义全文润色",
            systemPrompt: "系统提示",
            userTemplate: "用户模板 {{content}}"
        )

        let reopened = try NativeDatabase(databaseURL: url)
        let customized = try XCTUnwrap(try reopened.promptTemplate(key: .polishDraft))
        XCTAssertEqual(customized.user_template, "用户模板 {{content}}")
        XCTAssertEqual(customized.is_default, 0)

        let seed = try XCTUnwrap(
            NativePrompts.defaultPromptTemplates().first { $0.key == .writingReview }
        )
        let untouched = try XCTUnwrap(try reopened.promptTemplate(key: .writingReview))
        XCTAssertEqual(untouched.user_template, seed.user_template)
        XCTAssertEqual(untouched.is_default, 1)
    }

    /// 回归：App 的写作诊断实际走 DB 里的 seed 模板（promptTemplate 非 nil 就会短路掉
    /// NativePrompts 里的内联 prompt）。该模板一度缺评分锚点、缺 {{previous_review}}，
    /// 导致同一份逐字节相同的正文三次诊断给出 58/72/73，且第二次诊断读不到上一次结论。
    func testSeededWritingReviewTemplateCarriesAnchorsAndPreviousReview() throws {
        let database = try makeDatabase()
        let review = try XCTUnwrap(try database.promptTemplate(key: .writingReview))

        XCTAssertTrue(review.user_template.contains("评分锚点"), "写作诊断模板缺评分锚点，分数会向 70 分档塌缩")
        XCTAssertTrue(review.user_template.contains("90–100"), "评分锚点缺分档定义")
        XCTAssertTrue(
            review.user_template.contains("分数必须与 issues 清单一致"),
            "缺一致性约束，分数会与问题清单脱钩"
        )
        XCTAssertTrue(
            review.user_template.contains("{{previous_review}}"),
            "模板没有 previous_review 占位符，上一次诊断会被 replacePlaceholders 静默丢弃"
        )
        XCTAssertTrue(review.user_template.contains("resolved_from_last"), "缺已解决问题字段，改对了也不记分")
    }

    /// 回归：体裁匹配是字符串精确相等，而 articles.genre 存的是保存时的写作方向原文，
    /// 方向换个说法样本就归零（作者库里"经典文学解读"匹配 0 篇，文章却标着"文学原著"）。
    /// genre 传 nil 表示不限体裁，供 resolveStyle 落空时兜底，保证模型至少见过作者的文字。
    func testRecentArticlesForSamplesFallsBackToAnyGenre() throws {
        let database = try makeDatabase()
        _ = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "叹香菱",
                content: "菱花空对雪澌澌",
                summary: "摘要",
                status: "已归档",
                tags: [],
                related_topic_id: nil,
                genre: "文学原著"
            )
        )

        _ = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "改到一半的稿",
                content: "半成品",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "情感文学"
            )
        )

        // 方向写法不一致 → 精确匹配落空
        XCTAssertTrue(try database.recentArticlesForSamples(genre: "经典文学解读").isEmpty)
        XCTAssertEqual(try database.recentArticlesForSamples(genre: "文学原著").count, 1)
        // 兜底：不限体裁时能取到文章，且只取完成稿——草稿不能当风格范本
        let fallback = try database.recentArticlesForSamples(genre: nil, finishedOnly: true)
        XCTAssertEqual(fallback.map(\.title), ["叹香菱"])
    }

    /// PRD 24.8：编辑量基准必须是**模型产出**的版本。覆盖保存也会记一条 confirmed 版本，
    /// 内容就是作者当下的正文；拿它当基准，编辑比例结构上恒为 0。
    func testLatestModelDraftVersionSkipsManualSaveSnapshots() throws {
        let database = try makeDatabase()
        let article = try database.saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: "叹香菱",
                content: "作者手改后的正文",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "文学原著"
            )
        )
        _ = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: "叹香菱",
            action: "定点改写·语言腔调",
            note: "",
            before: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "模型给的正文"),
            after: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "模型改写后的正文")
        )
        _ = try database.saveDraftVersion(
            articleID: article.id,
            titleSnapshot: "叹香菱",
            action: DraftVersionAction.manualSave,
            note: "",
            before: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "模型改写后的正文"),
            after: DraftSnapshot(title: "叹香菱", summary: "摘要", content: "作者手改后的正文")
        )

        let baseline = try XCTUnwrap(database.latestModelDraftVersion(articleID: article.id))

        XCTAssertEqual(baseline.action, "定点改写·语言腔调", "基准应跳过覆盖保存留下的版本")
        // 拿模型那版做基准，编辑量才量得出作者改了多少。
        let record = try database.saveEditRecord(article: article, draftVersion: baseline)
        XCTAssertGreaterThan(record.added_characters + record.removed_characters, 0)
        XCTAssertNotEqual(record.edit_level, "zero")
    }

    private func makeDatabase() throws -> NativeDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try NativeDatabase(databaseURL: directory.appending(path: "creative_workshop.sqlite3"))
    }

    private func makeVersion10Database(articleTitle: String) throws -> (URL, Int) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "creative_workshop.sqlite3")

        var database: NativeDatabase? = try NativeDatabase(databaseURL: databaseURL)
        let article = try XCTUnwrap(database).saveArticle(
            id: nil,
            payload: ArticleSaveRequest(
                title: articleTitle,
                content: "正文",
                summary: "摘要",
                status: "草稿",
                tags: [],
                related_topic_id: nil,
                genre: "情感文学"
            )
        )
        database = nil

        try executeRawSQL(
            "DROP TABLE IF EXISTS schema_migrations; PRAGMA user_version = 10;",
            at: databaseURL
        )
        return (databaseURL, article.id)
    }

    private func executeRawSQL(_ sql: String, at databaseURL: URL) throws {
        var rawDatabase: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &rawDatabase) == SQLITE_OK else {
            XCTFail("无法创建迁移测试数据库")
            return
        }
        defer { sqlite3_close(rawDatabase) }
        XCTAssertEqual(sqlite3_exec(rawDatabase, sql, nil, nil, nil), SQLITE_OK)
    }
}
