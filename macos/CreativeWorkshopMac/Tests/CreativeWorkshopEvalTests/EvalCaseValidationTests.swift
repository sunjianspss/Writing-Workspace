import XCTest
@testable import CreativeWorkshopEval

final class EvalCaseValidationTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-case-validation-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeRawCase(_ json: String, fileName: String, in directory: URL) throws {
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent(fileName))
    }

    func testMissingRequiredFieldProducesActionableErrorNamingFileAndField() throws {
        let directory = try makeTempDirectory()
        try writeRawCase(
            """
            {"id": "case-01", "kind": "idea", "direction": "随笔", "materials": "", "content": ""}
            """,
            fileName: "case-01.json",
            in: directory
        )

        XCTAssertThrowsError(try EvalCaseLoader.loadCases(from: directory)) { error in
            guard let message = (error as? LocalizedError)?.errorDescription else {
                return XCTFail("期望可执行的错误信息")
            }
            XCTAssertTrue(message.contains("case-01.json"))
            XCTAssertTrue(message.contains("idea"))
        }
    }

    func testInvalidKindProducesActionableErrorNamingExpectedValues() throws {
        let directory = try makeTempDirectory()
        try writeRawCase(
            """
            {"id": "case-01", "kind": "outline", "idea": "写一篇关于独处的随笔",
             "direction": "随笔", "materials": "", "content": ""}
            """,
            fileName: "case-01.json",
            in: directory
        )

        XCTAssertThrowsError(try EvalCaseLoader.loadCases(from: directory)) { error in
            guard let message = (error as? LocalizedError)?.errorDescription else {
                return XCTFail("期望可执行的错误信息")
            }
            XCTAssertTrue(message.contains("case-01.json"))
            XCTAssertTrue(message.contains("kind"))
            XCTAssertTrue(message.contains("idea"))
            XCTAssertTrue(message.contains("draft"))
        }
    }

    func testIdeaShorterThanMinimumLengthIsRejected() throws {
        let directory = try makeTempDirectory()
        try writeRawCase(
            """
            {"id": "case-01", "kind": "idea", "idea": "太短", "direction": "随笔", "materials": "", "content": ""}
            """,
            fileName: "case-01.json",
            in: directory
        )

        XCTAssertThrowsError(try EvalCaseLoader.loadCases(from: directory)) { error in
            guard let message = (error as? LocalizedError)?.errorDescription else {
                return XCTFail("期望可执行的错误信息")
            }
            XCTAssertTrue(message.contains("case-01.json"))
            XCTAssertTrue(message.contains("idea"))
        }
    }

    func testDraftContentShorterThanMinimumLengthIsRejected() throws {
        let directory = try makeTempDirectory()
        try writeRawCase(
            """
            {"id": "case-01", "kind": "draft", "idea": "关于一次旅行的初稿修订",
             "direction": "随笔", "materials": "", "content": "太短的初稿"}
            """,
            fileName: "case-01.json",
            in: directory
        )

        XCTAssertThrowsError(try EvalCaseLoader.loadCases(from: directory)) { error in
            guard let message = (error as? LocalizedError)?.errorDescription else {
                return XCTFail("期望可执行的错误信息")
            }
            XCTAssertTrue(message.contains("case-01.json"))
            XCTAssertTrue(message.contains("content"))
        }
    }

    func testValidIdeaCaseWithEmptyContentLoadsSuccessfully() throws {
        let directory = try makeTempDirectory()
        try writeRawCase(
            """
            {"id": "case-01", "kind": "idea", "idea": "写一篇关于独处的随笔",
             "direction": "随笔", "materials": "素材", "content": ""}
            """,
            fileName: "case-01.json",
            in: directory
        )

        let cases = try EvalCaseLoader.loadCases(from: directory)

        XCTAssertEqual(cases.count, 1)
        XCTAssertEqual(cases[0].id, "case-01")
    }
}
