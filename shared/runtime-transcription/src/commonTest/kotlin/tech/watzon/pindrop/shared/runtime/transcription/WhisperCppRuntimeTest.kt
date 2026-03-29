package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.encodeUtf8
import okio.Path.Companion.toPath
import okio.fakefilesystem.FakeFileSystem
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class WhisperCppRuntimeTest {
    @Test
    fun repositoryReturnsCuratedArtifactForSupportedModel() {
        val repository = WhisperCppRemoteModelRepository()
        val model = requireNotNull(
            LocalTranscriptionCatalog.model(
                platform = LocalPlatformId.WINDOWS,
                modelId = TranscriptionModelId("openai_whisper-base.en"),
            ),
        )

        val artifacts = repository.artifactsFor(model)

        assertEquals(1, artifacts.size)
        assertEquals("ggml-base.en.bin", artifacts.single().fileName)
        assertTrue(artifacts.single().downloadUrl.endsWith("/ggml-base.en.bin"))
    }

    @Test
    fun unsupportedWhisperModelsRequireManualSetupOffMacos() {
        val curated = requireNotNull(
            LocalTranscriptionCatalog.model(
                platform = LocalPlatformId.LINUX,
                modelId = TranscriptionModelId("openai_whisper-base.en"),
            ),
        )
        val manualSetup = requireNotNull(
            LocalTranscriptionCatalog.model(
                platform = LocalPlatformId.LINUX,
                modelId = TranscriptionModelId("openai_whisper-large-v3-v20240930"),
            ),
        )
        val recommendedEnglish = LocalTranscriptionCatalog.recommendedModels(
            platform = LocalPlatformId.LINUX,
            language = TranscriptionLanguage.ENGLISH,
        )

        assertEquals(LocalModelProvider.WCPP, curated.provider)
        assertEquals(tech.watzon.pindrop.shared.core.ModelAvailability.AVAILABLE, curated.availability)
        assertEquals(tech.watzon.pindrop.shared.core.ModelAvailability.REQUIRES_SETUP, manualSetup.availability)
        assertFalse(recommendedEnglish.any { it.id == manualSetup.id })
    }

    @Test
    fun runtimeInstallsLoadsTranscribesAndDeletesWithWhisperCppBackend() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        val repository = WhisperCppRemoteModelRepository()
        val model = requireNotNull(
            LocalTranscriptionCatalog.model(
                platform = LocalPlatformId.WINDOWS,
                modelId = TranscriptionModelId("openai_whisper-base.en"),
            ),
        )
        val artifact = repository.artifactsFor(model).single()
        val bridge = FakeWhisperCppBridge()
        val runtime = LocalTranscriptionRuntime(
            platform = LocalPlatformId.WINDOWS,
            installedModelIndex = FileSystemInstalledModelIndex(fileSystem, installRoot),
            modelInstaller = FileSystemModelInstaller(
                fileSystem = fileSystem,
                installRoot = installRoot,
                repository = repository,
                downloadClient = FakeArtifactDownloadClient(
                    fileSystem = fileSystem,
                    contentByUrl = mapOf(artifact.downloadUrl to "binary".encodeUtf8()),
                ),
            ),
            backendRegistry = DefaultBackendRegistry(
                platform = LocalPlatformId.WINDOWS,
                backends = listOf(WhisperCppBackend(bridge)),
            ),
        )

        runtime.refreshInstalledModels()
        runtime.installModel(model.id)
        runtime.loadModel(model.id)
        val result = runtime.transcribe(TranscriptionRequest(audioData = byteArrayOf(1, 2, 3)))
        runtime.deleteModel(model.id)

        assertEquals("transcribed", result.text)
        assertEquals(listOf("/models/openai_whisper-base.en/ggml-base.en.bin"), bridge.loadedPaths)
        assertEquals(1, bridge.transcribeCalls)
        assertFalse(fileSystem.exists(installRoot / model.id.value))
        assertEquals(LocalRuntimeState.UNLOADED, runtime.state)
    }

    @Test
    fun factoryBuildsWorkingWhisperCppRuntimeFromSharedPieces() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        val bridge = FakeWhisperCppBridge()
        val runtime = WhisperCppRuntimeFactory.create(
            platform = LocalPlatformId.WINDOWS,
            fileSystem = fileSystem,
            installRoot = installRoot,
            httpClient = HttpClient(
                MockEngine { request ->
                    val fileName = request.url.encodedPath.substringAfterLast('/')
                    respond(
                        content = fileName.encodeUtf8().toByteArray(),
                        status = HttpStatusCode.OK,
                    )
                },
            ),
            bridge = bridge,
        )
        val modelId = TranscriptionModelId("openai_whisper-base.en")

        runtime.refreshInstalledModels()
        runtime.installModel(modelId)
        runtime.loadModel(modelId)
        val result = runtime.transcribe(TranscriptionRequest(audioData = byteArrayOf(4, 5, 6)))

        assertEquals("transcribed", result.text)
        assertEquals(
            listOf("/models/openai_whisper-base.en/ggml-base.en.bin"),
            bridge.loadedPaths,
        )
    }

    @Test
    fun defaultBackendRegistryPrefersRegisteredWhisperCppBackendOffMacos() {
        val backend = WhisperCppBackend(FakeWhisperCppBridge())
        val registry = DefaultBackendRegistry(
            platform = LocalPlatformId.LINUX,
            backends = listOf(backend),
        )
        val model = requireNotNull(
            LocalTranscriptionCatalog.model(
                platform = LocalPlatformId.LINUX,
                modelId = TranscriptionModelId("openai_whisper-base.en"),
            ),
        )

        assertEquals(LocalBackendId.WHISPER_CPP, registry.preferredBackend(model))
        assertNotNull(registry.backend(LocalBackendId.WHISPER_CPP))
    }
}

private class FakeWhisperCppBridge : WhisperCppBridgePort {
    val loadedPaths = mutableListOf<String>()
    var transcribeCalls: Int = 0

    override suspend fun loadModel(modelPath: String) {
        loadedPaths += modelPath
    }

    override suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        transcribeCalls += 1
        return TranscriptionResult(text = "transcribed")
    }

    override suspend fun unloadModel() = Unit
}

private class FakeArtifactDownloadClient(
    private val fileSystem: FakeFileSystem,
    private val contentByUrl: Map<String, okio.ByteString>,
) : DownloadClientPort {
    override suspend fun download(
        artifact: RemoteModelArtifact,
        destination: okio.Path,
        onProgress: (bytesDownloaded: Long, totalBytes: Long?) -> Unit,
    ) {
        val content = contentByUrl.getValue(artifact.downloadUrl)
        fileSystem.write(destination) {
            write(content)
        }
        onProgress(content.size.toLong(), content.size.toLong())
    }
}
