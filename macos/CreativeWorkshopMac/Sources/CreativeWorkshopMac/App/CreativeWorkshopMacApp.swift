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
                .frame(minWidth: 980, minHeight: 680)
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
