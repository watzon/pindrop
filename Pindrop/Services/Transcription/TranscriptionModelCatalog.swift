//
//  TranscriptionModelCatalog.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import Foundation

enum TranscriptionModelCatalog {
    static var availableModels: [ModelManager.WhisperModel] {
        KMPTranscriptionBridge.localAvailableModels() + remoteModels
    }

    private static let remoteModels: [ModelManager.WhisperModel] = [
        ModelManager.WhisperModel(
            name: "openai_whisper-1",
            displayName: "OpenAI Whisper API",
            sizeInMB: 0,
            description: "Cloud-based transcription via OpenAI's API",
            speedRating: 9.0,
            accuracyRating: 9.5,
            language: .multilingual,
            provider: .openAI,
            availability: .comingSoon
        ),
        ModelManager.WhisperModel(
            name: "groq_whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            sizeInMB: 0,
            description: "Lightning-fast cloud inference powered by Groq",
            speedRating: 10.0,
            accuracyRating: 9.5,
            language: .multilingual,
            provider: .groq,
            availability: .comingSoon
        ),
        ModelManager.WhisperModel(
            name: "elevenlabs_scribe",
            displayName: "ElevenLabs Scribe",
            sizeInMB: 0,
            description: "High-quality transcription with speaker diarization",
            speedRating: 8.0,
            accuracyRating: 9.3,
            language: .multilingual,
            provider: .elevenLabs,
            availability: .comingSoon
        )
    ]

    static func recommendedModels(
        availableModels: [ModelManager.WhisperModel],
        for language: AppLanguage
    ) -> [ModelManager.WhisperModel] {
        let localRecommended = KMPTranscriptionBridge.recommendedLocalModels(for: language)

        guard !localRecommended.isEmpty else {
            return KMPTranscriptionBridge.recommendedModels(
                availableModels: availableModels,
                for: language
            )
        }

        return localRecommended
    }
}
