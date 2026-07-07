import Foundation
import CreativeWorkshopCore

func run() async -> Int32 {
    let arguments = CommandLine.arguments
    var pipelines = PipelineRunner.pipelineNames
    if let flagIndex = arguments.firstIndex(of: "--pipelines"), arguments.count > flagIndex + 1 {
        let requested = arguments[flagIndex + 1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !requested.isEmpty {
            pipelines = requested
        }
    }
    for pipeline in pipelines where !PipelineRunner.pipelineNames.contains(pipeline) {
        FileHandle.standardError.write("未知的评测管线：\(pipeline)（可选：\(PipelineRunner.pipelineNames.joined(separator: ","))）\n".data(using: .utf8)!)
        return 1
    }

    let apiKey = EvalPipelineFacade.readAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
        FileHandle.standardError.write((EvalError.missingAPIKey.errorDescription ?? "缺少 API Key").appending("\n").data(using: .utf8)!)
        return 1
    }

    let cwd = FileManager.default.currentDirectoryPath
    let evalsDir = URL(fileURLWithPath: cwd).appendingPathComponent("evals")
    let casesDir = evalsDir.appendingPathComponent("cases")
    let reportsDir = evalsDir.appendingPathComponent("reports")
    let resultsDBURL = evalsDir.appendingPathComponent("eval_results.sqlite3")

    do {
        let cases = try EvalCaseLoader.loadCases(from: casesDir)
        guard !cases.isEmpty else {
            FileHandle.standardError.write("evals/cases 下没有找到用例 JSON 文件。\n".data(using: .utf8)!)
            return 1
        }

        let facade = try EvalPipelineFacade(apiKey: apiKey)
        let runner = PipelineRunner(facade: facade)

        var outcomes: [PipelineOutcome] = []
        for evalCase in cases {
            for pipeline in pipelines {
                print("运行 \(evalCase.id) / \(pipeline) ...")
                let outcome = try await runner.run(pipeline: pipeline, evalCase: evalCase)
                outcomes.append(outcome)
            }
        }

        let runID = UUID().uuidString
        let timestampFormatter = ISO8601DateFormatter()
        let runTimestamp = timestampFormatter.string(from: Date())
        let gitDescribe = GitDescribe.current(repositoryPath: cwd)

        let store = try EvalResultsStore(databaseURL: resultsDBURL)
        let previousScores = try store.previousRunScores(before: runTimestamp)

        let encoder = JSONEncoder()
        for outcome in outcomes {
            let rawJSON = String(data: try encoder.encode(outcome), encoding: .utf8) ?? "{}"
            try store.insert(runID: runID, runTimestamp: runTimestamp, gitDescribe: gitDescribe, outcome: outcome, rawJSON: rawJSON)
        }

        let report = ReportGenerator.generate(
            runID: runID,
            runTimestamp: runTimestamp,
            gitDescribe: gitDescribe,
            outcomes: outcomes,
            previousScores: previousScores
        )
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        let reportFileName = runTimestamp.replacingOccurrences(of: ":", with: "-") + ".md"
        let reportURL = reportsDir.appendingPathComponent(reportFileName)
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        print("评测完成，报告已写入：\(reportURL.path)")
        return 0
    } catch {
        FileHandle.standardError.write("评测失败：\(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }
}

let exitCode = await run()
exit(exitCode)
