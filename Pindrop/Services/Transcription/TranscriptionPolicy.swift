//
//  TranscriptionPolicy.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import Foundation

enum TranscriptionPolicy {
    static func normalizedTranscriptionText(_ text: String) -> String {
        KMPTranscriptionBridge.normalizeTranscriptionText(text)
    }

    static func isTranscriptionEffectivelyEmpty(_ text: String) -> Bool {
        KMPTranscriptionBridge.isTranscriptionEffectivelyEmpty(text)
    }

    static func shouldPersistHistory(outputSucceeded: Bool, text: String) -> Bool {
        KMPTranscriptionBridge.shouldPersistHistory(outputSucceeded: outputSucceeded, text: text)
    }

    static func shouldUseSpeakerDiarization(
        diarizationFeatureEnabled: Bool,
        isStreamingSessionActive: Bool
    ) -> Bool {
        KMPTranscriptionBridge.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: diarizationFeatureEnabled,
            isStreamingSessionActive: isStreamingSessionActive
        )
    }

    static func shouldUseStreamingTranscription(
        streamingFeatureEnabled: Bool,
        outputMode: OutputMode,
        aiEnhancementEnabled: Bool,
        isQuickCaptureMode: Bool
    ) -> Bool {
        KMPTranscriptionBridge.shouldUseStreamingTranscription(
            streamingFeatureEnabled: streamingFeatureEnabled,
            outputMode: outputMode,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )
    }

    static func providerSupportsLocalModelLoading(
        _ provider: ModelManager.ModelProvider
    ) -> Bool {
        KMPTranscriptionBridge.providerSupportsLocalModelLoading(provider)
    }

    static func modelSupportsLanguage(
        _ support: ModelManager.LanguageSupport,
        language: AppLanguage
    ) -> Bool {
        KMPTranscriptionBridge.modelSupportsLanguage(support, language: language)
    }
}

enum RecordingInteractionPolicy {
    static func shouldSuppressEscapeEvent(isRecording: Bool, isProcessing: Bool) -> Bool {
        isRecording || isProcessing
    }

    static func isDoubleEscapePress(
        now: Date,
        lastEscapeTime: Date?,
        threshold: TimeInterval
    ) -> Bool {
        guard let lastEscapeTime else { return false }
        return now.timeIntervalSince(lastEscapeTime) <= threshold
    }
}
