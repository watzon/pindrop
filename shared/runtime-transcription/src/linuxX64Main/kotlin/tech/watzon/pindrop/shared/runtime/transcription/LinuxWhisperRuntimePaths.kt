@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.runtime.transcription

import kotlinx.cinterop.toKString
import platform.posix.getenv

object LinuxWhisperRuntimePaths {
    const val DEFAULT_MODELS_ROOT = "~/.local/share/pindrop/models"
    const val DEFAULT_HELPER_ROOT = "~/.local/share/pindrop/bin"
    const val DEFAULT_TEMP_ROOT = "~/.cache/pindrop/runtime-transcription"

    val modelsRoot: String
        get() = pathPolicy().modelsRoot

    val helperRoot: String
        get() = pathPolicy().helperRoot

    val tempRoot: String
        get() = pathPolicy().tempRoot

    fun resolveWhisperBinary(): String {
        return WhisperCppCommandBuilder.resolveLinuxBinaryPath(
            homeDirectory = getenv("HOME")?.toKString(),
            environment = currentEnvironment(),
        )
    }

    fun pathPolicy(): LinuxWhisperRuntimePathPolicy {
        return WhisperCppCommandBuilder.linuxPathPolicy(
            homeDirectory = getenv("HOME")?.toKString(),
            environment = currentEnvironment(),
        )
    }

    private fun currentEnvironment(): Map<String, String> {
        return listOf(
            "PINDROP_WHISPER_CPP_BIN",
            "XDG_DATA_HOME",
            "XDG_CACHE_HOME",
        ).mapNotNull { key ->
            getenv(key)?.toKString()?.let { key to it }
        }.toMap()
    }
}
