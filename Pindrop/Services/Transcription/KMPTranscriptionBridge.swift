//
//  KMPTranscriptionBridge.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import Foundation

#if canImport(PindropSharedTranscription)
import PindropSharedTranscription
#endif

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
    static func normalizeTranscriptionText(_ text: String) -> String {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.normalizeTranscriptionText(text: text)
        #else
        text.trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
    }

    static func isTranscriptionEffectivelyEmpty(_ text: String) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.isTranscriptionEffectivelyEmpty(text: text)
        #else
        let normalizedText = normalizeTranscriptionText(text)
        if normalizedText.isEmpty {
            return true
        }

        return normalizedText.caseInsensitiveCompare("[BLANK AUDIO]") == .orderedSame
        #endif
    }

    static func shouldPersistHistory(outputSucceeded: Bool, text: String) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.shouldPersistHistory(
            outputSucceeded: outputSucceeded,
            text: text
        )
        #else
        outputSucceeded && !isTranscriptionEffectivelyEmpty(text)
        #endif
    }

    static func shouldUseStreamingTranscription(
        streamingFeatureEnabled: Bool,
        outputMode: OutputMode,
        aiEnhancementEnabled: Bool,
        isQuickCaptureMode: Bool
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.shouldUseStreamingTranscription(
            streamingFeatureEnabled: streamingFeatureEnabled,
            outputMode: outputMode.kmpValue,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )
        #else
        streamingFeatureEnabled &&
            outputMode == .directInsert &&
            !aiEnhancementEnabled &&
            !isQuickCaptureMode
        #endif
    }

    static func shouldUseSpeakerDiarization(
        diarizationFeatureEnabled: Bool,
        isStreamingSessionActive: Bool
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: diarizationFeatureEnabled,
            isStreamingSessionActive: isStreamingSessionActive
        )
        #else
        diarizationFeatureEnabled && !isStreamingSessionActive
        #endif
    }

    static func providerSupportsLocalModelLoading(
        _ provider: ModelManager.ModelProvider
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.providerSupportsLocalLoading(
            provider: coreProvider(from: provider)
        )
        #else
        provider == .whisperKit || provider == .parakeet
        #endif
    }

    static func modelSupportsLanguage(
        _ support: ModelManager.LanguageSupport,
        language: AppLanguage
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.supportsLanguage(
            support: coreLanguageSupport(from: support),
            language: coreLanguage(from: language)
        )
        #else
        if language == .automatic {
            return true
        }

        switch support {
        case .englishOnly:
            return language == .english
        case .fullMultilingual:
            return true
        case .parakeetV3European:
            switch language {
            case .automatic, .english, .spanish, .french, .german, .portugueseBrazil, .italian, .dutch, .turkish:
                return true
            case .simplifiedChinese, .japanese, .korean:
                return false
            }
        }
        #endif
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
        #if canImport(PindropSharedTranscription)
        let policy = TranscriptionRuntimePolicy(
            selectedProvider: coreProvider(from: selectedProvider),
            selectedModelId: CoreTranscriptionModelId(value: selectedModelName),
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
        #else
        let useStreaming = shouldUseStreamingTranscription(
            streamingFeatureEnabled: streamingFeatureEnabled,
            outputMode: outputMode,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )

        return SharedTranscriptionSessionPlan(
            useStreaming: useStreaming,
            useSpeakerDiarization: shouldUseSpeakerDiarization(
                diarizationFeatureEnabled: diarizationFeatureEnabled,
                isStreamingSessionActive: useStreaming
            )
        )
        #endif
    }

    static func planModelLoad(
        requestedProvider: ModelManager.ModelProvider,
        currentProvider: ModelManager.ModelProvider?,
        loadsFromPath: Bool
    ) -> SharedModelLoadPlan {
        #if canImport(PindropSharedTranscription)
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
        #else
        let resolvedProvider: ModelManager.ModelProvider = loadsFromPath ? .whisperKit : requestedProvider
        return SharedModelLoadPlan(
            resolvedProvider: resolvedProvider,
            shouldUnloadCurrentModel: currentProvider != nil && currentProvider != resolvedProvider,
            supportsLocalModelLoading: resolvedProvider.isLocal,
            prefersPathBasedLoading: loadsFromPath && resolvedProvider == .whisperKit
        )
        #endif
    }

    static func planTranscriptionExecution(
        selectedProvider: ModelManager.ModelProvider,
        selectedModelName: String,
        diarizationRequested: Bool,
        isStreamingSessionActive: Bool
    ) -> SharedTranscriptionExecutionPlan {
        #if canImport(PindropSharedTranscription)
        let plan = SharedTranscriptionOrchestrator.shared.planTranscriptionExecution(
            selectedProvider: coreProvider(from: selectedProvider),
            selectedModelId: CoreTranscriptionModelId(value: selectedModelName),
            diarizationRequested: diarizationRequested,
            isStreamingSessionActive: isStreamingSessionActive
        )

        return SharedTranscriptionExecutionPlan(
            selectedProvider: modelProvider(from: plan.selectedProvider),
            selectedModelId: plan.selectedModelId.value,
            useSpeakerDiarization: plan.useSpeakerDiarization,
            shouldNormalizeOutput: plan.shouldNormalizeOutput
        )
        #else
        SharedTranscriptionExecutionPlan(
            selectedProvider: selectedProvider,
            selectedModelId: selectedModelName,
            useSpeakerDiarization: diarizationRequested && !isStreamingSessionActive,
            shouldNormalizeOutput: true
        )
        #endif
    }

    static func beginModelLoad(
        currentState: TranscriptionService.State
    ) -> SharedTranscriptionStateTransition {
        #if canImport(PindropSharedTranscription)
        let transition = SharedTranscriptionOrchestrator.shared.beginModelLoad(
            currentState: coreState(from: currentState)
        )
        return stateTransition(from: transition)
        #else
        if currentState == .transcribing {
            return SharedTranscriptionStateTransition(
                nextState: currentState,
                errorCode: .engineSwitchDuringTranscription
            )
        }

        return SharedTranscriptionStateTransition(nextState: .loading, errorCode: nil)
        #endif
    }

    static func completeModelLoad(success: Bool) -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeModelLoad(success: success)
        )
        #else
        success ? .ready : .error
        #endif
    }

    static func beginBatchTranscription(
        currentState: TranscriptionService.State,
        hasLoadedModel: Bool,
        audioByteCount: Int
    ) -> SharedTranscriptionStateTransition {
        #if canImport(PindropSharedTranscription)
        let transition = SharedTranscriptionOrchestrator.shared.beginBatchTranscription(
            currentState: coreState(from: currentState),
            hasLoadedModel: hasLoadedModel,
            audioByteCount: Int32(audioByteCount)
        )
        return stateTransition(from: transition)
        #else
        if !hasLoadedModel {
            return SharedTranscriptionStateTransition(nextState: currentState, errorCode: .modelNotLoaded)
        }
        if audioByteCount <= 0 {
            return SharedTranscriptionStateTransition(nextState: currentState, errorCode: .invalidAudioData)
        }
        if currentState == .transcribing {
            return SharedTranscriptionStateTransition(nextState: currentState, errorCode: .transcriptionAlreadyInProgress)
        }

        return SharedTranscriptionStateTransition(nextState: .transcribing, errorCode: nil)
        #endif
    }

    static func completeBatchTranscription() -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeBatchTranscription()
        )
        #else
        .ready
        #endif
    }

    static func stateAfterUnload() -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.stateAfterUnload()
        )
        #else
        .unloaded
        #endif
    }

    static func stateAfterStreamingPrepared(
        currentState: TranscriptionService.State
    ) -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.stateAfterStreamingPrepared(
                currentState: coreState(from: currentState)
            )
        )
        #else
        switch currentState {
        case .unloaded, .error:
            .ready
        case .loading, .ready, .transcribing:
            currentState
        }
        #endif
    }

    static func failStreamingPreparation() -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.failStreamingPreparation()
        )
        #else
        .error
        #endif
    }

    static func beginStreaming(
        currentState: TranscriptionService.State,
        hasPreparedStreamingEngine: Bool
    ) -> SharedTranscriptionStateTransition {
        #if canImport(PindropSharedTranscription)
        let transition = SharedTranscriptionOrchestrator.shared.beginStreaming(
            currentState: coreState(from: currentState),
            hasPreparedStreamingEngine: hasPreparedStreamingEngine
        )
        return stateTransition(from: transition)
        #else
        if currentState == .transcribing {
            return SharedTranscriptionStateTransition(nextState: currentState, errorCode: .transcriptionAlreadyInProgress)
        }
        if !hasPreparedStreamingEngine {
            return SharedTranscriptionStateTransition(nextState: currentState, errorCode: .streamingNotReady)
        }

        return SharedTranscriptionStateTransition(nextState: .transcribing, errorCode: nil)
        #endif
    }

    static func validateStreamingAudio(
        isStreamingSessionActive: Bool
    ) -> SharedTranscriptionSessionErrorCode? {
        #if canImport(PindropSharedTranscription)
        sessionErrorCode(
            from: SharedTranscriptionOrchestrator.shared.validateStreamingAudio(
                isStreamingSessionActive: isStreamingSessionActive
            )
        )
        #else
        isStreamingSessionActive ? nil : .streamingNotReady
        #endif
    }

    static func completeStreamingSession(
        hasLoadedModel: Bool,
        hasPreparedStreamingEngine: Bool
    ) -> TranscriptionService.State {
        #if canImport(PindropSharedTranscription)
        serviceState(
            from: SharedTranscriptionOrchestrator.shared.completeStreamingSession(
                hasLoadedModel: hasLoadedModel,
                hasPreparedStreamingEngine: hasPreparedStreamingEngine
            )
        )
        #else
        (hasLoadedModel || hasPreparedStreamingEngine) ? .ready : .unloaded
        #endif
    }

    static func recommendedModels(
        availableModels: [ModelManager.WhisperModel],
        for language: AppLanguage
    ) -> [ModelManager.WhisperModel] {
        #if canImport(PindropSharedTranscription)
        let orchestrator = SharedTranscriptionOrchestrator.shared
        let curatedIds = recommendedModelNames(for: language).map { CoreTranscriptionModelId(value: $0) }
        let descriptors = availableModels.map(coreDescriptor(from:))
        let language = coreLanguage(from: language)

        let orderedDescriptors = orchestrator.recommendedModels(
            allModels: descriptors,
            curatedIds: curatedIds,
            language: language
        )

        let modelsByName = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.name, $0) })
        return orderedDescriptors.compactMap { modelsByName[$0.id.value] }
        #else
        let recommendedModelNames = recommendedModelNames(for: language)
        let recommendationRanks = Dictionary(
            uniqueKeysWithValues: recommendedModelNames.enumerated().map { index, name in
                (name, index)
            }
        )

        return availableModels
            .filter { recommendedModelNames.contains($0.name) }
            .filter { $0.supports(language: language) }
            .sorted {
                recommendationRanks[$0.name, default: .max] < recommendationRanks[$1.name, default: .max]
            }
        #endif
    }

    static func resolveStartupModel(
        selectedModelId: String,
        defaultModelId: String,
        availableModels: [ModelManager.WhisperModel],
        downloadedModelIds: [String]
    ) -> SharedStartupModelResolution {
        #if canImport(PindropSharedTranscription)
        let orchestrator = SharedTranscriptionOrchestrator.shared
        let descriptors = availableModels.map(coreDescriptor(from:))
        let modelsByName = Dictionary(uniqueKeysWithValues: availableModels.map { ($0.name, $0) })

        let resolution = orchestrator.resolveStartupModel(
            selectedModelId: CoreTranscriptionModelId(value: selectedModelId),
            defaultModelId: CoreTranscriptionModelId(value: defaultModelId),
            availableModels: descriptors,
            downloadedModelIds: downloadedModelIds.map(CoreTranscriptionModelId.init(value:))
        )

        let resolvedModel = modelsByName[resolution.resolvedModel.id.value] ?? availableModels.first!
        return SharedStartupModelResolution(
            action: startupAction(from: resolution.action),
            resolvedModel: resolvedModel,
            updatedSelectedModelId: resolution.updatedSelectedModelId.value
        )
        #else
        let selectedModel = availableModels.first(where: { $0.name == selectedModelId })
            ?? availableModels.first(where: { $0.name == defaultModelId })
            ?? availableModels.first!

        if downloadedModelIds.contains(selectedModel.name) {
            return SharedStartupModelResolution(
                action: .loadSelected,
                resolvedModel: selectedModel,
                updatedSelectedModelId: selectedModel.name
            )
        }

        if let fallbackModel = availableModels.first(where: { downloadedModelIds.contains($0.name) }) {
            return SharedStartupModelResolution(
                action: .loadFallback,
                resolvedModel: fallbackModel,
                updatedSelectedModelId: fallbackModel.name
            )
        }

        return SharedStartupModelResolution(
            action: .downloadSelected,
            resolvedModel: selectedModel,
            updatedSelectedModelId: selectedModel.name
        )
        #endif
    }

    static func determineEventTapRecovery(
        elapsedSinceLastDisable: TimeInterval?,
        consecutiveDisableCount: Int,
        disableLoopWindow: TimeInterval,
        maxReenableAttemptsBeforeRecreate: Int
    ) -> SharedEventTapRecoveryDecision {
        #if canImport(PindropSharedTranscription)
        let decision = SharedTranscriptionOrchestrator.shared.determineEventTapRecovery(
            elapsedSinceLastDisableSeconds: elapsedSinceLastDisable.map(NSNumber.init(value:)),
            consecutiveDisableCount: Int32(consecutiveDisableCount),
            disableLoopWindowSeconds: disableLoopWindow,
            maxReenableAttemptsBeforeRecreate: Int32(maxReenableAttemptsBeforeRecreate)
        )

        return SharedEventTapRecoveryDecision(
            consecutiveDisableCount: Int(decision.consecutiveDisableCount),
            action: eventTapRecoveryAction(from: decision.action)
        )
        #else
        let nextCount: Int
        if let elapsedSinceLastDisable, elapsedSinceLastDisable <= disableLoopWindow {
            nextCount = consecutiveDisableCount + 1
        } else {
            nextCount = 1
        }

        return SharedEventTapRecoveryDecision(
            consecutiveDisableCount: nextCount,
            action: nextCount >= max(1, maxReenableAttemptsBeforeRecreate) ? .recreate : .reenable
        )
        #endif
    }

    static func shouldRunLiveContextSession(
        aiEnhancementEnabled: Bool,
        uiContextEnabled: Bool,
        liveSessionEnabled: Bool
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.shouldRunLiveContextSession(
            aiEnhancementEnabled: aiEnhancementEnabled,
            uiContextEnabled: uiContextEnabled,
            liveSessionEnabled: liveSessionEnabled
        )
        #else
        aiEnhancementEnabled && uiContextEnabled && liveSessionEnabled
        #endif
    }

    static func shouldAppendTransition(
        signature: String,
        trigger: String,
        lastSignature: String?
    ) -> Bool {
        #if canImport(PindropSharedTranscription)
        SharedTranscriptionOrchestrator.shared.shouldAppendTransition(
            signature: signature,
            trigger: trigger,
            lastSignature: lastSignature
        )
        #else
        trigger == "recordingStart" || lastSignature == nil || lastSignature != signature
        #endif
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

#if canImport(PindropSharedTranscription)
private extension KMPTranscriptionBridge {
    static func coreProvider(from provider: ModelManager.ModelProvider) -> CoreTranscriptionProviderId {
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

    static func modelProvider(from provider: CoreTranscriptionProviderId) -> ModelManager.ModelProvider {
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

    static func coreLanguage(from language: AppLanguage) -> CoreTranscriptionLanguage {
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
    ) -> CoreModelLanguageSupport {
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
    ) -> CoreModelAvailability {
        switch availability {
        case .available:
            .available
        case .comingSoon:
            .comingSoon
        case .requiresSetup:
            .requiresSetup
        }
    }

    static func coreDescriptor(from model: ModelManager.WhisperModel) -> CoreModelDescriptor {
        CoreModelDescriptor(
            id: CoreTranscriptionModelId(value: model.name),
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

    static func coreState(from state: TranscriptionService.State) -> CoreSharedTranscriptionState {
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

    static func serviceState(from state: CoreSharedTranscriptionState) -> TranscriptionService.State {
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
#endif
