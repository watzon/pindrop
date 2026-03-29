package tech.watzon.pindrop.shared.runtime.transcription

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult

class LocalTranscriptionRuntimeTest {
    @Test
    fun catalogPreservesRecommendedOrder() {
        val models = LocalTranscriptionCatalog.recommendedModels(
            platform = LocalPlatformId.MACOS,
            language = TranscriptionLanguage.ENGLISH,
        )

        assertEquals(
            listOf(
                "openai_whisper-base.en",
                "openai_whisper-small.en",
                "openai_whisper-medium",
                "openai_whisper-large-v3_turbo",
                "parakeet-tdt-0.6b-v2",
            ),
            models.map { it.id.value },
        )
    }

    @Test
    fun catalogMapsProviderByPlatform() {
        val macWhisper = LocalTranscriptionCatalog.model(LocalPlatformId.MACOS, TranscriptionModelId("openai_whisper-base"))
        val linuxWhisper = LocalTranscriptionCatalog.model(LocalPlatformId.LINUX, TranscriptionModelId("openai_whisper-base"))
        val windowsParakeet = LocalTranscriptionCatalog.model(LocalPlatformId.WINDOWS, TranscriptionModelId("parakeet-tdt-0.6b-v3"))

        assertEquals(LocalModelProvider.WHISPER_KIT, macWhisper?.provider)
        assertEquals(LocalModelProvider.WCPP, linuxWhisper?.provider)
        assertEquals(LocalModelProvider.PARAKEET_NATIVE, windowsParakeet?.provider)
    }

    @Test
    fun startupResolutionMatchesSelectedFallbackRules() = runTest {
        val runtime = runtimeWith(
            installed = listOf(
                InstalledModelRecord(
                    modelId = TranscriptionModelId("openai_whisper-base"),
                    state = ModelInstallState.INSTALLED,
                    storage = ModelStorageLayout("/tmp", "/tmp/base"),
                    installedProvider = LocalModelProvider.WHISPER_KIT,
                ),
            ),
        )

        runtime.refreshInstalledModels()
        val resolution = runtime.resolveStartupModel(
            selectedModelId = TranscriptionModelId("missing"),
            defaultModelId = TranscriptionModelId("openai_whisper-base.en"),
        )

        assertEquals(LocalModelSelectionAction.LOAD_FALLBACK, resolution.action)
        assertEquals("openai_whisper-base", resolution.updatedSelectedModelId.value)
    }

    @Test
    fun runtimeLoadsTranscribesAndUnloadsThroughBackend() = runTest {
        val backend = FakeBackend()
        val runtime = runtimeWith(
            installed = listOf(
                InstalledModelRecord(
                    modelId = TranscriptionModelId("openai_whisper-base"),
                    state = ModelInstallState.INSTALLED,
                    storage = ModelStorageLayout("/tmp", "/tmp/base"),
                    installedProvider = LocalModelProvider.WHISPER_KIT,
                ),
            ),
            backendRegistry = FakeBackendRegistry(
                preferredByModelId = mapOf("openai_whisper-base" to LocalBackendId.WHISPER_KIT),
                backends = mapOf(LocalBackendId.WHISPER_KIT to backend),
            ),
        )

        runtime.refreshInstalledModels()
        runtime.loadModel(TranscriptionModelId("openai_whisper-base"))
        val result = runtime.transcribe(TranscriptionRequest(audioData = byteArrayOf(1, 2, 3)))
        runtime.unloadModel()

        assertEquals("ok", result.text)
        assertEquals(LocalRuntimeState.UNLOADED, runtime.state)
        assertEquals(1, backend.transcribeCalls)
    }

    @Test
    fun runtimeRejectsEmptyAudio() = runTest {
        val backend = FakeBackend()
        val runtime = runtimeWith(
            installed = listOf(
                InstalledModelRecord(
                    modelId = TranscriptionModelId("openai_whisper-base"),
                    state = ModelInstallState.INSTALLED,
                    storage = ModelStorageLayout("/tmp", "/tmp/base"),
                    installedProvider = LocalModelProvider.WHISPER_KIT,
                ),
            ),
            backendRegistry = FakeBackendRegistry(
                preferredByModelId = mapOf("openai_whisper-base" to LocalBackendId.WHISPER_KIT),
                backends = mapOf(LocalBackendId.WHISPER_KIT to backend),
            ),
        )

        runtime.refreshInstalledModels()
        runtime.loadModel(TranscriptionModelId("openai_whisper-base"))

        assertFailsWith<IllegalArgumentException> {
            runtime.transcribe(TranscriptionRequest(audioData = byteArrayOf()))
        }
        assertEquals(LocalRuntimeErrorCode.INVALID_AUDIO_DATA, runtime.lastErrorCode)
    }

