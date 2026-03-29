//
//  KMPTranscriptionBridge.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import Foundation

import PindropSharedTranscription

struct SharedTranscriptionSessionPlan: Equatable, Sendable {
    let useStreaming: Bool
    let useSpeakerDiarization: Bool
}

struct SharedModelLoadPlan: Equatable, Sendable {
    let resolvedProvider: ModelManager.ModelProvider
    let shouldUnloadCurrentModel: Bool
    let supportsLocalModelLoading: Bool
    let prefersPathBasedLoading: Bool
}

struct SharedTranscriptionExecutionPlan: Equatable, Sendable {
    let selectedProvider: ModelManager.ModelProvider
    let selectedModelId: String
    let useSpeakerDiarization: Bool
    let shouldNormalizeOutput: Bool
}

enum SharedStartupModelAction: Sendable {
    case loadSelected
    case loadFallback
    case downloadSelected
}

struct SharedStartupModelResolution: Sendable {
    let action: SharedStartupModelAction
    let resolvedModel: ModelManager.WhisperModel
    let updatedSelectedModelId: String
}

enum SharedEventTapRecoveryAction: Sendable {
    case reenable
    case recreate
}

struct SharedEventTapRecoveryDecision: Sendable, Equatable {
    let consecutiveDisableCount: Int
    let action: SharedEventTapRecoveryAction
}

enum SharedTranscriptionSessionErrorCode: Sendable {
    case engineSwitchDuringTranscription
    case modelNotLoaded
    case invalidAudioData
    case transcriptionAlreadyInProgress
    case streamingNotReady
}

struct SharedTranscriptionStateTransition: Equatable, Sendable {
    let nextState: TranscriptionService.State
    let errorCode: SharedTranscriptionSessionErrorCode?
}

enum KMPTranscriptionBridge {
    static func localAvailableModels() -> [ModelManager.WhisperModel] {
        LocalTranscriptionCatalog.shared.models(platform: localPlatform()).map(localModel(from:))
    }

    static func recommendedLocalModels(for language: AppLanguage) -> [ModelManager.WhisperModel] {
        LocalTranscriptionCatalog.shared.recommendedModels(
            platform: localPlatform(),
            language: coreLanguage(from: language)
        ).map(localModel(from:))
    }

    static func normalizeTranscriptionText(_ text: String) -> String {
        SharedTranscriptionOrchestrator.shared.normalizeTranscriptionText(text: text)
    }

    static func isTranscriptionEffectivelyEmpty(_ text: String) -> Bool {
        SharedTranscriptionOrchestrator.shared.isTranscriptionEffectivelyEmpty(text: text)
    }

    static func shouldPersistHistory(outputSucceeded: Bool, text: String) -> Bool {
        SharedTranscriptionOrchestrator.shared.shouldPersistHistory(
            outputSucceeded: outputSucceeded,
            text: text
        )
    }

    static func shouldUseStreamingTranscription(
        streamingFeatureEnabled: Bool,
        outputMode: OutputMode,
        aiEnhancementEnabled: Bool,
        isQuickCaptureMode: Bool
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.shouldUseStreamingTranscription(
            streamingFeatureEnabled: streamingFeatureEnabled,
            outputMode: outputMode.kmpValue,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )
    }

