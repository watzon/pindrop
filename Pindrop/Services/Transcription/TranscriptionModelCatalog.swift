//
//  TranscriptionModelCatalog.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import Foundation

enum TranscriptionModelCatalog {
    static let availableModels: [ModelManager.WhisperModel] = [
        ModelManager.WhisperModel(
            name: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeInMB: 75,
            description: "Fastest model, ideal for quick dictation with acceptable accuracy",
            speedRating: 10.0,
            accuracyRating: 6.0,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-tiny.en",
            displayName: "Whisper Tiny (English)",
            sizeInMB: 75,
            description: "English-optimized tiny model with slightly better accuracy",
            speedRating: 10.0,
            accuracyRating: 6.5,
            language: .english
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeInMB: 145,
            description: "Good balance between speed and accuracy for everyday use",
            speedRating: 9.0,
            accuracyRating: 7.0,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-base.en",
            displayName: "Whisper Base (English)",
            sizeInMB: 145,
            description: "English-optimized base model, recommended for most users",
            speedRating: 9.0,
            accuracyRating: 7.5,
            language: .english
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-small",
            displayName: "Whisper Small",
            sizeInMB: 483,
            description: "Higher accuracy for complex vocabulary and technical terms",
            speedRating: 7.5,
            accuracyRating: 8.0,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-small_216MB",
            displayName: "Whisper Small (Quantized)",
            sizeInMB: 216,
            description: "Quantized small model - half the size with similar accuracy",
            speedRating: 8.0,
            accuracyRating: 7.8,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-small.en",
            displayName: "Whisper Small (English)",
            sizeInMB: 483,
            description: "English-optimized with excellent accuracy for professional use",
            speedRating: 7.5,
            accuracyRating: 8.5,
            language: .english
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-small.en_217MB",
            displayName: "Whisper Small (English, Quantized)",
            sizeInMB: 217,
            description: "Quantized English small model - compact and fast",
            speedRating: 8.0,
            accuracyRating: 8.3,
            language: .english
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-medium",
            displayName: "Whisper Medium",
            sizeInMB: 1530,
            description: "Excellent for multilingual and code-switching (e.g. Chinese/English mix)",
            speedRating: 6.5,
            accuracyRating: 8.8,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-medium.en",
            displayName: "Whisper Medium (English)",
            sizeInMB: 1530,
            description: "English-optimized medium model with high accuracy",
            speedRating: 6.5,
            accuracyRating: 9.0,
            language: .english
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v2",
            displayName: "Whisper Large v2",
            sizeInMB: 3100,
            description: "Previous generation large model, still very capable",
            speedRating: 5.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v2_949MB",
            displayName: "Whisper Large v2 (Quantized)",
            sizeInMB: 949,
            description: "Quantized large v2 - much smaller with minimal accuracy loss",
            speedRating: 6.0,
            accuracyRating: 9.1,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v2_turbo",
            displayName: "Whisper Large v2 Turbo",
            sizeInMB: 3100,
            description: "Turbo-optimized large v2 for faster inference",
            speedRating: 6.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v2_turbo_955MB",
            displayName: "Whisper Large v2 Turbo (Quantized)",
            sizeInMB: 955,
            description: "Quantized turbo large v2 - fast and compact",
            speedRating: 7.0,
            accuracyRating: 9.1,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3",
            displayName: "Whisper Large v3",
            sizeInMB: 3100,
            description: "Maximum accuracy for demanding transcription tasks",
            speedRating: 5.0,
            accuracyRating: 9.7,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3_947MB",
            displayName: "Whisper Large v3 (Quantized)",
            sizeInMB: 947,
            description: "Quantized large v3 - great accuracy in a smaller package",
            speedRating: 6.0,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3_turbo",
            displayName: "Whisper Large v3 Turbo",
            sizeInMB: 809,
            description: "Near large-model accuracy with significantly faster processing",
            speedRating: 7.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3_turbo_954MB",
            displayName: "Whisper Large v3 Turbo (Quantized)",
            sizeInMB: 954,
            description: "Quantized turbo v3 - balanced speed and accuracy",
            speedRating: 7.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3-v20240930",
            displayName: "Whisper Large v3 (Sep 2024)",
            sizeInMB: 3100,
            description: "Updated large v3 with improved multilingual performance",
            speedRating: 5.0,
            accuracyRating: 9.8,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3-v20240930_547MB",
            displayName: "Whisper Large v3 Sep 2024 (Q 547MB)",
            sizeInMB: 547,
            description: "Heavily quantized - smallest large v3 variant",
            speedRating: 7.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3-v20240930_626MB",
            displayName: "Whisper Large v3 Sep 2024 (Q 626MB)",
            sizeInMB: 626,
            description: "Quantized Sep 2024 large v3 - compact with great accuracy",
            speedRating: 6.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3-v20240930_turbo",
            displayName: "Whisper Large v3 Sep 2024 Turbo",
            sizeInMB: 3100,
            description: "Latest turbo-optimized large v3 - best overall performance",
            speedRating: 6.5,
            accuracyRating: 9.8,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "openai_whisper-large-v3-v20240930_turbo_632MB",
            displayName: "Whisper Large v3 Sep 2024 Turbo (Quantized)",
            sizeInMB: 632,
            description: "Quantized latest turbo - excellent accuracy in ~600MB",
            speedRating: 7.5,
            accuracyRating: 9.5,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "distil-whisper_distil-large-v3",
            displayName: "Distil Large v3",
            sizeInMB: 1510,
            description: "Distilled large v3 - faster with minimal accuracy loss",
            speedRating: 7.5,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "distil-whisper_distil-large-v3_594MB",
            displayName: "Distil Large v3 (Quantized)",
            sizeInMB: 594,
            description: "Quantized distilled model - great speed/accuracy tradeoff",
            speedRating: 8.0,
            accuracyRating: 9.0,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "distil-whisper_distil-large-v3_turbo",
            displayName: "Distil Large v3 Turbo",
            sizeInMB: 1510,
            description: "Turbo-optimized distilled model for fastest large-class inference",
            speedRating: 8.0,
            accuracyRating: 9.3,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "distil-whisper_distil-large-v3_turbo_600MB",
            displayName: "Distil Large v3 Turbo (Quantized)",
            sizeInMB: 600,
            description: "Quantized turbo distilled - fastest large-class model at ~600MB",
            speedRating: 8.5,
            accuracyRating: 9.0,
            language: .multilingual
        ),
        ModelManager.WhisperModel(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet TDT 0.6B V2",
            sizeInMB: 2580,
            description: "NVIDIA's state-of-the-art speech recognition model, English-only",
            speedRating: 8.5,
            accuracyRating: 9.8,
            language: .english,
            provider: .parakeet,
            availability: .available
        ),
        ModelManager.WhisperModel(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet TDT 0.6B V3",
            sizeInMB: 2670,
            description: "Latest Parakeet model with multilingual support",
            speedRating: 8.0,
            accuracyRating: 9.9,
            language: .multilingual,
            languageSupport: .parakeetV3European,
            provider: .parakeet,
            availability: .available
        ),
        ModelManager.WhisperModel(
            name: "parakeet-tdt-1.1b",
            displayName: "Parakeet TDT 1.1B",
            sizeInMB: 4400,
            description: "Larger Parakeet model with exceptional accuracy",
            speedRating: 7.0,
            accuracyRating: 9.95,
            language: .english,
            provider: .parakeet,
            availability: .comingSoon
        ),
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
        KMPTranscriptionBridge.recommendedModels(
            availableModels: availableModels,
            for: language
        )
    }
}
