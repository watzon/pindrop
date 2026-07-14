//
//  TelemetryEvents.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  The complete catalog of telemetry signals Pindrop can emit. Every signal name
//  and parameter key lives in this file so the full collection surface can be
//  audited at a glance and documented in docs/TELEMETRY.md. Parameter values are
//  restricted to enum labels, buckets, booleans, and model/backend identifiers —
//  never transcript text, audio, prompts, file names, URLs, or any other user
//  content.
//

import Foundation

enum TelemetryEvent: String, CaseIterable {
    case appLaunched = "app.launched"
    case onboardingCompleted = "app.onboardingCompleted"
    case transcriptionSucceeded = "transcription.succeeded"
    case transcriptionFailed = "transcription.failed"
    case transcriptionEmptyResult = "transcription.emptyResult"
    case modelDownloadStarted = "model.downloadStarted"
    case modelDownloadFailed = "model.downloadFailed"
    case modelLoadFailed = "model.loadFailed"
    case enhancementFailed = "enhancement.failed"
}

enum TelemetryParameter {
    /// Effective transcription backend (`parakeet` / `apple`).
    static let backend = "backend"
    /// Selected transcription model identifier (a Pindrop model name, never user content).
    static let model = "model"
    /// Pipeline stage or flow the signal fired from (`transcribe`, `recording`, `quick-capture`, …).
    static let stage = "stage"
    /// Bare enum case label of a domain error, with associated values stripped.
    static let errorCase = "errorCase"
    /// Bucketed dictation duration — raw durations never leave the device.
    static let durationBucket = "durationBucket"
    /// Bucketed transcript word count — raw counts never leave the device.
    static let wordCountBucket = "wordCountBucket"
    /// Whether AI enhancement rewrote the transcript (`true` / `false`).
    static let enhanced = "enhanced"
    /// Whether speaker diarization ran for the dictation (`true` / `false`).
    static let diarized = "diarized"
    /// AI enhancement provider kind label (`openai`, `anthropic`, `ollama`, …).
    static let providerKind = "providerKind"
    /// Interface locale identifier (e.g. `en`, `pt-BR`).
    static let locale = "locale"
}
