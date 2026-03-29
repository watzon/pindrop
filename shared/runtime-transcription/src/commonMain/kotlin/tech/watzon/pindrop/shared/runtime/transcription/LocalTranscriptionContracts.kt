package tech.watzon.pindrop.shared.runtime.transcription

import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult

enum class LocalModelFamily {
    WHISPER,
    PARAKEET,
}

enum class LocalModelProvider {
    WHISPER_KIT,
    WCPP,
    PARAKEET_COREML,
    PARAKEET_NATIVE,
}

enum class LocalBackendId {
    WHISPER_KIT,
    WHISPER_CPP,
    PARAKEET_APPLE,
    PARAKEET_NATIVE,
}

enum class LocalPlatformId {
    MACOS,
    WINDOWS,
    LINUX,
}

enum class ModelInstallState {
    NOT_INSTALLED,
    INSTALLING,
    INSTALLED,
    FAILED,
}

enum class LocalRuntimeState {
    UNLOADED,
    LOADING,
    READY,
    TRANSCRIBING,
    INSTALLING,
    ERROR,
}

enum class LocalRuntimeErrorCode {
    MODEL_NOT_FOUND,
    MODEL_NOT_INSTALLED,
    BACKEND_UNAVAILABLE,
    UNSUPPORTED_ON_PLATFORM,
    ENGINE_SWITCH_DURING_TRANSCRIPTION,
    INVALID_AUDIO_DATA,
    TRANSCRIPTION_ALREADY_IN_PROGRESS,
    TRANSCRIPTION_FAILED,
    INSTALL_FAILED,
    DELETE_FAILED,
    LOAD_FAILED,
}

data class ModelStorageLayout(
    val installRootPath: String,
    val modelPath: String?,
)

data class LocalModelDescriptor(
    val id: TranscriptionModelId,
    val family: LocalModelFamily,
    val provider: LocalModelProvider,
    val displayName: String,
    val languageSupport: ModelLanguageSupport,
    val sizeInMb: Int,
    val description: String,
    val speedRating: Double,
    val accuracyRating: Double,
    val availability: ModelAvailability,
)

data class ModelInstallProgress(
    val modelId: TranscriptionModelId,
    val progress: Double,
    val state: ModelInstallState,
    val message: String? = null,
)

data class InstalledModelRecord(
    val modelId: TranscriptionModelId,
    val state: ModelInstallState,
    val storage: ModelStorageLayout,
    val installedProvider: LocalModelProvider? = null,
    val lastError: String? = null,
)

enum class LocalModelSelectionAction {
    LOAD_SELECTED,
    LOAD_FALLBACK,
    DOWNLOAD_SELECTED,
}

data class LocalModelSelectionResolution(
    val action: LocalModelSelectionAction,
    val resolvedModel: LocalModelDescriptor,
    val updatedSelectedModelId: TranscriptionModelId,
)

data class ActiveLocalModel(
    val descriptor: LocalModelDescriptor,
    val installedRecord: InstalledModelRecord? = null,
    val loadedFromPath: String? = null,
)

interface InstalledModelIndexPort {
    suspend fun refreshInstalledModels(): List<InstalledModelRecord>
}

interface ModelInstallerPort {
    suspend fun installModel(
        model: LocalModelDescriptor,
        onProgress: (ModelInstallProgress) -> Unit,
    ): InstalledModelRecord

    suspend fun deleteModel(model: LocalModelDescriptor)
}

interface LocalInferenceBackendPort {
    val backendId: LocalBackendId
    val supportedFamilies: Set<LocalModelFamily>
    val supportsPathLoading: Boolean

    suspend fun loadModel(
        model: LocalModelDescriptor,
        installedRecord: InstalledModelRecord?,
    )

    suspend fun loadModelFromPath(path: String)
    suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult
    suspend fun unloadModel()
}

interface BackendRegistryPort {
    fun preferredBackend(model: LocalModelDescriptor): LocalBackendId?
    fun backend(id: LocalBackendId): LocalInferenceBackendPort?
}

interface RuntimeObserver {
    fun onStateChanged(state: LocalRuntimeState)
    fun onActiveModelChanged(model: ActiveLocalModel?)
    fun onInstallProgress(progress: ModelInstallProgress?)
    fun onErrorChanged(errorCode: LocalRuntimeErrorCode?, message: String?)
}
