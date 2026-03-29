@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class ModelsSettingsPage(
    private val locale: String,
    initialSelectedModel: String,
    initialSelectedLanguage: String,
) {
    private val selectedModelEntry = gtk_entry_new()
    private val selectedLanguageEntry = gtk_entry_new()

    init {
        gtk_editable_set_text(selectedModelEntry?.reinterpret(), initialSelectedModel.ifBlank { SettingsDefaults.selectedModel })
        gtk_editable_set_text(selectedLanguageEntry?.reinterpret(), initialSelectedLanguage.ifBlank { SettingsDefaults.selectedLanguage })
    }

    fun title(): String = SharedLocalization.getString("Models", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Transcription model and language defaults"))
        gtk_box_append(box?.reinterpret(), labeledRow("Selected Model", selectedModelEntry, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Transcription Language", selectedLanguageEntry, locale))

        val placeholder = gtk_label_new(
            SharedLocalization.getString(
                "Model download and removal controls land in a later Linux phase. This page stores the preferred defaults now.",
                locale,
            ),
        )
        gtk_label_set_wrap(placeholder?.reinterpret(), 1)
        gtk_widget_add_css_class(placeholder, "dim-label")
        gtk_widget_set_halign(placeholder, GTK_ALIGN_START)
        gtk_box_append(box?.reinterpret(), placeholder)
        return box
    }

    fun values(): Map<String, Any> {
        return mapOf(
            SettingsKeys.selectedModel to gtk_editable_get_text(selectedModelEntry?.reinterpret()).toKString().ifBlank { SettingsDefaults.selectedModel },
            SettingsKeys.selectedLanguage to gtk_editable_get_text(selectedLanguageEntry?.reinterpret()).toKString().ifBlank { SettingsDefaults.selectedLanguage },
        )
    }
}
