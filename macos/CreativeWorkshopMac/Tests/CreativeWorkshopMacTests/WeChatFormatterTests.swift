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
