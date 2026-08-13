import SwiftUI
import CreativeWorkshopCore

/// 两列工作台的唯一导航来源（24.13）。
///
/// 此前导航被劈在三处——侧栏 List、Composer 分段、Inspector 分段——共 10 个目的地，
/// 而「最近文章」列表还跟导航项挤在同一列里。这里把它们收拢成两组：
/// 「当前稿件」跟着这一篇走，「工作区」是跨稿件的库。
enum WorkspaceDestination: String, CaseIterable, Identifiable, Hashable {
    case process
    case article
    case community
    case review
    case prePublish
    case articles
    case topics
    case materials
    case library
    case settings

    var id: String { rawValue }

    /// 跟着当前稿件走的五个视角。
    static let draftGroup: [WorkspaceDestination] = [.process, .article, .community, .review, .prePublish]

    /// 跨稿件的列表与库。
    static let workspaceGroup: [WorkspaceDestination] = [.articles, .topics, .materials, .library]

    var title: String {
        switch self {
        case .process: "创作过程"
        case .article: "正文"
        case .community: "发布物料"
        case .review: "诊断复核"
        case .prePublish: "发表前审核"
        case .articles: "我的文章"
        case .topics: "待写选题"
        case .materials: "素材箱"
        case .library: "资料库"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .process: "sparkles"
        case .article: "doc.text"
        case .community: "megaphone"
        case .review: "text.magnifyingglass"
        case .prePublish: "checkmark.shield"
        case .articles: "doc.on.doc"
        case .topics: "target"
        case .materials: "tray.full"
        case .library: "chart.bar.doc.horizontal"
        case .settings: "gearshape"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: WorkspaceDestination
    @ObservedObject var store: WorkshopStore
    @SceneStorage("isRecentArticlesExpanded") private var isRecentExpanded = false
    @ObservedObject var profile: AuthorProfile
    @AppStorage("workshopAppearance") private var appearance = WorkshopAppearance.system.rawValue
    @State private var isAuthorEditorPresented = false
    @State private var isHoveringAuthor = false

    private var currentAppearance: WorkshopAppearance {
        WorkshopAppearance(rawValue: appearance) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: WorkshopMetrics.sectionSpacing) {
                    newDraftRow
                    draftSection
                    workspaceSection
                    recentSection
                }
                .padding(.horizontal, WorkshopMetrics.controlSpacing)
                .padding(.bottom, WorkshopMetrics.controlSpacing)
            }
            .scrollContentBackground(.hidden)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WorkshopPalette.navBackground)
    }

    private var newDraftRow: some View {
        WorkspaceNavRow(
            title: "新建文章",
            symbol: "square.and.pencil",
            isSelected: false
        ) {
            store.newDraft()
            navigateAfterSessionSwitch(to: .process)
        }
        .padding(.top, WorkshopMetrics.controlSpacing)
    }

    /// 「当前稿件」组常驻，不跟着选中项收起：任何时候都能一眼看到在写哪篇、
    /// 什么状态、有没有待复核。
    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader("当前稿件")

            HStack(spacing: WorkshopMetrics.controlSpacing) {
                Text(currentDraftTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WorkshopPalette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(store.articleStatus)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WorkshopPalette.statusColor(store.articleStatus))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule()
                            .stroke(WorkshopPalette.statusColor(store.articleStatus).opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.horizontal, WorkshopMetrics.controlSpacing)
            .padding(.top, 3)
            .padding(.bottom, 5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前稿件：\(currentDraftTitle)，\(store.articleStatus)")

            ForEach(WorkspaceDestination.draftGroup) { destination in
                WorkspaceNavRow(
                    title: destination.title,
                    symbol: destination.symbol,
                    isSelected: selection == destination,
                    attentionCount: destination == .review ? pendingReviewCount : 0,
                    isIndented: true
                ) {
                    selection = destination
                }
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader("工作区")

            ForEach(WorkspaceDestination.workspaceGroup) { destination in
                WorkspaceNavRow(
                    title: destination.title,
                    symbol: destination.symbol,
                    isSelected: selection == destination,
                    count: count(for: destination)
                ) {
                    selection = destination
                }
            }
        }
    }

    /// 「最近」默认折叠，不再跟导航项抢位置。完整列表在「我的文章」。
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                isRecentExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("最近")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isRecentExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WorkshopPalette.textTertiary)
                .padding(.horizontal, WorkshopMetrics.controlSpacing)
                .padding(.top, WorkshopMetrics.fieldSpacing)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecentExpanded ? "收起最近文章" : "展开最近文章")

            if isRecentExpanded {
                if store.articles.isEmpty {
                    Text("还没有保存过的文章。")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkshopPalette.textTertiary)
                        .padding(.horizontal, WorkshopMetrics.controlSpacing)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.articles.prefix(6)) { article in
                        WorkspaceNavRow(
                            title: article.displayTitle,
                            symbol: nil,
                            isSelected: false
                        ) {
                            store.openArticle(article)
                            navigateAfterSessionSwitch(to: .article)
                        }
                    }
                }
            }
        }
    }

    /// 底部：设置、外观切换，以及作者位。作者档案是纯本地的身份显示——
    /// 没有注册、没有服务端，也不参与生成。运行中的模型跟在作者名下面一行。
    private var footer: some View {
        VStack(spacing: 2) {
            HStack(spacing: WorkshopMetrics.fieldSpacing) {
                WorkspaceNavRow(
                    title: WorkspaceDestination.settings.title,
                    symbol: WorkspaceDestination.settings.symbol,
                    isSelected: selection == .settings
                ) {
                    selection = .settings
                }

                appearanceMenu
            }

            authorRow
        }
        .padding(WorkshopMetrics.controlSpacing)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WorkshopPalette.navDivider)
                .frame(height: 1)
        }
    }

    /// 作者位：头像 + 笔名，点开可编辑。运行中的模型降为第二行的小字，
    /// 它仍然需要一直可见，但不该占据身份位。
    private var authorRow: some View {
        Button {
            isAuthorEditorPresented = true
        } label: {
            HStack(spacing: WorkshopMetrics.controlSpacing) {
                AuthorAvatar(profile: profile, size: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .font(.system(size: 12.5))
                        .foregroundStyle(WorkshopPalette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.runtimeStatus == nil ? WorkshopPalette.textTertiary : WorkshopPalette.published)
                            .frame(width: 5, height: 5)
                        Text(store.runtimeStatus?.model ?? "未配置模型")
                            .font(.system(size: 10.5))
                            .foregroundStyle(WorkshopPalette.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, WorkshopMetrics.fieldSpacing)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHoveringAuthor ? WorkshopPalette.rowHover : .clear,
                        in: RoundedRectangle(cornerRadius: WorkshopMetrics.navRowCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringAuthor = $0 }
        .help("运行后端：\(store.runtimeStatus?.backend ?? "未就绪")")
        .accessibilityLabel("作者档案：\(profile.displayName)")
        .accessibilityHint("编辑笔名与头像")
        .popover(isPresented: $isAuthorEditorPresented, arrowEdge: .top) {
            AuthorProfileEditor(profile: profile)
        }
    }

    private var appearanceMenu: some View {
        Menu {
            Picker("外观", selection: $appearance) {
                ForEach(WorkshopAppearance.allCases) { option in
                    Label(option.title, systemImage: option.symbol)
                        .tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            Image(systemName: currentAppearance.symbol)
                .font(.system(size: 13))
                .foregroundStyle(WorkshopPalette.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("外观：\(currentAppearance.title)")
        .accessibilityLabel("切换外观，当前是\(currentAppearance.title)")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WorkshopPalette.textTertiary)
            .padding(.horizontal, WorkshopMetrics.controlSpacing)
            .padding(.top, WorkshopMetrics.fieldSpacing)
            .padding(.bottom, 4)
    }

    /// `openArticle`/`newDraft` 只是「请求」切换：当前稿件有未保存修改时会挂起等作者确认。
    /// 挂起时不能抢先导航，否则作者会被带到目标视图却看到旧稿。真正切换后的导航
    /// 由 `ContentView` 在确认弹窗里接管。
    private func navigateAfterSessionSwitch(to destination: WorkspaceDestination) {
        guard store.pendingSessionSwitch == nil else { return }
        selection = destination
    }

    private var currentDraftTitle: String {
        let trimmed = store.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名草稿" : trimmed
    }

    /// 待复核计数：待复核版本与待复核的问题改写各算一条。
    private var pendingReviewCount: Int {
        (store.pendingDraftReview == nil ? 0 : 1) + (store.pendingIssueRewrite == nil ? 0 : 1)
    }

    private func count(for destination: WorkspaceDestination) -> Int? {
        switch destination {
        case .articles: store.articles.count
        case .topics: store.topics.count
        case .materials: store.ideas.count
        default: nil
        }
    }

}

/// 导航行。选中态是抬高的中性面，不用强调色——强调色留给动作与状态。
private struct WorkspaceNavRow: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    var count: Int?
    var attentionCount: Int = 0
    var isIndented: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(isSelected ? WorkshopPalette.textPrimary : WorkshopPalette.textSecondary)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(symbol == nil ? WorkshopPalette.textSecondary : WorkshopPalette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if attentionCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WorkshopPalette.attention)
                            .frame(width: 6, height: 6)
                        Text("\(attentionCount)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(WorkshopPalette.attention)
                    }
                } else if let count {
                    Text("\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WorkshopPalette.textTertiary)
                }
            }
            .padding(.vertical, WorkshopMetrics.fieldSpacing)
            .padding(.trailing, WorkshopMetrics.controlSpacing)
            .padding(.leading, isIndented ? 22 : WorkshopMetrics.controlSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: WorkshopMetrics.navRowCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(attentionCount > 0 ? "有 \(attentionCount) 项待复核" : "")
    }

    private var background: Color {
        if isSelected {
            return WorkshopPalette.rowSelected
        }
        return isHovering ? WorkshopPalette.rowHover : .clear
    }
}

/// 头像：设过图就用图，没设就用笔名缩写兜底。
private struct AuthorAvatar: View {
    @ObservedObject var profile: AuthorProfile
    let size: CGFloat

    var body: some View {
        Group {
            if let avatar = profile.avatar {
                Image(nsImage: avatar)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                WorkshopPalette.rowSelected
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: size * 0.38, weight: .medium))
                            .foregroundStyle(WorkshopPalette.textSecondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// 作者档案编辑：笔名与头像，仅此而已。它不进 prompt，也不进署名。
private struct AuthorProfileEditor: View {
    @ObservedObject var profile: AuthorProfile

    var body: some View {
        VStack(alignment: .leading, spacing: WorkshopMetrics.stackSpacing) {
            HStack(spacing: WorkshopMetrics.stackSpacing) {
                AuthorAvatar(profile: profile, size: 52)

                VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
                    Button("选择头像…") {
                        profile.chooseAvatar()
                    }

                    Button("移除头像") {
                        profile.removeAvatar()
                    }
                    .disabled(profile.avatar == nil)
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
                Text("笔名")
                    .font(.caption.weight(.semibold))
                TextField("例如：向阳", text: $profile.penName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Text("只用于本机显示。不会进入提示词、署名或任何生成结果。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(WorkshopMetrics.sectionSpacing)
    }
}
