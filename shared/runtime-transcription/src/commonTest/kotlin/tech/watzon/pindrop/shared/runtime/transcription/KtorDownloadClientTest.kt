package tech.watzon.pindrop.shared.runtime.transcription

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlinx.coroutines.test.runTest
import okio.Path.Companion.toPath
import okio.fakefilesystem.FakeFileSystem
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class KtorDownloadClientTest {
    @Test
    fun downloadStreamsBodyToDiskAndReportsProgress() = runTest {
        val fileSystem = FakeFileSystem()
        val destination = "/models/base/ggml-base.bin".toPath()
        val client = HttpClient(
            MockEngine {
                respond(
                    content = ByteReadChannel("binary"),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentLength, "6"),
                )
            },
        )
        val downloadClient = KtorDownloadClient(client, fileSystem)
        val progress = mutableListOf<Pair<Long, Long?>>()

        downloadClient.download(
            artifact = RemoteModelArtifact(
                fileName = "ggml-base.bin",
                downloadUrl = "https://example.invalid/ggml-base.bin",
            ),
            destination = destination,
        ) { downloaded, total ->
            progress += downloaded to total
        }

        val content = fileSystem.read(destination) { readUtf8() }
        assertEquals("binary", content)
        assertTrue(progress.first() == (0L to 6L))
        assertTrue(progress.last() == (6L to 6L))
    }

    @Test
    fun downloadDeletesPartialFileOnFailure() = runTest {
        val fileSystem = FakeFileSystem()
        val destination = "/models/base/ggml-base.bin".toPath()
        val client = HttpClient(
            MockEngine {
                respond(
                    content = ByteReadChannel("boom"),
                    status = HttpStatusCode.BadGateway,
                )
            },
        )
        val downloadClient = KtorDownloadClient(client, fileSystem)

        runCatching {
            downloadClient.download(
                artifact = RemoteModelArtifact(
                    fileName = "ggml-base.bin",
                    downloadUrl = "https://example.invalid/ggml-base.bin",
                ),
                destination = destination,
            ) { _, _ -> }
        }

        assertFalse(fileSystem.exists(destination))
    }
}
