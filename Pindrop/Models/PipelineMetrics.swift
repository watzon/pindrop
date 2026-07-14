//
//  PipelineMetrics.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  Per-dictation latency breakdown captured while the stop → transcribe →
//  enhance → paste pipeline runs. Persisted on TranscriptionRecord as JSON
//  (one optional column, same pattern as diarizationSegmentsJSON) so new
//  stages can be added without another schema migration.
//

import Foundation

/// Which pipeline produced the record. Streaming sessions transcribe live and
/// only re-transcribe + enhance at stop, so their stage set differs from batch.
enum PipelineKind: String, Codable, Sendable {
    case batch
    case streaming
}

struct PipelineMetrics: Codable, Equatable, Sendable {
    var kind: PipelineKind

    /// Finalizing the audio buffers after the stop hotkey.
    var audioStopSeconds: Double?
    /// Local ASR inference (batch transcription, or the offline re-transcribe
    /// pass of a streaming session).
    var transcriptionSeconds: Double?
    /// Dictionary replacements, mention rewriting, and workspace-tree capture.
    var textProcessingSeconds: Double?
    /// Full AI-enhancement stage: prompt assembly + request + post-processing.
    var enhancementSeconds: Double?
    /// Network round-trip (or on-device inference) portion of the enhancement stage.
    var enhancementRequestSeconds: Double?
    /// Pasting/inserting into the destination app.
    var outputSeconds: Double?
    /// Stop hotkey → output landed. Slightly more than the sum of stages
    /// (includes diarization encode, snapshot capture, and other glue).
    var totalSeconds: Double?

    // MARK: AI enhancement request details

    var enhancementProvider: String?
    var enhancementModel: String?
    var enhancementPromptTokens: Int?
    var enhancementCompletionTokens: Int?
    /// Reasoning/thinking tokens when the provider reports them
    /// (OpenAI `completion_tokens_details.reasoning_tokens`).
    var enhancementReasoningTokens: Int?
    var enhancementTotalTokens: Int?

    init(kind: PipelineKind) {
        self.kind = kind
    }

    /// True when at least one stage duration was captured — records saved by
    /// paths that don't instrument (media imports, MCP) stay nil-JSON instead
    /// of showing an empty breakdown.
    var hasAnyStage: Bool {
        audioStopSeconds != nil
            || transcriptionSeconds != nil
            || textProcessingSeconds != nil
            || enhancementSeconds != nil
            || outputSeconds != nil
            || totalSeconds != nil
    }

    var hasTokenUsage: Bool {
        enhancementPromptTokens != nil
            || enhancementCompletionTokens != nil
            || enhancementReasoningTokens != nil
            || enhancementTotalTokens != nil
    }

    // MARK: - JSON round-trip

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PipelineMetrics.self, from: data) else {
            return nil
        }
        self = decoded
    }

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Compact single-line summary for the `app`/`aiEnhancement` logs, e.g.
    /// `stop=0.08s transcribe=1.42s enhance=2.61s(req=2.55s in=812 out=96 think=64) paste=0.05s total=4.31s`.
    var logSummary: String {
        var parts: [String] = ["kind=\(kind.rawValue)"]
        func stage(_ label: String, _ value: Double?) {
            if let value {
                parts.append("\(label)=\(String(format: "%.2f", value))s")
            }
        }
        stage("stop", audioStopSeconds)
        stage("transcribe", transcriptionSeconds)
        stage("textproc", textProcessingSeconds)
        if let enhancementSeconds {
            var enhanceDetail = String(format: "enhance=%.2fs", enhancementSeconds)
            var innards: [String] = []
            if let enhancementRequestSeconds {
                innards.append(String(format: "req=%.2fs", enhancementRequestSeconds))
            }
            if let enhancementPromptTokens { innards.append("in=\(enhancementPromptTokens)") }
            if let enhancementCompletionTokens { innards.append("out=\(enhancementCompletionTokens)") }
            if let enhancementReasoningTokens { innards.append("think=\(enhancementReasoningTokens)") }
            if !innards.isEmpty {
                enhanceDetail += "(\(innards.joined(separator: " ")))"
            }
            parts.append(enhanceDetail)
        }
        stage("paste", outputSeconds)
        stage("total", totalSeconds)
        return parts.joined(separator: " ")
    }
}

extension Duration {
    /// Wall-clock seconds for persisting/logging stage durations.
    var pipelineSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
