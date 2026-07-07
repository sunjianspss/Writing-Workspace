import AppKit
import SwiftUI
import CreativeWorkshopCore

@main
struct CreativeWorkshopMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkshopStore()

    var body: some Scene {
        WindowGroup("创作工坊") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    await store.refreshAll()
                }
        }
        .commands {
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

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
