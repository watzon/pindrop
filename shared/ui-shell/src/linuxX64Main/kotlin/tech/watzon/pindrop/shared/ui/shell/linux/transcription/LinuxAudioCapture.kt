@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.transcription

import kotlinx.cinterop.toKString
import okio.FileSystem
import okio.Path.Companion.toPath
import okio.buffer
import okio.use
import platform.posix.getpid
import platform.posix.kill
import platform.posix.pclose
import platform.posix.popen
import platform.posix.sleep
import platform.posix.time
import tech.watzon.pindrop.shared.feature.transcription.AudioCapturePort
import tech.watzon.pindrop.shared.runtime.transcription.LinuxWhisperRuntimePaths

class LinuxAudioCapture(
    private val fileSystem: FileSystem = FileSystem.SYSTEM,
    private val tempRootProvider: () -> String = { LinuxWhisperRuntimePaths.tempRoot },
) : AudioCapturePort {
    private var processId: Int? = null
    private var activeCapturePath: String? = null
    private var preferredInputDeviceId: String? = null

    override suspend fun startCapture() {
        if (isCapturing()) {
            throw LinuxAudioCaptureError("Audio capture is already active")
        }

        val tempRoot = tempRootProvider().toPath()
        fileSystem.createDirectories(tempRoot)
        val capturePath = (tempRoot / "capture-${time(null)}-${getpid()}.wav").toString()
        val command = resolveCaptureCommand(capturePath)
        val pid = runBackgroundCommand(command)

        processId = pid
        activeCapturePath = capturePath
    }

    override suspend fun stopCapture(): ByteArray {
        val capturePath = activeCapturePath ?: throw LinuxAudioCaptureError("No active capture path")
        val pid = processId ?: throw LinuxAudioCaptureError("No active capture process")
        kill(pid, 2)
        sleep(1u)

        processId = null
        activeCapturePath = null

        val path = capturePath.toPath()
        if (!fileSystem.exists(path)) {
            throw LinuxAudioCaptureError("Capture helper did not produce a WAV file")
        }

        return fileSystem.source(path).buffer().use { source ->
            source.readByteArray().also {
                fileSystem.delete(path)
            }
        }
    }

    override suspend fun cancelCapture() {
        processId?.let { kill(it, 2) }
        activeCapturePath?.toPath()?.let { path ->
            if (fileSystem.exists(path)) {
                fileSystem.delete(path)
            }
        }
        processId = null
        activeCapturePath = null
    }

    override fun isCapturing(): Boolean = processId != null

    override fun setPreferredInputDevice(deviceId: String?) {
        preferredInputDeviceId = deviceId
    }

    internal fun resolveCaptureCommand(outputPath: String): List<String> {
        val deviceArgs = preferredInputDeviceId?.takeIf { it.isNotBlank() }?.let {
            listOf("--device", it)
        } ?: emptyList()

        return when {
            commandExists("pw-record") -> listOf(
                "pw-record",
                "--rate",
                "16000",
                "--channels",
                "1",
                outputPath,
            ) + deviceArgs
            commandExists("parecord") -> listOf(
                "parecord",
                "--rate=16000",
                "--channels=1",
                "--file-format=wav",
                outputPath,
            ) + deviceArgs
            else -> throw LinuxAudioCaptureError("Neither pw-record nor parecord is installed")
        }
    }

    private fun commandExists(command: String): Boolean {
        val process = popen("command -v $command 2>/dev/null", "r") ?: return false
        return try {
            process.readLine().isNotBlank()
        } finally {
            pclose(process)
        }
    }

    private fun runBackgroundCommand(command: List<String>): Int {
        val shellCommand = command.joinToString(" ") { it.shellQuoted() } + " >/dev/null 2>&1 & echo $!"
        val process = popen(shellCommand, "r") ?: throw LinuxAudioCaptureError("Unable to start audio capture helper")
        return try {
            process.readLine().toIntOrNull() ?: throw LinuxAudioCaptureError("Audio capture helper did not return a pid")
        } finally {
            pclose(process)
        }
    }

    private fun String.shellQuoted(): String = "'" + replace("'", "'\\''") + "'"

    private fun kotlinx.cinterop.CPointer<platform.posix.FILE>.readLine(): String {
        val builder = StringBuilder()
        while (true) {
            val next = platform.posix.fgetc(this)
            if (next == -1 || next == '\n'.code) {
                break
            }
            builder.append(next.toChar())
        }
        return builder.toString().trim()
    }
}

class LinuxAudioCaptureError(message: String) : Exception(message)
