import SwiftUI
import CreativeWorkshopCore

// 24.13：这里原本是常驻右侧的 Inspector 窄栏，用一个四段 Picker 切换。两列工作台把
// 它拆散——诊断类卡片归「诊断复核」，发布类归「发表前审核」，跨稿件统计归「资料库」。
// 原「上下文」分段整段取消：运行后端与 SQLite 路径在设置里已有，字数与诊断分降级进状态栏，
// 大纲与素材编辑器和「创作过程」屏重复。

/// 「诊断复核」屏。两列结构下没有第三列可用，所以这一屏会把正文整个换走；
/// 顶栏因此常驻一个「回到正文」的回程入口。
struct DraftReviewView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var selection: WorkspaceDestination

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "当前稿件", title: "诊断复核") {
                HStack(spacing: WorkshopMetrics.controlSpacing) {
                    Button {
                        Task { await store.reviewCurrentDraft() }
                    } label: {
                        Label("重新诊断", systemImage: "text.magnifyingglass")
                    }
                    .disabled(!store.canRunWritingCoach)

                    Button {
                        selection = .article
                    } label: {
                        Label("回到正文", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
                    if store.pendingDraftReview != nil {
                        PendingDraftReviewCard(store: store)
                    }
                    if store.pendingIssueRewrite != nil {
                        PendingIssueRewriteCard(store: store)
                    }
                    AdvisorCard(store: store)
                    AgentRunsCard(store: store)
                    CoachCard(store: store)
                    DimensionTrendsCard(store: store)
                    ReaderPerspectiveCard(store: store)
                }
                .frame(maxWidth: 1_060, alignment: .leading)
                .padding(WorkshopMetrics.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「发表前审核」屏：终审报告、编辑量与改稿版本。
///
/// 终审报告由发布流程（标记「已发布」）自动产出，没有独立的手动触发口，
/// 所以顶栏只给回程——发布状态控件在「正文」屏。
struct PrePublishView: View {
    @ObservedObject var store: WorkshopStore
    @Binding var selection: WorkspaceDestination

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "当前稿件", title: "发表前审核") {
                Button {
                    selection = .article
                } label: {
                    Label("回到正文", systemImage: "doc.text")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
                    PrePublishAuditCard(store: store)
                    EditMetricsCard(store: store)
                    DraftVersionsCard(store: store)
                }
                .frame(maxWidth: 1_060, alignment: .leading)
                .padding(WorkshopMetrics.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「资料库」屏：跨稿件的统计与选题储备，不跟着当前稿件走。
struct LibraryView: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(spacing: 0) {
            WorkshopScreenHeader(group: "工作区", title: "资料库") {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
                    StatsCard(stats: store.stats)
                    TopicsCard(store: store)
                }
                .frame(maxWidth: 1_060, alignment: .leading)
                .padding(WorkshopMetrics.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PrePublishAuditCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发表前终审")
                .font(.headline)

            if let audit = store.latestPrePublishAudit {
                HStack {
                    Label(audit.passed == 1 ? "终审通过" : "建议复核", systemImage: audit.passed == 1 ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(audit.passed == 1 ? .green : .orange)
                    Spacer()
                    if let createdAt = audit.created_at {
                        Text(createdAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let summary = audit.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(audit.issues.prefix(5)) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(issue.category)
                                .font(.caption.weight(.semibold))
                            Text(issue.severity)
                                .font(.caption2)
                                .foregroundStyle(issue.severity == "高" ? .red : .orange)
                            Spacer()
                            if store.canLocateAuditIssue(issue) {
                                Button {
                                    Task { await store.rewriteFromAuditIssue(issue) }
                                } label: {
                                    Label("定位并改写", systemImage: "location.magnifyingglass")
                                }
                                .controlSize(.mini)
                                .disabled(store.isLoading)
                            }
                        }
                        if let excerpt = issue.excerpt, !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("“\(excerpt)”")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Text(issue.problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let suggestion = issue.suggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } else {
                Text("发布为「已发布」前会自动运行一次终审，检查错字、引文、一致性和作者雷区。终审失败不会阻塞发布。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EditMetricsCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发表前编辑量")
                .font(.headline)
            if let stats = store.editRecordStats, stats.total > 0 {
                HStack {
                    metric("记录", "\(stats.total)")
                    metric("零改率", percent(stats.zeroEditRate))
                    metric("轻改率", percent(stats.lightEditRate))
                }
                Text("按已发布文章的「最近确认 AI 稿 → 发布稿」字符级编辑比例统计，零改 ≤1%，轻改 ≤10%。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !store.editRecordMonthlySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(store.editRecordMonthlySummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("发布文章后会自动记录编辑比例，用来观察系统是否越来越接近「少改即可发表」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct AdvisorCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("智能下一步")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.runWritingAdvisor() }
                } label: {
                    Label("判断", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .disabled(!store.canRunAdvisor)
            }

            if let run = store.latestAdvisorRun {
                HStack {
                    Text(run.stage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                    if let focus = run.focus_area,
                       !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(focus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                advisorList(title: "上下文观察", values: run.context_findings, systemImage: "doc.text.magnifyingglass")

                VStack(alignment: .leading, spacing: 5) {
                    Text("最大问题")
                        .font(.caption.weight(.semibold))
                    Text(run.main_problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("建议下一步")
                        .font(.caption.weight(.semibold))
                    Text(run.next_action)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(run.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                advisorList(title: "执行计划", values: run.execution_plan, systemImage: "checklist")
                advisorList(title: "风险提示", values: run.risk_notes, systemImage: "exclamationmark.triangle")

                if !run.actions.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(run.actions) { action in
                            Button {
                                store.performAdvisorAction(action)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .controlSize(.small)
                        }
                    }

                    Button {
                        Task { await store.executeAdvisorPlan() }
                    } label: {
                        Label("按计划执行", systemImage: "play.circle")
                    }
                    .controlSize(.small)
                    .disabled(!store.canExecuteAdvisorPlan)

                    if let progress = store.advisorPlanProgress {
                        Text(progress.currentAction.map { "第 \(progress.currentIndex)/\(progress.totalSteps) 步：\($0.title)" } ?? "计划执行中…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let context = run.context_summary,
                   !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("本次上下文") {
                        Text(context)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let rawOutput = run.raw_output,
                   !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("模型原始建议") {
                        Text(rawOutput)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("让系统先判断当前稿件阶段、最大问题和下一步动作。它会结合当前稿件、素材、风格和最近诊断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func advisorList(title: String, values: [String], systemImage: String) -> some View {
        let cleanValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanValues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                ForEach(Array(cleanValues.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AgentRunsCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("代理运行记录")
                .font(.headline)

            if store.agentRuns.isEmpty {
                Text("完成一次生成、诊断或智能下一步后，这里会沉淀可复盘的运行记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.agentRuns.prefix(6)) { run in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            runMeta(run)
                            if let input = run.input_summary.nilIfEmpty {
                                labeledText("输入摘要", input)
                            }
                            if let output = run.output_summary.nilIfEmpty {
                                labeledText("输出摘要", output)
                            }
                            if let error = run.error.nilIfEmpty {
                                labeledText("错误/降级", error, color: .orange)
                            }
                            if !run.steps.isEmpty {
                                Divider()
                                ForEach(run.steps) { step in
                                    stepView(step)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.run_type)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(run.summary ?? run.title_snapshot ?? "无摘要")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            statusBadge(run.status)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runMeta(_ run: AgentRun) -> some View {
        HStack(spacing: 8) {
            statusBadge(run.status)
            if let elapsed = run.elapsed_ms {
                Text("\(elapsed) ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let model = run.model.nilIfEmpty {
                Text(model)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func stepView(_ step: AgentStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(step.step_index). \(step.name)")
                    .font(.caption.weight(.semibold))
                Spacer()
                statusBadge(step.status)
            }
            if let output = step.output_summary.nilIfEmpty {
                Text(output)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if let error = step.error.nilIfEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func labeledText(_ title: String, _ value: String, color: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSuccess = normalized == "success"
        return Text(isSuccess ? "成功" : "兜底")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isSuccess ? Color.green : Color.orange).opacity(0.14), in: Capsule())
            .foregroundStyle(isSuccess ? .green : .orange)
    }
}

private struct CoachCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("写作教练")
                    .font(.headline)
                Spacer()
                Menu {
                    Button {
                        store.copyThirtyDayReviewReport()
                    } label: {
                        Label("复制 30 天报告", systemImage: "doc.on.doc")
                    }
                    Button {
                        store.exportThirtyDayReviewReport()
                    } label: {
                        Label("导出 30 天报告", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("报告", systemImage: "calendar.badge.clock")
                }
                .labelStyle(.iconOnly)
                .help("复制或导出最近 30 天写作教练报告")
                .controlSize(.small)
                .disabled(store.writingReviews.isEmpty)

                Button {
                    store.copyLatestWritingReview()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help(store.latestReview == nil ? "暂无可复制的诊断" : "复制完整写作教练诊断")
                .controlSize(.small)
                .disabled(store.latestReview == nil)

                Button {
                    Task { await store.reviewCurrentDraft() }
                } label: {
                    Label("诊断", systemImage: "text.magnifyingglass")
                }
                .controlSize(.small)
                .disabled(!store.canRunWritingCoach)

                Button {
                    Task { await store.improveDraftFromLatestReview() }
                } label: {
                    Label("按诊断改全文", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .disabled(!store.canImproveFromReview)
            }

            if let review = store.latestReview {
                reviewSummary(review)
                resolvedIssuesRow(review.resolved_from_last)
                reviewList(title: "优点", values: review.strengths.prefix(3).map(\.self))
                issuesList(review.issues.prefix(4).map(\.self))
                reviewList(title: "修改顺序", values: review.revision_plan.prefix(4).map(\.self))
                reviewList(title: "训练重点", values: review.training_focus.prefix(3).map(\.self))
                if let rawOutput = review.raw_output,
                   !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("模型原始诊断") {
                        Text(rawOutput)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("还没有复盘记录。完成一版想法、大纲或正文后，可以让 AI 先做编辑诊断，再决定怎么改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.writingReviews.isEmpty {
                Divider()
                Text("最近复盘")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.writingReviews.prefix(3)) { review in
                    reviewDetailDisclosure(review)
                }
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    /// 18.3.2 验收标准 2：即便"已解决"列表为空，也要有明确展示，不能只字不提。
    private func resolvedIssuesRow(_ resolved: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("已解决（较上次诊断）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if resolved.isEmpty {
                Text("暂无已判定解决的历史问题。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(resolved, id: \.self) { item in
                    Label(item, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private func reviewSummary(_ review: WritingReview) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let score = review.overall_score {
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.title3.bold())
                    Text("分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 46)
                .background(scoreColor(score).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(scoreColor(score))
            }
            Text(review.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reviewList(title: String, values: [String]) -> some View {
        Group {
            if !values.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    ForEach(values, id: \.self) { value in
                        Label(value, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private func issuesList(_ issues: [WritingReviewIssue]) -> some View {
        Group {
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("优先修改")
                        .font(.caption.weight(.semibold))
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(issue.dimension)
                                    .font(.caption.weight(.semibold))
                                Text(issue.severity)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityColor(issue.severity).opacity(0.14), in: Capsule())
                                    .foregroundStyle(severityColor(issue.severity))
                                Spacer()
                                if store.canLocateIssue(issue) {
                                    Button {
                                        Task { await store.rewriteFromIssue(issue) }
                                    } label: {
                                        Label("定位并改写", systemImage: "location.magnifyingglass")
                                    }
                                    .controlSize(.mini)
                                    .disabled(store.isLoading)
                                }
                            }
                            if let excerpt = issue.excerpt,
                               !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("“\(excerpt)”")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                            Text(issue.problem)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(issue.suggestion)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func reviewDetailDisclosure(_ review: WritingReview) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                reviewSummary(review)
                reviewList(title: "优点", values: review.strengths.prefix(4).map(\.self))
                issuesList(review.issues.prefix(6).map(\.self))
                reviewList(title: "修改顺序", values: review.revision_plan.prefix(6).map(\.self))
                reviewList(title: "训练重点", values: review.training_focus.prefix(5).map(\.self))
                reviewList(title: "风格观察", values: review.style_notes.prefix(4).map(\.self))
                if let rawOutput = review.raw_output,
                   !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("模型原始诊断") {
                        Text(rawOutput)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(review.title_snapshot ?? "未命名文章")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let score = review.overall_score {
                        Text("\(score) 分")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(scoreColor(score))
                    }
                }
                Text(review.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...:
            return .green
        case 60..<80:
            return .orange
        default:
            return .red
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "高":
            return .red
        case "中":
            return .orange
        default:
            return .gray
        }
    }
}

/// 诊断-改写闭环的候选确认卡（18.3.1）：改写结果先在这里展示，人工确认后才写入正文。
private struct PendingIssueRewriteCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        if let pending = store.pendingIssueRewrite {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("定点改写候选", systemImage: "wand.and.stars.inverse")
                        .font(.headline)
                    Spacer()
                    if pending.usedFallback {
                        Text("本地兜底")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }

                Text("针对「\(pending.issue.dimension)」：\(pending.issue.problem)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("原文")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(pending.originalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("改写为")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(pending.replacement)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                if let note = pending.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Button("确认替换正文") {
                        Task { await store.confirmPendingIssueRewrite() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("放弃") {
                        store.discardPendingIssueRewrite()
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// 大范围生成动作的"待复核"卡（18.4.1）：正文已经预览显示，这里并排给出改前/改后对比、自检提示和雷区清单。
private struct PendingDraftReviewCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        if let pending = store.pendingDraftReview {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("「\(pending.actionTitle)」待复核", systemImage: "checklist")
                        .font(.headline)
                    Spacer()
                    if pending.usedFallback {
                        Text("本地兜底")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }

                Text("正文已经更新到编辑器中，确认前不会覆盖已保存的文章。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // 24.9-P1：这次模型读的是你哪几篇文章。评测报告一直有「风格样本」行，App 侧
                // 直到现在只能查库——"写出来不像我"最常见的原因就是样本取错了档。
                if let samples = pending.styleSamples {
                    Label(samples.summaryLine, systemImage: "text.book.closed")
                        .font(.caption2)
                        .foregroundStyle(samples.titles.isEmpty || samples.usedDraftFallback ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = pending.note,
                   !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DisclosureGroup("本次生成说明") {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                }

                if let summaryLines = pending.agentSessionSummary, !summaryLines.isEmpty {
                    agentSessionSummaryDisclosure(summaryLines)
                }

                if let trace = pending.agentTrace {
                    agentTraceDisclosure(trace)
                }

                if let judgement = pending.candidateJudgement {
                    DisclosureGroup("候选评委：\(judgement.summary ?? judgement.bestReason ?? "已完成排序")") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(judgement.rankings) { ranking in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("候选 \(ranking.candidate_index)")
                                            .font(.caption.weight(.semibold))
                                        Text("\(ranking.score) 分")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        if ranking.candidate_index == judgement.best_candidate_index {
                                            Text("默认采用")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text(ranking.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.semibold))
                }

                if let fragments = pending.retrievedFragments, !fragments.isEmpty {
                    DisclosureGroup("本次引用了你的 \(fragments.count) 条素材") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(fragments) { fragment in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(fragment.citationTitle)
                                        .font(.caption.weight(.semibold))
                                    Text(fragment.content)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.semibold))
                }

                if let iterations = pending.iterationSummary, !iterations.isEmpty {
                    DisclosureGroup("自动迭代摘要：\(iterations.count) 轮") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(iterations) { iteration in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("第 \(iteration.round) 轮")
                                            .font(.caption.weight(.semibold))
                                        if let score = iteration.score {
                                            Text("\(score) 分")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let reason = iteration.stoppedReason {
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text("高 \(iteration.highIssueCount) / 中 \(iteration.mediumIssueCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    ForEach(iteration.remainingIssues.prefix(3), id: \.self) { issue in
                                        Text("· \(issue)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.semibold))
                }

                let gate = AgentDraftQualityGateEvaluator.evaluate(
                    trace: pending.agentTrace,
                    selfCheck: pending.selfCheck,
                    content: pending.after.content,
                    knownPitfalls: pending.matchedPitfalls.map(\.description)
                )
                // 统一收敛质量门/自检/雷区三路信号（PRD 23.7），发表前终审不在待复核阶段出现，故 audit 留空。
                let verificationReport = VerificationReport.build(
                    gate: gate,
                    selfCheck: pending.selfCheck,
                    pitfalls: pending.matchedPitfalls
                )

                if let gate {
                    qualityGateCard(gate)
                }

                diffPreview(before: pending.before.content, after: pending.after.content)

                let selfCheckEntries = verificationReport.entries(source: .selfCheck)
                if !selfCheckEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("自检提示（建议复查）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(selfCheckEntries) { entry in
                            let parts = entry.detail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("“\(parts[0])”")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                if parts.count > 1 {
                                    Text(parts[1])
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                let pitfallEntries = verificationReport.entries(source: .pitfall)
                if !pitfallEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本次生成时生效的作者雷区（请人工核对）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(pitfallEntries) { entry in
                            Text("· \(entry.detail)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button("确认定稿") {
                        Task { await store.confirmPendingDraftReview() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("放弃，恢复之前内容") {
                        Task { await store.discardPendingDraftReview() }
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 23.6.5 会话摘要：共 N 步、每步动作与理由、停止原因，直接读任务 14 已生成的 `agentSessionSummary`。
    private func agentSessionSummaryDisclosure(_ lines: [String]) -> some View {
        DisclosureGroup("代理会话摘要") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
    }

    private func agentTraceDisclosure(_ trace: AgentDraftTrace) -> some View {
        DisclosureGroup("代理运行轨迹") {
            VStack(alignment: .leading, spacing: 10) {
                traceKeyValue("工作标题", trace.workingTitle)
                traceKeyValue("核心问题", trace.coreQuestion)
                traceKeyValue("核心主张", trace.thesis)
                traceKeyValue("目标读者", trace.targetReader)
                traceList("论点检查指令", trace.argumentDirectives)
                traceList("缺少的证据/场景", trace.missingEvidence)
                traceList("素材缺口（建议补素材后重新生成）", trace.unresolvedGaps)
                traceList("分段成稿自检", trace.sectionSummaries)
                traceList("自我批评", trace.critiqueNotes)
            }
            .padding(.top, 6)
        }
        .font(.caption.weight(.semibold))
    }

    private func traceKeyValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func traceList(_ title: String, _ values: [String]) -> some View {
        let cleanValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanValues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(cleanValues.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func qualityGateCard(_ gate: AgentDraftQualityGate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("代理质量门", systemImage: gate.reviewCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gate.reviewCount == 0 ? .green : .orange)
                Spacer()
                Text("\(gate.passedCount)/\(gate.items.count) 通过")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(gate.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(gate.items) { item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: item.status == .passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(item.status == .passed ? .green : .orange)
                        .font(.caption)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .background((gate.reviewCount == 0 ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func diffPreview(before: String, after: String) -> some View {
        let summary = TextDiff.summary(before: before, after: after)
        return DisclosureGroup("正文变化：+\(summary.added) / -\(summary.removed)") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(TextDiff.lines(before: before, after: after).filter { $0.kind != .equal }.prefix(20)) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.kind == .added ? "+" : "-")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(line.kind == .added ? .green : .red)
                            .frame(width: 12)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.caption2.monospaced())
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
    }
}

/// 文学写作能力雷达（18.4.2）：基于历史诊断维度出现频次的趋势。
private struct DimensionTrendsCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        let trends = store.dimensionTrends
        VStack(alignment: .leading, spacing: 10) {
            Text("文学写作能力雷达")
                .font(.headline)

            if trends.isEmpty {
                Text("积累更多写作诊断记录后，这里会显示各维度问题的变化趋势。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trends) { trend in
                    HStack {
                        Text(trend.dimension)
                            .font(.caption)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)
                        trendBar(trend)
                        Text(trendLabel(trend.direction))
                            .font(.caption2)
                            .foregroundStyle(trendColor(trend.direction))
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Text("对比最近样本的前半段与后半段，反映「哪类问题在减少、哪类在反复出现」。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func trendBar(_ trend: DimensionTrend) -> some View {
        GeometryReader { proxy in
            let maxCount = max(trend.recentCount, trend.earlierCount, 1)
            HStack(alignment: .bottom, spacing: 4) {
                bar(count: trend.earlierCount, maxCount: maxCount, width: proxy.size.width, color: .secondary)
                bar(count: trend.recentCount, maxCount: maxCount, width: proxy.size.width, color: trendColor(trend.direction))
            }
        }
        .frame(height: 14)
    }

    private func bar(count: Int, maxCount: Int, width: CGFloat, color: Color) -> some View {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.5))
            .frame(width: max(4, width / 2 * max(ratio, count > 0 ? 0.08 : 0)), height: 10)
    }

    private func trendLabel(_ direction: TrendDirection) -> String {
        switch direction {
        case .improving:
            return "在减少"
        case .worsening:
            return "在增加"
        case .steady:
            return "较稳定"
        }
    }

    private func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .improving:
            return .green
        case .worsening:
            return .red
        case .steady:
            return .secondary
        }
    }
}

/// 读者视角模拟（18.4.3）：定性补充诊断，不计入 overall_score，不替代编辑视角诊断。
private struct ReaderPerspectiveCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("读者视角模拟")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.runReaderPerspective() }
                } label: {
                    Label("模拟", systemImage: "person.fill.viewfinder")
                }
                .controlSize(.small)
                .disabled(!store.canRunReaderPerspective)
            }

            if let perspective = store.latestReaderPerspective {
                if let persona = perspective.reader_persona, !persona.isEmpty {
                    labeledRow("读者画像", persona)
                }
                if let dropOff = perspective.drop_off_point, !dropOff.isEmpty {
                    labeledRow("最可能失去兴趣", dropOff)
                }
                if let memorable = perspective.most_memorable_point, !memorable.isEmpty {
                    labeledRow("最可能被记住/转发", memorable)
                }
                if let note = perspective.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("补充「读者视角」作为编辑诊断的参考，不影响诊断分数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DraftVersionsCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("改稿版本")
                .font(.headline)

            if store.draftVersions.isEmpty {
                Text("一键初稿、大纲成稿、全文改写、多版本候选、局部改写和覆盖保存后，会自动保存修改前后版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.draftVersions.prefix(5)) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(version.action)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let createdAt = version.created_at {
                                Text(createdAt.prefix(10))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if let note = version.note,
                           !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            Button("恢复前") {
                                store.restoreDraftVersionBefore(version)
                            }
                            Button("恢复后") {
                                store.restoreDraftVersionAfter(version)
                            }
                        }
                        .controlSize(.mini)

                        diffDisclosure(version)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func diffDisclosure(_ version: DraftVersion) -> some View {
        let summary = TextDiff.summary(before: version.before_content, after: version.after_content)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(TextDiff.lines(before: version.before_content, after: version.after_content).filter { $0.kind != .equal }.prefix(14)) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(marker(for: line.kind))
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(color(for: line.kind))
                            .frame(width: 12)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.caption2.monospaced())
                            .foregroundStyle(color(for: line.kind))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                if summary.isEmpty {
                    Text("正文没有变化。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("差异：+\(summary.added) / -\(summary.removed)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.isEmpty ? .secondary : .primary)
        }
    }

    private func marker(for kind: TextDiffKind) -> String {
        switch kind {
        case .equal:
            return " "
        case .added:
            return "+"
        case .removed:
            return "-"
        }
    }

    private func color(for kind: TextDiffKind) -> Color {
        switch kind {
        case .equal:
            return .secondary
        case .added:
            return .green
        case .removed:
            return .red
        }
    }
}

private struct StatsCard: View {
    let stats: OverviewStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("统计")
                .font(.headline)
            HStack {
                metric("文章", stats?.article_total)
                metric("本周", stats?.week_article_total)
                metric("选题", stats?.topic_pending)
            }
            if let direction = stats?.top_direction, !direction.isEmpty {
                Text("高频方向：\(direction)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value ?? 0)")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TopicsCard: View {
    @ObservedObject var store: WorkshopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("待写选题")
                .font(.headline)

            if !store.lastFilteredDuplicateTopics.isEmpty {
                duplicateHint
            }

            ForEach(store.topics.prefix(8)) { topic in
                VStack(alignment: .leading, spacing: 5) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(topic.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let description = topic.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    HStack {
                        Button("使用") {
                            store.useTopic(topic)
                        }
                        Button("生成大纲") {
                            store.useTopic(topic)
                            Task { await store.generateOutline() }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(topic.id == store.selectedTopicID ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                Divider()
            }
        }
        .padding(12)
        .background(WorkshopPalette.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    /// 选题去重提示（18.5.2）：与已有选题过于相似的候选不会入库，这里说明被过滤了哪些。
    private var duplicateHint: some View {
        DisclosureGroup("本次有 \(store.lastFilteredDuplicateTopics.count) 个候选选题与已有选题重复，已自动过滤") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.lastFilteredDuplicateTopics, id: \.title) { topic in
                    Text("· \(topic.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
    }
}
