import Foundation

/// R5 瘦身·任务 23：自动保存（19.3.1）的存储与防抖调度层。
/// 快照的字段收集/应用属于 UI 状态绑定，仍归 WorkshopStore；这里只负责
/// "什么时候写、写到哪、怎么读回"。UserDefaults 可注入，便于测试与隔离。
@MainActor
package final class AutosaveController {
    private let defaults: UserDefaults
    private let key: String
    private var pendingTask: Task<Void, Never>?

    package init(
        defaults: UserDefaults = .standard,
        key: String = "CreativeWorkshopMac.autosavedDraft.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    package func load() -> AutoSavedDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AutoSavedDraft.self, from: data)
    }

    package func persist(_ snapshot: AutoSavedDraft) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    package func clear() {
        defaults.removeObject(forKey: key)
    }

    /// 防抖调度：窗口期内的连续调用合并为一次写入（默认 650ms，与迁移前一致）。
    package func schedule(
        debounceNanoseconds: UInt64 = 650_000_000,
        _ write: @escaping @MainActor () -> Void
    ) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.pendingTask = nil
            write()
        }
    }

    /// 取消挂起的防抖写入（调用方随后应立即执行一次同步写入）。
    package func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
