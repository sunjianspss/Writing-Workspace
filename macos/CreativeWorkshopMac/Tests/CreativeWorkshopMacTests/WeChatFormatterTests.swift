import JavaScriptCore
import XCTest
@testable import CreativeWorkshopMac

@MainActor
final class WeChatFormatterTests: XCTestCase {
    func testDocumentBuildsMarkdownFromCurrentArticleFields() {
        let document = WeChatFormatterDocument(
            title: "文章标题",
            summary: "摘要内容",
            content: "## 第一节\n\n正文"
        )

        XCTAssertEqual(
            document.markdown,
            "# 文章标题\n\n> 摘要内容\n\n## 第一节\n\n正文"
        )
        XCTAssertEqual(document.plainText, "文章标题\n\n摘要内容\n\n## 第一节\n\n正文")
        XCTAssertEqual(document.readingMinutes, 1)
        XCTAssertFalse(document.contentIsEmpty)
    }

    func testSuggestedFilenameRemovesCharactersForbiddenBySavePanelTargets() {
        let document = WeChatFormatterDocument(
            title: "  标题/:*?\"<>|测试  ",
            summary: "",
            content: "正文"
        )

        XCTAssertEqual(document.suggestedFilename, "标题--------测试")
        XCTAssertFalse(document.suggestedFilename.contains("/"), "已知非法文件名输入必须被净化")
    }

    func testBundledFormatterResourceKeepsAllDeclaredThemesAndBridgeDependencies() throws {
        let url = try WeChatFormatterResource.htmlURL()
        let html = try String(contentsOf: url, encoding: .utf8)
        let resourceDirectory = url.deletingLastPathComponent()

        XCTAssertGreaterThan(html.utf8.count, 150_000)
        XCTAssertTrue(html.contains("function renderPreview()"))
        XCTAssertTrue(html.contains("function generateWechatHtml(container)"))
        XCTAssertTrue(html.contains("function preprocessWechatCopyContainer(rootEl)"))
        XCTAssertTrue(html.contains("DOMPurify.sanitize"))

        XCTAssertEqual(WeChatFormatterTheme.all.count, 20)
        XCTAssertEqual(Set(WeChatFormatterTheme.all.map(\.id)).count, WeChatFormatterTheme.all.count)
        for theme in WeChatFormatterTheme.all {
            XCTAssertTrue(html.contains("            \(theme.id): {"), "资源中缺少主题：\(theme.id)")
        }
        XCTAssertTrue(WeChatFormatterController.bridgeScript.contains("currentCss = themes[key].css"))

        let localDependencies = [
            "vendor/marked.min.js",
            "vendor/purify.min.js",
            "vendor/highlight.min.js",
            "vendor/katex/katex.min.js",
            "vendor/katex/katex.min.css",
            "vendor/html2pdf.bundle.min.js",
            "vendor/html2canvas.min.js"
        ]
        for dependency in localDependencies {
            let fileURL = resourceDirectory.appending(path: dependency)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "缺少离线资源：\(dependency)")
            XCTAssertGreaterThan(try Data(contentsOf: fileURL).count, 1_000)
        }

        let headEnd = try XCTUnwrap(html.range(of: "</head>"))
        let documentHead = String(html[..<headEnd.lowerBound])
        XCTAssertFalse(documentHead.contains("src=\"https://"), "运行时脚本不得依赖 CDN")
        XCTAssertFalse(documentHead.contains("href=\"https://"), "运行时样式不得依赖 CDN")
        XCTAssertFalse(
            documentHead.contains(" integrity=\""),
            "通过 file:// 加载的本地资源不得携带会被 WebKit 拒绝的 SRI 元数据"
        )

