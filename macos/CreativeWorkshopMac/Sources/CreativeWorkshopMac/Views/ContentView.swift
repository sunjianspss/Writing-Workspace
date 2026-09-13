import SwiftUI
import CreativeWorkshopCore

/// 两列工作台（24.13）：左列是唯一导航，右列一次只做一件事，状态栏钉在右列底部。
///
/// 此前是「侧栏 → Composer → 可选 Inspector」三栏，导航散在三个控件里。改成两列后
/// Inspector 不再常驻——它的卡片按归属拆进了「诊断复核」「发表前审核」「资料库」三个目的地。
struct ContentView: View {
    @ObservedObject var store: WorkshopStore
    @ObservedObject var navigator: WorkspaceNavigator
    @ObservedObject var profile: AuthorProfile

    /// 选中态由 `navigator` 持有，这样 ⌘, 这类菜单命令也能改它。
    private var selection: Binding<WorkspaceDestination> { $navigator.destination }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection, store: store, profile: profile)
                .navigationSplitViewColumnWidth(
                    min: 232,
                    ideal: WorkshopMetrics.navColumnIdealWidth,
                    max: 320
                )
        } detail: {
            VStack(spacing: 0) {
                // 右列的宽度在这里钉死。
                //
                // SwiftUI 的 HStack/HSplitView 在内容超出可用宽度时**不裁剪**，而是整体
                // 溢出并居中——于是内容会盖到左列上、也会被窗口右边缘切掉。素材箱就是
                // 这样：分栏要 1041pt，窗口只有 980，两边各切掉约 30pt，侧栏的分组标题
                // 和右侧的按钮同时消失。
                //
                // `width: proxy.size.width` 把"可用宽度"变成硬约束：超出的部分在右列
                // 内部解决（压缩或裁剪），不再向外挤。这与「正文」页那条纵向接缝是同一
                // 类问题的两个方向。
                GeometryReader { proxy in
                    detailContent
                        .frame(width: proxy.size.width, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                WorkshopOperationStatusBar(
                    text: store.statusText,
                    isRunning: store.isLoading,
                    canCancel: store.canCancelCurrentOperation,
                    metrics: statusMetrics,
                    onCancel: { store.cancelCurrentOperation() }
                )
            }
            // 右列显式刷同一张底色：不刷就落在系统窗口底色上，与左列一深一浅。
            .background(WorkshopPalette.canvas)
        }
        .onDisappear {
            store.saveAutosaveSnapshot()
        }
        .alert("当前稿件尚未保存", isPresented: Binding(
            get: { store.pendingSessionSwitch != nil },
            set: { if !$0 { store.cancelPendingSessionSwitch() } }
        )) {
            Button("取消", role: .cancel) {
                store.cancelPendingSessionSwitch()
            }
            Button("放弃修改并切换", role: .destructive) {
                // 切换被挂起时调用方没有导航（否则会带着作者看旧稿），
                // 所以确认之后要在这里补上那一步。
                let target = store.pendingSessionSwitch
                store.confirmPendingSessionSwitch()

                switch target {
                case .article:
                    navigator.destination = .article
                case .newDraft:
                    navigator.destination = .process
                case nil:
                    break
                }
            }
        } message: {
            Text("切换会清除当前未保存的标题、正文、素材和写作设置。")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch navigator.destination {
        case .process, .article, .community:
            ComposerView(store: store, selection: selection)
        case .review:
            DraftReviewView(store: store, selection: selection)
        case .prePublish:
            PrePublishView(store: store, selection: selection)
        case .library:
            LibraryView(store: store)
        case .articles:
            ArticlesView(store: store, selection: selection)
        case .topics:
            TopicsView(store: store, selection: selection)
        case .materials:
            MaterialsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }

    /// 原 Inspector「上下文」分段里值得一直看见的读数，降级到状态栏。
    /// 运行后端与模型不在这里重复——它们在左列底部。
    private var statusMetrics: [WorkshopStatusMetric] {
        var metrics = [WorkshopStatusMetric("正文", "\(store.content.count) 字")]

        if let score = store.latestReview?.overall_score {
            metrics.append(WorkshopStatusMetric("诊断", "\(score) 分"))
        }

        return metrics
    }
}
