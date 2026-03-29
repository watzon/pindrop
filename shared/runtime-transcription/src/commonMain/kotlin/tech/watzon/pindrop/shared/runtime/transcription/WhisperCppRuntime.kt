package tech.watzon.pindrop.shared.runtime.transcription

import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult

interface WhisperCppBridgePort {
    suspend fun loadModel(modelPath: String)
    suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult
    suspend fun unloadModel()
}

class WhisperCppBackend(
    private val bridge: WhisperCppBridgePort,
) : LocalInferenceBackendPort {
    override val backendId: LocalBackendId = LocalBackendId.WHISPER_CPP
    override val supportedFamilies: Set<LocalModelFamily> = setOf(LocalModelFamily.WHISPER)
    override val supportsPathLoading: Boolean = true

    override suspend fun loadModel(
        model: LocalModelDescriptor,
        installedRecord: InstalledModelRecord?,
    ) {
        require(model.family in supportedFamilies) {
            "Backend $backendId does not support model family ${model.family}"
        }

        val modelPath = installedRecord?.storage?.modelPath
            ?: error("Installed model path is missing for ${model.id.value}")
        bridge.loadModel(modelPath)
    }

    override suspend fun loadModelFromPath(path: String) {
        bridge.loadModel(path)
    }

    override suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        return bridge.transcribe(request)
    }

    override suspend fun unloadModel() {
        bridge.unloadModel()
    }
}

class DefaultBackendRegistry(
    private val platform: LocalPlatformId,
    backends: Collection<LocalInferenceBackendPort>,
) : BackendRegistryPort {
    private val backendsById = backends.associateBy { it.backendId }

    override fun preferredBackend(model: LocalModelDescriptor): LocalBackendId? {
        return preferredBackendIds(model).firstOrNull { backendId ->
            backendId in model.supportedBackends && backendId in backendsById
        }
    }

    override fun backend(id: LocalBackendId): LocalInferenceBackendPort? = backendsById[id]

    private fun preferredBackendIds(model: LocalModelDescriptor): List<LocalBackendId> {
        return when (model.family) {
            LocalModelFamily.WHISPER -> {
                if (platform == LocalPlatformId.MACOS) {
                    listOf(LocalBackendId.WHISPER_KIT, LocalBackendId.WHISPER_CPP)
                } else {
                    listOf(LocalBackendId.WHISPER_CPP)
                }
            }

            LocalModelFamily.PARAKEET -> {
                if (platform == LocalPlatformId.MACOS) {
                    listOf(LocalBackendId.PARAKEET_APPLE, LocalBackendId.PARAKEET_NATIVE)
                } else {
                    listOf(LocalBackendId.PARAKEET_NATIVE)
                }
            }
        }
    }
}
