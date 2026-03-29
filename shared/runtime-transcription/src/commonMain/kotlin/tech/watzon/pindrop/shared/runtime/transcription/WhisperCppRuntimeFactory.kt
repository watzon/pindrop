package tech.watzon.pindrop.shared.runtime.transcription

import okio.FileSystem
import okio.Path

object WhisperCppRuntimeFactory {
    fun create(
        platform: LocalPlatformId,
        fileSystem: FileSystem,
        installRoot: Path,
        downloadClient: DownloadClientPort,
        bridge: WhisperCppBridgePort,
        observer: RuntimeObserver? = null,
        repository: RemoteModelRepositoryPort = WhisperCppRemoteModelRepository(),
    ): LocalTranscriptionRuntime {
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
                downloadClient = downloadClient,
            ),
            backendRegistry = DefaultBackendRegistry(
                platform = platform,
                backends = listOf(WhisperCppBackend(bridge)),
            ),
            observer = observer,
        )
    }
}
