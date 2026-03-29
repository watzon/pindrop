@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class DictionarySettingsPage(
    private val locale: String,
    initialAutomaticDictionaryLearningEnabled: Boolean,
) {
    private val automaticLearningSwitch = gtk_switch_new()

    init {
        gtk_switch_set_active(automaticLearningSwitch?.reinterpret(), if (initialAutomaticDictionaryLearningEnabled) 1 else 0)
    }

    fun title(): String = SharedLocalization.getString("Dictionary", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Automatic learning and future word replacements"))
        gtk_box_append(box?.reinterpret(), labeledRow("Automatic Dictionary Learning", automaticLearningSwitch, locale))

        val placeholder = gtk_label_new(
            SharedLocalization.getString(
                "Custom replacements and dictionary editing arrive in a later Linux phase.",
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
            SettingsKeys.automaticDictionaryLearningEnabled to (gtk_switch_get_active(automaticLearningSwitch?.reinterpret()) == 1),
        )
    }
}
