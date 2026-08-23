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

    /// 复制到公众号时的半透明压平是纯函数，直接在 JSContext 里跑真实实现。
    /// 公众号编辑器可能丢掉 alpha，把 rgba(…) 当实心色渲染：万圣节 15% 的橙会
    /// 变成纯橙，tech 的半透明边框会变成实线亮边。所以复制前必须按主题纸底压平。
    func testWechatCopyFlattensTranslucentColorsAgainstThemePaper() throws {
        let html = try String(contentsOf: WeChatFormatterResource.htmlURL(), encoding: .utf8)
        var source = ""
        for name in ["hexToRgbTriplet", "flattenWechatAlpha"] {
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
            try XCTUnwrap(XCTUnwrap(context.evaluateScript(expression)).toString())
        }

        // 万圣节那种 15% 的橙，叠在浅纸上压平后仍是浅橙，而不是实心橙
        XCTAssertEqual(try evaluate("flattenWechatAlpha('rgba(255, 107, 0, 0.1)', '#ffffff')"), "#fff0e6")

        // 同一个颜色叠在深色纸上必须得到不同结果——证明压平真的用了纸底，
        // 而不是一律按白底算
        let onDark = try evaluate("flattenWechatAlpha('rgba(255, 107, 0, 0.1)', '#0d1117')")
        XCTAssertNotEqual(onDark, "#fff0e6", "深色纸底上的压平结果不能和白底相同")

        // 半透明还藏在 border 简写和渐变色标里（实测 tech 主题 22 处 rgba 中有
        // 16 处在 border-*、1 处在 background-image），必须整串替换
        let border = try evaluate("flattenWechatAlpha('1px solid rgba(0, 217, 255, 0.3)', '#1a1a2e')")
        XCTAssertFalse(border.contains("rgba("), "border 简写里的 rgba 必须一并压平")
        XCTAssertTrue(border.hasPrefix("1px solid #"), "压平后应保持 border 简写结构：\(border)")

        // 全透明必须保持透明。压成底色会毁掉多层背景的层叠——网格笔记的格子是两层
        // 渐变叠加，上层原本透明的部分若变成实心底色，会把下层横线整片盖掉，
        // 粘到公众号后网格整个消失（真实反馈修过一次）。
        XCTAssertEqual(try evaluate("flattenWechatAlpha('rgba(0, 0, 0, 0)', '#fefefe')"), "transparent")
        XCTAssertEqual(
            try evaluate("flattenWechatAlpha('linear-gradient(rgba(200,200,200,0.1) 1px, rgba(0,0,0,0) 1px)', '#fefefe')")
                .contains("transparent") ? "保留" : "被压平",
            "保留",
            "渐变里的全透明色标必须保留"
        )

        // 不含 alpha 的值必须原样返回，压平不能顺手改写别的东西
        XCTAssertEqual(try evaluate("flattenWechatAlpha('1px solid #dccdb4', '#faf6ee')"), "1px solid #dccdb4")

        // 源码级守卫：rgbToHex 不得再把 rgba(…) 原样吐出去
        let rgbToHexStart = try XCTUnwrap(html.range(of: "        function rgbToHex("))
        let rgbToHexEnd = try XCTUnwrap(html.range(of: "\n        }\n", range: rgbToHexStart.lowerBound..<html.endIndex))
        let rgbToHexBody = String(html[rgbToHexStart.lowerBound..<rgbToHexEnd.upperBound])
        XCTAssertTrue(rgbToHexBody.contains("flattenWechatAlpha"), "rgbToHex 必须把半透明压平后再返回")
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
