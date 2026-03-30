@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.reinterpret
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionState
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionUiState
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_ALIGN_CENTER
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_ORIENTATION_HORIZONTAL
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_box_append
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_box_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_label_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_label_set_text
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_add_css_class
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_hide
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_set_halign
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_set_margin_bottom
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_set_margin_end
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_set_margin_start
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_set_margin_top
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_widget_show
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_destroy
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_present
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_set_child
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_set_decorated
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_set_default_size
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_set_resizable
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_window_set_title

/**
 * Small best-effort recording overlay for Linux dictation sessions.
 */
class LinuxFloatingIndicator(
    private val settings: SettingsPersistence,
) {
    private val window = gtk_window_new()
    private val label = gtk_label_new("Recording")

    init {
        gtk_window_set_title(window?.reinterpret(), "Pindrop")
        gtk_window_set_default_size(window?.reinterpret(), 220, 56)
        gtk_window_set_resizable(window?.reinterpret(), 0)
        gtk_window_set_decorated(window?.reinterpret(), 0)

        val container = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_widget_set_margin_top(container, 14)
        gtk_widget_set_margin_bottom(container, 14)
        gtk_widget_set_margin_start(container, 18)
        gtk_widget_set_margin_end(container, 18)
        gtk_widget_set_halign(container, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(container, "card")

        gtk_widget_add_css_class(label, "title-4")
        gtk_box_append(container?.reinterpret(), label)

        gtk_window_set_child(window?.reinterpret(), container)
        gtk_widget_hide(window)
    }

    fun update(state: VoiceSessionUiState) {
        if (!isEnabled()) {
            hide()
            return
        }

        when (state.state) {
            VoiceSessionState.STARTING,
            VoiceSessionState.RECORDING,
            VoiceSessionState.PROCESSING,
            -> show(state.message ?: labelFor(state.state))
            VoiceSessionState.IDLE,
            VoiceSessionState.COMPLETED,
            VoiceSessionState.ERROR,
            -> hide()
        }
    }

    fun destroy() {
        window?.let { gtk_window_destroy(it.reinterpret()) }
    }

    private fun show(text: String) {
        gtk_label_set_text(label?.reinterpret(), text)
        gtk_window_present(window?.reinterpret())
        gtk_widget_show(window)
    }

    private fun hide() {
        gtk_widget_hide(window)
    }

    private fun isEnabled(): Boolean {
        return settings.getBool(SettingsKeys.floatingIndicatorEnabled) ?: SettingsDefaults.floatingIndicatorEnabled
    }

    private fun labelFor(state: VoiceSessionState): String {
        return when (state) {
            VoiceSessionState.STARTING -> "Starting microphone capture..."
            VoiceSessionState.RECORDING -> "Recording..."
            VoiceSessionState.PROCESSING -> "Transcribing locally..."
            VoiceSessionState.IDLE,
            VoiceSessionState.COMPLETED,
            VoiceSessionState.ERROR,
            -> "Pindrop"
        }
    }
}
