package enum AgentRunPayloads {
    package static func singleStep(
        name: String,
        success: Bool,
        elapsedMS: Int,
        inputSummary: String,
        outputSummary: String,
        error: String
    ) -> AgentStepPayload {
        AgentStepPayload(
            step_index: 1,
            name: name,
            status: success ? "success" : "fallback",
            input_summary: inputSummary,
            output_summary: outputSummary,
            elapsed_ms: elapsedMS,
            error: error
        )
    }

    package static func reindexed(_ steps: [AgentStepPayload]) -> [AgentStepPayload] {
        steps.enumerated().map { offset, step in
            AgentStepPayload(
                step_index: offset + 1,
                name: step.name,
                status: step.status,
                input_summary: step.input_summary,
                output_summary: step.output_summary,
                elapsed_ms: step.elapsed_ms,
                error: step.error,
                step_type: step.step_type,
                decision_json: step.decision_json
            )
        }
    }
}
