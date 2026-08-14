import AppKit
import SwiftUI

/// A deliberately small set of layout constants shared by the native app.
/// Add a token only after two real screens need the same value.
enum WorkshopMetrics {
    static let fieldSpacing: CGFloat = 6
    static let controlSpacing: CGFloat = 8
    static let stackSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let pagePadding: CGFloat = 20
    static let controlCornerRadius: CGFloat = 8
    static let settingsContentMaxWidth: CGFloat = 680
    static let statusBarHeight: CGFloat = 32
    static let navRowCornerRadius: CGFloat = 6
    static let navColumnIdealWidth: CGFloat = 252
}

/// 工作台可以跟随系统，也可以被钉在浅色或深色。
enum WorkshopAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 两列工作台的色板（24.13）。导航列、屏幕顶栏与状态栏用这里的显式值，
/// 其余卡片继续走 AppKit 语义色。
///
/// 每个 token 都是随外观解析的动态色，所以「跟随系统 / 浅色 / 深色」三种设置
/// 都成立——不是把深色硬编码进视图。
///
/// `canvas` 是两列共用的底色：左列和右列都显式刷它，两边就不会再一深一浅
/// （右列原先落在系统窗口底色上，深色下还会被壁纸染色）。浅色取原导航列的暖灰，
/// 深色取原右列那一档亮度——底色抬高后，分隔线与行状态在深色下同步上移一档。
///
/// `surface` 是卡片填充，也必须是显式值：卡片原先刷 SwiftUI 的 `.background`，
/// 而那个语义色在深色下会被桌面壁纸染色，于是卡片泛蓝、和暖调底色打架。深色取
/// 中性黑（原发布物料卡片那一档），浅色取白——白卡片在暖灰底上正好浮起来。
///
/// 选中态是抬高的中性面而不是强调色：强调色只留给动作与状态，琥珀只表示草稿，
/// 红色只表示待复核计数。语义色在浅色下取更深的变体，保证对比度。
enum WorkshopPalette {
    static let canvas = adaptive(light: 0xF5F3F1, dark: 0x2A2827)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let navDivider = adaptive(light: 0xE3E0DC, dark: 0x3A3735)
    static let rowHover = adaptive(light: 0xEAE7E3, dark: 0x35322F)
    static let rowSelected = adaptive(light: 0xDCD8D2, dark: 0x403C39)
    static let textPrimary = adaptive(light: 0x1C1B1A, dark: 0xEDEDEA)
    static let textSecondary = adaptive(light: 0x5E5A55, dark: 0x9A9793)
    /// 深色下随底色一起抬高：留在原来的 0x6B6865 会跌到 2.6:1。
    static let textTertiary = adaptive(light: 0x8A8580, dark: 0x807C78)
    static let draft = adaptive(light: 0x9A6710, dark: 0xD9A441)
    static let published = adaptive(light: 0x2C6E3B, dark: 0x5FA96A)
    static let attention = adaptive(light: 0xA82D28, dark: 0xD9635F)

    /// 稿件状态的唯一取色口，避免各视图各自判断字符串。
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "已发布": published
        case "已归档": textTertiary
        default: draft
        }
    }

    /// 用 AppKit 的动态色而不是读环境里的 `colorScheme`：这样一个静态常量就能
    /// 在两种外观下各自解析，视图不必把外观一路传下去。
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum WorkshopEditorStyle {
    case prose
    case code

    var font: Font {
        switch self {
        case .prose:
            return .body
        case .code:
            return .system(.callout, design: .monospaced)
        }
    }
}

/// Consistent label, editor and guidance treatment for substantial text fields.
struct WorkshopLabeledEditor: View {
    let title: String
    @Binding var text: String
    let minimumHeight: CGFloat
    let hint: String
    let style: WorkshopEditorStyle

    init(
        _ title: String,
        text: Binding<String>,
        minimumHeight: CGFloat,
        hint: String = "",
        style: WorkshopEditorStyle = .prose
    ) {
        self.title = title
        _text = text
        self.minimumHeight = minimumHeight
        self.hint = hint
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkshopMetrics.fieldSpacing) {
            Text(title)
                .font(.caption.weight(.semibold))

            TextEditor(text: $text)
                .font(style.font)
                .scrollContentBackground(.hidden)
                .padding(WorkshopMetrics.controlSpacing)
                .frame(maxWidth: .infinity, minHeight: minimumHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: WorkshopMetrics.controlCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: WorkshopMetrics.controlCornerRadius)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityLabel(title)
                .accessibilityHint(hint)

            if !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 右列的顶栏：左边是「组 / 当前屏」的面包屑，右边是这一屏的动作。
/// 两列结构下右列一次只做一件事，所以每屏都要自报家门。
struct WorkshopScreenHeader<Actions: View>: View {
    let group: String
    let title: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: WorkshopMetrics.stackSpacing) {
            HStack(spacing: WorkshopMetrics.fieldSpacing) {
                Text(group)
                    .foregroundStyle(WorkshopPalette.textTertiary)
                Text("/")
                    .foregroundStyle(WorkshopPalette.textTertiary)
                Text(title)
                    .fontWeight(.medium)
            }
            .font(.callout)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group)，\(title)")

            Spacer(minLength: WorkshopMetrics.stackSpacing)

            actions()
                .controlSize(.small)
        }
        .padding(.horizontal, WorkshopMetrics.pagePadding)
        .padding(.vertical, WorkshopMetrics.stackSpacing)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkshopPalette.navDivider)
                .frame(height: 1)
        }
    }
}

/// 状态栏右侧的一条只读读数。24.13 起它还承接了原 Inspector「上下文」分段里
/// 那些不值得占一个导航目的地的信息：字数、诊断分、运行后端。
struct WorkshopStatusMetric: Hashable {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// The app-level operation surface. It reports the Store's current state on every
/// workspace screen and exposes cancellation only while it is actually available.
///
/// 24.13：状态栏移入右列（左列底部改放设置与运行标识），并接过原 Inspector
/// 「上下文」分段的读数。
struct WorkshopOperationStatusBar: View {
    let text: String
    let isRunning: Bool
    let canCancel: Bool
    let metrics: [WorkshopStatusMetric]
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: WorkshopMetrics.controlSpacing) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("任务正在运行")
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(text)
                .accessibilityLabel("当前状态：\(text)")

            if canCancel {
                Button("取消", role: .cancel, action: onCancel)
                    .controlSize(.small)
                    .accessibilityHint("停止当前生成任务")
            }

            Spacer(minLength: WorkshopMetrics.stackSpacing)

            ForEach(metrics, id: \.self) { metric in
                HStack(spacing: 4) {
                    Text(metric.label)
                        .foregroundStyle(WorkshopPalette.textTertiary)
                    Text(metric.value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(metric.label)：\(metric.value)")
            }
        }
        .padding(.horizontal, WorkshopMetrics.stackSpacing)
        .frame(maxWidth: .infinity, minHeight: WorkshopMetrics.statusBarHeight)
        .background(WorkshopPalette.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WorkshopPalette.navDivider)
                .frame(height: 1)
        }
    }
}
