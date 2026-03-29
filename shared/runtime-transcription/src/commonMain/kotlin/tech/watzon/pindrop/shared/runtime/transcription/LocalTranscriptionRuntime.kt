package tech.watzon.pindrop.shared.runtime.transcription

import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult

class LocalTranscriptionRuntime(
    private val platform: LocalPlatformId,
    private val installedModelIndex: InstalledModelIndexPort,
    private val modelInstaller: ModelInstallerPort,
    private val backendRegistry: BackendRegistryPort,
    private val observer: RuntimeObserver? = null,
) {
    var state: LocalRuntimeState = LocalRuntimeState.UNLOADED
        private set

    var activeModel: ActiveLocalModel? = null
        private set

    var lastProgress: ModelInstallProgress? = null
        private set

    var lastErrorCode: LocalRuntimeErrorCode? = null
        private set

    var lastErrorMessage: String? = null
        private set

    private var installedModels: List<InstalledModelRecord> = emptyList()
    private var activeBackend: LocalInferenceBackendPort? = null

    fun catalog(): List<LocalModelDescriptor> = LocalTranscriptionCatalog.models(platform)

    fun recommendedModels(language: TranscriptionLanguage): List<LocalModelDescriptor> {
        return LocalTranscriptionCatalog.recommendedModels(platform, language)
    }

    suspend fun refreshInstalledModels(): List<InstalledModelRecord> {
        installedModels = installedModelIndex.refreshInstalledModels()
        return installedModels
    }

    fun installedModels(): List<InstalledModelRecord> = installedModels

    fun resolveStartupModel(
        selectedModelId: TranscriptionModelId,
        defaultModelId: TranscriptionModelId,
    ): LocalModelSelectionResolution {
        val models = catalog()
        val normalizedSelectedModel = models.firstOrNull { it.id == selectedModelId }
            ?: models.firstOrNull { it.id == defaultModelId }
            ?: models.first()

        val installedSet = installedModels
            .filter { it.state == ModelInstallState.INSTALLED }
            .map { it.modelId }
            .toSet()

        if (normalizedSelectedModel.id in installedSet) {
            return LocalModelSelectionResolution(
                action = LocalModelSelectionAction.LOAD_SELECTED,
                resolvedModel = normalizedSelectedModel,
                updatedSelectedModelId = normalizedSelectedModel.id,
            )
        }

        val fallbackModel = models.firstOrNull { it.id in installedSet }
        if (fallbackModel != null) {
            return LocalModelSelectionResolution(
                action = LocalModelSelectionAction.LOAD_FALLBACK,
                resolvedModel = fallbackModel,
                updatedSelectedModelId = fallbackModel.id,
            )
        }

        return LocalModelSelectionResolution(
            action = LocalModelSelectionAction.DOWNLOAD_SELECTED,
            resolvedModel = normalizedSelectedModel,
            updatedSelectedModelId = normalizedSelectedModel.id,
        )
    }

    suspend fun installModel(modelId: TranscriptionModelId): InstalledModelRecord {
        val model = requireModel(modelId)
        transitionTo(LocalRuntimeState.INSTALLING)
        clearError()

        return runCatching {
            val record = modelInstaller.installModel(model) { progress ->
                lastProgress = progress
                observer?.onInstallProgress(progress)
            }
            installedModels = refreshInstalledModels()
            transitionTo(if (activeModel != null) LocalRuntimeState.READY else LocalRuntimeState.UNLOADED)
            record
        }.getOrElse { error ->
            setError(LocalRuntimeErrorCode.INSTALL_FAILED, error.message)
            transitionTo(LocalRuntimeState.ERROR)
            throw error
        }
    }

    suspend fun deleteModel(modelId: TranscriptionModelId) {
        val model = requireModel(modelId)
        clearError()

        runCatching {
            if (activeModel?.descriptor?.id == modelId) {
                unloadModel()
            }
            modelInstaller.deleteModel(model)
            installedModels = refreshInstalledModels()
        }.getOrElse { error ->
            setError(LocalRuntimeErrorCode.DELETE_FAILED, error.message)
            throw error
        }
    }

    suspend fun loadModel(modelId: TranscriptionModelId) {
        if (state == LocalRuntimeState.TRANSCRIBING) {
            setError(LocalRuntimeErrorCode.ENGINE_SWITCH_DURING_TRANSCRIPTION, null)
            return
        }

        val model = requireModel(modelId)
        if (model.availability != ModelAvailability.AVAILABLE) {
            setError(LocalRuntimeErrorCode.UNSUPPORTED_ON_PLATFORM, "Model ${model.id.value} is not available")
            transitionTo(LocalRuntimeState.ERROR)
            return
        }

        val installedRecord = installedModels.firstOrNull {
            it.modelId == modelId && it.state == ModelInstallState.INSTALLED
        }
        if (installedRecord == null) {
            setError(LocalRuntimeErrorCode.MODEL_NOT_INSTALLED, null)
            transitionTo(LocalRuntimeState.ERROR)
            return
        }

        val backendId = backendRegistry.preferredBackend(model)
        val backend = backendId?.let(backendRegistry::backend)
        if (backend == null || model.family !in backend.supportedFamilies) {
            setError(LocalRuntimeErrorCode.BACKEND_UNAVAILABLE, null)
            transitionTo(LocalRuntimeState.ERROR)
            return
        }

        clearError()
        transitionTo(LocalRuntimeState.LOADING)

        runCatching {
            if (activeBackend != null && activeBackend !== backend) {
                activeBackend?.unloadModel()
            }

            backend.loadModel(model, installedRecord)
            activeBackend = backend
            activeModel = ActiveLocalModel(model, installedRecord = installedRecord)
            observer?.onActiveModelChanged(activeModel)
            transitionTo(LocalRuntimeState.READY)
        }.getOrElse { error ->
            setError(LocalRuntimeErrorCode.LOAD_FAILED, error.message)
            transitionTo(LocalRuntimeState.ERROR)
            throw error
        }
    }

    suspend fun loadModelFromPath(path: String, family: LocalModelFamily = LocalModelFamily.WHISPER) {
        if (state == LocalRuntimeState.TRANSCRIBING) {
            setError(LocalRuntimeErrorCode.ENGINE_SWITCH_DURING_TRANSCRIPTION, null)
            return
        }

        val backend = backendRegistry.backend(
            when (family) {
                LocalModelFamily.WHISPER -> LocalBackendId.WHISPER_KIT
                LocalModelFamily.PARAKEET -> LocalBackendId.PARAKEET_APPLE
            },
        )

        if (backend == null || !backend.supportsPathLoading) {
            setError(LocalRuntimeErrorCode.BACKEND_UNAVAILABLE, null)
            transitionTo(LocalRuntimeState.ERROR)
            return
        }

        clearError()
        transitionTo(LocalRuntimeState.LOADING)

        runCatching {
            if (activeBackend != null && activeBackend !== backend) {
                activeBackend?.unloadModel()
            }
            backend.loadModelFromPath(path)
            activeBackend = backend
            activeModel = null
            observer?.onActiveModelChanged(null)
            transitionTo(LocalRuntimeState.READY)
        }.getOrElse { error ->
            setError(LocalRuntimeErrorCode.LOAD_FAILED, error.message)
            transitionTo(LocalRuntimeState.ERROR)
            throw error
        }
    }

    suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        val backend = activeBackend
        if (backend == null) {
            setError(LocalRuntimeErrorCode.MODEL_NOT_INSTALLED, "No model is loaded")
            transitionTo(LocalRuntimeState.ERROR)
            error("No local transcription backend is loaded")
        }
        if (request.audioData.isEmpty()) {
            setError(LocalRuntimeErrorCode.INVALID_AUDIO_DATA, null)
            throw IllegalArgumentException("Audio data must not be empty")
        }
        if (state == LocalRuntimeState.TRANSCRIBING) {
            setError(LocalRuntimeErrorCode.TRANSCRIPTION_ALREADY_IN_PROGRESS, null)
            throw IllegalStateException("Transcription already in progress")
        }

        clearError()
        transitionTo(LocalRuntimeState.TRANSCRIBING)

        return runCatching {
            backend.transcribe(request)
        }.onSuccess {
            transitionTo(LocalRuntimeState.READY)
        }.getOrElse { error ->
            setError(LocalRuntimeErrorCode.TRANSCRIPTION_FAILED, error.message)
            transitionTo(LocalRuntimeState.ERROR)
            throw error
        }
    }

    suspend fun unloadModel() {
        activeBackend?.unloadModel()
        activeBackend = null
        activeModel = null
        observer?.onActiveModelChanged(null)
        clearError()
        transitionTo(LocalRuntimeState.UNLOADED)
    }

    private fun requireModel(modelId: TranscriptionModelId): LocalModelDescriptor {
        return LocalTranscriptionCatalog.model(platform, modelId)
            ?: run {
                setError(LocalRuntimeErrorCode.MODEL_NOT_FOUND, modelId.value)
                error("Model ${modelId.value} not found")
            }
    }

    private fun transitionTo(newState: LocalRuntimeState) {
        state = newState
        observer?.onStateChanged(newState)
    }

    private fun setError(errorCode: LocalRuntimeErrorCode, message: String?) {
        lastErrorCode = errorCode
        lastErrorMessage = message
        observer?.onErrorChanged(errorCode, message)
    }

    private fun clearError() {
        lastErrorCode = null
        lastErrorMessage = null
        observer?.onErrorChanged(null, null)
    }
}