    @Test
    fun runtimeReportsBackendUnavailable() = runTest {
        val runtime = runtimeWith(
            installed = listOf(
                InstalledModelRecord(
                    modelId = TranscriptionModelId("parakeet-tdt-0.6b-v3"),
                    state = ModelInstallState.INSTALLED,
                    storage = ModelStorageLayout("/tmp", "/tmp/v3"),
                    installedProvider = LocalModelProvider.PARAKEET_NATIVE,
                ),
            ),
            backendRegistry = FakeBackendRegistry(
                preferredByModelId = emptyMap(),
                backends = emptyMap(),
            ),
        )

        runtime.refreshInstalledModels()
        runtime.loadModel(TranscriptionModelId("parakeet-tdt-0.6b-v3"))

        assertEquals(LocalRuntimeState.ERROR, runtime.state)
        assertEquals(LocalRuntimeErrorCode.BACKEND_UNAVAILABLE, runtime.lastErrorCode)
    }

    @Test
    fun languageSupportMatchesCurrentSemantics() {
        assertNotNull(
            LocalTranscriptionCatalog.recommendedModels(LocalPlatformId.MACOS, TranscriptionLanguage.SPANISH)
                .firstOrNull { it.languageSupport == ModelLanguageSupport.PARAKEET_V3_EUROPEAN },
        )
        assertNull(
            LocalTranscriptionCatalog.recommendedModels(LocalPlatformId.MACOS, TranscriptionLanguage.SPANISH)
                .firstOrNull { it.languageSupport == ModelLanguageSupport.ENGLISH_ONLY },
        )
    }

    private fun runtimeWith(
        installed: List<InstalledModelRecord>,
        backendRegistry: BackendRegistryPort = FakeBackendRegistry(
            preferredByModelId = mapOf("openai_whisper-base" to LocalBackendId.WHISPER_KIT),
            backends = mapOf(LocalBackendId.WHISPER_KIT to FakeBackend()),
        ),
    ): LocalTranscriptionRuntime {
        return LocalTranscriptionRuntime(
            platform = LocalPlatformId.MACOS,
            installedModelIndex = FakeInstalledModelIndex(installed),
            modelInstaller = FakeInstaller(installed.toMutableList()),
            backendRegistry = backendRegistry,
        )
    }
}

private class FakeInstalledModelIndex(
    private val installed: List<InstalledModelRecord>,
) : InstalledModelIndexPort {
    override suspend fun refreshInstalledModels(): List<InstalledModelRecord> = installed
}

private class FakeInstaller(
    private val installed: MutableList<InstalledModelRecord>,
) : ModelInstallerPort {
    override suspend fun installModel(
        model: LocalModelDescriptor,
        onProgress: (ModelInstallProgress) -> Unit,
    ): InstalledModelRecord {
        onProgress(
            ModelInstallProgress(
                modelId = model.id,
                progress = 1.0,
                state = ModelInstallState.INSTALLED,
            ),
        )
        return InstalledModelRecord(
            modelId = model.id,
            state = ModelInstallState.INSTALLED,
            storage = ModelStorageLayout("/tmp", "/tmp/${model.id.value}"),
            installedProvider = model.provider,
        ).also(installed::add)
    }

    override suspend fun deleteModel(model: LocalModelDescriptor) {
        installed.removeAll { it.modelId == model.id }
    }
}

private class FakeBackend : LocalInferenceBackendPort {
    override val backendId: LocalBackendId = LocalBackendId.WHISPER_KIT
    override val supportedFamilies: Set<LocalModelFamily> = setOf(LocalModelFamily.WHISPER, LocalModelFamily.PARAKEET)
    override val supportsPathLoading: Boolean = true
    var transcribeCalls: Int = 0

    override suspend fun loadModel(
        model: LocalModelDescriptor,
        installedRecord: InstalledModelRecord?,
    ) = Unit

    override suspend fun loadModelFromPath(path: String) = Unit

    override suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        transcribeCalls += 1
        return TranscriptionResult(text = "ok")
    }

    override suspend fun unloadModel() = Unit
}

private class FakeBackendRegistry(
    private val preferredByModelId: Map<String, LocalBackendId>,
    private val backends: Map<LocalBackendId, LocalInferenceBackendPort>,
) : BackendRegistryPort {
    override fun preferredBackend(model: LocalModelDescriptor): LocalBackendId? {
        return preferredByModelId[model.id.value]
    }

    override fun backend(id: LocalBackendId): LocalInferenceBackendPort? {
        return backends[id]
    }
}
