import Foundation

package extension AIRun where T == GeneratedTopicsDocument {
    var topicsResult: (payloads: [TopicPayload], elapsedMS: Int, success: Bool, error: String, inputSummary: String, outputSummary: String) {
        (result.topics, elapsedMS, success, error, inputSummary, outputSummary)
    }
}

package extension AIRun where T == OutlineResult {
    var outlineResponse: OutlineResponse {
        OutlineResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == DraftResult {
    var draftResponse: DraftResponse {
        DraftResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == WritingReviewResult {
    var writingReviewResponse: WritingReviewResponse {
        WritingReviewResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == PublishAssetsResult {
    var publishAssetsResponse: PublishAssetsResponse {
        PublishAssetsResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == RewriteResult {
    var rewriteSelectionResponse: RewriteSelectionResponse {
        RewriteSelectionResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == WritingAdvisorResult {
    var writingAdvisorResponse: WritingAdvisorResponse {
        WritingAdvisorResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == DraftSelfCheckResult {
    var draftSelfCheckResponse: DraftSelfCheckResponse {
        DraftSelfCheckResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == PitfallSummaryResult {
    var pitfallSummaryResponse: PitfallSummaryResponse {
        PitfallSummaryResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == EditPreferenceSummaryResult {
    var editPreferenceSummaryResponse: EditPreferenceSummaryResponse {
        EditPreferenceSummaryResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == ReaderPerspectiveResult {
    var readerPerspectiveResponse: ReaderPerspectiveResponse {
        ReaderPerspectiveResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == PrePublishAuditReport {
    var prePublishAuditResponse: PrePublishAuditResponse {
        PrePublishAuditResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}

package extension AIRun where T == CandidateJudgeResult {
    var candidateJudgeResponse: CandidateJudgeResponse {
        CandidateJudgeResponse(result: result, elapsed_ms: elapsedMS, success: success, error: error, input_summary: inputSummary, output_summary: outputSummary)
    }
}
