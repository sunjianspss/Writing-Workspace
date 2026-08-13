import AppKit
import Foundation
import SwiftUI
import CreativeWorkshopCore

/// 本地作者档案（24.14）：笔名与头像，纯本地，不注册、不联网。
///
/// 这是身份显示，不是产品事实——它不进 prompt、不进署名、不影响任何生成结果，
/// 所以不占主 SQLite 的表：笔名落在 UserDefaults，头像落在应用支持目录里的一个 PNG，
/// 和数据库同一处。想让它参与创作是另一个决定，那时才该谈迁移。
@MainActor
final class AuthorProfile: ObservableObject {
    private static let penNameKey = "authorPenName"
    private static let avatarFileName = "author-avatar.png"

    private let defaults: UserDefaults

    @Published var penName: String {
        didSet {
            defaults.set(penName, forKey: Self.penNameKey)
        }
    }

    /// 头像从磁盘读进来后留在内存里；换图时整体替换，视图靠 `@Published` 刷新。
    @Published private(set) var avatar: NSImage?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        penName = defaults.string(forKey: Self.penNameKey) ?? ""
        avatar = Self.avatarURL.flatMap { NSImage(contentsOf: $0) }
    }

    /// 笔名为空时用于头像兜底的缩写：中文取首字，拉丁字母取前两位。
    var initials: String {
        let trimmed = penName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "作者" }

        if first.isLetter, first.isASCII {
            return String(trimmed.prefix(2)).uppercased()
        }
        return String(first)
    }

    var displayName: String {
        let trimmed = penName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未署名作者" : trimmed
    }

    /// 选一张图作为头像。统一转成 PNG 存下，避免把原图格式和体积带进来。
    func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "选作头像"

        guard panel.runModal() == .OK,
              let source = panel.url,
              let image = NSImage(contentsOf: source) else {
            return
        }

        guard let destination = Self.avatarURL, let data = Self.pngData(from: image) else {
            return
        }

        do {
            try data.write(to: destination, options: .atomic)
            avatar = NSImage(data: data)
        } catch {
            // 写不进去就保持原头像，不清空作者已有的设置。
        }
    }

    func removeAvatar() {
        if let url = Self.avatarURL {
            try? FileManager.default.removeItem(at: url)
        }
        avatar = nil
    }

    private static var avatarURL: URL? {
        try? NativePaths.applicationSupportDirectory.appending(path: avatarFileName)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
