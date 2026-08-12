import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CreativeWorkshopCore

struct WeChatFormatterView: View {
    let title: String
    let summary: String
    let content: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("wechatFormatter.theme") private var selectedThemeKey = "wechat"
    @AppStorage("wechatFormatter.customCSS") private var customCSS = ""
    @StateObject private var controller = WeChatFormatterController()
    @State private var isShowingCSSEditor = false
    @State private var cssDraft = ""

    private var document: WeChatFormatterDocument {
        WeChatFormatterDocument(title: title, summary: summary, content: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            ZStack {
                WeChatFormatterWebView(controller: controller)

                if !controller.isReady {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(controller.statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 980, idealWidth: 1_140, minHeight: 680, idealHeight: 780)
        .onAppear {
            controller.update(document: document)
            controller.prepare(themeKey: selectedThemeKey, customCSS: customCSS)
        }
        .onChange(of: document) { newDocument in
            controller.update(document: newDocument)
        }
        .onChange(of: selectedThemeKey) { newTheme in
            customCSS = ""
            controller.applyTheme(newTheme)
        }
        .sheet(isPresented: $isShowingCSSEditor) {
            WeChatFormatterCSSEditor(
                css: $cssDraft,
                onApply: {
                    customCSS = cssDraft
                    controller.applyCustomCSS(cssDraft)
                },
                onRestoreTheme: {
                    customCSS = ""
                    controller.applyTheme(selectedThemeKey)
                }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("公众号排版", systemImage: "doc.richtext")
                .font(.headline)

            Picker("主题", selection: $selectedThemeKey) {
                ForEach(WeChatFormatterTheme.all) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            .frame(width: 176)
            .disabled(!controller.isReady || controller.isWorking)

            Button {
                controller.fetchCurrentCSS { css in
                    cssDraft = css
                    isShowingCSSEditor = true
                }
            } label: {
                Label("自定义样式", systemImage: "paintbrush")
            }
            .disabled(!controller.isReady || controller.isWorking)

            Button {
                controller.chooseImages()
            } label: {
                Label(
                    controller.imageCount > 0 ? "图片 \(controller.imageCount)" : "载入图片",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            .disabled(!controller.isReady || controller.isWorking)
            .help("选择图片文件或 Obsidian 附件文件夹，解析正文中的本地图片引用。")

            Spacer()

            Menu {
                Button("导出 Markdown") {
                    controller.exportMarkdown(document)
                }
                Button("导出微信 HTML") {
                    controller.exportHTML(document)
                }
                Divider()
                Button("导出 PNG") {
                    controller.exportImage(format: .png, document: document)
                }
                Button("导出 JPG") {
                    controller.exportImage(format: .jpeg, document: document)
                }
                Button("导出 PDF") {
                    controller.exportPDF(document: document)
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
            }
            .disabled(!controller.isReady || controller.isWorking)

            Button {
                controller.copyForWeChat(document: document)
            } label: {
                Label("复制到公众号", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.isReady || controller.isWorking || document.contentIsEmpty)

            Button("完成") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            if controller.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(controller.statusText)
                .foregroundStyle(controller.hasError ? Color.red : Color.secondary)
                .lineLimit(1)
            Spacer()
            Text("正文 \(content.count) 字 · 约 \(document.readingMinutes) 分钟")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct WeChatFormatterCSSEditor: View {
    @Binding var css: String
    let onApply: () -> Void
    let onRestoreTheme: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义公众号样式")
                .font(.title3.weight(.semibold))
            Text("选择器会自动限定在预览区域。修改后可以立即预览，并保存在本机。")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $css)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 720, minHeight: 460)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

            HStack {
                Button("恢复当前主题") {
                    onRestoreTheme()
                    dismiss()
                }
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("应用") {
                    onApply()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }
}

struct WeChatFormatterWebView: NSViewRepresentable {
    @ObservedObject var controller: WeChatFormatterController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        controller.connect(webView)

        do {
            let url = try WeChatFormatterResource.htmlURL()
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } catch {
            controller.fail(error)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.connect(webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let controller: WeChatFormatterController

        init(controller: WeChatFormatterController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller.didFinishLoading(webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            controller.fail(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            controller.fail(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

struct WeChatFormatterDocument: Equatable {
    let title: String
    let summary: String
    let content: String

    var markdown: String {
        ArticleExportFormatter.articleContent(
            format: .markdown,
            title: title,
            summary: summary,
            content: content
        )
    }

    var plainText: String {
        [title, summary, content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var contentIsEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var readingMinutes: Int {
        max(1, Int(ceil(Double(max(1, content.count)) / 400.0)))
    }

    var suggestedFilename: String {
        let clean = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[/:*?\"<>|]", with: "-", options: .regularExpression)
        return clean.isEmpty ? "微信文章" : String(clean.prefix(80))
    }
}

struct WeChatFormatterTheme: Identifiable, Equatable {
    let id: String
    let name: String

    static let all: [WeChatFormatterTheme] = [
        .init(id: "default", name: "默认清新"),
        .init(id: "wechat", name: "微信官方"),
        .init(id: "elegant", name: "优雅古典"),
        .init(id: "tech", name: "科技极客"),
        .init(id: "warm", name: "暖色温馨"),
        .init(id: "minimal", name: "极简留白"),
        .init(id: "academic", name: "学术论文"),
        .init(id: "night", name: "暗夜护眼"),
        .init(id: "handwriting", name: "手写笔记"),
        .init(id: "poetry", name: "诗歌雅韵"),
        .init(id: "poetry_gilded", name: "诗歌·鎏金信笺"),
        .init(id: "poetry_moonlight", name: "诗歌·月光绢帛"),
        .init(id: "xiaohongshu", name: "小红书"),
        .init(id: "sticker", name: "便签贴纸"),
        .init(id: "halloween", name: "万圣节"),
        .init(id: "christmas", name: "圣诞节"),
        .init(id: "gradient", name: "渐变流光"),
        .init(id: "xhs_grid", name: "网格笔记"),
        .init(id: "xhs_doodle", name: "手绘涂鸦")
    ]
}

enum WeChatFormatterResource {
    enum ResourceError: LocalizedError {
        case missingHTML

        var errorDescription: String? {
            "公众号排版资源未被打包进应用。"
        }
    }

    static func htmlURL() throws -> URL {
        if let url = WorkshopResourceBundle.bundle.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WeChatFormatter"
        ) {
            return url
        }
        throw ResourceError.missingHTML
    }
}

@MainActor
final class WeChatFormatterController: NSObject, ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isWorking = false
    @Published private(set) var hasError = false
    @Published private(set) var imageCount = 0
    @Published private(set) var statusText = "正在载入排版引擎…"

    private weak var webView: WKWebView?
    private var document = WeChatFormatterDocument(title: "", summary: "", content: "")
    private var themeKey = "wechat"
    private var customCSS = ""

    func connect(_ webView: WKWebView) {
        self.webView = webView
    }

    func prepare(themeKey: String, customCSS: String) {
        self.themeKey = themeKey
        self.customCSS = customCSS
        synchronizeIfReady()
    }

    func update(document: WeChatFormatterDocument) {
        self.document = document
        synchronizeIfReady()
    }

    func didFinishLoading(_ webView: WKWebView) {
        connect(webView)
        webView.evaluateJavaScript(Self.bridgeScript) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.fail(error)
                return
            }

            if let readiness = result as? [String: Any],
               readiness["ready"] as? Bool == false {
                let missing = (readiness["missing"] as? [String])?.joined(separator: "、") ?? "网页依赖"
                self.fail(FormatterError.message("排版资源加载失败：\(missing)。请重新构建或安装应用。"))
                return
            }

            self.isReady = true
            self.hasError = false
            self.statusText = "排版工具已就绪"
            self.synchronizeIfReady()
        }
    }

    func fail(_ error: Error) {
        isWorking = false
        isReady = false
        hasError = true
        statusText = error.localizedDescription
    }

    func applyTheme(_ key: String) {
        themeKey = key
        customCSS = ""
        guard isReady else { return }
        evaluate("window.creativeWorkshopSetTheme(\(Self.javaScriptLiteral(key)));", success: "已应用主题")
    }

    func applyCustomCSS(_ css: String) {
        customCSS = css
        guard isReady else { return }
        evaluate("window.creativeWorkshopSetCustomCSS(\(Self.javaScriptLiteral(css)));", success: "已应用自定义样式")
    }

    func fetchCurrentCSS(completion: @escaping (String) -> Void) {
        guard let webView, isReady else {
            completion(customCSS)
            return
        }
        webView.evaluateJavaScript("window.creativeWorkshopGetCSS();") { [weak self] result, error in
            if let error {
                self?.fail(error)
                completion(self?.customCSS ?? "")
                return
            }
            completion(result as? String ?? self?.customCSS ?? "")
        }
    }

    func copyForWeChat(document: WeChatFormatterDocument) {
        guard !document.contentIsEmpty else {
            statusText = "正文为空，无法复制"
            return
        }
        isWorking = true
        hasError = false
        statusText = "正在生成微信公众号富文本…"
        generateWechatHTML { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let html):
                let item = NSPasteboardItem()
                item.setString(html, forType: .html)
                item.setString(document.plainText, forType: .string)
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.writeObjects([item]) {
                    self.statusText = "已复制富文本，可直接粘贴到公众号编辑器"
                } else {
                    self.fail(FormatterError.message("写入系统剪贴板失败。"))
                }
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    func exportMarkdown(_ document: WeChatFormatterDocument) {
        save(
            data: Data(document.markdown.utf8),
            filename: "\(document.suggestedFilename).md",
            contentType: UTType(filenameExtension: "md") ?? .plainText,
            successMessage: "已导出 Markdown"
        )
    }

    func exportHTML(_ document: WeChatFormatterDocument) {
        isWorking = true
        hasError = false
        statusText = "正在生成微信 HTML…"
        generateWechatHTML { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let body):
                let html = """
                <!doctype html>
                <html lang="zh-CN">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>\(Self.escapeHTML(document.title))</title>
                </head>
                <body>\(body)</body>
                </html>
                """
                self.save(
                    data: Data(html.utf8),
                    filename: "\(document.suggestedFilename).html",
                    contentType: .html,
                    successMessage: "已导出微信 HTML"
                )
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    func exportPDF(document: WeChatFormatterDocument) {
        guard let webView, isReady else { return }
        isWorking = true
        hasError = false
        statusText = "正在生成 PDF…"
        pageRect { [weak self, weak webView] result in
            guard let self, let webView else { return }
            switch result {
            case .failure(let error):
                self.fail(error)
            case .success(let rect):
                let configuration = WKPDFConfiguration()
                configuration.rect = rect
                webView.createPDF(configuration: configuration) { result in
                    self.isWorking = false
                    switch result {
                    case .success(let data):
                        self.save(
                            data: data,
                            filename: "\(document.suggestedFilename).pdf",
                            contentType: .pdf,
                            successMessage: "已导出 PDF"
                        )
                    case .failure(let error):
                        self.fail(error)
                    }
                }
            }
        }
    }

    enum ImageFormat {
        case png
        case jpeg

        var contentType: UTType { self == .png ? .png : .jpeg }
        var fileExtension: String { self == .png ? "png" : "jpg" }
        var bitmapType: NSBitmapImageRep.FileType { self == .png ? .png : .jpeg }
        var properties: [NSBitmapImageRep.PropertyKey: Any] {
            self == .png ? [:] : [.compressionFactor: 0.92]
        }
    }

    func exportImage(format: ImageFormat, document: WeChatFormatterDocument) {
        guard let webView, isReady else { return }
        isWorking = true
        hasError = false
        statusText = "正在生成 \(format.fileExtension.uppercased()) 图片…"
        pageRect { [weak self, weak webView] result in
            guard let self, let webView else { return }
            switch result {
            case .failure(let error):
                self.fail(error)
            case .success(let rect):
                let configuration = WKSnapshotConfiguration()
                configuration.rect = rect
                configuration.snapshotWidth = 1_200
                webView.takeSnapshot(with: configuration) { image, error in
                    self.isWorking = false
                    if let error {
                        self.fail(error)
                        return
                    }
                    guard let tiff = image?.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let data = bitmap.representation(using: format.bitmapType, properties: format.properties) else {
                        self.fail(FormatterError.message("图片编码失败。"))
                        return
                    }
                    self.save(
                        data: data,
                        filename: "\(document.suggestedFilename).\(format.fileExtension)",
                        contentType: format.contentType,
                        successMessage: "已导出 \(format.fileExtension.uppercased()) 图片"
                    )
                }
            }
        }
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "选择图片或 Obsidian 附件文件夹"
        panel.prompt = "载入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            self.isWorking = true
            self.hasError = false
            self.statusText = "正在读取图片…"

            Task.detached(priority: .userInitiated) {
                let imported = Self.collectImages(from: urls)
                await MainActor.run {
                    self.send(images: imported)
                }
            }
        }
    }

    private func synchronizeIfReady() {
        guard let webView, isReady else { return }
        let payload = ["markdown": document.markdown]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            fail(FormatterError.message("稿件内容无法传入排版工具。"))
            return
        }

        let cssCommand = customCSS.isEmpty
            ? "window.creativeWorkshopSetTheme(\(Self.javaScriptLiteral(themeKey)));"
            : "window.creativeWorkshopSetTheme(\(Self.javaScriptLiteral(themeKey)));window.creativeWorkshopSetCustomCSS(\(Self.javaScriptLiteral(customCSS)));"
        webView.evaluateJavaScript("window.creativeWorkshopSetDocument(\(json));\(cssCommand)") { [weak self] _, error in
            if let error {
                self?.fail(error)
            } else {
                self?.statusText = "已同步当前稿件"
            }
        }
    }

    private func evaluate(_ script: String, success: String) {
        guard let webView else { return }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.fail(error)
            } else {
                self?.hasError = false
                self?.statusText = success
            }
        }
    }

    private func generateWechatHTML(completion: @escaping (Result<String, Error>) -> Void) {
        guard let webView, isReady else {
            completion(.failure(FormatterError.message("排版工具尚未载入完成。")))
            return
        }
        webView.callAsyncJavaScript(
            "return await window.creativeWorkshopNativeHTML();",
            arguments: [:],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .success(let value):
                guard let html = value as? String, !html.isEmpty else {
                    completion(.failure(FormatterError.message("没有生成可复制的 HTML。")))
                    return
                }
                completion(.success(html))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func pageRect(completion: @escaping (Result<CGRect, Error>) -> Void) {
        guard let webView, isReady else {
            completion(.failure(FormatterError.message("排版工具尚未载入完成。")))
            return
        }
        webView.callAsyncJavaScript(
            "return window.creativeWorkshopPageSize();",
            arguments: [:],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let value):
                guard let size = value as? [String: Any],
                      let width = (size["width"] as? NSNumber)?.doubleValue,
                      let height = (size["height"] as? NSNumber)?.doubleValue else {
                    completion(.failure(FormatterError.message("无法读取预览尺寸。")))
                    return
                }
                completion(.success(CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height))))
            }
        }
    }

    private func send(images: [ImportedImage]) {
        guard let webView, isReady else {
            isWorking = false
            return
        }
        guard !images.isEmpty else {
            isWorking = false
            statusText = "所选位置没有可用图片"
            return
        }

        let arguments: [String: Any] = [
            "images": images.map {
                ["name": $0.name, "relativePath": $0.relativePath, "dataURL": $0.dataURL]
            }
        ]
        webView.callAsyncJavaScript(
            "return window.creativeWorkshopImportImages(images);",
            arguments: arguments,
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let value):
                let added = (value as? NSNumber)?.intValue ?? images.count
                self.imageCount += added
                self.statusText = "已载入 \(added) 张图片"
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func save(
        data: Data,
        filename: String,
        contentType: UTType,
        successMessage: String
    ) {
        let panel = NSSavePanel()
        panel.title = "导出公众号排版文件"
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "已取消导出"
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            hasError = false
            statusText = successMessage
        } catch {
            fail(error)
        }
    }

    private struct ImportedImage: Sendable {
        let name: String
        let relativePath: String
        let dataURL: String
    }

    nonisolated private static func collectImages(from roots: [URL]) -> [ImportedImage] {
        var seen = Set<URL>()
        var output: [ImportedImage] = []

        for root in roots {
            let accessed = root.startAccessingSecurityScopedResource()
            defer {
                if accessed { root.stopAccessingSecurityScopedResource() }
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let fileURL = enumerator?.nextObject() as? URL {
                    let relative = String(fileURL.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    appendImage(fileURL, relativePath: relative, seen: &seen, output: &output)
                }
            } else {
                appendImage(root, relativePath: root.lastPathComponent, seen: &seen, output: &output)
            }
        }
        return output
    }

    nonisolated private static func appendImage(
        _ url: URL,
        relativePath: String,
        seen: inout Set<URL>,
        output: inout [ImportedImage]
    ) {
        guard seen.insert(url.standardizedFileURL).inserted,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let data = try? Data(contentsOf: url) else { return }
        let mime = type.preferredMIMEType ?? "application/octet-stream"
        output.append(
            ImportedImage(
                name: url.lastPathComponent,
                relativePath: relativePath.isEmpty ? url.lastPathComponent : relativePath,
                dataURL: "data:\(mime);base64,\(data.base64EncodedString())"
            )
        )
    }

    private enum FormatterError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let value): return value
            }
        }
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let bridgeScript = #"""
    (() => {
        if (window.creativeWorkshopBridgeInstalled) {
            return { ready: getMissingCoreDependencies().length === 0, missing: getMissingCoreDependencies() };
        }
        window.creativeWorkshopBridgeInstalled = true;

        document.body.classList.add('creative-workshop-embedded');
        const embeddedStyle = document.createElement('style');
        embeddedStyle.id = 'creative-workshop-embedded-style';
        embeddedStyle.textContent = `
            html, body {
                height: auto !important;
                min-height: 100% !important;
                overflow: visible !important;
                background: #eef1f5 !important;
            }
            body.creative-workshop-embedded .header,
            body.creative-workshop-embedded .main-container > .panel:first-child,
            body.creative-workshop-embedded .main-container > .panel:last-child > .panel-header,
            body.creative-workshop-embedded #toc-panel {
                display: none !important;
            }
            body.creative-workshop-embedded .main-container {
                display: block !important;
                height: auto !important;
                min-height: 100vh !important;
                padding: 0 !important;
                overflow: visible !important;
            }
            body.creative-workshop-embedded .main-container > .panel:last-child {
                display: block !important;
                height: auto !important;
                min-height: 100vh !important;
                border: 0 !important;
                border-radius: 0 !important;
                overflow: visible !important;
                background: #eef1f5 !important;
            }
            body.creative-workshop-embedded #preview-scroll {
                height: auto !important;
                min-height: 100vh !important;
                overflow: visible !important;
                padding: 28px !important;
                background: #eef1f5 !important;
            }
            body.creative-workshop-embedded #preview-container {
                box-sizing: border-box !important;
                width: min(100%, 780px) !important;
                min-height: calc(100vh - 56px) !important;
                margin: 0 auto !important;
                background-color: #fff;
                box-shadow: 0 10px 32px rgba(15, 23, 42, 0.12);
            }
            body.creative-workshop-embedded .toast {
                position: fixed !important;
            }
        `;
        document.head.appendChild(embeddedStyle);

        window.creativeWorkshopSetDocument = (payload) => {
            const input = document.getElementById('markdown-input');
            input.value = payload && typeof payload.markdown === 'string' ? payload.markdown : '';
            renderPreview();
            updateStats();
            window.scrollTo({ top: 0, behavior: 'instant' });
            return true;
        };

        window.creativeWorkshopSetTheme = (key) => {
            if (!themes[key]) return false;
            selectTheme(key);
            currentCss = themes[key].css;
            localStorage.setItem('wxArticleCss', currentCss);
            localStorage.setItem('wxArticleTheme', currentTheme);
            localStorage.setItem('wxArticleStyleVersion', STYLE_VERSION);
            applyCurrentCss();
            return true;
        };

        window.creativeWorkshopSetCustomCSS = (css) => {
            currentCss = typeof css === 'string' ? css : '';
            localStorage.setItem('wxArticleCss', currentCss);
            localStorage.setItem('wxArticleTheme', currentTheme);
            applyCurrentCss();
            return true;
        };

        window.creativeWorkshopGetCSS = () => currentCss;

        window.creativeWorkshopImportImages = (images) => {
            if (!Array.isArray(images)) return 0;
            images.forEach((image) => {
                addImageToCache(image.name, image.dataURL, image.relativePath || image.name);
            });
            updateImageButton();
            renderPreview();
            return images.length;
        };

        window.creativeWorkshopNativeHTML = async () => {
            const container = document.getElementById('preview-container');
            if (!container || !container.children.length) return '';

            const tempDiv = document.createElement('div');
            tempDiv.id = 'temp-copy-container';
            tempDiv.innerHTML = container.innerHTML;
            tempDiv.style.position = 'absolute';
            tempDiv.style.left = '0';
            tempDiv.style.top = '0';
            tempDiv.style.zIndex = '-1';
            tempDiv.style.width = `${Math.max(320, Math.round(container.getBoundingClientRect().width || 780))}px`;
            document.body.appendChild(tempDiv);

            const previewStyle = document.getElementById('custom-style');
            let tempStyle = null;
            try {
                if (previewStyle) {
                    tempStyle = document.createElement('style');
                    tempStyle.textContent = previewStyle.textContent.replace(/#preview-container/g, '#temp-copy-container');
                    document.head.appendChild(tempStyle);
                }
                await new Promise((resolve) => setTimeout(resolve, 50));
                await preprocessWechatCopyContainer(tempDiv);
                return generateWechatHtml(tempDiv);
            } finally {
                if (tempStyle) tempStyle.remove();
                tempDiv.remove();
            }
        };

        window.creativeWorkshopPageSize = () => ({
            width: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth, window.innerWidth),
            height: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, window.innerHeight)
        });

        const missing = getMissingCoreDependencies();
        return { ready: missing.length === 0, missing };
    })();
    """#
}