        let katexCSS = try String(
            contentsOf: resourceDirectory.appending(path: "vendor/katex/katex.min.css"),
            encoding: .utf8
        )
        let fontPattern = try NSRegularExpression(pattern: #"url\(fonts/([^\)]+)\)"#)
        let fullRange = NSRange(katexCSS.startIndex..<katexCSS.endIndex, in: katexCSS)
        let fontNames = fontPattern.matches(in: katexCSS, range: fullRange).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: katexCSS) else { return nil }
            return String(katexCSS[range])
        }
        XCTAssertEqual(Set(fontNames).count, 60)
        for fontName in Set(fontNames) {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: resourceDirectory.appending(path: "vendor/katex/fonts/\(fontName)").path
                ),
                "缺少 KaTeX 字体：\(fontName)"
            )
        }
    }

    func testBundledInlineScriptAndNativeBridgeAreValidJavaScript() throws {
        let html = try String(contentsOf: WeChatFormatterResource.htmlURL(), encoding: .utf8)
        let marker = try XCTUnwrap(html.range(of: "<script>\n        // ==================== 主题配置"))
        let scriptStart = html.index(marker.lowerBound, offsetBy: "<script>".count)
        let scriptEnd = try XCTUnwrap(html.range(of: "</script>", range: scriptStart..<html.endIndex))
        let inlineScript = String(html[scriptStart..<scriptEnd.lowerBound])

        try assertValidJavaScript(inlineScript)
        try assertValidJavaScript(WeChatFormatterController.bridgeScript)
    }

    /// 复制到公众号时的颜色兜底逻辑是纯函数，直接在 JSContext 里跑真实实现。
    /// 这三条断言各自对应一个真实修过的故障：
    /// 1. 半透明底色必须压平成实色——公众号丢掉 alpha 会把 rgba(255,107,0,.1) 渲染成实心橙；
    /// 2. 深色纸底上的浅色前景不能被"修正"掉，否则暗夜护眼的标题会被压黑；
    /// 3. 白底上的近白前景必须被压深，否则粘出去就是白底白字。
    func testWechatCopyColorFallbacksSurviveHostileEditors() throws {
        let html = try String(contentsOf: WeChatFormatterResource.htmlURL(), encoding: .utf8)
        let helpers = ["rgbToHex", "flattenColorToHex", "copyContrastRatio", "ensureCopyContrast"]
        var source = "var activeWechatCopyBg = '#ffffff';\n"
        for name in helpers {
            let start = try XCTUnwrap(html.range(of: "        function \(name)("))
            let end = try XCTUnwrap(html.range(of: "\n        }\n", range: start.lowerBound..<html.endIndex))
            source += String(html[start.lowerBound..<end.upperBound]) + "\n"
        }

        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in
            XCTFail("JavaScript 执行错误：\(exception?.toString() ?? "未知错误")")
        }
        context.evaluateScript(source)
        XCTAssertNil(context.exception)

        func evaluate(_ expression: String) throws -> String {
            let value = try XCTUnwrap(context.evaluateScript(expression))
            return value.toString() ?? ""
        }

        // 1. 万圣节/圣诞节的底色是半透明的，必须按叠在白纸上压平
        XCTAssertEqual(try evaluate("flattenColorToHex('rgba(255, 107, 0, 0.1)')"), "#fff0e6")
        XCTAssertEqual(try evaluate("flattenColorToHex('rgb(13, 17, 23)')"), "#0d1117")

        // 2. 深色纸底上的浅色标题要原样保留（暗夜护眼 h1 = #f0f6fc）
        context.evaluateScript("activeWechatCopyBg = '#0d1117';")
        XCTAssertEqual(try evaluate("ensureCopyContrast('#f0f6fc')"), "#f0f6fc")

        // 3. 白纸底上的近白前景必须被压深到看得清
        context.evaluateScript("activeWechatCopyBg = '#ffffff';")
        let rescued = try evaluate("ensureCopyContrast('#f0f6fc')")
        XCTAssertNotEqual(rescued, "#f0f6fc", "白底上的近白色必须被压深")
        let ratio = try evaluate("copyContrastRatio('\(rescued)', '#ffffff')")
        XCTAssertGreaterThanOrEqual(Double(ratio) ?? 0, 3.0, "压深后至少要到 3:1")
    }

    private func assertValidJavaScript(_ script: String) throws {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in
            XCTFail("JavaScript 语法错误：\(exception?.toString() ?? "未知错误")")
        }
        let data = try JSONEncoder().encode(script)
        let literal = try XCTUnwrap(String(data: data, encoding: .utf8))
        let function = context.evaluateScript("new Function(\(literal))")
        XCTAssertFalse(function?.isUndefined ?? true)
        XCTAssertNil(context.exception)
    }

}
