@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.core.platform

import kotlinx.cinterop.*
import platform.posix.*

/**
 * Linux actual implementation of [AutostartManager] using XDG .desktop file
 * at ~/.config/autostart/pindrop.desktop.
 */
actual class AutostartManager actual constructor(
    private val autostartDir: String
) {
    private val desktopFilePath: String
        get() = "$autostartDir/pindrop.desktop"

    actual fun enableAutostart(): Boolean {
        mkdirp(autostartDir)
        val content = """
            [Desktop Entry]
            Type=Application
            Name=Pindrop
            Exec=/usr/bin/pindrop
            Icon=pindrop
            Comment=Privacy-first dictation app
            X-GNOME-Autostart-enabled=true
            StartupWMClass=pindrop
        """.trimIndent()
        writeFileContent(desktopFilePath, content)
        return fileExists(desktopFilePath)
    }

    actual fun disableAutostart(): Boolean {
        if (fileExists(desktopFilePath)) {
            remove(desktopFilePath)
        }
        return !fileExists(desktopFilePath)
    }

    actual fun isAutostartEnabled(): Boolean {
        return fileExists(desktopFilePath)
    }

    // --- Helpers ---

    private fun fileExists(path: String): Boolean {
        return access(path, F_OK) == 0
    }

    private fun writeFileContent(path: String, content: String) {
        val file = fopen(path, "w") ?: return
        try {
            val bytes = content.encodeToByteArray()
            bytes.usePinned { pinned ->
                fwrite(pinned.addressOf(0), 1u, bytes.size.toULong(), file)
            }
        } finally {
            fclose(file)
        }
    }

    private fun mkdirp(dirPath: String) {
        val parts = dirPath.split("/")
        var current = ""
        for (part in parts) {
            if (part.isEmpty()) continue
            current += "/$part"
            mkdir(current, 0x1EDu) // 0755 = rwxr-xr-x
        }
    }
}