    static func shouldUseSpeakerDiarization(
        diarizationFeatureEnabled: Bool,
        isStreamingSessionActive: Bool
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: diarizationFeatureEnabled,
            isStreamingSessionActive: isStreamingSessionActive
        )
    }

    static func providerSupportsLocalModelLoading(
        _ provider: ModelManager.ModelProvider
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.providerSupportsLocalLoading(
            provider: coreProvider(from: provider)
        )
    }

    static func modelSupportsLanguage(
        _ support: ModelManager.LanguageSupport,
        language: AppLanguage
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.supportsLanguage(
            support: coreLanguageSupport(from: support),
            language: coreLanguage(from: language)
        )
    }

    static func planSession(
        selectedProvider: ModelManager.ModelProvider,
        selectedModelName: String,
        streamingFeatureEnabled: Bool,
        diarizationFeatureEnabled: Bool,
        outputMode: OutputMode,
        aiEnhancementEnabled: Bool,
        isQuickCaptureMode: Bool
    ) -> SharedTranscriptionSessionPlan {
        let policy = TranscriptionRuntimePolicy(
            selectedProvider: coreProvider(from: selectedProvider),
            selectedModelId: TranscriptionModelId(value: selectedModelName),
            streamingFeatureEnabled: streamingFeatureEnabled,
            diarizationFeatureEnabled: diarizationFeatureEnabled,
            outputMode: outputMode.kmpValue,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )

        let plan = SharedTranscriptionOrchestrator.shared.planSession(policy: policy)
        return SharedTranscriptionSessionPlan(
            useStreaming: plan.useStreaming,
            useSpeakerDiarization: plan.useSpeakerDiarization
        )
    }

    static func planModelLoad(
        requestedProvider: ModelManager.ModelProvider,
        currentProvider: ModelManager.ModelProvider?,
        loadsFromPath: Bool
    ) -> SharedModelLoadPlan {
        let plan = SharedTranscriptionOrchestrator.shared.planModelLoad(
            requestedProvider: coreProvider(from: requestedProvider),
            currentProvider: currentProvider.map { coreProvider(from: $0) },
            loadsFromPath: loadsFromPath
        )

        return SharedModelLoadPlan(
            resolvedProvider: modelProvider(from: plan.resolvedProvider),
            shouldUnloadCurrentModel: plan.shouldUnloadCurrentModel,
            supportsLocalModelLoading: plan.supportsLocalModelLoading,
            prefersPathBasedLoading: plan.prefersPathBasedLoading
        )
    }

    static func planTranscriptionExecution(
        selectedProvider: ModelManager.ModelProvider,
        selectedModelName: String,
        diarizationRequested: Bool,
        isStreamingSessionActive: Bool
    ) -> SharedTranscriptionExecutionPlan {
        let plan = SharedTranscriptionOrchestrator.shared.planTranscriptionExecution(
            selectedProvider: coreProvider(from: selectedProvider),
            selectedModelId: TranscriptionModelId(value: selectedModelName),
            diarizationRequested: diarizationRequested,
            isStreamingSessionActive: isStreamingSessionActive
        )

        return SharedTranscriptionExecutionPlan(
            selectedProvider: modelProvider(from: plan.selectedProvider),
            selectedModelId: plan.selectedModelId.value,
            useSpeakerDiarization: plan.useSpeakerDiarization,
            shouldNormalizeOutput: plan.shouldNormalizeOutput
        )
    }

    static func beginModelLoad(
        currentState: TranscriptionService.State
    ) -> SharedTranscriptionStateTransition {
        let transition = SharedTranscriptionOrchestrator.shared.beginModelLoad(
            currentState: coreState(from: currentState)
        )
        return stateTransition(from: transition)
    }

    static func completeModelLoad(success: Bool) -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeModelLoad(success: success)
        )
    }

    static func beginBatchTranscription(
        currentState: TranscriptionService.State,
        hasLoadedModel: Bool,
        audioByteCount: Int
    ) -> SharedTranscriptionStateTransition {
        let transition = SharedTranscriptionOrchestrator.shared.beginBatchTranscription(
            currentState: coreState(from: currentState),
            hasLoadedModel: hasLoadedModel,
            audioByteCount: Int32(audioByteCount)
        )
        return stateTransition(from: transition)
    }

    static func completeBatchTranscription() -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeBatchTranscription()
        )
    }

    static func stateAfterUnload() -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.stateAfterUnload()
        )
    }

    static func stateAfterStreamingPrepared(
        currentState: TranscriptionService.State
    ) -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.stateAfterStreamingPrepared(
                currentState: coreState(from: currentState)
            )
        )
    }

    static func failStreamingPreparation() -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.failStreamingPreparation()
        )
    }

    static func beginStreaming(
        currentState: TranscriptionService.State,
        hasPreparedStreamingEngine: Bool
    ) -> SharedTranscriptionStateTransition {
        let transition = SharedTranscriptionOrchestrator.shared.beginStreaming(
            currentState: coreState(from: currentState),
            hasPreparedStreamingEngine: hasPreparedStreamingEngine
        )
        return stateTransition(from: transition)
    }

    static func validateStreamingAudio(
        isStreamingSessionActive: Bool
    ) -> SharedTranscriptionSessionErrorCode? {
        sessionErrorCode(
            from: SharedTranscriptionOrchestrator.shared.validateStreamingAudio(
                isStreamingSessionActive: isStreamingSessionActive
            )
        )
    }

    static func completeStreamingSession(
        hasLoadedModel: Bool,
        hasPreparedStreamingEngine: Bool
    ) -> TranscriptionService.State {
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeStreamingSession(
                hasLoadedModel: hasLoadedModel,
                hasPreparedStreamingEngine: hasPreparedStreamingEngine
            )
        )
    }

    static func recommendedModels(
        availableModels: [ModelManager.WhisperModel],
        for language: AppLanguage
    ) -> [ModelManager.WhisperModel] {
        let orchestrator = SharedTranscriptionOrchestrator.shared
        let curatedIds = recommendedModelNames(for: language).map { TranscriptionModelId(value: $0) }
        let descriptors = availableModels.map(coreDescriptor(from:))
        let language = coreLanguage(from: language)

        let orderedDescriptors = orchestrator.recommendedModels(
            allModels: descriptors,
            curatedIds: curatedIds,
            language: language
        )

        let modelsByName = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.name, $0) })
        return orderedDescriptors.compactMap { modelsByName[$0.id.value] }
    }

    static func resolveStartupModel(
        selectedModelId: String,
        defaultModelId: String,
        availableModels: [ModelManager.WhisperModel],
        downloadedModelIds: [String]
    ) -> SharedStartupModelResolution {
        let orchestrator = SharedTranscriptionOrchestrator.shared
        let descriptors = availableModels.map(coreDescriptor(from:))
        let modelsByName = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.name, $0) })

        let resolution = orchestrator.resolveStartupModel(
            selectedModelId: TranscriptionModelId(value: selectedModelId),
            defaultModelId: TranscriptionModelId(value: defaultModelId),
            availableModels: descriptors,
            downloadedModelIds: downloadedModelIds.map { TranscriptionModelId(value: $0) }
        )

        let resolvedModel = modelsByName[resolution.resolvedModel.id.value] ?? availableModels.first!
        return SharedStartupModelResolution(
            action: startupAction(from: resolution.action),
            resolvedModel: resolvedModel,
            updatedSelectedModelId: resolution.updatedSelectedModelId.value
        )
    }

    static func determineEventTapRecovery(
        elapsedSinceLastDisable: TimeInterval?,
        consecutiveDisableCount: Int,
        disableLoopWindow: TimeInterval,
        maxReenableAttemptsBeforeRecreate: Int
    ) -> SharedEventTapRecoveryDecision {
        let decision = SharedTranscriptionOrchestrator.shared.determineEventTapRecovery(
            elapsedSinceLastDisableSeconds: elapsedSinceLastDisable.map(KotlinDouble.init(value:)),
            consecutiveDisableCount: Int32(consecutiveDisableCount),
            disableLoopWindowSeconds: disableLoopWindow,
            maxReenableAttemptsBeforeRecreate: Int32(maxReenableAttemptsBeforeRecreate)
        )

        return SharedEventTapRecoveryDecision(
            consecutiveDisableCount: Int(decision.consecutiveDisableCount),
            action: eventTapRecoveryAction(from: decision.action)
        )
    }

    static func shouldRunLiveContextSession(
        aiEnhancementEnabled: Bool,
        uiContextEnabled: Bool,
        liveSessionEnabled: Bool
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.shouldRunLiveContextSession(
            aiEnhancementEnabled: aiEnhancementEnabled,
            uiContextEnabled: uiContextEnabled,
            liveSessionEnabled: liveSessionEnabled
        )
    }

    static func shouldAppendTransition(
        signature: String,
        trigger: String,
        lastSignature: String?
    ) -> Bool {
        SharedTranscriptionOrchestrator.shared.shouldAppendTransition(
            signature: signature,
            trigger: trigger,
            lastSignature: lastSignature
        )
    }

    private static func recommendedModelNames(for language: AppLanguage) -> [String] {
        switch language {
        case .english:
            ModelManager.englishRecommendedModelNames
        case .automatic,
             .simplifiedChinese,
             .spanish,
             .french,
             .german,
             .turkish,
             .japanese,
             .portugueseBrazil,
             .italian,
             .dutch,
             .korean:
            ModelManager.multilingualRecommendedModelNames
        }
    }
}

