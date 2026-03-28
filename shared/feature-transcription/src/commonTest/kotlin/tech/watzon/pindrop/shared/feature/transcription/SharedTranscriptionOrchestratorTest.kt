package tech.watzon.pindrop.shared.feature.transcription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import tech.watzon.pindrop.shared.core.SharedTranscriptionState
import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.ModelDescriptor
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionProviderId

class SharedTranscriptionOrchestratorTest {
    @Test
    fun stateMachinePreventsLoadWhileTranscribing() {
        val transition = SharedTranscriptionOrchestrator.beginModelLoad(
            currentState = SharedTranscriptionState.TRANSCRIBING,
        )

        assertEquals(SharedTranscriptionState.TRANSCRIBING, transition.nextState)
        assertEquals(SharedSessionErrorCode.ENGINE_SWITCH_DURING_TRANSCRIPTION, transition.errorCode)
    }

    @Test
    fun stateMachineValidatesBatchTranscriptionPreconditions() {
        val unloaded = SharedTranscriptionOrchestrator.beginBatchTranscription(
            currentState = SharedTranscriptionState.UNLOADED,
            hasLoadedModel = false,
            audioByteCount = 128,
        )
        assertEquals(SharedSessionErrorCode.MODEL_NOT_LOADED, unloaded.errorCode)

        val emptyAudio = SharedTranscriptionOrchestrator.beginBatchTranscription(
            currentState = SharedTranscriptionState.READY,
            hasLoadedModel = true,
            audioByteCount = 0,
        )
        assertEquals(SharedSessionErrorCode.INVALID_AUDIO_DATA, emptyAudio.errorCode)

        val started = SharedTranscriptionOrchestrator.beginBatchTranscription(
            currentState = SharedTranscriptionState.READY,
            hasLoadedModel = true,
            audioByteCount = 128,
        )
        assertEquals(SharedTranscriptionState.TRANSCRIBING, started.nextState)
        assertNull(started.errorCode)
    }

    @Test
    fun stateMachineManagesStreamingLifecycle() {
        val begin = SharedTranscriptionOrchestrator.beginStreaming(
            currentState = SharedTranscriptionState.READY,
            hasPreparedStreamingEngine = true,
        )
        assertEquals(SharedTranscriptionState.STREAMING, begin.nextState)
        assertNull(begin.errorCode)

        assertEquals(
            SharedSessionErrorCode.STREAMING_NOT_READY,
            SharedTranscriptionOrchestrator.validateStreamingAudio(isStreamingSessionActive = false),
        )
        assertNull(SharedTranscriptionOrchestrator.validateStreamingAudio(isStreamingSessionActive = true))

        assertEquals(
            SharedTranscriptionState.READY,
            SharedTranscriptionOrchestrator.completeStreamingSession(
                hasLoadedModel = false,
                hasPreparedStreamingEngine = true,
            ),
        )
    }

