package tech.watzon.pindrop.shared.runtime.transcription

data class LinuxWhisperRuntimePathPolicy(
    val modelsRoot: String,
    val helperRoot: String,
    val tempRoot: String,
)

object WhisperCppCommandBuilder {
    fun buildCommand(
        binaryPath: String,
        modelPath: String,
        audioPath: String,
        languageCode: String?,
    ): List<String> {
        val command = mutableListOf(binaryPath, "-m", modelPath, "-f", audioPath)
        normalizeLanguageCode(languageCode)?.let { normalized ->
            command += listOf("-l", normalized)
        }
        return command
    }

    fun resolveLinuxBinaryPath(
        homeDirectory: String?,
        environment: Map<String, String>,
    ): String {
        environment[ENV_WHISPER_CPP_BIN]
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?.let { return it }

        val hasExplicitHelperRoot = !environment[XDG_DATA_HOME].isNullOrBlank() || !homeDirectory.isNullOrBlank()
        val helperRoot = linuxPathPolicy(homeDirectory, environment).helperRoot
        return if (hasExplicitHelperRoot && helperRoot.isNotEmpty()) {
            "$helperRoot/$DEFAULT_BINARY_NAME"
        } else {
            DEFAULT_BINARY_NAME
        }
    }

    fun linuxPathPolicy(
        homeDirectory: String?,
        environment: Map<String, String>,
    ): LinuxWhisperRuntimePathPolicy {
        val normalizedHome = homeDirectory?.trim()?.takeIf(String::isNotEmpty)
        val dataBase = environment[XDG_DATA_HOME]
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: normalizedHome?.let { "$it/.local/share" }
            ?: ".local/share"
        val cacheBase = environment[XDG_CACHE_HOME]
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: normalizedHome?.let { "$it/.cache" }
            ?: ".cache"

        return LinuxWhisperRuntimePathPolicy(
            modelsRoot = "$dataBase/pindrop/models",
            helperRoot = "$dataBase/pindrop/bin",
            tempRoot = "$cacheBase/pindrop/runtime-transcription",
        )
    }

    private fun normalizeLanguageCode(languageCode: String?): String? {
        return languageCode
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?.lowercase()
    }

    private const val DEFAULT_BINARY_NAME = "whisper-cli"
    private const val ENV_WHISPER_CPP_BIN = "PINDROP_WHISPER_CPP_BIN"
    private const val XDG_DATA_HOME = "XDG_DATA_HOME"
    private const val XDG_CACHE_HOME = "XDG_CACHE_HOME"
}
