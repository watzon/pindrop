package tech.watzon.pindrop.shared.runtime.transcription

import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId

object LocalTranscriptionCatalog {
    private val englishRecommendedIds = listOf(
        TranscriptionModelId("openai_whisper-base.en"),
        TranscriptionModelId("openai_whisper-small.en"),
        TranscriptionModelId("openai_whisper-medium"),
        TranscriptionModelId("openai_whisper-large-v3_turbo"),
        TranscriptionModelId("parakeet-tdt-0.6b-v2"),
    )

    private val multilingualRecommendedIds = listOf(
        TranscriptionModelId("openai_whisper-base"),
        TranscriptionModelId("openai_whisper-small"),
        TranscriptionModelId("openai_whisper-medium"),
        TranscriptionModelId("openai_whisper-large-v3_turbo"),
        TranscriptionModelId("parakeet-tdt-0.6b-v3"),
    )

    private val localModels = listOf(
        whisper("openai_whisper-tiny", "Whisper Tiny", 75, "Fastest model, ideal for quick dictation with acceptable accuracy", 10.0, 6.0),
        whisper("openai_whisper-tiny.en", "Whisper Tiny (English)", 75, "English-optimized tiny model with slightly better accuracy", 10.0, 6.5, ModelLanguageSupport.ENGLISH_ONLY),
        whisper("openai_whisper-base", "Whisper Base", 145, "Good balance between speed and accuracy for everyday use", 9.0, 7.0),
        whisper("openai_whisper-base.en", "Whisper Base (English)", 145, "English-optimized base model, recommended for most users", 9.0, 7.5, ModelLanguageSupport.ENGLISH_ONLY),
        whisper("openai_whisper-small", "Whisper Small", 483, "Higher accuracy for complex vocabulary and technical terms", 7.5, 8.0),
        whisper("openai_whisper-small_216MB", "Whisper Small (Quantized)", 216, "Quantized small model - half the size with similar accuracy", 8.0, 7.8),
        whisper("openai_whisper-small.en", "Whisper Small (English)", 483, "English-optimized with excellent accuracy for professional use", 7.5, 8.5, ModelLanguageSupport.ENGLISH_ONLY),
        whisper("openai_whisper-small.en_217MB", "Whisper Small (English, Quantized)", 217, "Quantized English small model - compact and fast", 8.0, 8.3, ModelLanguageSupport.ENGLISH_ONLY),
        whisper("openai_whisper-medium", "Whisper Medium", 1530, "Excellent for multilingual and code-switching (e.g. Chinese/English mix)", 6.5, 8.8),
        whisper("openai_whisper-medium.en", "Whisper Medium (English)", 1530, "English-optimized medium model with high accuracy", 6.5, 9.0, ModelLanguageSupport.ENGLISH_ONLY),
        whisper("openai_whisper-large-v2", "Whisper Large v2", 3100, "Previous generation large model, still very capable", 5.0, 9.3),
        whisper("openai_whisper-large-v2_949MB", "Whisper Large v2 (Quantized)", 949, "Quantized large v2 - much smaller with minimal accuracy loss", 6.0, 9.1),
        whisper("openai_whisper-large-v2_turbo", "Whisper Large v2 Turbo", 3100, "Turbo-optimized large v2 for faster inference", 6.5, 9.3),
        whisper("openai_whisper-large-v2_turbo_955MB", "Whisper Large v2 Turbo (Quantized)", 955, "Quantized turbo large v2 - fast and compact", 7.0, 9.1),
        whisper("openai_whisper-large-v3", "Whisper Large v3", 3100, "Maximum accuracy for demanding transcription tasks", 5.0, 9.7),
        whisper("openai_whisper-large-v3_947MB", "Whisper Large v3 (Quantized)", 947, "Quantized large v3 - great accuracy in a smaller package", 6.0, 9.5),
        whisper("openai_whisper-large-v3_turbo", "Whisper Large v3 Turbo", 809, "Near large-model accuracy with significantly faster processing", 7.5, 9.5),
        whisper("openai_whisper-large-v3_turbo_954MB", "Whisper Large v3 Turbo (Quantized)", 954, "Quantized turbo v3 - balanced speed and accuracy", 7.5, 9.3),
        whisper("openai_whisper-large-v3-v20240930", "Whisper Large v3 (Sep 2024)", 3100, "Updated large v3 with improved multilingual performance", 5.0, 9.8),
        whisper("openai_whisper-large-v3-v20240930_547MB", "Whisper Large v3 Sep 2024 (Q 547MB)", 547, "Heavily quantized - smallest large v3 variant", 7.0, 9.3),
        whisper("openai_whisper-large-v3-v20240930_626MB", "Whisper Large v3 Sep 2024 (Q 626MB)", 626, "Quantized Sep 2024 large v3 - compact with great accuracy", 6.5, 9.5),
        whisper("openai_whisper-large-v3-v20240930_turbo", "Whisper Large v3 Sep 2024 Turbo", 3100, "Latest turbo-optimized large v3 - best overall performance", 6.5, 9.8),
        whisper("openai_whisper-large-v3-v20240930_turbo_632MB", "Whisper Large v3 Sep 2024 Turbo (Quantized)", 632, "Quantized latest turbo - excellent accuracy in ~600MB", 7.5, 9.5),
        whisper("distil-whisper_distil-large-v3", "Distil Large v3", 1510, "Distilled large v3 - faster with minimal accuracy loss", 7.5, 9.3),
        whisper("distil-whisper_distil-large-v3_594MB", "Distil Large v3 (Quantized)", 594, "Quantized distilled model - great speed/accuracy tradeoff", 8.0, 9.0),
        whisper("distil-whisper_distil-large-v3_turbo", "Distil Large v3 Turbo", 1510, "Turbo-optimized distilled model for fastest large-class inference", 8.0, 9.3),
        whisper("distil-whisper_distil-large-v3_turbo_600MB", "Distil Large v3 Turbo (Quantized)", 600, "Quantized turbo distilled - fastest large-class model at ~600MB", 8.5, 9.0),
        parakeet("parakeet-tdt-0.6b-v2", "Parakeet TDT 0.6B V2", 2580, "NVIDIA's state-of-the-art speech recognition model, English-only", 8.5, 9.8, ModelLanguageSupport.ENGLISH_ONLY),
        parakeet("parakeet-tdt-0.6b-v3", "Parakeet TDT 0.6B V3", 2670, "Latest Parakeet model with multilingual support", 8.0, 9.9, ModelLanguageSupport.PARAKEET_V3_EUROPEAN),
        parakeet("parakeet-tdt-1.1b", "Parakeet TDT 1.1B", 4400, "Larger Parakeet model with exceptional accuracy", 7.0, 9.95, ModelLanguageSupport.ENGLISH_ONLY, ModelAvailability.COMING_SOON),
    )

