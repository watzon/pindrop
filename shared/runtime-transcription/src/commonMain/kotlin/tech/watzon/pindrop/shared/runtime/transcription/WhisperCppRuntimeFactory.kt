package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import okio.FileSystem
import okio.Path

object WhisperCppRuntimeFactory {
    fun create(
        platform: LocalPlatformId,
        fileSystem: FileSystem,
        installRoot: Path,
        httpClient: HttpClient,
        bridge: WhisperCppBridgePort,
        observer: RuntimeObserver? = null,
    ): LocalTranscriptionRuntime {
        val repository = WhisperCppRemoteModelRepository()
        return LocalTranscriptionRuntime(
            platform = platform,
            installedModelIndex = FileSystemInstalledModelIndex(
                fileSystem = fileSystem,
                installRoot = installRoot,
            ),
            modelInstaller = FileSystemModelInstaller(
                fileSystem = fileSystem,
                installRoot = installRoot,
                repository = repository,
                downloadClient = KtorDownloadClient(
                    httpClient = httpClient,
                    fileSystem = fileSystem,
                ),
            ),
            backendRegistry = DefaultBackendRegistry(
                platform = platform,
                backends = listOf(WhisperCppBackend(bridge)),
            ),
            observer = observer,
        )
    }
}
