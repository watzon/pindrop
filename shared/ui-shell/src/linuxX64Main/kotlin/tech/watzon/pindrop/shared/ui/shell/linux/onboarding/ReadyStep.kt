@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Ready step — confirmation "You're all set" page.
 *
 * Shows a summary of the user's setup choices and confirms onboarding is complete.
 *
 * Adapted from macOS ReadyStepView.swift.
 *
 * Created on 2026-03-29.
 */
class ReadyStep(
    private val settings: SettingsPersistence,
    private val locale: String,
    private val onboardingRef: CPointer<*>?,
) : OnboardingStep {

    override fun title(locale: String): String =
        SharedLocalization.getString("You're All Set!", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)

        // Success heading
        val heading = gtk_label_new(
            SharedLocalization.getString("You're All Set!", locale)
        )
        gtk_widget_add_css_class(heading, "title-1")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Pindrop is ready to use.\nClick the tray icon to get started.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Summary section
        val summaryBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
        gtk_widget_set_margin_top(summaryBox, 16)
        gtk_widget_add_css_class(summaryBox, "pindrop-summary-card")

        val model = settings.getString(SettingsKeys.selectedModel) ?: "Base"
        val hotkey = settings.getString(SettingsKeys.Hotkeys.toggleHotkey) ?: ""
        val aiEnabled = settings.getBool(SettingsKeys.aiEnhancementEnabled) ?: false

        val summaryRows = listOf(
            Pair(
                SharedLocalization.getString("Model", locale),
                model.removePrefix("openai_whisper-")
            ),
            Pair(
                SharedLocalization.getString("Toggle", locale),
                if (hotkey.isEmpty()) SharedLocalization.getString("Not set", locale) else hotkey
            ),
            Pair(
                SharedLocalization.getString("AI Enhancement", locale),
                if (aiEnabled) SharedLocalization.getString("Enabled", locale)
                else SharedLocalization.getString("Disabled", locale)
            ),
        )

        for ((label, value) in summaryRows) {
            val row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
            gtk_widget_set_margin_start(row, 16)
            gtk_widget_set_margin_end(row, 16)
            gtk_widget_set_margin_top(row, 4)
            gtk_widget_set_margin_bottom(row, 4)

            val labelWidget = gtk_label_new(label)
            gtk_widget_add_css_class(labelWidget, "dim-label")
            gtk_widget_set_halign(labelWidget, GTK_ALIGN_START)
            gtk_widget_set_hexpand(labelWidget, 1)
            gtk_box_append(row?.reinterpret(), labelWidget)

            val valueWidget = gtk_label_new(value)
            gtk_widget_add_css_class(valueWidget, "heading")
            gtk_widget_set_halign(valueWidget, GTK_ALIGN_END)
            gtk_box_append(row?.reinterpret(), valueWidget)

            gtk_box_append(summaryBox?.reinterpret(), row)
        }

        gtk_box_append(box?.reinterpret(), summaryBox)

        val finishButton = gtk_button_new_with_label(
            SharedLocalization.getString("Launch Pindrop", locale)
        )
        gtk_widget_add_css_class(finishButton, "suggested-action")
        gtk_widget_set_halign(finishButton, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(finishButton, 12)
        g_signal_connect_data(
            finishButton,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    data.asStableRef<OnboardingWizard>().get().finishFromCallToAction()
                }
            }.reinterpret(),
            onboardingRef,
            null,
            0u,
        )
        gtk_box_append(box?.reinterpret(), finishButton)

        return box
    }
}
