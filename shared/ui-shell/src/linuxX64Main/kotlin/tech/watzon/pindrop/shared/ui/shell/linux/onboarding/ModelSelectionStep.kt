@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * Model selection step — let the user pick a default transcription model.
 *
 * Shows a list of available Whisper models with size/speed/accuracy info.
 * Stores the selected model in SettingsPersistence.
 *
 * Adapted from macOS ModelSelectionStepView.swift.
 *
 * Created on 2026-03-29.
 */
class ModelSelectionStep(
    private val settings: SettingsPersistence,
    private val locale: String
) : OnboardingStep {

    /** Available model definitions. */
    private val models = listOf(
        ModelOption("openai_whisper-tiny", "Tiny", 75),
        ModelOption("openai_whisper-tiny.en", "Tiny (English)", 75),
        ModelOption("openai_whisper-base", "Base", 145),
        ModelOption("openai_whisper-base.en", "Base (English)", 145),
        ModelOption("openai_whisper-small", "Small", 488),
        ModelOption("openai_whisper-small.en", "Small (English)", 488),
        ModelOption("openai_whisper-medium", "Medium", 1519),
        ModelOption("openai_whisper-medium.en", "Medium (English)", 1519),
    )

    /** Currently selected model name. */
    private var selectedModel: String = settings.getString(SettingsKeys.selectedModel)
        ?: SettingsDefaults.selectedModel

    /** Map from button pointer to model ID for callback routing. */
    private val buttonModelMap = mutableMapOf<CPointer<*>?, String>()

    /** StableRef for passing this step to signal callbacks. */
    private val selfRef = StableRef.create(this)

    override fun title(locale: String): String =
        SharedLocalization.getString("Choose a Model", this.locale)

    override fun createContent(): CPointer<GtkWidget>? {
        val outerBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
        gtk_widget_set_margin_start(outerBox, 40)
        gtk_widget_set_margin_end(outerBox, 40)
        gtk_widget_set_margin_top(outerBox, 24)

        // Description
        val desc = gtk_label_new(
            SharedLocalization.getString(
                "Smaller models are faster but less accurate.\nStart with Base for the best balance.",
                locale
            )
        )
        gtk_label_set_wrap(desc?.reinterpret(), 1)
        gtk_widget_add_css_class(desc, "body")
        gtk_widget_set_halign(desc, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(desc, "dim-label")
        gtk_box_append(outerBox?.reinterpret(), desc)

        // Model list with radio buttons
        val listBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
        gtk_widget_add_css_class(listBox, "boxed-list-separate")
        gtk_widget_set_margin_top(listBox, 12)

        var groupOwner: CPointer<GtkCheckButton>? = null

        for (model in models) {
            val row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)
            gtk_widget_set_margin_start(row, 12)
            gtk_widget_set_margin_end(row, 12)
            gtk_widget_set_margin_top(row, 8)
            gtk_widget_set_margin_bottom(row, 8)

            // Radio button
            val radio = gtk_check_button_new()
            if (groupOwner == null) {
                groupOwner = radio?.reinterpret()
            } else {
                gtk_check_button_set_group(radio?.reinterpret(), groupOwner)
            }

            // Select if matches current
            if (model.id == selectedModel) {
                gtk_check_button_set_active(radio?.reinterpret(), 1)
            }

            // Track which button maps to which model
            buttonModelMap[radio] = model.id

            // Connect toggled signal
            g_signal_connect_data(
                radio,
                "toggled",
                staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                    if (data != null) {
                        val step = data.asStableRef<ModelSelectionStep>().get()
                        step.handleToggle()
                    }
                }.reinterpret(),
                selfRef.asCPointer(),
                null,
                0u
            )

            // Info column
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

            // Recommended badge for base model
            if (model.id == "openai_whisper-base") {
                val badge = gtk_label_new(
                    SharedLocalization.getString("Recommended", locale)
                )
                gtk_widget_add_css_class(badge, "tag")
                gtk_widget_add_css_class(badge, "suggested-action")
                gtk_widget_set_valign(badge, GTK_ALIGN_CENTER)
                gtk_box_append(row?.reinterpret(), badge)
            }

            gtk_box_append(listBox?.reinterpret(), row)
        }

        gtk_box_append(outerBox?.reinterpret(), listBox)
        return outerBox
    }

    /** Called from the toggled signal — find which radio is now active. */
    private fun handleToggle() {
        for ((buttonPtr, modelId) in buttonModelMap) {
            val btn = buttonPtr?.reinterpret<GtkCheckButton>()
            if (btn != null && gtk_check_button_get_active(btn) == 1) {
                selectedModel = modelId
                break
            }
        }
    }

    override fun onComplete() {
        settings.setString(SettingsKeys.selectedModel, selectedModel)
    }

    private fun formatModelDetail(model: ModelOption): String {
        val sizeStr = if (model.sizeMB >= 1000) {
            String.format("%.1f GB", model.sizeMB / 1000.0)
        } else {
            "${model.sizeMB} MB"
        }
        val speedStr = when {
            model.sizeMB < 100 -> SharedLocalization.getString("Very Fast", locale)
            model.sizeMB < 300 -> SharedLocalization.getString("Fast", locale)
            model.sizeMB < 600 -> SharedLocalization.getString("Medium", locale)
            else -> SharedLocalization.getString("Slower", locale)
        }
        return "$sizeStr · $speedStr"
    }

    private data class ModelOption(
        val id: String,
        val displayName: String,
        val sizeMB: Int,
    )
}
