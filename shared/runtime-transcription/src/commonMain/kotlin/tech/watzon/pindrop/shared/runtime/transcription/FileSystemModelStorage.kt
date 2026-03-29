package tech.watzon.pindrop.shared.runtime.transcription

import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath
import okio.buffer
import okio.use
import tech.watzon.pindrop.shared.core.TranscriptionModelId

data class RemoteModelArtifact(
    val fileName: String,
    val downloadUrl: String,
    val sizeBytes: Long? = null,
    val sha256: String? = null,
)

interface RemoteModelRepositoryPort {
    fun artifactsFor(model: LocalModelDescriptor): List<RemoteModelArtifact>
}

interface DownloadClientPort {
    suspend fun download(
        artifact: RemoteModelArtifact,
        destination: Path,
        onProgress: (bytesDownloaded: Long, totalBytes: Long?) -> Unit,
    )
}

class FileSystemInstalledModelIndex(
    private val fileSystem: FileSystem,
    private val installRoot: Path,
) : InstalledModelIndexPort {
    override suspend fun refreshInstalledModels(): List<InstalledModelRecord> {
        if (!fileSystem.exists(installRoot)) {
            return emptyList()
        }

        return fileSystem.list(installRoot)
            .filter { candidate ->
                fileSystem.metadataOrNull(candidate)?.isDirectory == true &&
                    !candidate.name.startsWith(".")
            }
            .map(::recordForModelDirectory)
    }

    private fun recordForModelDirectory(modelDirectory: Path): InstalledModelRecord {
        val modelId = TranscriptionModelId(modelDirectory.name)
        val provider = readProvider(modelDirectory)
        val modelFile = fileSystem.list(modelDirectory)
            .firstOrNull { child ->
                fileSystem.metadataOrNull(child)?.isRegularFile == true &&
                    child.name !in RESERVED_FILE_NAMES
            }

        val installState = when {
            fileSystem.exists(modelDirectory / INSTALL_FAILED_FILE_NAME) -> ModelInstallState.FAILED
            fileSystem.exists(modelDirectory / INSTALL_COMPLETE_FILE_NAME) -> ModelInstallState.INSTALLED
            else -> ModelInstallState.NOT_INSTALLED
        }

        return InstalledModelRecord(
            modelId = modelId,
            state = installState,
            storage = ModelStorageLayout(
                installRootPath = modelDirectory.toString(),
                modelPath = modelFile?.toString(),
            ),
            installedProvider = provider,
            lastError = readOptionalText(modelDirectory / INSTALL_FAILED_FILE_NAME),
        )
    }

    private fun readProvider(modelDirectory: Path): LocalModelProvider? {
        val providerText = readOptionalText(modelDirectory / PROVIDER_FILE_NAME) ?: return null
        return LocalModelProvider.entries.firstOrNull { it.name == providerText }
    }

    private fun readOptionalText(path: Path): String? {
        if (!fileSystem.exists(path)) {
            return null
        }

        return fileSystem.source(path).buffer().use { source ->
            source.readUtf8().trim().takeIf { it.isNotEmpty() }
        }
    }

    companion object {
        internal const val INSTALL_COMPLETE_FILE_NAME = ".installed"
        internal const val INSTALL_FAILED_FILE_NAME = ".failed"
        internal const val PROVIDER_FILE_NAME = ".provider"
        internal val RESERVED_FILE_NAMES = setOf(
            INSTALL_COMPLETE_FILE_NAME,
            INSTALL_FAILED_FILE_NAME,
            PROVIDER_FILE_NAME,
        )
    }
}