private extension KMPTranscriptionBridge {
    static func coreProvider(from provider: ModelManager.ModelProvider) -> TranscriptionProviderId {
        switch provider {
        case .whisperKit:
            .whisperKit
        case .parakeet:
            .parakeet
        case .openAI:
            .openAi
        case .elevenLabs:
            .elevenLabs
        case .groq:
            .groq
        }
    }

    static func modelProvider(from provider: TranscriptionProviderId) -> ModelManager.ModelProvider {
        switch provider {
        case .whisperKit:
            .whisperKit
        case .parakeet:
            .parakeet
        case .openAi:
            .openAI
        case .elevenLabs:
            .elevenLabs
        case .groq:
            .groq
        default:
            .whisperKit
        }
    }

    static func coreLanguage(from language: AppLanguage) -> TranscriptionLanguage {
        switch language {
        case .automatic:
            .automatic
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .spanish:
            .spanish
        case .french:
            .french
        case .german:
            .german
        case .turkish:
            .turkish
        case .japanese:
            .japanese
        case .portugueseBrazil:
            .portugueseBrazil
        case .italian:
            .italian
        case .dutch:
            .dutch
        case .korean:
            .korean
        }
    }

    static func coreLanguageSupport(
        from support: ModelManager.LanguageSupport
    ) -> ModelLanguageSupport {
        switch support {
        case .englishOnly:
            .englishOnly
        case .fullMultilingual:
            .fullMultilingual
        case .parakeetV3European:
            .parakeetV3European
        }
    }

