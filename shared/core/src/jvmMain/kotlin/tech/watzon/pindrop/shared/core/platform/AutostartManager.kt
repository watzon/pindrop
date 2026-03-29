package tech.watzon.pindrop.shared.core.platform

import java.io.File
import java.nio.file.Files

/**
 * JVM actual implementation of [AutostartManager] backed by filesystem operations.
 *
 * For JVM tests. The production Linux implementation uses the same XDG .desktop
 * file approach (in linuxX64Main).
 */
actual class AutostartManager actual constructor(
    private val autostartDir: String
) {
    private val desktopFile: File
        get() = File(autostartDir, "pindrop.desktop")

    actual fun enableAutostart(): Boolean {
        val dir = File(autostartDir)
        if (!dir.exists()) dir.mkdirs()
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
        desktopFile.writeText(content)
        return desktopFile.exists()
    }

    actual fun disableAutostart(): Boolean {
        if (desktopFile.exists()) {
            desktopFile.delete()
        }
        return !desktopFile.exists()
    }

    actual fun isAutostartEnabled(): Boolean {
        return desktopFile.exists()
    }
}
