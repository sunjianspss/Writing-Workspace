import Foundation
import CreativeWorkshopCore

enum WorkshopRetrieval {
    static func materialsBlock(
        query: String,
        materials: String,
        database: NativeDatabase
    ) throws -> (materials: String, fragments: [RetrievedFragment], corpus: [Fragment]) {
        let fragments = try database.rebuildFragments()
        let retrieved = FragmentRetriever.retrieve(query: query, fragments: fragments, limit: 3)
        guard !retrieved.isEmpty else {
            return (materials, [], fragments)
        }
        let block = retrieved.enumerated().map { index, fragment in
            """
            \(index + 1). 来源：\(fragment.citationTitle)（\(fragment.source_type)#\(fragment.source_id)，相关度 \(String(format: "%.2f", fragment.score))）
            \(fragment.content)
            """
        }.joined(separator: "\n\n")
        let combined = [
            materials.trimmingCharacters(in: .whitespacesAndNewlines),
            "【本地检索到的个人素材片段】\n\(block)\n\n要求：优先使用这些真实素材中的具体细节，不要虚构相似经历替代。"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return (combined, retrieved, fragments)
    }
}
