package tech.watzon.pindrop.shared.runtime.transcription

import kotlin.test.Test
import kotlin.test.assertEquals

class WhisperCppCommandBuilderTest {
    @Test
    fun linuxBinaryLookupPrefersEnvOverrideThenLocalHelperThenPath() {
        val home = "/home/tester"

        assertEquals(
            "/custom/whisper-cli",
            WhisperCppCommandBuilder.resolveLinuxBinaryPath(
                homeDirectory = home,
                environment = mapOf("PINDROP_WHISPER_CPP_BIN" to "/custom/whisper-cli"),
            ),
        )
        assertEquals(
            "/home/tester/.local/share/pindrop/bin/whisper-cli",
            WhisperCppCommandBuilder.resolveLinuxBinaryPath(
                homeDirectory = home,
                environment = emptyMap<String, String>(),
            ),
        )
        assertEquals(
            "whisper-cli",
            WhisperCppCommandBuilder.resolveLinuxBinaryPath(
                homeDirectory = null,
                environment = emptyMap<String, String>(),
            ),
        )
    }

    @Test
    fun linuxPathPolicyUsesXdgStyleDefaults() {
        val paths = WhisperCppCommandBuilder.linuxPathPolicy(
            homeDirectory = "/home/tester",
            environment = emptyMap<String, String>(),
        )

        assertEquals("/home/tester/.local/share/pindrop/models", paths.modelsRoot)
        assertEquals("/home/tester/.local/share/pindrop/bin", paths.helperRoot)
        assertEquals("/home/tester/.cache/pindrop/runtime-transcription", paths.tempRoot)
    }

    @Test
    fun commandBuilderEmitsDeterministicWhisperCliArguments() {
        assertEquals(
            listOf(
                "/opt/pindrop/bin/whisper-cli",
                "-m",
                "/home/tester/.local/share/pindrop/models/openai_whisper-base.en/ggml-base.en.bin",
                "-f",
                "/home/tester/.cache/pindrop/runtime-transcription/capture.wav",
                "-l",
                "en",
            ),
            WhisperCppCommandBuilder.buildCommand(
                binaryPath = "/opt/pindrop/bin/whisper-cli",
                modelPath = "/home/tester/.local/share/pindrop/models/openai_whisper-base.en/ggml-base.en.bin",
                audioPath = "/home/tester/.cache/pindrop/runtime-transcription/capture.wav",
                languageCode = "EN",
            ),
        )
    }
}
