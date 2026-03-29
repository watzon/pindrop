@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.schemasettings.AppLanguage
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.ThemeMode
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class GeneralSettingsPage(
    private val locale: String,
    initialLanguage: String,
    initialThemeMode: String,
    initialLaunchAtLogin: Boolean,
    initialShowInDock: Boolean,
) {
    private val languages = AppLanguage.entries.map(AppLanguage::rawValue)
    private val themeModes = ThemeMode.entries.map(ThemeMode::rawValue)

    private val languageDropDown = gtk_drop_down_new_from_strings(dropDownStrings(languages))
    private val themeDropDown = gtk_drop_down_new_from_strings(dropDownStrings(themeModes))
    private val launchAtLoginSwitch = gtk_switch_new()
    private val showInDockSwitch = gtk_switch_new()

    init {
        gtk_drop_down_set_selected(
            languageDropDown?.reinterpret(),
            languages.indexOf(initialLanguage).takeIf { it >= 0 }?.toUInt() ?: 0u,
        )
        gtk_drop_down_set_selected(
            themeDropDown?.reinterpret(),
            themeModes.indexOf(initialThemeMode).takeIf { it >= 0 }?.toUInt() ?: 0u,
        )
        gtk_switch_set_active(launchAtLoginSwitch?.reinterpret(), if (initialLaunchAtLogin) 1 else 0)
        gtk_switch_set_active(showInDockSwitch?.reinterpret(), if (initialShowInDock) 1 else 0)
    }

    fun title(): String = SharedLocalization.getString("General", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Language, appearance, and startup behavior"))
        gtk_box_append(box?.reinterpret(), labeledRow("Language", languageDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Theme", themeDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Launch at Login", launchAtLoginSwitch, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Show in Dock", showInDockSwitch, locale))
        return box
    }

    fun values(): Map<String, Any> {
        val languageIndex = gtk_drop_down_get_selected(languageDropDown?.reinterpret()).toInt()
        val themeIndex = gtk_drop_down_get_selected(themeDropDown?.reinterpret()).toInt()
        return mapOf(
            SettingsKeys.selectedLanguage to languages.getOrElse(languageIndex) { SettingsDefaults.selectedLanguage },
            SettingsKeys.themeMode to themeModes.getOrElse(themeIndex) { SettingsDefaults.themeMode },
            SettingsKeys.launchAtLogin to (gtk_switch_get_active(launchAtLoginSwitch?.reinterpret()) == 1),
            SettingsKeys.showInDock to (gtk_switch_get_active(showInDockSwitch?.reinterpret()) == 1),
        )
    }
}
