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

    // 断点续跑（24.9）：全量一轮 112 格约 8 小时，中断后此前只能从 case-01 重烧。
    let resumeRequested = arguments.contains("--resume")

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
        let currentGit = GitDescribe.current(repositoryPath: cwd)
        let store = try EvalResultsStore(databaseURL: resultsDBURL)

        let runID: String
        let runTimestamp: String
        var reportGitDescribe = currentGit
        // 续跑沿用上一轮的 run_id 与时间戳：报告因此补成整轮，而不是留下两份各跑一半的报告。
        // 新跑出来的行记当前的 git describe（它们确实由当前代码产出），报告头把两者都写出来。
        var completedPairs: Set<String> = []
        var outcomes: [PipelineOutcome] = []
        if resumeRequested {
            guard let latest = try store.latestRun() else {
                FileHandle.standardError.write("库里没有可续跑的 run（evals/eval_results.sqlite3 为空）。\n".data(using: .utf8)!)
                return 1
            }
            runID = latest.runID
            runTimestamp = latest.runTimestamp
            completedPairs = try store.completedPairs(runID: latest.runID)
            outcomes = try store.outcomes(runID: latest.runID)
            if latest.gitDescribe != currentGit {
                reportGitDescribe = "\(latest.gitDescribe) → \(currentGit)（续跑）"
            }
            print("续跑 run \(latest.runID)（\(latest.runTimestamp)）：已有 \(completedPairs.count) 格成功结果，本次只跑缺口。")
        } else {
            runID = UUID().uuidString
            runTimestamp = ISO8601DateFormatter().string(from: Date())
        }
        let previousSamples = try store.previousRunSamples(before: runTimestamp)
        let encoder = JSONEncoder()

        var offlineWaits = 0
        var abortedByOffline = false

        caseLoop: for evalCase in cases {
            for pipeline in pipelines {
                if completedPairs.contains("\(evalCase.id)|\(pipeline)") {
                    print("跳过 \(evalCase.id) / \(pipeline)（已有成功结果）")
                    continue
                }
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
                    try store.insert(runID: runID, runTimestamp: runTimestamp, gitDescribe: currentGit, outcome: outcome, rawJSON: rawJSON)
                    // 续跑重跑过的格子要替换掉库里读回来的旧结果，否则报告会展示那条已被作废的行。
                    if let existing = outcomes.firstIndex(where: { $0.caseID == outcome.caseID && $0.pipeline == outcome.pipeline }) {
                        outcomes[existing] = outcome
                    } else {
                        outcomes.append(outcome)
                    }
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
            gitDescribe: reportGitDescribe,
            outcomes: outcomes,
            previousSamples: previousSamples,
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
