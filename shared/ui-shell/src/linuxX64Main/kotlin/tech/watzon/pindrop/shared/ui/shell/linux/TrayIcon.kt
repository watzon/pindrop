@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.appindicator.*

/**
 * AppIndicator system tray icon integration.
 *
 * Creates a tray icon using the Ayatana/AppIndicator library via D-Bus,
 * which works across GNOME (with AppIndicator extension), KDE, XFCE, etc.
 *
 * The icon name "pindrop" expects a pindrop.svg in the system icon theme
 * or in the local data directory (e.g., ~/.local/share/icons/).
 *
 * Created on 2026-03-29.
 */
class TrayIcon {
    private val indicator: CPointer<AppIndicator>? = app_indicator_new(
        "pindrop",
        "pindrop",
        APP_INDICATOR_CATEGORY_APPLICATION_STATUS
    )

    /**
     * Whether the AppIndicator was successfully created.
     * If false, the tray is not available and [TrayFallback] should be used.
     */
    fun isActive(): Boolean = indicator != null

    /**
     * Attach a [TrayMenu] to the tray icon.
     * The menu is displayed when the user clicks the tray icon.
     */
    fun setMenu(menu: TrayMenu) {
        indicator?.let { ind ->
            menu.gtkMenu?.let { m ->
                app_indicator_set_menu(ind, m)
            }
        }
    }

    /**
     * Set the tray icon visibility status.
     * @param active true to show (ACTIVE), false to hide (PASSIVE)
     */
    fun setStatus(active: Boolean) {
        val status = if (active) {
            APP_INDICATOR_STATUS_ACTIVE
        } else {
            APP_INDICATOR_STATUS_PASSIVE
        }
        indicator?.let { app_indicator_set_status(it, status) }
    }

    /**
     * Set the icon name from the system icon theme.
     * Common names: "pindrop", "pindrop-recording", "pindrop-paused"
     */
    fun setIcon(iconName: String) {
        indicator?.let { app_indicator_set_icon(it, iconName) }
    }

    /**
     * Set a tooltip for the tray icon (not all trays support this).
     */
    fun setTooltip(tooltip: String) {
        indicator?.let { app_indicator_set_tooltip(it, tooltip) }
    }
}
