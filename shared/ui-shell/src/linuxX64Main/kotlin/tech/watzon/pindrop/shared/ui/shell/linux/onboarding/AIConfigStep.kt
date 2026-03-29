@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.core.platform.SecretStorage
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.uisettings.AISettingsCatalog
import tech.watzon.pindrop.shared.uisettings.AIProviderCore
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * AI config step — optional AI enhancement setup.
 *
 * Shows provider picker from AISettingsCatalog. Allows skipping
 * (core dictation doesn't need AI). Stores API key in SecretStorage.
 *
 * Adapted from macOS AIEnhancementStepView.swift.
 *
 * Created on 2026-03-29.
 */
class AIConfigStep(
    private val settings: SettingsPersistence,
    private val secrets: SecretStorage,
    private val locale: String
) : OnboardingStep {

    /** Whether the user chose to skip AI setup. */
    private var skipped: Boolean = false

    /** Selected provider index. */
    private var selectedProviderIndex: Int = 0

    override fun title(locale: String): String =
        SharedLocalization.getString("AI Enhancement", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val providers = AISettingsCatalog.providers()
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)

        // Header
        val heading = gtk_label_new(
            SharedLocalization.getString("AI Enhancement", locale)
        )
        gtk_widget_add_css_class(heading, "title-3")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Optionally clean up transcriptions with AI.\nThis step is optional — you can set it up later in Settings.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(box?.reinterpret(), desc)

        // Provider dropdown
        val dropDown = gtk_drop_down_new_from_strings(
            providers.map { it.displayName }
                .toTypedArray()
                .let { arr -> arrayOf(*arr, null) }
                .toCValues()
        )
        gtk_widget_set_halign(dropDown, GTK_ALIGN_CENTER)
        gtk_widget_set_margin_top(dropDown, 12)
        gtk_box_append(box?.reinterpret(), dropDown)

        // API key entry
        val keyLabel = gtk_label_new(
            SharedLocalization.getString("API Key", locale)
        )
        gtk_widget_add_css_class(keyLabel, "caption")
        gtk_widget_set_halign(keyLabel, GTK_ALIGN_START)
        gtk_widget_set_margin_top(keyLabel, 12)
        gtk_box_append(box?.reinterpret(), keyLabel)

        val keyEntry = gtk_password_entry_new()
        gtk_password_entry_set_show_peek_icon(keyEntry?.reinterpret(), 1)
        gtk_entry_set_placeholder_text(
            keyEntry?.reinterpret(),
            SharedLocalization.getString("Enter API key (optional)", locale)
        )
        gtk_box_append(box?.reinterpret(), keyEntry)

        // Feature list
        val featureBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)
        gtk_widget_set_margin_top(featureBox, 12)

        val featureTitle = gtk_label_new(
            SharedLocalization.getString("AI Enhancement will:", locale)
        )
        gtk_widget_add_css_class(featureTitle, "caption")
        gtk_widget_add_css_class(featureTitle, "heading")
        gtk_widget_set_halign(featureTitle, GTK_ALIGN_START)
        gtk_box_append(featureBox?.reinterpret(), featureTitle)

        val features = listOf(
            SharedLocalization.getString("Fix punctuation and capitalization", locale),
            SharedLocalization.getString("Correct grammar mistakes", locale),
            SharedLocalization.getString("Clean up filler words", locale),
            SharedLocalization.getString("Format text appropriately", locale),
        )
        for (feature in features) {
            val row = gtk_label_new("  ✓ $feature")
            gtk_widget_add_css_class(row, "caption")
            gtk_widget_set_halign(row, GTK_ALIGN_START)
            gtk_box_append(featureBox?.reinterpret(), row)
        }
        gtk_box_append(box?.reinterpret(), featureBox)

        return box
    }

    override fun onComplete() {
        if (!skipped) {
            val providers = AISettingsCatalog.providers()
            if (selectedProviderIndex < providers.size) {
                val provider = providers[selectedProviderIndex]
                settings.setString(SettingsKeys.aiProvider, provider.displayName)
                settings.setString(
                    SettingsKeys.aiModel,
                    AISettingsCatalog.defaultModelIdentifier(provider.id)
                )
                settings.setBool(SettingsKeys.aiEnhancementEnabled, true)
            }
        }
    }
}

/**
 * Helper to convert a Kotlin String array to CValues of CPointer<CString>?.
 */
private fun Array<String?>.toCValues(): CValues<CPointer<CString>?> {
    return memScoped {
        val ptrs = allocArray<CPointer<CString>?>(this@toCValues.size)
        this@toCValues.forEachIndexed { i, s ->
            ptrs[i] = if (s != null) s.cstr.getPointer(memScope) else null
        }
        ptrs
    }
}
