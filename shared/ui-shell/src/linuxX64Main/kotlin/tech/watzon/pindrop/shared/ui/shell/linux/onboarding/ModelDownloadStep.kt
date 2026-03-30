@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.ui.shell.linux.models.LinuxModelController
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

class ModelDownloadStep(
    private val settings: SettingsPersistence,
    private val locale: String,
) : OnboardingStep {
    private val modelController = LinuxModelController(settings)
    private val selfRef = StableRef.create(this)
    private var progressBar: CPointer<GtkProgressBar>? = null
    private var statusLabel: CPointer<GtkWidget>? = null

    override fun title(locale: String): String = SharedLocalization.getString("Download Model", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16)
        gtk_widget_set_margin_start(box, 40)
        gtk_widget_set_margin_end(box, 40)
        gtk_widget_set_margin_top(box, 24)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)

        val heading = gtk_label_new(SharedLocalization.getString("Model Download", locale))
        gtk_widget_add_css_class(heading, "title-3")
        gtk_widget_set_halign(heading, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), heading)

        statusLabel = gtk_label_new(
            SharedLocalization.getString(
                "Download the selected model now so Linux dictation is ready before you finish setup.",
                locale,
            ),
        )
        gtk_label_set_wrap(statusLabel?.reinterpret(), 1)
        gtk_widget_set_halign(statusLabel, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(statusLabel, "dim-label")
        gtk_box_append(box?.reinterpret(), statusLabel)

        progressBar = gtk_progress_bar_new()?.reinterpret()
        gtk_progress_bar_set_fraction(progressBar, 0.0)
        gtk_widget_set_margin_top(progressBar, 8)
        gtk_widget_set_margin_bottom(progressBar, 8)
        gtk_box_append(box?.reinterpret(), progressBar?.reinterpret())

        val actionButton = gtk_button_new_with_label(SharedLocalization.getString("Download", locale))
        gtk_widget_add_css_class(actionButton, "suggested-action")
        gtk_widget_set_halign(actionButton, GTK_ALIGN_CENTER)
        g_signal_connect_data(
            actionButton,
            "clicked",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                data?.asStableRef<ModelDownloadStep>()?.get()?.downloadSelectedModel()
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u,
        )
        gtk_box_append(box?.reinterpret(), actionButton)

        val info = gtk_label_new(
            SharedLocalization.getString(
                "Model downloads are typically 75 MB to 1.5 GB depending on your selection.",
                locale,
            ),
        )
        gtk_label_set_wrap(info?.reinterpret(), 1)
        gtk_widget_add_css_class(info, "caption")
        gtk_widget_add_css_class(info, "dim-label")
        gtk_widget_set_halign(info, GTK_ALIGN_CENTER)
        gtk_box_append(box?.reinterpret(), info)

        return box
    }

    private fun downloadSelectedModel() {
        val selectedModel = TranscriptionModelId(
            settings.getString(SettingsKeys.selectedModel) ?: modelController.selectedModelId.value,
        )
        runCatching {
            modelController.install(selectedModel) { progress, message ->
                gtk_progress_bar_set_fraction(progressBar, progress)
                gtk_label_set_text(
                    statusLabel?.reinterpret(),
                    message ?: "Downloading ${selectedModel.value}",
                )
            }
        }.onSuccess {
            gtk_progress_bar_set_fraction(progressBar, 1.0)
            gtk_label_set_text(
                statusLabel?.reinterpret(),
                SharedLocalization.getString("Install complete. This model is ready to use.", locale),
            )
        }.onFailure { error ->
            gtk_label_set_text(
                statusLabel?.reinterpret(),
                error.message ?: SharedLocalization.getString("Model install failed.", locale),
            )
        }
    }
}
