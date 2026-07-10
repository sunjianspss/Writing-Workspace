import SwiftUI
import CreativeWorkshopCore

struct ContentView: View {
    @ObservedObject var store: WorkshopStore
    @SceneStorage("selectedSidebarItem") private var selectedSidebarItem: SidebarItem = .articles
    @SceneStorage("isInspectorVisible") private var isInspectorVisible = true
    private let inspectorVisibilityWidth: CGFloat = 940

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem, store: store)
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        GeometryReader { geometry in
            let shouldShowInspector = isInspectorVisible && geometry.size.width >= inspectorVisibilityWidth

            HSplitView {
                primaryDetail
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(2)

                if shouldShowInspector {
                    InspectorView(store: store)
                        .frame(minWidth: 210, idealWidth: 240, maxWidth: 364)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryDetail: some View {
        switch selectedSidebarItem {
        case .materials:
            MaterialsView(store: store)
        case .topics:
            TopicsView(store: store, sidebarSelection: $selectedSidebarItem)
        case .articles:
            ComposerView(store: store, isInspectorVisible: $isInspectorVisible)
        }
    }
}
