@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SecretStorage
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uisettings.AIEnhancementDraft
import tech.watzon.pindrop.shared.uisettings.AIEnhancementPresenter
import tech.watzon.pindrop.shared.uisettings.AIModelSnapshot
import tech.watzon.pindrop.shared.uisettings.AIProviderCore
import tech.watzon.pindrop.shared.uisettings.AISettingsCatalog
import tech.watzon.pindrop.shared.uisettings.CustomProviderTypeCore
import tech.watzon.pindrop.shared.uisettings.PromptPresetSnapshot
import tech.watzon.pindrop.shared.uisettings.PromptTypeCore
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class AISettingsPage(
    private val locale: String,
    private val secrets: SecretStorage,
    private val initialEnabled: Boolean,
    initialProvider: String,
    initialCustomProvider: String,
    initialModel: String,
    initialPrompt: String,
) {
    private val providers = AISettingsCatalog.providers()
    private val customProviders = AISettingsCatalog.customProviders()

    private val enabledSwitch = gtk_switch_new()
    private val providerDropDown = gtk_drop_down_new_from_strings(dropDownStrings(providers.map { it.displayName }))
    private val customProviderDropDown = gtk_drop_down_new_from_strings(dropDownStrings(customProviders.map { it.displayName }))
    private val apiKeyEntry = gtk_password_entry_new()
    private val modelEntry = gtk_entry_new()
    private val promptBuffer = gtk_text_buffer_new(null)
    private val promptView = gtk_text_view_new_with_buffer(promptBuffer)

    init {
        gtk_switch_set_active(enabledSwitch?.reinterpret(), if (initialEnabled) 1 else 0)
        gtk_drop_down_set_selected(providerDropDown?.reinterpret(), providers.indexOfFirst { it.displayName == initialProvider }.takeIf { it >= 0 }?.toUInt() ?: 0u)
        gtk_drop_down_set_selected(customProviderDropDown?.reinterpret(), customProviders.indexOfFirst { it.displayName == initialCustomProvider }.takeIf { it >= 0 }?.toUInt() ?: 0u)
        gtk_editable_set_text(modelEntry?.reinterpret(), initialModel.ifBlank { SettingsDefaults.aiModel })
        gtk_password_entry_set_show_peek_icon(apiKeyEntry?.reinterpret(), 1)
        gtk_text_buffer_set_text(promptBuffer, initialPrompt.ifBlank { SettingsDefaults.aiEnhancementPrompt }, -1)
    }

    fun title(): String = SharedLocalization.getString("AI Enhancement", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Provider, model, prompt, and secure API key storage"))
        gtk_box_append(box?.reinterpret(), labeledRow("Enable AI Enhancement", enabledSwitch, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Provider", providerDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Custom Provider", customProviderDropDown, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("API Key", apiKeyEntry, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Model", modelEntry, locale))
        gtk_box_append(box?.reinterpret(), labeledRow("Prompt", promptView, locale))

        val viewState = AIEnhancementPresenter.present(
            AIEnhancementDraft(
                selectedProvider = providers.firstOrNull()?.id ?: AIProviderCore.OPENAI,
                selectedCustomProvider = customProviders.firstOrNull()?.id ?: CustomProviderTypeCore.CUSTOM,
                apiKey = "",
                selectedModel = SettingsDefaults.aiModel,
                customModel = SettingsDefaults.aiModel,
                enhancementPrompt = SettingsDefaults.aiEnhancementPrompt,
                noteEnhancementPrompt = SettingsDefaults.noteEnhancementPrompt,
                selectedPromptType = PromptTypeCore.TRANSCRIPTION,
                selectedPresetId = SettingsDefaults.selectedPresetId,
                customEndpointText = "",
                availableModels = emptyList<AIModelSnapshot>(),
                modelErrorMessage = null,
                isLoadingModels = false,
                aiEnhancementEnabled = initialEnabled,
            ),
            presets = emptyList<PromptPresetSnapshot>(),
        )

        val help = gtk_label_new(viewState.apiKeyHelpText ?: SharedLocalization.getString("API keys are stored in SecretStorage on Linux.", locale))
        gtk_label_set_wrap(help?.reinterpret(), 1)
        gtk_widget_add_css_class(help, "dim-label")
        gtk_widget_set_halign(help, GTK_ALIGN_START)
        gtk_box_append(box?.reinterpret(), help)
        return box
    }

    fun values(): Map<String, Any> {
        val providerIndex = gtk_drop_down_get_selected(providerDropDown?.reinterpret()).toInt()
        val customProviderIndex = gtk_drop_down_get_selected(customProviderDropDown?.reinterpret()).toInt()
        return mapOf(
            SettingsKeys.aiEnhancementEnabled to (gtk_switch_get_active(enabledSwitch?.reinterpret()) == 1),
            SettingsKeys.aiProvider to providers.getOrElse(providerIndex) { providers.first() }.displayName,
            SettingsKeys.customLocalProviderType to customProviders.getOrElse(customProviderIndex) { customProviders.first() }.displayName,
            SettingsKeys.aiModel to gtk_editable_get_text(modelEntry?.reinterpret()).toKString().ifBlank { SettingsDefaults.aiModel },
            SettingsKeys.aiEnhancementPrompt to textBufferString(promptBuffer).ifBlank { SettingsDefaults.aiEnhancementPrompt },
        )
    }

    fun saveSecrets() {
        val providerIndex = gtk_drop_down_get_selected(providerDropDown?.reinterpret()).toInt()
        val account = providers.getOrElse(providerIndex) { providers.first() }.displayName
        val apiKey = gtk_editable_get_text(apiKeyEntry?.reinterpret()).toKString()
        if (apiKey.isBlank()) {
            secrets.deleteSecret(account = account, service = "pindrop-ai")
        } else {
            secrets.storeSecret(account = account, service = "pindrop-ai", value = apiKey)
        }
    }
}
