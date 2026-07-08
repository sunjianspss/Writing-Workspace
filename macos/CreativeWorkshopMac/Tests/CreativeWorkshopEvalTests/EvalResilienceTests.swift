import XCTest
@testable import CreativeWorkshopEval

/// 评测韧性修缮（第二轮评测离线事故后）：离线熔断检测器 + --cases 过滤。
final class EvalResilienceTests: XCTestCase {
    func testInstantOfflineFailureIsDetected() {
        XCTAssertTrue(OfflineBreaker.isInstantNetworkFailure(
            success: false,
            error: "模型服务连接失败：The Internet connection appears to be offline.",
            elapsedMS: 3
        ))
        XCTAssertTrue(OfflineBreaker.isInstantNetworkFailure(
            success: false,
            error: "调用失败：The network connection was lost.",
            elapsedMS: 800
        ))
    }

    func testSlowTimeoutIsNotTreatedAsOffline() {
        XCTAssertFalse(
            OfflineBreaker.isInstantNetworkFailure(success: false, error: "The request timed out.", elapsedMS: 240_000),
            "慢超时是真实信号，不该触发离线熔断"
        )
        XCTAssertFalse(
            OfflineBreaker.isInstantNetworkFailure(success: false, error: "The network connection was lost.", elapsedMS: 533_000),
            "耗时较长的连接中断包含真实工作，不该被当作瞬时失败丢弃"
        )
    }

    func testSuccessOrNonNetworkErrorNotTreatedAsOffline() {
        XCTAssertFalse(OfflineBreaker.isInstantNetworkFailure(success: true, error: "", elapsedMS: 1))
        XCTAssertFalse(OfflineBreaker.isInstantNetworkFailure(success: false, error: "模型返回内容不是有效 JSON。", elapsedMS: 10))
    }

    func testCaseFilterKeepsDirectoryOrderAndRejectsUnknownIDs() throws {
        let cases = [
            EvalCase(id: "case-01", kind: "idea", idea: "想法一想法一想法一", direction: "随笔", materials: "", content: ""),
            EvalCase(id: "case-02", kind: "idea", idea: "想法二想法二想法二", direction: "随笔", materials: "", content: ""),
            EvalCase(id: "case-03", kind: "idea", idea: "想法三想法三想法三", direction: "随笔", materials: "", content: "")
        ]

        let filtered = try CaseFilter.apply(["case-03", "case-01"], to: cases)
        XCTAssertEqual(filtered.map(\.id), ["case-01", "case-03"], "结果应保持目录排序而非参数顺序")

        do {
            _ = try CaseFilter.apply(["case-99"], to: cases)
            XCTFail("未知用例 id 应抛错")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("case-99"))
            XCTAssertTrue(error.localizedDescription.contains("case-01"), "错误信息应列出可选 id")
        }
    }
}