    fun models(platform: LocalPlatformId): List<LocalModelDescriptor> {
        return localModels.map { descriptor ->
            val preferredBackend = preferredBackendFor(platform, descriptor.family)
            val provider = providerFor(preferredBackend)
            val availability = if (preferredBackend in descriptor.supportedBackends) {
                descriptor.availability
            } else {
                ModelAvailability.COMING_SOON
            }

            descriptor.copy(
                provider = provider,
                availability = availability,
            )
        }
    }

    fun recommendedModelIds(language: TranscriptionLanguage): List<TranscriptionModelId> {
        return if (language == TranscriptionLanguage.ENGLISH) {
            englishRecommendedIds
        } else {
            multilingualRecommendedIds
        }
    }

    fun recommendedModels(
        platform: LocalPlatformId,
        language: TranscriptionLanguage,
    ): List<LocalModelDescriptor> {
        val models = models(platform)
        val ranks = recommendedModelIds(language).withIndex().associate { it.value to it.index }
        return models
            .filter { it.id in ranks.keys }
            .filter { it.availability == ModelAvailability.AVAILABLE }
            .filter { supportsLanguage(it.languageSupport, language) }
            .sortedBy { ranks[it.id] ?: Int.MAX_VALUE }
    }

    fun model(platform: LocalPlatformId, modelId: TranscriptionModelId): LocalModelDescriptor? {
        return models(platform).firstOrNull { it.id == modelId }
    }

