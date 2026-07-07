import XCTest
@testable import CreativeWorkshopMac
@testable import CreativeWorkshopCore

/// PRD 23.7：质量门/自检/雷区/终审四路验证信号统一为 VerificationReport。
final class VerificationReportTests: XCTestCase {
    // MARK: - 各来源的映射

    func testGateMappingPreservesTitleDetailAndMapsStatusToLevel() {
        let gate = AgentDraftQualityGate(items: [
            QualityGateItem(title: "写作 Brief", detail: "已明确核心问题。", status: .passed),
            QualityGateItem(title: "论点检查", detail: "缺少明确的论点修订指令。", status: .review)
        ])

        let report = VerificationReport.build(gate: gate)
        let entries = report.entries(source: .gate)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].title, "写作 Brief")
        XCTAssertEqual(entries[0].detail, "已明确核心问题。")
        XCTAssertEqual(entries[0].level, .passed)
        XCTAssertEqual(entries[1].level, .review)
    }

    func testSelfCheckMappingOnlyEmitsEntriesWhenConcernsFlagged() {
        let withConcerns = DraftSelfCheckResult(
            has_concerns: true,
            flagged_excerpts: [FlaggedExcerpt(excerpt: "空泛表达", concern: "缺少证据")],
            raw_output: nil
        )
        let report = VerificationReport.build(selfCheck: withConcerns)
        let entries = report.entries(source: .selfCheck)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].level, .review)
        XCTAssertEqual(entries[0].detail, "空泛表达\n缺少证据")

        let noConcerns = DraftSelfCheckResult(has_concerns: false, flagged_excerpts: [], raw_output: nil)
        XCTAssertTrue(VerificationReport.build(selfCheck: noConcerns).entries(source: .selfCheck).isEmpty)

        let nilConcerns = DraftSelfCheckResult(has_concerns: nil, flagged_excerpts: nil, raw_output: nil)
        XCTAssertTrue(VerificationReport.build(selfCheck: nilConcerns).entries(source: .selfCheck).isEmpty)
    }

    func testPitfallMappingEmitsOneReviewEntryPerCatalogPitfall() {
        let pitfalls = [
            AuthorPitfall(description: "不要鸡汤式收束", source_review_id: 1, created_at: nil),
            AuthorPitfall(description: "避免空洞排比句", source_review_id: nil, created_at: nil)
        ]
        let report = VerificationReport.build(pitfalls: pitfalls)
        let entries = report.entries(source: .pitfall)

        XCTAssertEqual(entries.map(\.detail), ["不要鸡汤式收束", "避免空洞排比句"])
        XCTAssertTrue(entries.allSatisfy { $0.level == .review })
    }

    func testAuditMappingMapsChineseSeverityStringsToLevels() {
        let audit = PrePublishAudit(
            id: 1,
            article_id: 1,
            title_snapshot: "标题",
            passed: 0,
            summary: "建议复核",
            issues: [
                AuditIssue(category: "错字/病句", severity: "高", excerpt: "葬花呤", problem: "疑似错字", suggestion: "改为葬花吟"),
                AuditIssue(category: "一致性", severity: "中", excerpt: nil, problem: "人称不一致", suggestion: nil),
                AuditIssue(category: "引文", severity: "低", excerpt: nil, problem: "引文来源模糊", suggestion: nil),
                AuditIssue(category: "作者雷区", severity: "未知", excerpt: nil, problem: "命中未知严重度", suggestion: nil)
            ],
            raw_output: nil,
            model: nil,
            created_at: nil
        )

        let entries = VerificationReport.build(audit: audit).entries(source: .audit)

        XCTAssertEqual(entries.map(\.level), [.high, .medium, .low, .medium])
        XCTAssertEqual(entries[0].title, "错字/病句")
        XCTAssertEqual(entries[0].detail, "葬花呤 — 疑似错字 — 改为葬花吟")
    }

    func testMissingSourcesProduceNoEntriesForThatSource() {
        let report = VerificationReport.build()
        XCTAssertTrue(report.entries.isEmpty)
    }

    // MARK: - compactLines 截断与排序

    func testCompactLinesSortsBySeverityAndTruncatesWithRemainderLine() {
        let gate = AgentDraftQualityGate(items: (1...5).map { index in
            QualityGateItem(title: "低优先级 \(index)", detail: "detail", status: .passed)
        })
        let audit = PrePublishAudit(
            id: 1,
            article_id: nil,
            title_snapshot: nil,
            passed: 0,
            summary: nil,
            issues: [
                AuditIssue(category: "作者雷区", severity: "高", excerpt: nil, problem: "高风险问题", suggestion: nil),
                AuditIssue(category: "一致性", severity: "中", excerpt: nil, problem: "中风险问题", suggestion: nil)
            ],
            raw_output: nil,
            model: nil,
            created_at: nil
        )

        let report = VerificationReport.build(gate: gate, audit: audit)
        XCTAssertEqual(report.entries.count, 7)

        let compact = report.compactLines(limit: 6)

        XCTAssertEqual(compact.count, 6)
        // 高优先于中，中优先于 passed；截断后最后一行收尾为"另有 N 项"。
        XCTAssertTrue(compact[0].contains("高风险问题"))
        XCTAssertTrue(compact[1].contains("中风险问题"))
        XCTAssertEqual(compact.last, "另有 2 项")
    }

    func testCompactLinesReturnsAllLinesWhenUnderLimit() {
        let gate = AgentDraftQualityGate(items: [
            QualityGateItem(title: "写作 Brief", detail: "已明确核心问题。", status: .passed)
        ])
        let compact = VerificationReport.build(gate: gate).compactLines(limit: 6)
        XCTAssertEqual(compact.count, 1)
        XCTAssertFalse(compact[0].contains("另有"))
    }

    // MARK: - 存量 UI 回归：待复核卡片读到的条目集合与改造前一致

    /// 复刻 InspectorView.PendingDraftReviewCard 改造前的三段拼装逻辑（质量门 items、
    /// 自检 flagged_excerpts、matchedPitfalls），断言改用 VerificationReport 后条目集合不变
    /// （store 层验证，不要求 UI 快照）。
    func testPendingDraftReviewEntriesMatchPreRefactorRendering() {
        let trace = AgentDraftTrace(
            workingTitle: "标题",
            coreQuestion: "",
            thesis: "",
            targetReader: "目标读者",
            argumentDirectives: [],
            missingEvidence: ["缺少亲历场景"],
            sectionSummaries: ["只有一段"],
            critiqueNotes: []
        )
        let selfCheck = DraftSelfCheckResult(
            has_concerns: true,
            flagged_excerpts: [FlaggedExcerpt(excerpt: "空泛表达", concern: "缺少证据")],
            raw_output: nil
        )
        let matchedPitfalls = [
            AuthorPitfall(description: "不要鸡汤式收束", source_review_id: 1, created_at: nil)
        ]

        let legacyGate = AgentDraftQualityGateEvaluator.evaluate(
            trace: trace,
            selfCheck: selfCheck,
            content: "",
            knownPitfalls: matchedPitfalls.map(\.description)
        )

        let report = VerificationReport.build(gate: legacyGate, selfCheck: selfCheck, pitfalls: matchedPitfalls)

        // 质量门：条目与 gate.items 逐一对应，标题、detail、通过/复核状态都不变。
        let gateEntries = report.entries(source: .gate)
        XCTAssertEqual(gateEntries.count, legacyGate?.items.count)
        for (entry, item) in zip(gateEntries, legacyGate?.items ?? []) {
            XCTAssertEqual(entry.title, item.title)
            XCTAssertEqual(entry.detail, item.detail)
            XCTAssertEqual(entry.level, item.status == .passed ? .passed : .review)
        }

        // 自检提示：原来渲染的引用片段 + 关注点，现在合并进同一个 entry.detail（用换行分隔，供视图拆分渲染）。
        let selfCheckEntries = report.entries(source: .selfCheck)
        XCTAssertEqual(selfCheckEntries.count, 1)
        XCTAssertEqual(selfCheckEntries[0].detail, "空泛表达\n缺少证据")

        // 作者雷区：原来逐条渲染 pending.matchedPitfalls 的 description，现在条目集合一致。
        let pitfallEntries = report.entries(source: .pitfall)
        XCTAssertEqual(pitfallEntries.map(\.detail), matchedPitfalls.map(\.description))
    }
}
