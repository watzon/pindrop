package tech.watzon.pindrop.shared.runtime.transcription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.encodeUtf8
import okio.Path.Companion.toPath
import okio.fakefilesystem.FakeFileSystem
import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionModelId

class FileSystemModelStorageTest {
    @Test
    fun installedModelIndexReadsInstalledDirectories() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        fileSystem.createDirectories(installRoot / "openai_whisper-base")
        fileSystem.write((installRoot / "openai_whisper-base" / ".installed")) {
            write("ok".encodeUtf8())
        }
        fileSystem.write((installRoot / "openai_whisper-base" / ".provider")) {
            write("WCPP".encodeUtf8())
        }
        fileSystem.write((installRoot / "openai_whisper-base" / "model.gguf")) {
            write("binary".encodeUtf8())
        }

        val index = FileSystemInstalledModelIndex(fileSystem = fileSystem, installRoot = installRoot)
        val records = index.refreshInstalledModels()

        assertEquals(1, records.size)
        assertEquals(ModelInstallState.INSTALLED, records.single().state)
        assertEquals(LocalModelProvider.WCPP, records.single().installedProvider)
        assertTrue(records.single().storage.modelPath?.endsWith("model.gguf") == true)
    }

    @Test
    fun installerDownloadsArtifactsAtomicallyAndIndexSeesThem() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        val model = whisperModel()
        val installer = FileSystemModelInstaller(
            fileSystem = fileSystem,
            installRoot = installRoot,
            repository = FakeRepository(
                artifacts = listOf(
                    RemoteModelArtifact(
                        fileName = "model.gguf",
                        downloadUrl = "https://example.invalid/model.gguf",
                        sizeBytes = 6,
                    ),
                ),
            ),
            downloadClient = FakeDownloadClient(
                fileSystem = fileSystem,
                contentByUrl = mapOf(
                    "https://example.invalid/model.gguf" to "binary".encodeUtf8(),
                ),
            ),
        )

        val progress = mutableListOf<ModelInstallProgress>()
        val record = installer.installModel(model) { progress += it }
        val indexed = FileSystemInstalledModelIndex(fileSystem, installRoot).refreshInstalledModels()

        assertEquals(ModelInstallState.INSTALLED, record.state)
        assertTrue(progress.any { it.state == ModelInstallState.INSTALLING })
        assertEquals(ModelInstallState.INSTALLED, progress.last().state)
        assertEquals(model.id, indexed.single().modelId)
        assertTrue(fileSystem.exists(installRoot / model.id.value / "model.gguf"))
        assertFalse(fileSystem.exists(installRoot / ".tmp" / model.id.value))
    }

    @Test
    fun installerMarksFailuresAndCleansTempDirectory() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        val model = whisperModel()
        val installer = FileSystemModelInstaller(
            fileSystem = fileSystem,
            installRoot = installRoot,
            repository = FakeRepository(
                artifacts = listOf(
                    RemoteModelArtifact(
                        fileName = "model.gguf",
                        downloadUrl = "https://example.invalid/model.gguf",
                    ),
                ),
            ),
            downloadClient = object : DownloadClientPort {
                override suspend fun download(
                    artifact: RemoteModelArtifact,
                    destination: okio.Path,
                    onProgress: (bytesDownloaded: Long, totalBytes: Long?) -> Unit,
                ) {
                    onProgress(0, artifact.sizeBytes)
                    error("network failed")
                }
            },
        )

        runCatching {
            installer.installModel(model) { }
        }

        val records = FileSystemInstalledModelIndex(fileSystem, installRoot).refreshInstalledModels()
        val failed = records.single()
        assertEquals(ModelInstallState.FAILED, failed.state)
        assertNotNull(failed.lastError)
        assertFalse(fileSystem.exists(installRoot / ".tmp" / model.id.value))
    }

    @Test
    fun installerDeletesInstalledModelDirectory() = runTest {
        val fileSystem = FakeFileSystem()
        val installRoot = "/models".toPath()
        val model = whisperModel()
        val installer = FileSystemModelInstaller(
            fileSystem = fileSystem,
            installRoot = installRoot,
            repository = FakeRepository(emptyList()),
            downloadClient = FakeDownloadClient(fileSystem, emptyMap()),
        )

        fileSystem.createDirectories(installRoot / model.id.value)
        fileSystem.write((installRoot / model.id.value / ".installed")) { write("ok".encodeUtf8()) }

        installer.deleteModel(model)

        assertFalse(fileSystem.exists(installRoot / model.id.value))
    }

    private fun whisperModel(): LocalModelDescriptor {
        return LocalModelDescriptor(
            id = TranscriptionModelId("openai_whisper-base"),
            family = LocalModelFamily.WHISPER,
            provider = LocalModelProvider.WCPP,
            supportedBackends = setOf(LocalBackendId.WHISPER_CPP),
            displayName = "Whisper Base",
            languageSupport = ModelLanguageSupport.FULL_MULTILINGUAL,
            sizeInMb = 145,
            description = "Test model",
            speedRating = 9.0,
            accuracyRating = 7.0,
            availability = ModelAvailability.AVAILABLE,
        )
    }
}

private class FakeRepository(
    private val artifacts: List<RemoteModelArtifact>,
) : RemoteModelRepositoryPort {
    override fun artifactsFor(model: LocalModelDescriptor): List<RemoteModelArtifact> = artifacts
}

private class FakeDownloadClient(
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
        onProgress(content.size.toLong(), artifact.sizeBytes ?: content.size.toLong())
    }
}
