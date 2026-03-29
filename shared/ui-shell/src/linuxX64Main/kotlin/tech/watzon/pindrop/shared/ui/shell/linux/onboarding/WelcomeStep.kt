@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Welcome step — the first onboarding page.
 *
 * Displays a welcome message, app description, and feature highlights.
 * Purely informational with no gates — always complete.
 *
 * Adapted from macOS WelcomeStepView.swift.
 *
 * Created on 2026-03-29.
 */
class WelcomeStep(
    private val locale: String
) : OnboardingStep {

    override fun title(locale: String): String =
        SharedLocalization.getString("Welcome to Pindrop", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)

        // App name heading
        val heading = gtk_label_new(
            SharedLocalization.getString("Welcome to Pindrop", locale)
        )
        gtk_widget_add_css_class(heading, "title-2")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        // Description
        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Local speech-to-text, right from your menu bar.\nFast, private, and always available.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Separator
        val sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)
        gtk_widget_set_margin_top(sep, 12)
        gtk_widget_set_margin_bottom(sep, 12)
        gtk_box_append(box?.reinterpret(), sep)

        // Feature list
        val features = listOf(
            SharedLocalization.getString("Powered by Whisper", locale),
            SharedLocalization.getString("100% local processing", locale),
            SharedLocalization.getString("Global keyboard shortcuts", locale),
        )
        for (feature in features) {
            val row = gtk_label_new("• $feature")
            gtk_widget_set_halign(row, GTK_ALIGN_START)
            gtk_widget_set_margin_start(row, 12)
            gtk_widget_add_css_class(row, "body")
            gtk_box_append(box?.reinterpret(), row)
        }

        // Spacer
        val spacer = gtk_label_new("")
        gtk_widget_set_vexpand(spacer, 1)
        gtk_box_append(box?.reinterpret(), spacer)

        // Get Started label (the assistant provides forward/apply buttons)
        val hint = gtk_label_new(
            SharedLocalization.getString("Click Next to continue.", locale)
        )
        gtk_widget_add_css_class(hint, "caption")
        gtk_widget_add_css_class(hint, "dim-label")
        gtk_widget_set_halign(hint, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), hint)

        return box
    }
}
