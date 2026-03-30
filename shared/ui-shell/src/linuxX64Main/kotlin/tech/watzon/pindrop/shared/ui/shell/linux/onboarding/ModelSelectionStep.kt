@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelDescriptor
import tech.watzon.pindrop.shared.runtime.transcription.LocalPlatformId
import tech.watzon.pindrop.shared.runtime.transcription.LocalTranscriptionCatalog
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class ModelSelectionStep(
    private val settings: SettingsPersistence,
    private val locale: String,
) : OnboardingStep {
    private val selectedLanguage = resolveLanguage()
    private val recommendedModels = LocalTranscriptionCatalog.recommendedModels(LocalPlatformId.LINUX, selectedLanguage)
    private val allModels = LocalTranscriptionCatalog.models(LocalPlatformId.LINUX)
    private val advancedModels = allModels.filter { candidate ->
        candidate.availability == ModelAvailability.AVAILABLE && recommendedModels.none { it.id == candidate.id }
    }

    private var selectedModel: String = settings.getString(SettingsKeys.selectedModel)
        ?: SettingsDefaults.selectedModel

    private val buttonModelMap = mutableMapOf<CPointer<*>?, String>()
    private val selfRef = StableRef.create(this)

    override fun title(locale: String): String = SharedLocalization.getString("Choose a Model", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val outerBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
        gtk_widget_set_margin_start(outerBox, 40)
        gtk_widget_set_margin_end(outerBox, 40)
        gtk_widget_set_margin_top(outerBox, 24)

        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Pick a recommended offline model now, or choose a larger model from advanced options.",
                locale,
            ),
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(outerBox?.reinterpret(), desc)

        appendSection(outerBox, SharedLocalization.getString("Recommended", locale), recommendedModels)
        if (advancedModels.isNotEmpty()) {
            appendSection(outerBox, SharedLocalization.getString("Advanced Choices", locale), advancedModels)
        }

        return outerBox
    }

    override fun onComplete() {
        settings.setString(SettingsKeys.selectedModel, selectedModel)
    }

    private fun appendSection(
        container: CPointer<GtkWidget>?,
        title: String,
        models: List<LocalModelDescriptor>,
    ) {
        val heading = gtk_label_new(title)
        gtk_widget_add_css_class(heading, "heading")
        gtk_widget_set_halign(heading, GTK_ALIGN_START)
        gtk_widget_set_margin_top(heading, 12)
        gtk_box_append(container?.reinterpret(), heading)

        val listBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)
        gtk_widget_add_css_class(listBox, "boxed-list-separate")
        gtk_widget_set_margin_top(listBox, 8)
        gtk_box_append(container?.reinterpret(), listBox)

        val existingGroup = buttonModelMap.keys.firstOrNull()?.reinterpret<GtkCheckButton>()
        models.forEach { model ->
            gtk_box_append(listBox?.reinterpret(), createModelRow(model, existingGroup))
        }
    }

    private fun createModelRow(
        model: LocalModelDescriptor,
        existingGroup: CPointer<GtkCheckButton>?,
    ): CPointer<GtkWidget>? {
        val row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)
        gtk_widget_set_margin_start(row, 12)
        gtk_widget_set_margin_end(row, 12)
        gtk_widget_set_margin_top(row, 8)
        gtk_widget_set_margin_bottom(row, 8)

        val radio = gtk_check_button_new()
        if (existingGroup != null) {
            gtk_check_button_set_group(radio?.reinterpret(), existingGroup)
        }
        if (model.id.value == selectedModel) {
            gtk_check_button_set_active(radio?.reinterpret(), 1)
        }
        buttonModelMap[radio] = model.id.value
        g_signal_connect_data(
            radio,
            "toggled",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                data?.asStableRef<ModelSelectionStep>()?.get()?.handleToggle()
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u,
        )

        val infoBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
        val nameLabel = gtk_label_new(model.displayName)
        gtk_widget_add_css_class(nameLabel, "heading")
        gtk_widget_set_halign(nameLabel, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), nameLabel)

        val detailLabel = gtk_label_new(formatModelDetail(model))
        gtk_widget_add_css_class(detailLabel, "caption")
        gtk_widget_add_css_class(detailLabel, "dim-label")
        gtk_widget_set_halign(detailLabel, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), detailLabel)

        gtk_box_append(row?.reinterpret(), radio)
        gtk_box_append(row?.reinterpret(), infoBox)

        if (recommendedModels.any { it.id == model.id }) {
            val badge = gtk_label_new(SharedLocalization.getString("Recommended", locale))
            gtk_widget_add_css_class(badge, "tag")
            gtk_widget_add_css_class(badge, "suggested-action")
            gtk_widget_set_valign(badge, GTK_ALIGN_CENTER)
            gtk_box_append(row?.reinterpret(), badge)
        }

        return row
    }

    private fun handleToggle() {
        for ((buttonPtr, modelId) in buttonModelMap) {
            val button = buttonPtr?.reinterpret<GtkCheckButton>()
            if (button != null && gtk_check_button_get_active(button) == 1) {
                selectedModel = modelId
                settings.setString(SettingsKeys.selectedModel, modelId)
                break
            }
        }
    }

    private fun resolveLanguage(): TranscriptionLanguage {
        return when (settings.getString(SettingsKeys.selectedLanguage) ?: SettingsDefaults.selectedLanguage) {
            "en" -> TranscriptionLanguage.ENGLISH
            "zh-Hans" -> TranscriptionLanguage.SIMPLIFIED_CHINESE
            "es" -> TranscriptionLanguage.SPANISH
            "fr" -> TranscriptionLanguage.FRENCH
            "de" -> TranscriptionLanguage.GERMAN
            "tr" -> TranscriptionLanguage.TURKISH
            "ja" -> TranscriptionLanguage.JAPANESE
            "pt-BR" -> TranscriptionLanguage.PORTUGUESE_BRAZIL
            "it" -> TranscriptionLanguage.ITALIAN
            "nl" -> TranscriptionLanguage.DUTCH
            "ko" -> TranscriptionLanguage.KOREAN
            else -> TranscriptionLanguage.AUTOMATIC
        }
    }

    private fun formatModelDetail(model: LocalModelDescriptor): String {
        val size = if (model.sizeInMb >= 1000) {
            String.format("%.1f GB", model.sizeInMb / 1000.0)
        } else {
            "${model.sizeInMb} MB"
        }
        return "$size · ${model.description}"
    }
}
