import Foundation
import SwiftUI

/// 左列当前选中的目的地。
///
/// 24.14：设置从独立的 `Settings` 场景搬进右列后，菜单里的 ⌘, 也要能选中它——
/// 而 `@SceneStorage` 只在视图里可读写，App 层够不着。所以选中态提到这个小对象上，
/// 由 App 持有，视图和菜单命令共享同一份。
///
/// 它只存导航状态，不碰任何产品事实——那些仍然归 `WorkshopStore` 和主 SQLite。
@MainActor
final class WorkspaceNavigator: ObservableObject {
    private static let storageKey = "selectedWorkspaceDestination"

    @Published var destination: WorkspaceDestination {
        didSet {
            UserDefaults.standard.set(destination.rawValue, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.storageKey)
        destination = stored.flatMap(WorkspaceDestination.init(rawValue:)) ?? .process
    }
}
