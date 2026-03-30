@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionState
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionUiState
import tech.watzon.pindrop.shared.ui.shell.linux.hotkeys.LinuxHotkeyBindingSnapshot
import tech.watzon.pindrop.shared.ui.shell.linux.hotkeys.LinuxHotkeyStatus
import tech.watzon.pindrop.shared.uishell.cinterop.appindicator.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * GTK 3 menu for the system tray icon.
 *
 * Builds a [GtkMenu] with: Pindrop header (disabled), separator,
 * Settings → Launch at Login (check) → separator → About Pindrop → Quit.
 *
 * All labels use [SharedLocalization] for i18n. The coordinator reference
 * is passed via [StableRef] to signal callbacks since static C functions
 * cannot capture Kotlin state directly.
 *
 * Created on 2026-03-29.
 */
class TrayMenu(
    private val coordinator: LinuxCoordinator
) {
    private val coordinatorRef = StableRef.create(coordinator)
    private val locale: String = coordinator.getLocale()

    /** The GTK 3 menu widget, pass to [TrayIcon.setMenu]. */
    val gtkMenu: CPointer<GtkMenu>? = buildMenu()

    /** Keep a reference to the autostart check item for live updates. */
    private var autostartCheckItem: CPointer<GtkWidget>? = null
    private var startRecordingItem: CPointer<GtkWidget>? = null
    private var stopRecordingItem: CPointer<GtkWidget>? = null
    private var sessionStatusItem: CPointer<GtkWidget>? = null
    private var toggleHotkeyStatusItem: CPointer<GtkWidget>? = null
    private var pushToTalkStatusItem: CPointer<GtkWidget>? = null

    /**
     * Build the full tray menu with localized items and signal handlers.
     */
    private fun buildMenu(): CPointer<GtkMenu>? {
        val menu = gtk_menu_new() ?: return null

        // --- Header: "Pindrop" (disabled label) ---
        val header = gtk_menu_item_new_with_label("Pindrop")
        gtk_menu_item_set_sensitive(header?.reinterpret(), 0)
        gtk_menu_shell_append(menu.reinterpret(), header)

        // --- Separator ---
        appendSeparator(menu)

        // --- Settings ---
        val startItem = gtk_menu_item_new_with_label("Start Recording")
        connectActivate(startItem) { coord -> coord.startRecording() }
        startRecordingItem = startItem
        gtk_menu_shell_append(menu.reinterpret(), startItem)

        val stopItem = gtk_menu_item_new_with_label("Stop Recording")
        connectActivate(stopItem) { coord -> coord.stopRecording() }
        stopRecordingItem = stopItem
        gtk_menu_shell_append(menu.reinterpret(), stopItem)

        sessionStatusItem = disabledStatusItem(menu, "Status: Ready to record.")
        updateRecordingState(VoiceSessionUiState(state = if (coordinator.isRecording()) VoiceSessionState.RECORDING else VoiceSessionState.IDLE))

        toggleHotkeyStatusItem = disabledStatusItem(menu, "Toggle Shortcut: Not configured")
        pushToTalkStatusItem = disabledStatusItem(menu, "Push-to-Talk: Not configured")

        val settingsLabel = SharedLocalization.getString("Settings", locale)
        val settingsItem = gtk_menu_item_new_with_label(settingsLabel)
        connectActivate(settingsItem) { coord ->
            coord.showSettings()
        }
        gtk_menu_shell_append(menu.reinterpret(), settingsItem)

        // --- Launch at Login (check item) ---
        val autostartLabel = SharedLocalization.getString("Launch at Login", locale)
        val checkItem = gtk_check_menu_item_new_with_label(autostartLabel)
        gtk_check_menu_item_set_active(
            checkItem?.reinterpret(),
            if (coordinator.isAutostartEnabled()) 1 else 0
        )
        connectActivate(checkItem) { coord ->
            coord.toggleAutostart()
        }
        autostartCheckItem = checkItem
        gtk_menu_shell_append(menu.reinterpret(), checkItem)

        // --- Separator ---
        appendSeparator(menu)

        // --- About Pindrop ---
        val aboutLabel = SharedLocalization.getString("About Pindrop", locale)
        val aboutItem = gtk_menu_item_new_with_label(aboutLabel)
        connectActivate(aboutItem) { coord ->
            coord.showAbout()
        }
        gtk_menu_shell_append(menu.reinterpret(), aboutItem)

        // --- Quit ---
        val quitLabel = SharedLocalization.getString("Quit", locale)
        val quitItem = gtk_menu_item_new_with_label(quitLabel)
        connectActivate(quitItem) { coord ->
            coord.quitApp()
        }
        gtk_menu_shell_append(menu.reinterpret(), quitItem)

        // Show all menu items
        gtk_widget_show_all(menu.reinterpret())

        return menu.reinterpret()
    }

    /**
     * Append a separator to the menu.
     */
    private fun appendSeparator(menu: CPointer<GtkWidget>?) {
        val sep = gtk_separator_menu_item_new()
        gtk_menu_shell_append(menu?.reinterpret(), sep)
        gtk_widget_show(sep)
    }

    private fun disabledStatusItem(menu: CPointer<GtkWidget>?, label: String): CPointer<GtkWidget>? {
        val item = gtk_menu_item_new_with_label(label)
        gtk_menu_item_set_sensitive(item?.reinterpret(), 0)
        gtk_menu_shell_append(menu?.reinterpret(), item)
        return item
    }

    /**
     * Connect the "activate" signal on a menu item to a coordinator action.
     *
     * Uses [StableRef.asCPointer] as user_data to pass the coordinator
     * reference into the static C callback.
     */
    private fun connectActivate(
        item: CPointer<GtkWidget>?,
        action: (LinuxCoordinator) -> Unit
    ) {
        g_signal_connect_data(
            item,
            "activate",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    val coord = data.asStableRef<LinuxCoordinator>().get()
                    action(coord)
                }
            }.reinterpret(),
            coordinatorRef.asCPointer(),
            null,
            0u
        )
    }

    /**
     * Update the autostart check item's active state.
     * Called by [LinuxCoordinator] after toggling autostart.
     */
    fun updateAutostartItem(enabled: Boolean) {
        autostartCheckItem?.let { item ->
            gtk_check_menu_item_set_active(
                item.reinterpret(),
                if (enabled) 1 else 0
            )
        }
    }

    fun updateRecordingState(state: VoiceSessionUiState) {
        val startEnabled = state.canRecord && when (state.state) {
            VoiceSessionState.IDLE,
            VoiceSessionState.COMPLETED,
            VoiceSessionState.ERROR,
            -> true

            VoiceSessionState.STARTING,
            VoiceSessionState.RECORDING,
            VoiceSessionState.PROCESSING,
            -> false
        }
        val stopEnabled = state.state == VoiceSessionState.RECORDING

        startRecordingItem?.let { gtk_menu_item_set_sensitive(it.reinterpret(), if (startEnabled) 1 else 0) }
        stopRecordingItem?.let { gtk_menu_item_set_sensitive(it.reinterpret(), if (stopEnabled) 1 else 0) }
    }

    fun updateSessionStatus(message: String) {
        gtk_menu_item_set_label(sessionStatusItem?.reinterpret(), "Status: $message")
    }

    fun updateHotkeyStatuses(snapshot: LinuxHotkeyBindingSnapshot) {
        gtk_menu_item_set_label(
            toggleHotkeyStatusItem?.reinterpret(),
            LinuxHotkeyStatus.formatMenuLabel("Toggle Shortcut", snapshot.toggle),
        )
        gtk_menu_item_set_label(
            pushToTalkStatusItem?.reinterpret(),
            LinuxHotkeyStatus.formatMenuLabel("Push-to-Talk", snapshot.pushToTalk),
        )
    }

    /**
     * Release the StableRef and clean up.
     * Must be called when the tray menu is discarded.
     */
    fun destroy() {
        coordinatorRef.dispose()
    }
}