    fun supportsLanguage(
        support: ModelLanguageSupport,
        language: TranscriptionLanguage,
    ): Boolean {
        if (language == TranscriptionLanguage.AUTOMATIC) {
            return true
        }

        return when (support) {
            ModelLanguageSupport.ENGLISH_ONLY -> language == TranscriptionLanguage.ENGLISH
            ModelLanguageSupport.FULL_MULTILINGUAL -> true
            ModelLanguageSupport.PARAKEET_V3_EUROPEAN -> language in setOf(
                TranscriptionLanguage.ENGLISH,
                TranscriptionLanguage.SPANISH,
                TranscriptionLanguage.FRENCH,
                TranscriptionLanguage.GERMAN,
                TranscriptionLanguage.PORTUGUESE_BRAZIL,
                TranscriptionLanguage.ITALIAN,
                TranscriptionLanguage.DUTCH,
                TranscriptionLanguage.TURKISH,
            )
        }
    }

    private fun whisper(
        id: String,
        displayName: String,
        sizeInMb: Int,
        description: String,
        speedRating: Double,
        accuracyRating: Double,
        languageSupport: ModelLanguageSupport = ModelLanguageSupport.FULL_MULTILINGUAL,
        availability: ModelAvailability = ModelAvailability.AVAILABLE,
    ): LocalModelDescriptor {
        return LocalModelDescriptor(
            id = TranscriptionModelId(id),
            family = LocalModelFamily.WHISPER,
            provider = LocalModelProvider.WHISPER_KIT,
            supportedBackends = setOf(LocalBackendId.WHISPER_KIT, LocalBackendId.WHISPER_CPP),
            displayName = displayName,
            languageSupport = languageSupport,
            sizeInMb = sizeInMb,
            description = description,
            speedRating = speedRating,
            accuracyRating = accuracyRating,
            availability = availability,
        )
    }

    private fun parakeet(
        id: String,
        displayName: String,
        sizeInMb: Int,
        description: String,
        speedRating: Double,
        accuracyRating: Double,
        languageSupport: ModelLanguageSupport,
        availability: ModelAvailability = ModelAvailability.AVAILABLE,
    ): LocalModelDescriptor {
        return LocalModelDescriptor(
            id = TranscriptionModelId(id),
            family = LocalModelFamily.PARAKEET,
            provider = LocalModelProvider.PARAKEET_COREML,
            supportedBackends = setOf(LocalBackendId.PARAKEET_APPLE),
            displayName = displayName,
            languageSupport = languageSupport,
            sizeInMb = sizeInMb,
            description = description,
            speedRating = speedRating,
            accuracyRating = accuracyRating,
            availability = availability,
        )
    }

    private fun preferredBackendFor(
        platform: LocalPlatformId,
        family: LocalModelFamily,
    ): LocalBackendId {
        return when (family) {
            LocalModelFamily.WHISPER -> {
                if (platform == LocalPlatformId.MACOS) {
                    LocalBackendId.WHISPER_KIT
                } else {
                    LocalBackendId.WHISPER_CPP
                }
            }

            LocalModelFamily.PARAKEET -> {
                if (platform == LocalPlatformId.MACOS) {
                    LocalBackendId.PARAKEET_APPLE
                } else {
                    LocalBackendId.PARAKEET_NATIVE
                }
            }
        }
    }

    private fun providerFor(backendId: LocalBackendId): LocalModelProvider {
        return when (backendId) {
            LocalBackendId.WHISPER_KIT -> LocalModelProvider.WHISPER_KIT
            LocalBackendId.WHISPER_CPP -> LocalModelProvider.WCPP
            LocalBackendId.PARAKEET_APPLE -> LocalModelProvider.PARAKEET_COREML
            LocalBackendId.PARAKEET_NATIVE -> LocalModelProvider.PARAKEET_NATIVE
        }
    }
}
