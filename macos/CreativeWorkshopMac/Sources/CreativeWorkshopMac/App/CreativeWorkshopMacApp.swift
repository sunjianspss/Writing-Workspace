import AppKit
import SwiftUI
import CreativeWorkshopCore

@main
struct CreativeWorkshopMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkshopStore()
    @StateObject private var navigator = WorkspaceNavigator()
    @StateObject private var profile = AuthorProfile()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("workshopAppearance") private var appearance = WorkshopAppearance.system.rawValue

    private var preferredAppearance: WorkshopAppearance {
        WorkshopAppearance(rawValue: appearance) ?? .system
    }

    var body: some Scene {
        WindowGroup("创作工坊") {
            ContentView(store: store, navigator: navigator, profile: profile)
                // 下限从 980 提到 1060：980 是个不实的数字。实测右列在最窄的那一屏
                // （素材箱：列表 + 编辑器双栏）要 1041pt，加上左列 232 就已经越界，
                // 于是内容溢出窗口、左右两侧一起被切。与其把每个按钮都改成会缩的，
                // 不如让下限说实话——1060 在 1512 宽的屏幕上仍然宽裕。
                .frame(minWidth: 1060, minHeight: 680)
                // 24.14：外观是作者的选择，不是硬编码。`WorkshopPalette` 的每个 token
                // 都随外观解析，所以三种设置都成立。
                .preferredColorScheme(preferredAppearance.colorScheme)
                .task {
                    appDelegate.onWillTerminate = { [weak store] in
                        store?.saveAutosaveSnapshot()
                    }
                    await store.refreshAll()
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        store.saveAutosaveSnapshot()
                    }
                }
        }
        // 让窗口真的尊重上面那个 minWidth/minHeight。默认的 .automatic 只把它当建议，
        // 拖拽过程中仍可能把内容压到最小尺寸以下——那时 HStack 不会裁剪，只会互相重叠，
        // 于是标题栏、红绿灯和正文叠在一起、顶部按钮整排消失。
        .windowResizability(.contentMinSize)
        .commands {
            // 设置不再是独立窗口，⌘, 改为选中左列底部那个目的地。
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    navigator.destination = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("新稿") {
                    store.newDraft()
                }
                .keyboardShortcut("n")

                Button("刷新") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")

                Button("直接生成初稿") {
                    Task { await store.quickDraft() }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("生成大纲") {
                    Task { await store.generateOutline() }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("大纲成稿") {
                    Task { await store.draftFromOutline() }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("全文自然润色") {
                    Task { await store.polishDraft(.natural) }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("保存文章") {
                    Task { await store.saveArticle() }
                }
                .keyboardShortcut("s")
            }
        }

    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onWillTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
    }
}
