package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import okio.FileSystem
import okio.Path
import okio.buffer
import okio.use

internal class KtorDownloadClient(
    private val httpClient: HttpClient,
    private val fileSystem: FileSystem,
) : DownloadClientPort {
    override suspend fun download(
        artifact: RemoteModelArtifact,
        destination: Path,
        onProgress: (bytesDownloaded: Long, totalBytes: Long?) -> Unit,
    ) {
        destination.parent?.let(fileSystem::createDirectories)

        runCatching {
            httpClient.prepareGet(artifact.downloadUrl).execute { response ->
                check(response.status.isSuccess()) {
                    "Download failed for ${artifact.fileName}: HTTP ${response.status.value}"
                }
                writeResponseBody(
                    response = response,
                    destination = destination,
                    fallbackTotalBytes = artifact.sizeBytes,
                    onProgress = onProgress,
                )
            }
        }.getOrElse { error ->
            if (fileSystem.exists(destination)) {
                fileSystem.delete(destination)
            }
            throw error
        }
    }

    private suspend fun writeResponseBody(
        response: HttpResponse,
        destination: Path,
        fallbackTotalBytes: Long?,
        onProgress: (bytesDownloaded: Long, totalBytes: Long?) -> Unit,
    ) {
        val totalBytes = response.headers[HttpHeaders.ContentLength]?.toLongOrNull() ?: fallbackTotalBytes
        val bytes = response.body<ByteArray>()

        onProgress(0L, totalBytes)

        fileSystem.sink(destination).buffer().use { sink ->
            sink.write(bytes)
        }
        onProgress(bytes.size.toLong(), totalBytes ?: bytes.size.toLong())
    }
}
