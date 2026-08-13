import Foundation

/// 正文选区与片段定位的纯逻辑（24.15 从 `WorkshopStore` 抽出）。
///
/// 这些规则是业务约束，不是 UI 投影：
/// - 定位 issue 片段只接受一次精确匹配，找不到就返回 nil。调用方必须据此提示
///   「未找到对应片段」，**不能猜一个近似位置**（18.3.1）。
/// - 替换只在选区内容仍与预期一致时发生，否则拒绝——正文在生成期间可能已被改动。
///
/// 抽成值类型后这些不变量可以脱离 `@MainActor` 的 Store 独立验证。
package struct DraftTextLocator {
    package let text: String

    package init(_ text: String) {
        self.text = text
    }

    /// 选区对应的文字；空选区或越界返回 nil。
    package func selectedText(in range: NSRange) -> String? {
        guard range.length > 0, let swiftRange = Range(range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    /// 按 `excerpt` 在正文中定位一次精确匹配。找不到返回 nil。
    package func locate(excerpt: String?) -> NSRange? {
        guard let excerpt else { return nil }
        let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let swiftRange = text.range(of: trimmed) else {
            return nil
        }
        return NSRange(swiftRange, in: text)
    }

    /// 选区前后各取 `radius` 个字符作为改写上下文；越界时退化为正文开头一段。
    package func context(around range: NSRange, radius: Int = 800) -> String {
        guard let swiftRange = Range(range, in: text) else {
            return String(text.prefix(radius * 2))
        }
        let leadingDistance = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
        let trailingDistance = text.distance(from: swiftRange.upperBound, to: text.endIndex)
        let lowerBound = text.index(swiftRange.lowerBound, offsetBy: -min(radius, leadingDistance))
        let upperBound = text.index(swiftRange.upperBound, offsetBy: min(radius, trailingDistance))
        return String(text[lowerBound..<upperBound])
    }

    /// 仅当选区内容仍等于 `expectedText` 时替换，返回新正文与替换后的选区。
    /// 内容已经变了就返回 nil——调用方必须放弃这次替换，不能强写。
    package func replacing(
        range: NSRange,
        expectedText: String,
        with replacement: String
    ) -> (text: String, selection: NSRange)? {
        guard let swiftRange = Range(range, in: text),
              String(text[swiftRange]) == expectedText else {
            return nil
        }

        var updated = text
        updated.replaceSubrange(swiftRange, with: replacement)
        return (updated, NSRange(location: range.location, length: replacement.utf16.count))
    }
}
