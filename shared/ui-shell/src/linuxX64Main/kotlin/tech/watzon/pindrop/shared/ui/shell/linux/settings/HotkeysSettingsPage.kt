@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class HotkeysSettingsPage(
    private val locale: String,
    initialToggleHotkey: String,
    initialPushToTalkHotkey: String,
    initialCopyLastTranscriptHotkey: String,
) {
    private val toggleHotkeyEntry = gtk_entry_new()
    private val pushToTalkHotkeyEntry = gtk_entry_new()
    private val copyLastTranscriptHotkeyEntry = gtk_entry_new()

    init {
        gtk_editable_set_text(toggleHotkeyEntry?.reinterpret(), initialToggleHotkey.ifBlank { SettingsDefaults.Hotkeys.toggleHotkey })
        gtk_editable_set_text(pushToTalkHotkeyEntry?.reinterpret(), initialPushToTalkHotkey.ifBlank { SettingsDefaults.Hotkeys.pushToTalkHotkey })
        gtk_editable_set_text(copyLastTranscriptHotkeyEntry?.reinterpret(), initialCopyLastTranscriptHotkey.ifBlank { SettingsDefaults.Hotkeys.copyLastTranscriptHotkey })
    }

    fun title(): String = SharedLocalization.getString("Hotkeys", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Shortcut preferences and Linux-specific guidance"))
        gtk_box_append(box?.reinterpret(), labeledRow("Toggle Recording", toggleHotkeyEntry, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Push-to-Talk", pushToTalkHotkeyEntry, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Copy Last Transcript", copyLastTranscriptHotkeyEntry, locale))

        val warning = gtk_label_new(
            SharedLocalization.getString(
                "Wayland support depends on your compositor. If a shortcut cannot bind, use the tray icon or CLI trigger instead.",
                locale,
            ),
        )
        gtk_label_set_wrap(warning?.reinterpret(), 1)
        gtk_widget_add_css_class(warning, "dim-label")
        gtk_widget_set_halign(warning, GTK_ALIGN_START)
        gtk_box_append(box?.reinterpret(), warning)
        return box
    }

    fun values(): Map<String, Any> {
        return mapOf(
            SettingsKeys.Hotkeys.toggleHotkey to gtk_editable_get_text(toggleHotkeyEntry?.reinterpret()).toKString(),
            SettingsKeys.Hotkeys.pushToTalkHotkey to gtk_editable_get_text(pushToTalkHotkeyEntry?.reinterpret()).toKString(),
            SettingsKeys.Hotkeys.copyLastTranscriptHotkey to gtk_editable_get_text(copyLastTranscriptHotkeyEntry?.reinterpret()).toKString(),
        )
    }
}
