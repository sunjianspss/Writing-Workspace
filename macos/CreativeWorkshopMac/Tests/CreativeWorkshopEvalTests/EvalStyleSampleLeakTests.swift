import XCTest
@testable import CreativeWorkshopEval

/// 评测风格样本的防泄漏守卫（PRD 24.4）。
///
/// 评测用例按「一鱼两吃」惯例取自作者的真实文章，而风格样本也来自同一批文章。
/// 一旦某篇文章同时充当「某条用例的答案」和「风格样本」，模型照抄样本即可拿高分，
/// 量具当场失效。自动识别同源不可靠（`articles.id=11` 带 YAML frontmatter，
/// 而 case-25 是 `# 鸳鸯` 开头，前缀指纹认不出来），因此这里改用
/// **任意位置的长公共子串**做判定，并要求样本文章不得是任何用例的来源。
final class EvalStyleSampleLeakTests: XCTestCase {
    /// 判定阈值：连续 60 个字（去空白后）完全相同即视为同源。正常的题材重合
    /// （都写红楼梦）不会产生这么长的逐字重合，而同一篇文章必然远超此长度。
    private let leakRunLength = 60

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CreativeWorkshopEvalTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CreativeWorkshopMac
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // <repo>
    }

    func testStyleSamplesAreNotTheSourceOfAnyEvalCase() throws {
        let evalsDir = repositoryRoot.appendingPathComponent("evals")
        let samples = try EvalStyleSampleLoader.load(from: evalsDir.appendingPathComponent("style_samples"))
        try XCTSkipIf(samples.isEmpty, "evals/style_samples 为空，本轮按零样本配置运行，无泄漏可言")

        let cases = try EvalCaseLoader.loadCases(from: evalsDir.appendingPathComponent("cases"))
        XCTAssertFalse(cases.isEmpty, "没有读到任何用例，守卫失去意义")

        for sample in samples {
            let sampleText = normalized(sample.text)
            for evalCase in cases {
                let caseText = normalized(evalCase.content + evalCase.idea)
                XCTAssertFalse(
                    hasCommonRun(sampleText, caseText, length: leakRunLength),
                    """
                    风格样本「\(sample.name)」与用例 \(evalCase.id) 有 \(leakRunLength) 字以上的逐字重合，\
                    说明它同时是该用例的来源。样本会把答案喂回模型，请改用一篇不做用例的文章。
                    """
                )
            }
        }
    }

    private func normalized(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }

    /// 两段文本是否存在长度 >= `length` 的公共子串。对其中一段的全部定长窗口建集合，
    /// 再逐窗查另一段——保证不漏判（步进式抽样会因为对齐问题漏掉）。
    private func hasCommonRun(_ lhs: String, _ rhs: String, length: Int) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard left.count >= length, right.count >= length else {
            return false
        }
        var windows = Set<String>(minimumCapacity: right.count)
        for start in 0...(right.count - length) {
            windows.insert(String(right[start..<(start + length)]))
        }
        for start in 0...(left.count - length) where windows.contains(String(left[start..<(start + length)])) {
            return true
        }
        return false
    }
}
