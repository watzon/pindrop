@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Hotkey setup step — display default hotkey and explain Linux limitations.
 *
 * Per D-04, D-13: Shows default hotkey, explains limitations (X11 works,
 * Wayland varies). Shows warning badge if runtime can't bind. Offers
 * alternatives: tray click, CLI trigger.
 *
 * Adapted from macOS HotkeySetupStepView.swift.
 *
 * Created on 2026-03-29.
 */
class HotkeySetupStep(
    private val settings: SettingsPersistence,
    private val locale: String
) : OnboardingStep {

    override fun title(locale: String): String =
        SharedLocalization.getString("Keyboard Shortcuts", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)

        // Description
        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Your hotkeys are ready to use.\nYou can customize them later in Settings.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Hotkey cards
        val toggleHotkey = settings.getString(SettingsKeys.Hotkeys.toggleHotkey)
            ?: SettingsDefaults.Hotkeys.toggleHotkey
        val pttHotkey = settings.getString(SettingsKeys.Hotkeys.pushToTalkHotkey)
            ?: SettingsDefaults.Hotkeys.pushToTalkHotkey
        val copyHotkey = settings.getString(SettingsKeys.Hotkeys.copyLastTranscriptHotkey)
            ?: SettingsDefaults.Hotkeys.copyLastTranscriptHotkey

        val hotkeys = listOf(
            Triple(
                SharedLocalization.getString("Toggle Recording", locale),
                SharedLocalization.getString("Press once to start, again to stop", locale),
                toggleHotkey
            ),
            Triple(
                SharedLocalization.getString("Push-to-Talk", locale),
                SharedLocalization.getString("Hold to record, release to transcribe", locale),
                pttHotkey
            ),
            Triple(
                SharedLocalization.getString("Copy Last Transcript", locale),
                SharedLocalization.getString("Quickly copy your last transcription", locale),
                copyHotkey
            ),
        )

        for ((title, description, hotkey) in hotkeys) {
            val card = createHotkeyCard(title, description, hotkey)
            gtk_box_append(box?.reinterpret(), card)
        }

        // Linux-specific warning
        val warningBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_widget_set_margin_top(warningBox, 8)

        val warningLabel = gtk_label_new(
            SharedLocalization.getString(
                "Note: Global hotkeys work on X11. On Wayland, support depends on your compositor.\nYou can always use the tray icon or CLI as alternatives.",
                locale
            )
        )
        gtk_label_set_wrap(warningLabel?.reinterpret(), 1)
        gtk_widget_add_css_class(warningLabel, "caption")
        gtk_widget_add_css_class(warningLabel, "dim-label")
        gtk_box_append(warningBox?.reinterpret(), warningLabel)

        gtk_box_append(box?.reinterpret(), warningBox)

        return box
    }

    private fun createHotkeyCard(
        title: String,
        description: String,
        hotkey: String
    ): CPointer<GtkWidget>? {
        val card = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)
        gtk_widget_set_margin_top(card, 8)
        gtk_widget_set_margin_bottom(card, 8)
        gtk_widget_add_css_class(card, "card")

        val infoBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
        gtk_widget_set_hexpand(infoBox, 1)

        val titleLabel = gtk_label_new(title)
        gtk_widget_add_css_class(titleLabel, "heading")
        gtk_widget_set_halign(titleLabel, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), titleLabel)

        val descLabel = gtk_label_new(description)
        gtk_widget_add_css_class(descLabel, "caption")
        gtk_widget_add_css_class(descLabel, "dim-label")
        gtk_widget_set_halign(descLabel, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), descLabel)

        gtk_box_append(card?.reinterpret(), infoBox)

        // Hotkey badge
        val hotkeyLabel = gtk_label_new(
            if (hotkey.isEmpty()) SharedLocalization.getString("Not Set", locale) else hotkey
        )
        gtk_widget_add_css_class(hotkeyLabel, "monospace")
        gtk_widget_add_css_class(hotkeyLabel, "accent")
        gtk_widget_set_margin_start(hotkeyLabel, 8)
        gtk_widget_set_valign(hotkeyLabel, GTK_ALIGN_CENTER)
        gtk_box_append(card?.reinterpret(), hotkeyLabel)

        return card
    }
}
