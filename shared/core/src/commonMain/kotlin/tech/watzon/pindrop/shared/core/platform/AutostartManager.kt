package tech.watzon.pindrop.shared.core.platform

/**
 * Platform-agnostic autostart (launch-at-login) manager.
 *
 * Each platform provides an `actual` implementation:
 * - macOS: SMAppService (via LaunchAtLogin)
 * - Linux: XDG .desktop file in autostartDir
 * - Windows: Registry Run key (future)
 *
 * @param autostartDir Directory where .desktop files go.
 *   - Linux: ~/.config/autostart
 *   - JVM tests: temp directory
 */
expect class AutostartManager(autostartDir: String) {

    fun enableAutostart(): Boolean

    fun disableAutostart(): Boolean

    fun isAutostartEnabled(): Boolean
}
