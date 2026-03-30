@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.ModelAvailability
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelDescriptor
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.ui.shell.linux.models.LinuxModelController
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class ModelsSettingsPage(
    private val locale: String,
    private val modelController: LinuxModelController,
    initialSelectedModel: String,
    initialSelectedLanguage: String,
) {
    private var selectedModel = initialSelectedModel.ifBlank { SettingsDefaults.selectedModel }
    private var selectedLanguage = initialSelectedLanguage.ifBlank { SettingsDefaults.selectedLanguage }
    private val statusLabel = gtk_label_new(null)
    private val selfRef = StableRef.create(this)
    private val actionMap = mutableMapOf<CPointer<*>?, Pair<String, String>>()

    fun title(): String = SharedLocalization.getString("Models", locale)

    fun build(): CPointer<GtkWidget>? {
        val box = settingsPageBox()
        gtk_box_append(box?.reinterpret(), pageHeading(title(), "Download, activate, and remove offline models"))

        gtk_label_set_wrap(statusLabel?.reinterpret(), 1)
        gtk_widget_add_css_class(statusLabel, "dim-label")
        gtk_widget_set_halign(statusLabel, GTK_ALIGN_START)
        gtk_label_set_text(statusLabel?.reinterpret(), "Selected model: $selectedModel")
        gtk_box_append(box?.reinterpret(), statusLabel)

        val installed = modelController.installedModels().associateBy { it.modelId.value }
        val catalog = modelController.allModels()
        catalog.forEach { model ->
            gtk_box_append(box?.reinterpret(), createModelRow(model, installed.containsKey(model.id.value)))
        }

        return box
    }

    fun values(): Map<String, Any> {
        return mapOf(
            SettingsKeys.selectedModel to selectedModel,
            SettingsKeys.selectedLanguage to selectedLanguage,
        )
    }

    private fun createModelRow(
        model: LocalModelDescriptor,
        isInstalled: Boolean,
    ): CPointer<GtkWidget>? {
        val row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)
        gtk_widget_set_margin_top(row, 8)
        gtk_widget_set_margin_bottom(row, 8)

        val infoBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
        val titleLabel = gtk_label_new(model.displayName)
        gtk_widget_add_css_class(titleLabel, "heading")
        gtk_widget_set_halign(titleLabel, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), titleLabel)

        val detail = gtk_label_new(modelSummary(model, isInstalled))
        gtk_label_set_wrap(detail?.reinterpret(), 1)
        gtk_widget_add_css_class(detail, "caption")
        gtk_widget_add_css_class(detail, "dim-label")
        gtk_widget_set_halign(detail, GTK_ALIGN_START)
        gtk_box_append(infoBox?.reinterpret(), detail)

        gtk_box_append(row?.reinterpret(), infoBox)

        when {
            model.availability == ModelAvailability.REQUIRES_SETUP -> {
                gtk_box_append(row?.reinterpret(), disabledStateLabel("Requires setup"))
            }

            model.availability == ModelAvailability.COMING_SOON -> {
                gtk_box_append(row?.reinterpret(), disabledStateLabel("Coming soon"))
            }

            !isInstalled -> {
                gtk_box_append(row?.reinterpret(), actionButton(model.id, "Download", "download"))
            }

            model.id.value == selectedModel -> {
                gtk_box_append(row?.reinterpret(), disabledStateLabel("Active"))
            }

            else -> {
                gtk_box_append(row?.reinterpret(), actionButton(model.id, "Use", "use"))
                gtk_box_append(row?.reinterpret(), actionButton(model.id, "Remove", "remove"))
            }
        }

        return row
    }

    private fun actionButton(
        modelId: TranscriptionModelId,
        label: String,
        action: String,
    ): CPointer<GtkWidget>? {
        val button = gtk_button_new_with_label(label)
        actionMap[button] = modelId.value to action
        g_signal_connect_data(
            button,
            "clicked",
            staticCFunction { sender: CPointer<*>?, data: CPointer<*>? ->
                if (sender != null && data != null) {
                    val page = data.asStableRef<ModelsSettingsPage>().get()
                    page.handleAction(sender)
                }
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u,
        )
        return button
    }

    private fun disabledStateLabel(text: String): CPointer<GtkWidget>? {
        val label = gtk_label_new(text)
        gtk_widget_add_css_class(label, "dim-label")
        gtk_widget_set_valign(label, GTK_ALIGN_CENTER)
        return label
    }

    private fun handleAction(sender: CPointer<*>) {
        val (modelId, action) = actionMap[sender] ?: return
        runCatching {
            when (action) {
                "download" -> modelController.install(TranscriptionModelId(modelId)) { progress, message ->
                    gtk_label_set_text(statusLabel?.reinterpret(), message ?: "Downloading $modelId (${(progress * 100).toInt()}%)")
                }
                "use" -> modelController.load(TranscriptionModelId(modelId))
                "remove" -> modelController.delete(TranscriptionModelId(modelId))
            }
        }.onSuccess {
            if (action != "remove") {
                selectedModel = modelId
                modelController.setSelectedModel(modelId)
            }
            val status = when (action) {
                "download" -> "Download complete"
                "use" -> "Active model updated"
                else -> "Model removed"
            }
            gtk_label_set_text(statusLabel?.reinterpret(), "$status: $modelId")
        }.onFailure { error ->
            gtk_label_set_text(statusLabel?.reinterpret(), error.message ?: "Model action failed")
        }
    }

    private fun modelSummary(model: LocalModelDescriptor, isInstalled: Boolean): String {
        val size = if (model.sizeInMb >= 1000) {
            String.format("%.1f GB", model.sizeInMb / 1000.0)
        } else {
            "${model.sizeInMb} MB"
        }
        val state = when {
            isInstalled && model.id.value == selectedModel -> "Installed · Active"
            isInstalled -> "Installed"
            model.availability == ModelAvailability.REQUIRES_SETUP -> "Requires manual setup"
            model.availability == ModelAvailability.COMING_SOON -> "Coming soon"
            else -> "Available"
        }
        return "$size · $state · ${model.description}"
    }
}
