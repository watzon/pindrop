package tech.watzon.pindrop.shared.feature.transcription

import tech.watzon.pindrop.shared.core.ModelDescriptor
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.SharedTranscriptionState
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionProviderId

data class TranscriptionRuntimePolicy(
    val selectedProvider: TranscriptionProviderId,
    val selectedModelId: TranscriptionModelId,
    val streamingFeatureEnabled: Boolean,
    val diarizationFeatureEnabled: Boolean,
    val outputMode: String,
    val aiEnhancementEnabled: Boolean,
    val isQuickCaptureMode: Boolean,
)

data class SharedOrchestrationPlan(
    val useStreaming: Boolean,
    val useSpeakerDiarization: Boolean,
)

data class SharedModelLoadPlan(
    val resolvedProvider: TranscriptionProviderId,
    val shouldUnloadCurrentModel: Boolean,
    val supportsLocalModelLoading: Boolean,
    val prefersPathBasedLoading: Boolean,
)

data class SharedTranscriptionExecutionPlan(
    val selectedProvider: TranscriptionProviderId,
    val selectedModelId: TranscriptionModelId,
    val useSpeakerDiarization: Boolean,
    val shouldNormalizeOutput: Boolean,
)

enum class StartupModelAction {
    LOAD_SELECTED,
    LOAD_FALLBACK,
    DOWNLOAD_SELECTED,
}

data class StartupModelResolution(
    val action: StartupModelAction,
    val resolvedModel: ModelDescriptor,
    val updatedSelectedModelId: TranscriptionModelId,
)

enum class EventTapRecoveryAction {
    REENABLE,
    RECREATE,
}

data class EventTapRecoveryDecision(
    val consecutiveDisableCount: Int,
    val action: EventTapRecoveryAction,
)

enum class SharedSessionErrorCode {
    ENGINE_SWITCH_DURING_TRANSCRIPTION,
    MODEL_NOT_LOADED,
    INVALID_AUDIO_DATA,
    TRANSCRIPTION_ALREADY_IN_PROGRESS,
    STREAMING_NOT_READY,
}

data class SharedStateTransition(
    val nextState: SharedTranscriptionState,
    val errorCode: SharedSessionErrorCode? = null,
)

