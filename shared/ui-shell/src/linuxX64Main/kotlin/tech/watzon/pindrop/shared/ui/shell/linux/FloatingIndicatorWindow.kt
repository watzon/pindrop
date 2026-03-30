@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlin.math.roundToInt
import kotlinx.cinterop.reinterpret
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionState
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionUiState
import tech.watzon.pindrop.shared.schemasettings.FloatingIndicatorType
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_ALIGN_CENTER
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_ALIGN_START
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_ORIENTATION_VERTICAL
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_box_append
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_box_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_label_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_label_set_text
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_label_set_wrap
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
 * Lightweight Linux recording overlay driven by shared voice-session state.
 *
 * Created on 2026-03-30.
 */
enum class FloatingIndicatorPresentationResult {
    SHOWN,
    HIDDEN,
    DISABLED,
    UNAVAILABLE,
}

class FloatingIndicatorWindow(
    private val settings: SettingsPersistence,
) {
    private var window = gtk_window_new()
    private val container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)
    private val titleLabel = gtk_label_new("Recording")
    private val detailLabel = gtk_label_new("Pindrop is listening")

    init {
        runCatching(::configureWindow)
    }

    fun update(state: VoiceSessionUiState): FloatingIndicatorPresentationResult {
        if (!isEnabled()) {
            hide()
            return FloatingIndicatorPresentationResult.DISABLED
        }

        return when (state.state) {
            VoiceSessionState.STARTING,
            VoiceSessionState.RECORDING,
            VoiceSessionState.PROCESSING,
            -> show(state.state, state.message)

            VoiceSessionState.IDLE,
            VoiceSessionState.COMPLETED,
            VoiceSessionState.ERROR,
            -> {
                hide()
                FloatingIndicatorPresentationResult.HIDDEN
            }
        }
    }

    fun destroy() {
        window?.let { gtk_window_destroy(it.reinterpret()) }
        window = null
    }

    private fun configureWindow() {
        gtk_window_set_title(window?.reinterpret(), "Pindrop Recording")
        gtk_window_set_default_size(window?.reinterpret(), defaultWidth(), 72)
        gtk_window_set_resizable(window?.reinterpret(), 0)
        gtk_window_set_decorated(window?.reinterpret(), 0)

        gtk_widget_set_margin_top(container, offsetY().coerceAtLeast(0) + 16)
        gtk_widget_set_margin_bottom(container, 16)
        gtk_widget_set_margin_start(container, offsetX().coerceAtLeast(0) + 18)
        gtk_widget_set_margin_end(container, 18)
        gtk_widget_set_halign(container, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(container, containerCssClass())

        gtk_widget_add_css_class(titleLabel, "title-4")
        gtk_widget_set_halign(titleLabel, GTK_ALIGN_START)

        gtk_label_set_wrap(detailLabel?.reinterpret(), 1)
        gtk_widget_add_css_class(detailLabel, "dim-label")
        gtk_widget_set_halign(detailLabel, GTK_ALIGN_START)

        gtk_box_append(container?.reinterpret(), titleLabel)
        gtk_box_append(container?.reinterpret(), detailLabel)
        gtk_window_set_child(window?.reinterpret(), container)
        gtk_widget_hide(window)
    }

    private fun show(
        state: VoiceSessionState,
        message: String?,
    ): FloatingIndicatorPresentationResult {
        return runCatching {
            if (window == null) {
                window = gtk_window_new()
                configureWindow()
            }

            gtk_label_set_text(titleLabel?.reinterpret(), titleFor(state))
            gtk_label_set_text(detailLabel?.reinterpret(), message ?: subtitleFor(state))
            gtk_window_set_default_size(window?.reinterpret(), defaultWidth(), 72)
            gtk_window_present(window?.reinterpret())
            gtk_widget_show(window)
            FloatingIndicatorPresentationResult.SHOWN
        }.getOrElse {
            hide()
            FloatingIndicatorPresentationResult.UNAVAILABLE
        }
    }

    private fun hide() {
        window?.let { gtk_widget_hide(it) }
    }

    private fun isEnabled(): Boolean {
        return settings.getBool(SettingsKeys.floatingIndicatorEnabled)
            ?: SettingsDefaults.floatingIndicatorEnabled
    }

    private fun type(): FloatingIndicatorType {
        val rawValue = settings.getString(SettingsKeys.floatingIndicatorType)
            ?: SettingsDefaults.floatingIndicatorType
        return FloatingIndicatorType.entries.firstOrNull { it.rawValue == rawValue }
            ?: FloatingIndicatorType.NOTCH
    }

    private fun offsetX(): Int {
        return (settings.getDouble(SettingsKeys.pillFloatingIndicatorOffsetX)
            ?: SettingsDefaults.pillFloatingIndicatorOffsetX).roundToInt()
    }

    private fun offsetY(): Int {
        return (settings.getDouble(SettingsKeys.pillFloatingIndicatorOffsetY)
            ?: SettingsDefaults.pillFloatingIndicatorOffsetY).roundToInt()
    }

    private fun defaultWidth(): Int {
        return when (type()) {
            FloatingIndicatorType.NOTCH -> 220
            FloatingIndicatorType.PILL -> 240 + offsetX().coerceAtLeast(0)
            FloatingIndicatorType.BUBBLE -> 200
        }
    }

    private fun containerCssClass(): String {
        return when (type()) {
            FloatingIndicatorType.NOTCH -> "card"
            FloatingIndicatorType.PILL -> "pill"
            FloatingIndicatorType.BUBBLE -> "osd"
        }
    }

    private fun titleFor(state: VoiceSessionState): String {
        return when (state) {
            VoiceSessionState.STARTING -> "Starting"
            VoiceSessionState.RECORDING -> "Recording"
            VoiceSessionState.PROCESSING -> "Processing"
            VoiceSessionState.IDLE,
            VoiceSessionState.COMPLETED,
            VoiceSessionState.ERROR,
            -> "Pindrop"
        }
    }

    private fun subtitleFor(state: VoiceSessionState): String {
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
