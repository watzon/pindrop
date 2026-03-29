@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.*
import platform.posix.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.core.platform.SecretStorage
import tech.watzon.pindrop.shared.core.platform.AutostartManager
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.*

/**
 * Linux lifecycle coordinator — adapts the macOS AppCoordinator pattern
 * to a GApplication/AdwApplication lifecycle.
 *
 * Owns platform services (SettingsPersistence, SecretStorage, AutostartManager)
 * and the tray/fallback UI.
 *
 * Created on 2026-03-29.
 */
class LinuxCoordinator(
    private val app: CPointer<AdwApplication>,
    private val window: CPointer<GtkWidget>
) {
    // Platform adapters (from core module)
    private val configDir: String = getConfigDir()
    private val settingsPersistence = SettingsPersistence(configDir)
    private val secretStorage = SecretStorage()
    private val autostartManager = AutostartManager(getAutostartDir())

    // Tray components (set up during start)
    private var trayIcon: TrayIcon? = null
    private var trayMenu: TrayMenu? = null
    private var trayFallback: TrayFallback? = null

    // First-run detection
    private var needsOnboarding: Boolean = false

    /**
     * Start the coordinator — load settings, detect first-run, set up tray.
     */
    fun start() {
        // 1. Load settings from TOML
        settingsPersistence.load()

        // 2. Check first-run state
        val completedOnboarding = settingsPersistence.getBool(SettingsKeys.hasCompletedOnboarding)
            ?: SettingsDefaults.hasCompletedOnboarding
        needsOnboarding = !completedOnboarding

        if (needsOnboarding) {
            // Plan 03 provides the onboarding wizard.
            // For now, show the main window with a placeholder.
            gtk_widget_show(window)
        }

        // 3. Synchronize autostart if launchAtLogin is enabled
        val launchAtLogin = settingsPersistence.getBool(SettingsKeys.launchAtLogin)
            ?: SettingsDefaults.launchAtLogin
        if (launchAtLogin) {
            val actualEnabled = autostartManager.isAutostartEnabled()
            if (actualEnabled != launchAtLogin) {
                if (launchAtLogin) {
                    autostartManager.enableAutostart()
                } else {
                    autostartManager.disableAutostart()
                }
            }
        }

        // 4. Initialize tray — try AppIndicator first, fallback if unavailable
        try {
            trayMenu = TrayMenu(this)
            trayIcon = TrayIcon()
            if (trayIcon?.isActive() == true) {
                trayIcon?.setMenu(trayMenu!!)
                trayIcon?.setStatus(true)
            } else {
                // AppIndicator not available, fall back
                throw IllegalStateException("AppIndicator not available")
            }
        } catch (_: Exception) {
            // Tray unavailable (no D-Bus indicator service)
            // Activate fallback
            trayIcon = null
            trayMenu?.destroy()
            trayMenu = null
            trayFallback = TrayFallback(this, window)
            trayFallback?.show()
        }
    }

    /**
     * Show settings — placeholder that Plan 03 will wire to settings dialog.
     */
    fun showSettings() {
        // TODO: Plan 03 creates the settings dialog
        gtk_window_present(window.reinterpret())
    }

    /**
     * Toggle autostart on/off. Called from tray menu.
     */
    fun toggleAutostart() {
        val current = autostartManager.isAutostartEnabled()
        val newState = !current
        val success = if (newState) {
            autostartManager.enableAutostart()
        } else {
            autostartManager.disableAutostart()
        }
        if (success) {
            settingsPersistence.setBool(SettingsKeys.launchAtLogin, newState)
            settingsPersistence.save()
            trayMenu?.updateAutostartItem(newState)
        }
    }

    /**
     * Check current autostart state.
     */
    fun isAutostartEnabled(): Boolean {
        return autostartManager.isAutostartEnabled()
    }

    /**
     * Show the GTK about dialog.
     */
    fun showAbout() {
        val aboutWindow = adw_about_window_new()
        adw_about_window_set_application_name(aboutWindow?.reinterpret(), "Pindrop")
        adw_about_window_set_version(aboutWindow?.reinterpret(), "0.1.0")
        adw_about_window_set_copyright(aboutWindow?.reinterpret(), "© 2026 Watzon Tech")
        adw_about_window_set_comments(
            aboutWindow?.reinterpret(),
            "Privacy-first dictation app"
        )
        gtk_window_set_modal(aboutWindow?.reinterpret(), 1)
        gtk_window_set_transient_for(aboutWindow?.reinterpret(), window.reinterpret())
        gtk_window_present(aboutWindow?.reinterpret())
    }

    /**
     * Quit the application — persist settings and shut down.
     */
    fun quitApp() {
        quit()
    }

    /**
     * Persist dirty settings, clean up resources, and quit the GApplication.
     */
    fun quit() {
        settingsPersistence.save()
        trayMenu?.destroy()
        trayFallback?.destroy()
        trayIcon = null
        trayMenu = null
        trayFallback = null
        g_application_quit(app.reinterpret())
    }

    /**
     * Get the current system locale for localization.
     * Parses LANG environment variable (e.g., "en_US.UTF-8" → "en").
     */
    fun getLocale(): String {
        val lang = getenv("LANG")?.toKString()
            ?: getenv("LC_ALL")?.toKString()
            ?: getenv("LC_MESSAGES")?.toKString()
            ?: return "en"
        // Extract language code from "en_US.UTF-8" or "en_US" or "en"
        val withoutEncoding = lang.substringBefore(".")
        val languageCode = withoutEncoding.substringBefore("_")
        return languageCode.lowercase()
    }

    // --- Helpers ---

    private fun getConfigDir(): String {
        val home = getenv("HOME")?.toKString() ?: "/tmp"
        return "$home/.config/pindrop"
    }

    private fun getAutostartDir(): String {
        val home = getenv("HOME")?.toKString() ?: "/tmp"
        return "$home/.config/autostart"
    }
}