object SharedTranscriptionOrchestrator {
    fun beginModelLoad(currentState: SharedTranscriptionState): SharedStateTransition {
        return if (currentState == SharedTranscriptionState.TRANSCRIBING || currentState == SharedTranscriptionState.STREAMING) {
            SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.ENGINE_SWITCH_DURING_TRANSCRIPTION,
            )
        } else {
            SharedStateTransition(nextState = SharedTranscriptionState.LOADING)
        }
    }

    fun completeModelLoad(success: Boolean): SharedTranscriptionState {
        return if (success) {
            SharedTranscriptionState.READY
        } else {
            SharedTranscriptionState.ERROR
        }
    }

    fun beginBatchTranscription(
        currentState: SharedTranscriptionState,
        hasLoadedModel: Boolean,
        audioByteCount: Int,
    ): SharedStateTransition {
        if (!hasLoadedModel) {
            return SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.MODEL_NOT_LOADED,
            )
        }

        if (audioByteCount <= 0) {
            return SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.INVALID_AUDIO_DATA,
            )
        }

        if (currentState == SharedTranscriptionState.TRANSCRIBING || currentState == SharedTranscriptionState.STREAMING) {
            return SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.TRANSCRIPTION_ALREADY_IN_PROGRESS,
            )
        }

        return SharedStateTransition(nextState = SharedTranscriptionState.TRANSCRIBING)
    }

    fun completeBatchTranscription(): SharedTranscriptionState {
        return SharedTranscriptionState.READY
    }

    fun stateAfterUnload(): SharedTranscriptionState {
        return SharedTranscriptionState.UNLOADED
    }

    fun stateAfterStreamingPrepared(currentState: SharedTranscriptionState): SharedTranscriptionState {
        return when (currentState) {
            SharedTranscriptionState.UNLOADED,
            SharedTranscriptionState.ERROR,
            -> SharedTranscriptionState.READY
            else -> currentState
        }
    }

    fun failStreamingPreparation(): SharedTranscriptionState {
        return SharedTranscriptionState.ERROR
    }

    fun beginStreaming(
        currentState: SharedTranscriptionState,
        hasPreparedStreamingEngine: Boolean,
    ): SharedStateTransition {
        if (currentState == SharedTranscriptionState.TRANSCRIBING || currentState == SharedTranscriptionState.STREAMING) {
            return SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.TRANSCRIPTION_ALREADY_IN_PROGRESS,
            )
        }

        if (!hasPreparedStreamingEngine) {
            return SharedStateTransition(
                nextState = currentState,
                errorCode = SharedSessionErrorCode.STREAMING_NOT_READY,
            )
        }

        return SharedStateTransition(nextState = SharedTranscriptionState.STREAMING)
    }

    fun validateStreamingAudio(isStreamingSessionActive: Boolean): SharedSessionErrorCode? {
        return if (isStreamingSessionActive) {
            null
        } else {
            SharedSessionErrorCode.STREAMING_NOT_READY
        }
    }

    fun completeStreamingSession(
        hasLoadedModel: Boolean,
        hasPreparedStreamingEngine: Boolean,
    ): SharedTranscriptionState {
        return if (hasLoadedModel || hasPreparedStreamingEngine) {
            SharedTranscriptionState.READY
        } else {
            SharedTranscriptionState.UNLOADED
        }
    }

    fun planSession(policy: TranscriptionRuntimePolicy): SharedOrchestrationPlan {
        val useStreaming = shouldUseStreamingTranscription(
            streamingFeatureEnabled = policy.streamingFeatureEnabled,
            outputMode = policy.outputMode,
            aiEnhancementEnabled = policy.aiEnhancementEnabled,
            isQuickCaptureMode = policy.isQuickCaptureMode,
        )

        return SharedOrchestrationPlan(
            useStreaming = useStreaming,
            useSpeakerDiarization = shouldUseSpeakerDiarization(
                diarizationFeatureEnabled = policy.diarizationFeatureEnabled,
                isStreamingSessionActive = useStreaming,
            ),
        )
    }

    fun shouldUseStreamingTranscription(
        streamingFeatureEnabled: Boolean,
        outputMode: String,
        aiEnhancementEnabled: Boolean,
        isQuickCaptureMode: Boolean,
    ): Boolean {
        return streamingFeatureEnabled &&
            outputMode == "directInsert" &&
            !aiEnhancementEnabled &&
            !isQuickCaptureMode
    }

    fun shouldUseSpeakerDiarization(
        diarizationFeatureEnabled: Boolean,
        isStreamingSessionActive: Boolean,
    ): Boolean {
        return diarizationFeatureEnabled && !isStreamingSessionActive
    }

    fun normalizeTranscriptionText(text: String): String {
        return text.trim()
    }

    fun isTranscriptionEffectivelyEmpty(text: String): Boolean {
        val normalized = normalizeTranscriptionText(text)
        return normalized.isEmpty() || normalized.equals("[BLANK AUDIO]", ignoreCase = true)
    }

    fun shouldPersistHistory(outputSucceeded: Boolean, text: String): Boolean {
        return outputSucceeded && !isTranscriptionEffectivelyEmpty(text)
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

    fun providerSupportsLocalLoading(provider: TranscriptionProviderId): Boolean {
        return provider == TranscriptionProviderId.WHISPER_KIT || provider == TranscriptionProviderId.PARAKEET
    }

    fun planModelLoad(
        requestedProvider: TranscriptionProviderId,
        currentProvider: TranscriptionProviderId?,
        loadsFromPath: Boolean,
    ): SharedModelLoadPlan {
        val resolvedProvider = if (loadsFromPath) {
            TranscriptionProviderId.WHISPER_KIT
        } else {
            requestedProvider
        }

        return SharedModelLoadPlan(
            resolvedProvider = resolvedProvider,
            shouldUnloadCurrentModel = currentProvider != null && currentProvider != resolvedProvider,
            supportsLocalModelLoading = providerSupportsLocalLoading(resolvedProvider),
            prefersPathBasedLoading = loadsFromPath && resolvedProvider == TranscriptionProviderId.WHISPER_KIT,
        )
    }

    fun planTranscriptionExecution(
        selectedProvider: TranscriptionProviderId,
        selectedModelId: TranscriptionModelId,
        diarizationRequested: Boolean,
        isStreamingSessionActive: Boolean,
    ): SharedTranscriptionExecutionPlan {
        return SharedTranscriptionExecutionPlan(
            selectedProvider = selectedProvider,
            selectedModelId = selectedModelId,
            useSpeakerDiarization = diarizationRequested && !isStreamingSessionActive,
            shouldNormalizeOutput = true,
        )
    }

    fun recommendedModels(
        allModels: List<ModelDescriptor>,
        curatedIds: List<TranscriptionModelId>,
        language: TranscriptionLanguage,
    ): List<ModelDescriptor> {
        val ranks = curatedIds.withIndex().associate { it.value to it.index }
        return allModels
            .filter { it.id in curatedIds }
            .filter { supportsLanguage(it.languageSupport, language) }
            .sortedBy { ranks[it.id] ?: Int.MAX_VALUE }
    }

    fun resolveStartupModel(
        selectedModelId: TranscriptionModelId,
        defaultModelId: TranscriptionModelId,
        availableModels: List<ModelDescriptor>,
        downloadedModelIds: List<TranscriptionModelId>,
    ): StartupModelResolution {
        val normalizedSelectedModel = availableModels.firstOrNull { it.id == selectedModelId }
            ?: availableModels.firstOrNull { it.id == defaultModelId }
            ?: availableModels.firstOrNull()
            ?: error("availableModels must not be empty")

        val downloadedSet = downloadedModelIds.toSet()
        if (normalizedSelectedModel.id in downloadedSet) {
            return StartupModelResolution(
                action = StartupModelAction.LOAD_SELECTED,
                resolvedModel = normalizedSelectedModel,
                updatedSelectedModelId = normalizedSelectedModel.id,
            )
        }

        val fallbackModel = availableModels.firstOrNull { it.id in downloadedSet }
        if (fallbackModel != null) {
            return StartupModelResolution(
                action = StartupModelAction.LOAD_FALLBACK,
                resolvedModel = fallbackModel,
                updatedSelectedModelId = fallbackModel.id,
            )
        }

        return StartupModelResolution(
            action = StartupModelAction.DOWNLOAD_SELECTED,
            resolvedModel = normalizedSelectedModel,
            updatedSelectedModelId = normalizedSelectedModel.id,
        )
    }

    fun determineEventTapRecovery(
        elapsedSinceLastDisableSeconds: Double?,
        consecutiveDisableCount: Int,
        disableLoopWindowSeconds: Double,
        maxReenableAttemptsBeforeRecreate: Int,
    ): EventTapRecoveryDecision {
        val nextCount = if (
            elapsedSinceLastDisableSeconds != null &&
            elapsedSinceLastDisableSeconds <= disableLoopWindowSeconds
        ) {
            consecutiveDisableCount + 1
        } else {
            1
        }

        val recreateThreshold = maxOf(1, maxReenableAttemptsBeforeRecreate)
        val action = if (nextCount >= recreateThreshold) {
            EventTapRecoveryAction.RECREATE
        } else {
            EventTapRecoveryAction.REENABLE
        }

        return EventTapRecoveryDecision(
            consecutiveDisableCount = nextCount,
            action = action,
        )
    }

    fun shouldRunLiveContextSession(
        aiEnhancementEnabled: Boolean,
        uiContextEnabled: Boolean,
        liveSessionEnabled: Boolean,
    ): Boolean {
        return aiEnhancementEnabled && uiContextEnabled && liveSessionEnabled
    }

    fun shouldAppendTransition(
        signature: String,
        trigger: String,
        lastSignature: String?,
    ): Boolean {
        if (trigger == "recording_start") {
            return true
        }

        return lastSignature == null || lastSignature != signature
    }
}
