package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import io.ktor.client.engine.curl.Curl
import okio.FileSystem
import okio.Path.Companion.toPath

object LinuxWhisperRuntimeBootstrap {
    fun create(
        fileSystem: FileSystem = FileSystem.SYSTEM,
        observer: RuntimeObserver? = null,
    ): LocalTranscriptionRuntime {
        val httpClient = HttpClient(Curl)
        val bridge = LinuxWhisperCppBridge(fileSystem = fileSystem)

        return WhisperCppRuntimeFactory.create(
            platform = LocalPlatformId.LINUX,
            fileSystem = fileSystem,
            installRoot = LinuxWhisperRuntimePaths.modelsRoot.toPath(),
            downloadClient = KtorDownloadClient(
                httpClient = httpClient,
                fileSystem = fileSystem,
            ),
            bridge = bridge,
            observer = observer,
            repository = WhisperCppRemoteModelRepository(),
        )
    }
}
