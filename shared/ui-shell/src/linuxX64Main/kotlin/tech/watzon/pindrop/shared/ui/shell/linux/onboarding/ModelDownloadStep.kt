@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Model download step — placeholder for model download progress.
 *
 * Shows a progress indicator placeholder. The actual download wiring
 * happens in Phase 3 when the model management module is built.
 * For now, shows a message that the model will be downloaded on first use.
 *
 * Adapted from macOS ModelDownloadStepView.swift.
 *
 * Created on 2026-03-29.
 */
class ModelDownloadStep(
    private val locale: String
) : OnboardingStep {

    override fun title(locale: String): String =
        SharedLocalization.getString("Download Model", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)

        // Status message
        val heading = gtk_label_new(
            SharedLocalization.getString("Model Download", locale)
        )
        gtk_widget_add_css_class(heading, "title-3")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Your selected model will be downloaded when you first start dictation.\nThis ensures you always have the latest version.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Progress placeholder — a simple spinner indicator
        val spinner = gtk_spinner_new()
        gtk_widget_set_size_request(spinner, 48, 48)
        gtk_widget_set_halign(spinner, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(spinner, 16)
        gtk_widget_set_margin_bottom(spinner, 16)
        // Don't start the spinner — model download is deferred
        gtk_box_append(box?.reinterpret(), spinner)

        // Info note
        val info = gtk_label_new(
            SharedLocalization.getString(
                "Model downloads are typically 75 MB to 1.5 GB depending on your selection.",
                locale
            )
        )
        gtk_label_set_wrap(info?.reinterpret(), 1)
        gtk_widget_add_css_class(info, "caption")
        gtk_widget_add_css_class(info, "dim-label")
        gtk_widget_set_halign(info, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(info, 8)
        gtk_box_append(box?.reinterpret(), info)

        return box
    }
}
