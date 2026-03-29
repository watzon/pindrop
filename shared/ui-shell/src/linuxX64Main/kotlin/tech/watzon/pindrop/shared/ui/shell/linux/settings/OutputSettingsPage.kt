@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.schemasettings.FloatingIndicatorType
import tech.watzon.pindrop.shared.schemasettings.OutputMode
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class OutputSettingsPage(
    private val locale: String,
    initialOutputMode: String,
    initialAddTrailingSpace: Boolean,
    initialFloatingIndicatorEnabled: Boolean,
    initialFloatingIndicatorType: String,
    initialOffsetX: Double,
    initialOffsetY: Double,
) {
    private val outputModes = OutputMode.entries.map(OutputMode::rawValue)
    private val floatingTypes = FloatingIndicatorType.entries.map(FloatingIndicatorType::rawValue)

    private val outputModeDropDown = gtk_drop_down_new_from_strings(dropDownStrings(outputModes))
    private val addTrailingSpaceSwitch = gtk_switch_new()
    private val floatingIndicatorSwitch = gtk_switch_new()
    private val floatingIndicatorDropDown = gtk_drop_down_new_from_strings(dropDownStrings(floatingTypes))
    private val offsetXSpin = gtk_spin_button_new_with_range(-500.0, 500.0, 1.0)
    private val offsetYSpin = gtk_spin_button_new_with_range(-500.0, 500.0, 1.0)

    init {
        gtk_drop_down_set_selected(
            outputModeDropDown?.reinterpret(),
            outputModes.indexOf(initialOutputMode).takeIf { it >= 0 }?.toUInt() ?: 0u,
        )
        gtk_drop_down_set_selected(
            floatingIndicatorDropDown?.reinterpret(),
            floatingTypes.indexOf(initialFloatingIndicatorType).takeIf { it >= 0 }?.toUInt() ?: 0u,
        )
        gtk_switch_set_active(addTrailingSpaceSwitch?.reinterpret(), if (initialAddTrailingSpace) 1 else 0)
        gtk_switch_set_active(floatingIndicatorSwitch?.reinterpret(), if (initialFloatingIndicatorEnabled) 1 else 0)
        gtk_spin_button_set_value(offsetXSpin?.reinterpret(), initialOffsetX)
        gtk_spin_button_set_value(offsetYSpin?.reinterpret(), initialOffsetY)
    }

    fun title(): String = SharedLocalization.getString("Output", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Text insertion and floating indicator behavior"))
        gtk_box_append(box?.reinterpret(), labeledRow("Output Mode", outputModeDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Add Trailing Space", addTrailingSpaceSwitch, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Floating Indicator", floatingIndicatorSwitch, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Indicator Style", floatingIndicatorDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Indicator Offset X", offsetXSpin, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Indicator Offset Y", offsetYSpin, locale))
        return box
    }

    fun values(): Map<String, Any> {
        val outputIndex = gtk_drop_down_get_selected(outputModeDropDown?.reinterpret()).toInt()
        val floatingIndex = gtk_drop_down_get_selected(floatingIndicatorDropDown?.reinterpret()).toInt()
        return mapOf(
            SettingsKeys.outputMode to outputModes.getOrElse(outputIndex) { SettingsDefaults.outputMode },
            SettingsKeys.addTrailingSpace to (gtk_switch_get_active(addTrailingSpaceSwitch?.reinterpret()) == 1),
            SettingsKeys.floatingIndicatorEnabled to (gtk_switch_get_active(floatingIndicatorSwitch?.reinterpret()) == 1),
            SettingsKeys.floatingIndicatorType to floatingTypes.getOrElse(floatingIndex) { SettingsDefaults.floatingIndicatorType },
            SettingsKeys.pillFloatingIndicatorOffsetX to gtk_spin_button_get_value(offsetXSpin?.reinterpret()),
            SettingsKeys.pillFloatingIndicatorOffsetY to gtk_spin_button_get_value(offsetYSpin?.reinterpret()),
        )
    }
}