    @Test
    fun streamingTruthTableMatchesMacOsPolicy() {
        assertTrue(
            SharedTranscriptionOrchestrator.shouldUseStreamingTranscription(
                streamingFeatureEnabled = true,
                outputMode = "directInsert",
                aiEnhancementEnabled = false,
                isQuickCaptureMode = false,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldUseStreamingTranscription(
                streamingFeatureEnabled = false,
                outputMode = "directInsert",
                aiEnhancementEnabled = false,
                isQuickCaptureMode = false,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldUseStreamingTranscription(
                streamingFeatureEnabled = true,
                outputMode = "clipboard",
                aiEnhancementEnabled = false,
                isQuickCaptureMode = false,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldUseStreamingTranscription(
                streamingFeatureEnabled = true,
                outputMode = "directInsert",
                aiEnhancementEnabled = true,
                isQuickCaptureMode = false,
            ),
        )
    }

    @Test
    fun diarizationTruthTableMatchesMacOsPolicy() {
        assertTrue(
            SharedTranscriptionOrchestrator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled = true,
                isStreamingSessionActive = false,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled = true,
                isStreamingSessionActive = true,
            ),
        )
    }

    @Test
    fun normalizationAndHistoryPersistenceMatchMacOsPolicy() {
        assertEquals("hello world", SharedTranscriptionOrchestrator.normalizeTranscriptionText("  hello world \n"))
        assertTrue(SharedTranscriptionOrchestrator.isTranscriptionEffectivelyEmpty("[blank audio]"))
        assertTrue(SharedTranscriptionOrchestrator.shouldPersistHistory(outputSucceeded = true, text = "hello"))
        assertFalse(SharedTranscriptionOrchestrator.shouldPersistHistory(outputSucceeded = false, text = "hello"))
    }

    @Test
    fun languageSupportMatchesParakeetAndEnglishOnlyRules() {
        assertTrue(
            SharedTranscriptionOrchestrator.supportsLanguage(
                ModelLanguageSupport.ENGLISH_ONLY,
                TranscriptionLanguage.ENGLISH,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.supportsLanguage(
                ModelLanguageSupport.ENGLISH_ONLY,
                TranscriptionLanguage.SPANISH,
            ),
        )
        assertTrue(
            SharedTranscriptionOrchestrator.supportsLanguage(
                ModelLanguageSupport.PARAKEET_V3_EUROPEAN,
                TranscriptionLanguage.SPANISH,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.supportsLanguage(
                ModelLanguageSupport.PARAKEET_V3_EUROPEAN,
                TranscriptionLanguage.SIMPLIFIED_CHINESE,
            ),
        )
    }

    @Test
    fun recommendedModelsFollowCuratedOrder() {
        val base = ModelDescriptor(
            id = TranscriptionModelId("base"),
            displayName = "Base",
            provider = TranscriptionProviderId.WHISPER_KIT,
            languageSupport = ModelLanguageSupport.FULL_MULTILINGUAL,
            sizeInMb = 145,
            description = "",
            speedRating = 9.0,
            accuracyRating = 7.0,
            availability = ModelAvailability.AVAILABLE,
        )
        val medium = base.copy(id = TranscriptionModelId("medium"), displayName = "Medium")
        val tiny = base.copy(id = TranscriptionModelId("tiny"), displayName = "Tiny")

        val result = SharedTranscriptionOrchestrator.recommendedModels(
            allModels = listOf(medium, tiny, base),
            curatedIds = listOf(tiny.id, base.id, medium.id),
            language = TranscriptionLanguage.ENGLISH,
        )

        assertEquals(listOf("tiny", "base", "medium"), result.map { it.id.value })
    }

    @Test
    fun modelLoadPlanningKeepsWhisperKitPrimaryForPathLoads() {
        val plan = SharedTranscriptionOrchestrator.planModelLoad(
            requestedProvider = TranscriptionProviderId.PARAKEET,
            currentProvider = TranscriptionProviderId.PARAKEET,
            loadsFromPath = true,
        )

        assertEquals(TranscriptionProviderId.WHISPER_KIT, plan.resolvedProvider)
        assertTrue(plan.shouldUnloadCurrentModel)
        assertTrue(plan.supportsLocalModelLoading)
        assertTrue(plan.prefersPathBasedLoading)
    }

    @Test
    fun transcriptionExecutionPlanningDisablesDiarizationDuringStreaming() {
        val plan = SharedTranscriptionOrchestrator.planTranscriptionExecution(
            selectedProvider = TranscriptionProviderId.WHISPER_KIT,
            selectedModelId = TranscriptionModelId("openai_whisper-base"),
            diarizationRequested = true,
            isStreamingSessionActive = true,
        )

        assertFalse(plan.useSpeakerDiarization)
        assertTrue(plan.shouldNormalizeOutput)
    }

    @Test
    fun startupModelResolutionFallsBackToDefaultWhenSelectedModelIsUnknown() {
        val defaultModel = ModelDescriptor(
            id = TranscriptionModelId("openai_whisper-base.en"),
            displayName = "Base",
            provider = TranscriptionProviderId.WHISPER_KIT,
            languageSupport = ModelLanguageSupport.ENGLISH_ONLY,
            sizeInMb = 145,
            description = "",
            speedRating = 9.0,
            accuracyRating = 7.0,
            availability = ModelAvailability.AVAILABLE,
        )

        val resolution = SharedTranscriptionOrchestrator.resolveStartupModel(
            selectedModelId = TranscriptionModelId("missing-model"),
            defaultModelId = defaultModel.id,
            availableModels = listOf(defaultModel),
            downloadedModelIds = listOf(defaultModel.id),
        )

        assertEquals(StartupModelAction.LOAD_SELECTED, resolution.action)
        assertEquals(defaultModel.id, resolution.resolvedModel.id)
        assertEquals(defaultModel.id, resolution.updatedSelectedModelId)
    }

    @Test
    fun startupModelResolutionUsesDownloadedFallbackWhenSelectedModelIsMissingLocally() {
        val selectedModel = ModelDescriptor(
            id = TranscriptionModelId("openai_whisper-base.en"),
            displayName = "Base",
            provider = TranscriptionProviderId.WHISPER_KIT,
            languageSupport = ModelLanguageSupport.ENGLISH_ONLY,
            sizeInMb = 145,
            description = "",
            speedRating = 9.0,
            accuracyRating = 7.0,
            availability = ModelAvailability.AVAILABLE,
        )
        val fallbackModel = selectedModel.copy(
            id = TranscriptionModelId("parakeet-tdt-0.6b-v2"),
            displayName = "Parakeet",
            provider = TranscriptionProviderId.PARAKEET,
        )

        val resolution = SharedTranscriptionOrchestrator.resolveStartupModel(
            selectedModelId = selectedModel.id,
            defaultModelId = selectedModel.id,
            availableModels = listOf(selectedModel, fallbackModel),
            downloadedModelIds = listOf(fallbackModel.id),
        )

        assertEquals(StartupModelAction.LOAD_FALLBACK, resolution.action)
        assertEquals(fallbackModel.id, resolution.resolvedModel.id)
        assertEquals(fallbackModel.id, resolution.updatedSelectedModelId)
    }

    @Test
    fun startupModelResolutionRequestsDownloadWhenNothingIsDownloaded() {
        val selectedModel = ModelDescriptor(
            id = TranscriptionModelId("openai_whisper-base.en"),
            displayName = "Base",
            provider = TranscriptionProviderId.WHISPER_KIT,
            languageSupport = ModelLanguageSupport.ENGLISH_ONLY,
            sizeInMb = 145,
            description = "",
            speedRating = 9.0,
            accuracyRating = 7.0,
            availability = ModelAvailability.AVAILABLE,
        )

        val resolution = SharedTranscriptionOrchestrator.resolveStartupModel(
            selectedModelId = selectedModel.id,
            defaultModelId = selectedModel.id,
            availableModels = listOf(selectedModel),
            downloadedModelIds = emptyList(),
        )

        assertEquals(StartupModelAction.DOWNLOAD_SELECTED, resolution.action)
        assertEquals(selectedModel.id, resolution.resolvedModel.id)
        assertEquals(selectedModel.id, resolution.updatedSelectedModelId)
    }

    @Test
    fun eventTapRecoveryRecreatesAfterRepeatedDisableBursts() {
        val decision = SharedTranscriptionOrchestrator.determineEventTapRecovery(
            elapsedSinceLastDisableSeconds = 0.2,
            consecutiveDisableCount = 2,
            disableLoopWindowSeconds = 1.0,
            maxReenableAttemptsBeforeRecreate = 3,
        )

        assertEquals(3, decision.consecutiveDisableCount)
        assertEquals(EventTapRecoveryAction.RECREATE, decision.action)
    }

    @Test
    fun liveContextSessionRequiresAllThreeFlags() {
        assertTrue(
            SharedTranscriptionOrchestrator.shouldRunLiveContextSession(
                aiEnhancementEnabled = true,
                uiContextEnabled = true,
                liveSessionEnabled = true,
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldRunLiveContextSession(
                aiEnhancementEnabled = true,
                uiContextEnabled = false,
                liveSessionEnabled = true,
            ),
        )
    }

    @Test
    fun transitionAppendSkipsDuplicateNonStartTransitions() {
        assertTrue(
            SharedTranscriptionOrchestrator.shouldAppendTransition(
                signature = "a",
                trigger = "recordingStart",
                lastSignature = "a",
            ),
        )
        assertFalse(
            SharedTranscriptionOrchestrator.shouldAppendTransition(
                signature = "a",
                trigger = "periodicRefresh",
                lastSignature = "a",
            ),
        )
        assertTrue(
            SharedTranscriptionOrchestrator.shouldAppendTransition(
                signature = "b",
                trigger = "periodicRefresh",
                lastSignature = "a",
            ),
        )
    }
}
