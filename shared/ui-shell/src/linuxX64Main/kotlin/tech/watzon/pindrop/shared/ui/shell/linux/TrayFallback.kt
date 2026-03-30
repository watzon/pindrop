@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Fallback for tray-less environments (tiling WMs, minimal setups).
 *
 * When AppIndicator is unavailable (no D-Bus indicator service running),
 * this class shows a small persistent GTK 4 window with:
 * - App icon/label ("Pindrop is running")
 * - "Settings" button
 * - "Quit" button
 *
 * This ensures the app doesn't silently disappear or crash when the
 * system tray is not supported (per D-09 in CONTEXT.md).
 *
 * Created on 2026-03-29.
 */
class TrayFallback(
    private val coordinator: LinuxCoordinator,
    private val parentWindow: CPointer<GtkWidget>
) {
    private val coordinatorRef = StableRef.create(coordinator)
    private val locale: String = coordinator.getLocale()
    private var fallbackWindow: CPointer<GtkWidget>? = null
    private var statusLabel: CPointer<GtkWidget>? = null
    private var startButton: CPointer<GtkWidget>? = null
    private var stopButton: CPointer<GtkWidget>? = null

    /**
     * Create and show the fallback window.
     */
    fun show() {
        fallbackWindow = buildFallbackWindow()
        fallbackWindow?.let { gtk_window_present(it.reinterpret()) }
    }

    /**
     * Build the fallback window with controls.
     */
    private fun buildFallbackWindow(): CPointer<GtkWidget>? {
        val window = gtk_window_new()
        gtk_window_set_title(window?.reinterpret(), "Pindrop")
        gtk_window_set_default_size(window?.reinterpret(), 220, 120)
        gtk_window_set_resizable(window?.reinterpret(), 0)

        // Don't destroy the app when this window is closed — just hide
        g_signal_connect_data(
            window,
            "close-request",
            staticCFunction { _: CPointer<*>?, _: CPointer<*>? ->
                // Return 1 (= TRUE) to prevent default destroy
                1
            }.reinterpret(),
            null,
            null,
            0u
        )

        // Vertical box layout
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
        gtk_widget_set_margin_top(box, 12)
        gtk_widget_set_margin_bottom(box, 12)
        gtk_widget_set_margin_start(box, 12)
        gtk_widget_set_margin_end(box, 12)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)

        // Status label
        statusLabel = gtk_label_new("Pindrop is running")
        gtk_widget_add_css_class(statusLabel, "title-4")

        // Settings button
        startButton = gtk_button_new_with_label("Start Recording")
        gtk_widget_add_css_class(startButton, "suggested-action")
        g_signal_connect_data(
            startButton,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    data.asStableRef<LinuxCoordinator>().get().startRecording()
                }
            }.reinterpret(),
            coordinatorRef.asCPointer(),
            null,
            0u
        )

        stopButton = gtk_button_new_with_label("Stop Recording")
        g_signal_connect_data(
            stopButton,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    data.asStableRef<LinuxCoordinator>().get().stopRecording()
                }
            }.reinterpret(),
            coordinatorRef.asCPointer(),
            null,
            0u
        )

        val settingsLabel = SharedLocalization.getString("Settings", locale)
        val settingsBtn = gtk_button_new_with_label(settingsLabel)
        g_signal_connect_data(
            settingsBtn,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    data.asStableRef<LinuxCoordinator>().get().showSettings()
                }
            }.reinterpret(),
            coordinatorRef.asCPointer(),
            null,
            0u
        )

        // Quit button
        val quitLabel = SharedLocalization.getString("Quit", locale)
        val quitBtn = gtk_button_new_with_label(quitLabel)
        g_signal_connect_data(
            quitBtn,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    data.asStableRef<LinuxCoordinator>().get().quitApp()
                }
            }.reinterpret(),
            coordinatorRef.asCPointer(),
            null,
            0u
        )

        // Pack widgets into box
        gtk_box_append(box?.reinterpret(), statusLabel)
        gtk_box_append(box?.reinterpret(), startButton)
        gtk_box_append(box?.reinterpret(), stopButton)
        gtk_box_append(box?.reinterpret(), settingsBtn)
        gtk_box_append(box?.reinterpret(), quitBtn)
        updateRecordingState(coordinator.isRecording())

        // Set box as window child
        gtk_window_set_child(window?.reinterpret(), box)

        return window
    }

    /**
     * Release the StableRef and destroy the fallback window.
     * Must be called when the fallback is discarded.
     */
    fun destroy() {
        coordinatorRef.dispose()
        fallbackWindow?.let { gtk_window_destroy(it.reinterpret()) }
        fallbackWindow = null
    }

    fun updateStatus(message: String) {
        gtk_label_set_text(statusLabel?.reinterpret(), message)
    }

    fun updateRecordingState(recording: Boolean) {
        gtk_widget_set_sensitive(startButton, if (recording) 0 else 1)
        gtk_widget_set_sensitive(stopButton, if (recording) 1 else 0)
    }
}
