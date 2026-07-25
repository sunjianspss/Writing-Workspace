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

    var requestedCaseIDs: [String] = []
    if let flagIndex = arguments.firstIndex(of: "--cases"), arguments.count > flagIndex + 1 {
        requestedCaseIDs = arguments[flagIndex + 1]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
        var cases = try EvalCaseLoader.loadCases(from: casesDir)
        guard !cases.isEmpty else {
            FileHandle.standardError.write("evals/cases 下没有找到用例 JSON 文件。\n".data(using: .utf8)!)
            return 1
        }
        if !requestedCaseIDs.isEmpty {
            cases = try CaseFilter.apply(requestedCaseIDs, to: cases)
        }

        let styleSamples = try EvalStyleSampleLoader.load(from: evalsDir.appendingPathComponent("style_samples"))
        if styleSamples.isEmpty {
            print("未找到 evals/style_samples 下的风格样本，本轮按零样本配置运行。")
        } else {
            print("注入风格样本 \(styleSamples.count) 篇：\(styleSamples.map(\.name).joined(separator: "、"))")
        }
        let facade = try EvalPipelineFacade(apiKey: apiKey, styleSamples: styleSamples.map(\.text))
        let runner = PipelineRunner(facade: facade)

        // 增量落盘（评测韧性修缮）：run 元信息与结果库在循环前就绪，每个 outcome 完成即入库，
        // 中断不再丢已完成的数据。previousScores 必须在本轮任何插入之前读取。
        let runID = UUID().uuidString
        let timestampFormatter = ISO8601DateFormatter()
        let runTimestamp = timestampFormatter.string(from: Date())
        let gitDescribe = GitDescribe.current(repositoryPath: cwd)
        let store = try EvalResultsStore(databaseURL: resultsDBURL)
        let previousScores = try store.previousRunScores(before: runTimestamp)
        let encoder = JSONEncoder()

        var outcomes: [PipelineOutcome] = []
        var offlineWaits = 0
        var abortedByOffline = false

        caseLoop: for evalCase in cases {
            for pipeline in pipelines {
                while true {
                    print("运行 \(evalCase.id) / \(pipeline) ...")
                    let outcome = try await runner.run(pipeline: pipeline, evalCase: evalCase)

                    // 离线熔断（评测韧性修缮）：瞬时网络失败的结果是污染数据，丢弃并等网络恢复后
                    // 重试同一"用例×管线"；持续离线达到上限则中止本轮。
                    if OfflineBreaker.isInstantNetworkFailure(success: outcome.success, error: outcome.error, elapsedMS: outcome.elapsedMS) {
                        offlineWaits += 1
                        guard offlineWaits <= OfflineBreaker.maxWaits else {
                            FileHandle.standardError.write("网络持续离线约 \(OfflineBreaker.waitSeconds * OfflineBreaker.maxWaits / 60) 分钟，评测中止；瞬时失败的结果已丢弃，已完成的 \(outcomes.count) 个结果均已入库。\n".data(using: .utf8)!)
                            abortedByOffline = true
                            break caseLoop
                        }
                        print("检测到瞬时网络失败（\(outcome.error)），丢弃本次结果，\(OfflineBreaker.waitSeconds) 秒后重试该管线（第 \(offlineWaits)/\(OfflineBreaker.maxWaits) 次等待）...")
                        try await Task.sleep(nanoseconds: UInt64(OfflineBreaker.waitSeconds) * 1_000_000_000)
                        continue
                    }

                    offlineWaits = 0
                    let rawJSON = String(data: try encoder.encode(outcome), encoding: .utf8) ?? "{}"
                    try store.insert(runID: runID, runTimestamp: runTimestamp, gitDescribe: gitDescribe, outcome: outcome, rawJSON: rawJSON)
                    outcomes.append(outcome)
                    break
                }
            }
        }

        guard !outcomes.isEmpty else {
            FileHandle.standardError.write("没有产出任何有效结果，评测失败。\n".data(using: .utf8)!)
            return 1
        }

        let report = ReportGenerator.generate(
            runID: runID,
            runTimestamp: runTimestamp,
            gitDescribe: gitDescribe,
            outcomes: outcomes,
            previousScores: previousScores,
            styleSampleNames: styleSamples.map(\.name),
            promptTemplateSummary: facade.promptTemplateSummary
        )
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        let reportFileName = runTimestamp.replacingOccurrences(of: ":", with: "-") + ".md"
        let reportURL = reportsDir.appendingPathComponent(reportFileName)
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        if abortedByOffline {
            print("评测因持续离线提前中止，报告仅含已完成的 \(outcomes.count) 个结果：\(reportURL.path)")
            return 2
        }
        print("评测完成，报告已写入：\(reportURL.path)")
        return 0
    } catch {
        FileHandle.standardError.write("评测失败：\(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }
}

let exitCode = await run()
exit(exitCode)
