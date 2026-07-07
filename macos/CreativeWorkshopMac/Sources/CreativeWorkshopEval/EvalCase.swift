import Foundation

struct EvalCase: Codable, Equatable {
    var id: String
    var kind: String
    var idea: String
    var direction: String
    var materials: String
    var content: String
}

/// 校验失败时的可执行错误信息（PRD 23.4 验收标准 2）：必须点名文件、字段与期望，
/// 不允许静默跳过非法用例。
enum EvalCaseValidationError: LocalizedError {
    case invalidJSON(file: String, message: String)
    case missingField(file: String, field: String)
    case invalidKind(file: String, value: String)
    case tooShort(file: String, field: String, minimumLength: Int, actualLength: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(file, message):
            return "用例文件 \(file) 不是合法 JSON：\(message)"
        case let .missingField(file, field):
            return "用例文件 \(file) 缺少必填字段「\(field)」，期望：非空字符串。"
        case let .invalidKind(file, value):
            return "用例文件 \(file) 的字段「kind」取值「\(value)」非法，期望：\"idea\" 或 \"draft\"。"
        case let .tooShort(file, field, minimumLength, actualLength):
            return "用例文件 \(file) 的字段「\(field)」长度为 \(actualLength)，期望：不少于 \(minimumLength) 个字符。"
        }
    }
}

enum EvalCaseLoader {
    /// idea 是驱动生成的主要输入，过短无法构成有意义的评测场景。
    static let minimumIdeaLength = 10
    /// kind=draft 的用例代表"已有初稿"，正文过短则无法体现真实修订场景。
    static let minimumDraftContentLength = 80

    private struct RawEvalCase: Decodable {
        var id: String?
        var kind: String?
        var idea: String?
        var direction: String?
        var materials: String?
        var content: String?
    }

    static func loadCases(from directory: URL) throws -> [EvalCase] {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { try loadCase(from: $0) }
    }

    static func loadCase(from file: URL) throws -> EvalCase {
        let fileName = file.lastPathComponent
        let data = try Data(contentsOf: file)
        let raw: RawEvalCase
        do {
            raw = try JSONDecoder().decode(RawEvalCase.self, from: data)
        } catch {
            throw EvalCaseValidationError.invalidJSON(file: fileName, message: error.localizedDescription)
        }

        func requireNonEmpty(_ value: String?, field: String) throws -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EvalCaseValidationError.missingField(file: fileName, field: field)
            }
            return value
        }

        let id = try requireNonEmpty(raw.id, field: "id")
        let kind = try requireNonEmpty(raw.kind, field: "kind")
        guard kind == "idea" || kind == "draft" else {
            throw EvalCaseValidationError.invalidKind(file: fileName, value: kind)
        }
        let idea = try requireNonEmpty(raw.idea, field: "idea")
        guard idea.count >= minimumIdeaLength else {
            throw EvalCaseValidationError.tooShort(
                file: fileName, field: "idea", minimumLength: minimumIdeaLength, actualLength: idea.count
            )
        }
        let direction = try requireNonEmpty(raw.direction, field: "direction")
        let materials = raw.materials ?? ""
        let content = raw.content ?? ""
        if kind == "draft" {
            guard content.count >= minimumDraftContentLength else {
                throw EvalCaseValidationError.tooShort(
                    file: fileName, field: "content", minimumLength: minimumDraftContentLength, actualLength: content.count
                )
            }
        }

        return EvalCase(id: id, kind: kind, idea: idea, direction: direction, materials: materials, content: content)
    }
}