    static func coreAvailability(
        from availability: ModelManager.ModelAvailability
    ) -> ModelAvailability {
        switch availability {
        case .available:
            .available
        case .comingSoon:
            .comingSoon
        case .requiresSetup:
            .requiresSetup
        }
    }

    static func coreDescriptor(from model: ModelManager.WhisperModel) -> ModelDescriptor {
        ModelDescriptor(
            id: TranscriptionModelId(value: model.name),
            displayName: model.displayName,
            provider: coreProvider(from: model.provider),
            languageSupport: coreLanguageSupport(from: model.languageSupport),
            sizeInMb: Int32(model.sizeInMB),
            description: model.description,
            speedRating: model.speedRating,
            accuracyRating: model.accuracyRating,
            availability: coreAvailability(from: model.availability)
        )
    }

    static func localProvider(
        from provider: LocalModelProvider
    ) -> ModelManager.ModelProvider {
        switch provider {
        case .whisperKit, .wcpp:
            .whisperKit
        case .parakeetCoreml, .parakeetNative:
            .parakeet
        default:
            .whisperKit
        }
    }

    static func localAvailability(
        from availability: ModelAvailability
    ) -> ModelManager.ModelAvailability {
        switch availability {
        case .available:
            .available
        case .comingSoon:
            .comingSoon
        case .requiresSetup:
            .requiresSetup
        default:
            .available
        }
    }

    static func localLanguageSupport(
        from support: ModelLanguageSupport
    ) -> ModelManager.LanguageSupport {
        switch support {
        case .englishOnly:
            .englishOnly
        case .fullMultilingual:
            .fullMultilingual
        case .parakeetV3European:
            .parakeetV3European
        default:
            .fullMultilingual
        }
    }

    static func localModel(
        from descriptor: LocalModelDescriptor
    ) -> ModelManager.WhisperModel {
        ModelManager.WhisperModel(
            name: descriptor.id.value,
            displayName: descriptor.displayName,
            sizeInMB: Int(descriptor.sizeInMb),
            description: descriptor.description_,
            speedRating: descriptor.speedRating,
            accuracyRating: descriptor.accuracyRating,
            languageSupport: localLanguageSupport(from: descriptor.languageSupport),
            provider: localProvider(from: descriptor.provider),
            availability: localAvailability(from: descriptor.availability)
        )
    }

    static func localPlatform() -> LocalPlatformId {
        #if os(macOS)
        .macos
        #elseif os(Windows)
        .windows
        #else
        .linux
        #endif
    }

    static func coreState(from state: TranscriptionService.State) -> SharedTranscriptionState {
        switch state {
        case .unloaded:
            .unloaded
        case .loading:
            .loading
        case .ready:
            .ready
        case .transcribing:
            .transcribing
        case .error:
            .error
        }
    }

    static func serviceState(from state: SharedTranscriptionState) -> TranscriptionService.State {
        switch state {
        case .unloaded:
            .unloaded
        case .loading:
            .loading
        case .ready:
            .ready
        case .transcribing, .streaming:
            .transcribing
        case .error:
            .error
        default:
            .ready
        }
    }

    static func sessionErrorCode(
        from errorCode: SharedSessionErrorCode?
    ) -> SharedTranscriptionSessionErrorCode? {
        guard let errorCode else { return nil }

        switch errorCode {
        case .engineSwitchDuringTranscription:
            return .engineSwitchDuringTranscription
        case .modelNotLoaded:
            return .modelNotLoaded
        case .invalidAudioData:
            return .invalidAudioData
        case .transcriptionAlreadyInProgress:
            return .transcriptionAlreadyInProgress
        case .streamingNotReady:
            return .streamingNotReady
        default:
            return nil
        }
    }

    static func stateTransition(
        from transition: SharedStateTransition
    ) -> SharedTranscriptionStateTransition {
        SharedTranscriptionStateTransition(
            nextState: serviceState(from: transition.nextState),
            errorCode: sessionErrorCode(from: transition.errorCode)
        )
    }

    static func startupAction(from action: StartupModelAction) -> SharedStartupModelAction {
        switch action {
        case .loadSelected:
            .loadSelected
        case .loadFallback:
            .loadFallback
        case .downloadSelected:
            .downloadSelected
        default:
            .loadSelected
        }
    }

    static func eventTapRecoveryAction(
        from action: EventTapRecoveryAction
    ) -> SharedEventTapRecoveryAction {
        switch action {
        case .reenable:
            .reenable
        case .recreate:
            .recreate
        default:
            .reenable
        }
    }
}

private extension OutputMode {
    var kmpValue: String {
        switch self {
        case .clipboard:
            "clipboard"
        case .directInsert:
            "directInsert"
        }
    }
}
