package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import io.ktor.utils.io.readAvailable
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
        val channel = response.bodyAsChannel()
        val buffer = ByteArray(BUFFER_SIZE_BYTES)
        var downloadedBytes = 0L

        onProgress(0L, totalBytes)

        fileSystem.sink(destination).buffer().use { sink ->
            while (true) {
                val readCount = channel.readAvailable(buffer, 0, buffer.size)
                if (readCount == -1) {
                    break
                }
                if (readCount == 0) {
                    continue
                }

                sink.write(buffer, 0, readCount)
                downloadedBytes += readCount
                onProgress(downloadedBytes, totalBytes)
            }
        }
    }

    private companion object {
        const val BUFFER_SIZE_BYTES = 64 * 1024
    }
}