class FileSystemModelInstaller(
    private val fileSystem: FileSystem,
    private val installRoot: Path,
    private val repository: RemoteModelRepositoryPort,
    private val downloadClient: DownloadClientPort,
) : ModelInstallerPort {
    override suspend fun installModel(
        model: LocalModelDescriptor,
        onProgress: (ModelInstallProgress) -> Unit,
    ): InstalledModelRecord {
        val artifacts = repository.artifactsFor(model)
        require(artifacts.isNotEmpty()) { "No artifacts configured for ${model.id.value}" }

        fileSystem.createDirectories(installRoot)

        val modelDirectory = modelInstallDirectory(model.id)
        val tempDirectory = tempInstallDirectory(model.id)
        cleanup(tempDirectory)
        fileSystem.createDirectories(tempDirectory)

        emitProgress(model, onProgress, 0.0, ModelInstallState.INSTALLING, "Starting download")

        return runCatching {
            artifacts.forEachIndexed { index, artifact ->
                val tempPath = tempDirectory / artifact.fileName
                downloadClient.download(artifact, tempPath) { downloadedBytes, totalBytes ->
                    val artifactProgress = when {
                        totalBytes == null || totalBytes <= 0L -> 0.0
                        else -> downloadedBytes.toDouble() / totalBytes.toDouble()
                    }.coerceIn(0.0, 1.0)
                    val overallProgress = (index.toDouble() + artifactProgress) / artifacts.size.toDouble()
                    emitProgress(
                        model = model,
                        onProgress = onProgress,
                        progress = overallProgress,
                        state = ModelInstallState.INSTALLING,
                        message = "Downloading ${artifact.fileName}",
                    )
                }

                if (artifact.sizeBytes != null) {
                    val actualSize = fileSystem.metadata(tempPath).size ?: 0L
                    check(actualSize == artifact.sizeBytes) {
                        "Downloaded size mismatch for ${artifact.fileName}: expected ${artifact.sizeBytes}, got $actualSize"
                    }
                }
            }

            cleanup(modelDirectory)
            fileSystem.createDirectories(modelDirectory)
            artifacts.forEach { artifact ->
                fileSystem.atomicMove(
                    source = tempDirectory / artifact.fileName,
                    target = modelDirectory / artifact.fileName,
                )
            }
            writeText(modelDirectory / FileSystemInstalledModelIndex.PROVIDER_FILE_NAME, model.provider.name)
            writeText(modelDirectory / FileSystemInstalledModelIndex.INSTALL_COMPLETE_FILE_NAME, "ok")
            cleanup(tempDirectory)

            emitProgress(model, onProgress, 1.0, ModelInstallState.INSTALLED, "Install complete")
            InstalledModelRecord(
                modelId = model.id,
                state = ModelInstallState.INSTALLED,
                storage = ModelStorageLayout(
                    installRootPath = modelDirectory.toString(),
                    modelPath = (modelDirectory / artifacts.first().fileName).toString(),
                ),
                installedProvider = model.provider,
            )
        }.getOrElse { error ->
            cleanup(modelDirectory)
            fileSystem.createDirectories(modelDirectory)
            writeText(modelDirectory / FileSystemInstalledModelIndex.INSTALL_FAILED_FILE_NAME, error.message ?: "install failed")
            cleanup(tempDirectory)
            emitProgress(
                model = model,
                onProgress = onProgress,
                progress = 0.0,
                state = ModelInstallState.FAILED,
                message = error.message ?: "Install failed",
            )
            throw error
        }
    }

    override suspend fun deleteModel(model: LocalModelDescriptor) {
        cleanup(modelInstallDirectory(model.id))
        cleanup(tempInstallDirectory(model.id))
    }

    private fun modelInstallDirectory(modelId: TranscriptionModelId): Path {
        return installRoot / modelId.value
    }

    private fun tempInstallDirectory(modelId: TranscriptionModelId): Path {
        return (installRoot / ".tmp").resolve(modelId.value)
    }

    private fun cleanup(path: Path) {
        if (fileSystem.exists(path)) {
            fileSystem.deleteRecursively(path, mustExist = false)
        }
    }

    private fun writeText(path: Path, text: String) {
        fileSystem.sink(path).buffer().use { sink ->
            sink.writeUtf8(text)
        }
    }

    private fun emitProgress(
        model: LocalModelDescriptor,
        onProgress: (ModelInstallProgress) -> Unit,
        progress: Double,
        state: ModelInstallState,
        message: String,
    ) {
        onProgress(
            ModelInstallProgress(
                modelId = model.id,
                progress = progress.coerceIn(0.0, 1.0),
                state = state,
                message = message,
            ),
        )
    }
}

private fun Path.resolve(child: String): Path = (toString().trimEnd('/') + "/" + child).toPath()
