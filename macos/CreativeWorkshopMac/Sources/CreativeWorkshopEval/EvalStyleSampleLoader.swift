import Foundation

/// 一份评测风格样本：`name` 用于在报告里写明本轮注入了哪几篇（可见性兜底自动判定的盲区）。
struct EvalStyleSample: Equatable {
    let name: String
    let text: String
}

/// 评测风格样本加载器（PRD 24.4）。
///
/// 样本**必须**来自 `evals/style_samples/` 下版本控制的固定文件，不能从活库动态抽取：
/// 活库每归档一篇新文章，注入的样本就会变，同一条用例的分数随之漂移，报告里
/// 「上次总分/差值」一列立刻沦为噪声——这正是 24.2 刚治好的病。量具的配置必须是固定的。
///
/// 同时，样本文章不得同时是任何用例的来源（评测用例按「一鱼两吃」惯例取自作者真实文章，
/// 把答案当风格样本喂回模型，照抄即得高分）。该约束由 `EvalStyleSampleLeakTests` 守卫。
enum EvalStyleSampleLoader {
    /// 按文件名升序读取目录下的 .md 样本；目录不存在或为空时返回空数组（评测照常跑，只是无样本）。
    static func load(from directory: URL) throws -> [EvalStyleSample] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.compactMap { url in
            let text = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return EvalStyleSample(name: url.deletingPathExtension().lastPathComponent, text: text)
        }
    }
}
