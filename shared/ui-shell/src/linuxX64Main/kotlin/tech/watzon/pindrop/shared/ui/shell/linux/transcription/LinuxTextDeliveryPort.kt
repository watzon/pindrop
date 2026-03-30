package tech.watzon.pindrop.shared.ui.shell.linux.transcription

import platform.posix.WEXITSTATUS
import platform.posix.getenv
import platform.posix.pclose
import platform.posix.popen
import platform.posix.system
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.feature.transcription.ClipboardPort
import tech.watzon.pindrop.shared.schemasettings.OutputMode
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys

/**
 * Linux transcript delivery backed by standard desktop clipboard tools and an
 * X11 paste keystroke fallback for direct insert.
 */
class LinuxTextDeliveryPort(
    private val settings: SettingsPersistence,
) : ClipboardPort {
    override fun copyText(text: String): Boolean {
        val normalizedText = deliveredText(text)
        val copied = copyToClipboard(normalizedText)

        if (outputMode() != OutputMode.DIRECT_INSERT) {
            return copied
        }

        if (!supportsDirectInsert()) {
            return copied
        }

        return if (tryDirectInsert()) {
            true
        } else {
            copied
        }
    }

    fun supportsDirectInsert(): Boolean {
        return getenv("DISPLAY") != null && commandExists("xdotool")
    }

    private fun deliveredText(text: String): String {
        val trailingSpace = settings.getBool(SettingsKeys.addTrailingSpace) ?: SettingsDefaults.addTrailingSpace
        if (!trailingSpace || text.endsWith(" ")) {
            return text
        }
        return "$text "
    }

    private fun outputMode(): OutputMode {
        return when (settings.getString(SettingsKeys.outputMode) ?: SettingsDefaults.outputMode) {
            OutputMode.DIRECT_INSERT.rawValue -> OutputMode.DIRECT_INSERT
            else -> OutputMode.CLIPBOARD
        }
    }

    private fun copyToClipboard(text: String): Boolean {
        return clipboardCommands().any { tryWriteCommand(it, text) }
    }

    private fun tryDirectInsert(): Boolean {
        return pasteCommands().any { runShellCommand(it) }
    }

    private fun clipboardCommands(): List<String> {
        return listOf(
            "wl-copy",
            "xclip -selection clipboard",
            "xsel --clipboard --input",
        )
    }

    private fun pasteCommands(): List<String> {
        return listOf(
            "xdotool key --clearmodifiers ctrl+shift+v",
            "xdotool key --clearmodifiers ctrl+v",
            "xdotool key --clearmodifiers Shift+Insert",
        )
    }

    private fun tryWriteCommand(command: String, text: String): Boolean {
        val process = popen(command, "w") ?: return false
        return try {
            text.encodeToByteArray().forEach { byte ->
                platform.posix.fputc(byte.toInt() and 0xFF, process)
            }
            WEXITSTATUS(pclose(process)) == 0
        } catch (_: Throwable) {
            pclose(process)
            false
        }
    }

    private fun commandExists(command: String): Boolean {
        return runShellCommand("command -v $command >/dev/null 2>&1")
    }

    private fun runShellCommand(command: String): Boolean {
        return system(command) == 0
    }
}
