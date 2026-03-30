@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.runtime.transcription

import kotlinx.cinterop.toKString
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath
import okio.buffer
import okio.use
import platform.posix.fgetc
import platform.posix.getpid
import platform.posix.pclose
import platform.posix.popen
import platform.posix.time
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult

class LinuxWhisperCppBridge(
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val binaryResolver: () -> String = { LinuxWhisperRuntimePaths.resolveWhisperBinary() },
    private val tempRootProvider: () -> String = { LinuxWhisperRuntimePaths.tempRoot },
) : WhisperCppBridgePort {
    private var loadedModelPath: String? = null

    override suspend fun loadModel(modelPath: String) {
        require(modelPath.isNotBlank()) { "Model path must not be blank" }
        val candidate = modelPath.toPath()
        if (!fileSystem.exists(candidate)) {
            throw LinuxWhisperCppBridgeError("Model file not found at $modelPath")
        }
        loadedModelPath = modelPath
    }

    override suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        val modelPath = loadedModelPath
            ?: throw LinuxWhisperCppBridgeError("Cannot transcribe before a model is loaded")
        if (request.audioData.isEmpty()) {
            throw LinuxWhisperCppBridgeError("Cannot transcribe empty audio data")
        }

        val tempRoot = tempRootProvider().toPath()
        fileSystem.createDirectories(tempRoot)
        val audioPath = tempRoot / tempFileName("capture", ".wav")

        return runCatching {
            fileSystem.sink(audioPath).buffer().use { sink ->
                sink.write(request.audioData)
            }

            val command = WhisperCppCommandBuilder.buildCommand(
                binaryPath = binaryResolver(),
                modelPath = modelPath,
                audioPath = audioPath.toString(),
                languageCode = request.language.toWhisperLanguageCode(),
            )
            val output = runCommand(command)
            val transcript = output.lineSequence()
                .map(String::trim)
                .filter(String::isNotEmpty)
                .joinToString("\n")

            if (transcript.isBlank()) {
                throw LinuxWhisperCppBridgeError("whisper.cpp returned an empty transcript")
            }

            TranscriptionResult(text = transcript)
        }.also {
            if (fileSystem.exists(audioPath)) {
                fileSystem.delete(audioPath)
            }
        }.getOrThrow()
    }

    override suspend fun unloadModel() {
        loadedModelPath = null
    }

    private fun runCommand(command: List<String>): String {
        val shellCommand = command.joinToString(" ") { it.shellQuoted() } + " 2>&1"
        val process = popen(shellCommand, "r")
            ?: throw LinuxWhisperCppBridgeError("Failed to launch whisper.cpp command")

        val output = buildString {
            while (true) {
                val next = fgetc(process)
                if (next == EOF) {
                    break
                }
                append(next.toChar())
            }
        }

        val exitCode = pclose(process)
        if (exitCode != 0) {
            throw LinuxWhisperCppBridgeError(
                "whisper.cpp exited with code $exitCode: ${output.trim()}",
            )
        }

        return output
    }

    private fun tempFileName(prefix: String, suffix: String): String {
        val timestamp = time(null)
        return "$prefix-$timestamp-${getpid()}$suffix"
    }

    private fun String.shellQuoted(): String {
        return "'" + replace("'", "'\\''") + "'"
    }

    private fun TranscriptionLanguage.toWhisperLanguageCode(): String? {
        return when (this) {
            TranscriptionLanguage.AUTOMATIC -> null
            TranscriptionLanguage.ENGLISH -> "en"
            TranscriptionLanguage.SIMPLIFIED_CHINESE -> "zh"
            TranscriptionLanguage.SPANISH -> "es"
            TranscriptionLanguage.FRENCH -> "fr"
            TranscriptionLanguage.GERMAN -> "de"
            TranscriptionLanguage.TURKISH -> "tr"
            TranscriptionLanguage.JAPANESE -> "ja"
            TranscriptionLanguage.PORTUGUESE_BRAZIL -> "pt"
            TranscriptionLanguage.ITALIAN -> "it"
            TranscriptionLanguage.DUTCH -> "nl"
            TranscriptionLanguage.KOREAN -> "ko"
        }
    }

    private companion object {
        const val EOF = -1
    }
}

class LinuxWhisperCppBridgeError(
    message: String,
) : Exception(message)
