@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import platform.posix.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Audio check step — soft probe for PipeWire/PulseAudio.
 *
 * Per D-04: This is a soft gate (inform, don't block). We detect the
 * audio system and show the result. If no audio system is found, we
 * show a warning but allow continuing — softer than macOS which blocks.
 *
 * Adapted from macOS PermissionsStepView.swift.
 *
 * Created on 2026-03-29.
 */
class AudioCheckStep(
    private val locale: String
) : OnboardingStep {

    /** Detected audio system name, set during content creation. */
    private var detectedAudioSystem: String = "Unknown"

    override fun title(locale: String): String =
        SharedLocalization.getString("Audio Setup", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)

        // Header
        val heading = gtk_label_new(
            SharedLocalization.getString("Audio Setup", locale)
        )
        gtk_widget_add_css_class(heading, "title-2")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Pindrop needs audio input for dictation.\nWe'll check your system's audio configuration.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Detect audio system
        detectedAudioSystem = detectAudioSystem()

        // Show detection result
        val resultBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
        gtk_widget_set_margin_top(resultBox, 16)

        val audioDetected = detectedAudioSystem != "None"

        val statusLabel = gtk_label_new(
            if (audioDetected) {
                SharedLocalization.getString("Audio system detected", locale) + ": $detectedAudioSystem"
            } else {
                SharedLocalization.getString("No audio system detected", locale)
            }
        )
        gtk_widget_add_css_class(statusLabel, "heading")
        gtk_widget_set_halign(statusLabel, GTK_ALIGN_CENTER)
        gtk_box_append(resultBox?.reinterpret(), statusLabel)

        if (audioDetected) {
            val successLabel = gtk_label_new(
                SharedLocalization.getString(
                    "Your audio system is ready for dictation.",
                    locale
                )
            )
            gtk_label_set_wrap(successLabel?.reinterpret(), 1)
            gtk_widget_add_css_class(successLabel, "success")
            gtk_widget_set_halign(successLabel, GTK_ALIGN_CENTER)
            gtk_box_append(resultBox?.reinterpret(), successLabel)
        } else {
            val warningLabel = gtk_label_new(
                SharedLocalization.getString(
                    "No PipeWire or PulseAudio detected.\nYou can continue, but audio recording may not work until an audio server is configured.",
                    locale
                )
            )
            gtk_label_set_wrap(warningLabel?.reinterpret(), 1)
            gtk_widget_add_css_class(warningLabel, "warning")
            gtk_widget_set_halign(warningLabel, GTK_ALIGN_CENTER)
            gtk_box_append(resultBox?.reinterpret(), warningLabel)
        }

        gtk_box_append(box?.reinterpret(), resultBox)

        // Info about Linux audio
        val infoLabel = gtk_label_new(
            SharedLocalization.getString(
                "On Linux, Pindrop uses PipeWire or PulseAudio for audio capture.",
                locale
            )
        )
        gtk_label_set_wrap(infoLabel?.reinterpret(), 1)
        gtk_widget_set_margin_top(infoLabel, 12)
        gtk_widget_add_css_class(infoLabel, "caption")
        gtk_widget_add_css_class(infoLabel, "dim-label")
        gtk_widget_set_halign(infoLabel, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), infoLabel)

        return box
    }

    /**
     * Detect the available audio system by checking for PipeWire/PulseAudio.
     * Uses environment variables and runtime checks.
     */
    private fun detectAudioSystem(): String {
        // Check for PipeWire (via PIPEWIRE_RUNTIME_DIR or pulseaudio compat)
        val pipewireRuntime = getenv("PIPEWIRE_RUNTIME_DIR")?.toKString()
        if (!pipewireRuntime.isNullOrEmpty()) {
            return "PipeWire"
        }

        // Check for PulseAudio via PULSE_SERVER
        val pulseServer = getenv("PULSE_SERVER")?.toKString()
        if (!pulseServer.isNullOrEmpty()) {
            return "PulseAudio"
        }

        // Check if pipewire-pulse is running (common default)
        val pipewireCheck = popen("pgrep -x pipewire 2>/dev/null", "r")
        if (pipewireCheck != null) {
            val buffer = ByteArray(64)
            val bytesRead = fread(buffer.refTo(0), 1u, 63u, pipewireCheck)
            pclose(pipewireCheck)
            if (bytesRead > 0u) {
                return "PipeWire"
            }
        }

        // Check for pulseaudio daemon
        val pulseCheck = popen("pgrep -x pulseaudio 2>/dev/null", "r")
        if (pulseCheck != null) {
            val buffer = ByteArray(64)
            val bytesRead = fread(buffer.refTo(0), 1u, 63u, pulseCheck)
            pclose(pulseCheck)
            if (bytesRead > 0u) {
                return "PulseAudio"
            }
        }

        return "None"
    }
}
