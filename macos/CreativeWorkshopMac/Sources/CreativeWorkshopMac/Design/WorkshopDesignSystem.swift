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
    static let statusBarHeight: CGFloat = 30
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

/// The app-level operation surface. It reports the Store's current state on every
/// workspace screen and exposes cancellation only while it is actually available.
struct WorkshopOperationStatusBar: View {
    let text: String
    let isRunning: Bool
    let canCancel: Bool
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

            Spacer(minLength: WorkshopMetrics.stackSpacing)

            if canCancel {
                Button("取消", role: .cancel, action: onCancel)
                    .controlSize(.small)
                    .accessibilityHint("停止当前生成任务")
            }
        }
        .padding(.horizontal, WorkshopMetrics.stackSpacing)
        .frame(maxWidth: .infinity, minHeight: WorkshopMetrics.statusBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
