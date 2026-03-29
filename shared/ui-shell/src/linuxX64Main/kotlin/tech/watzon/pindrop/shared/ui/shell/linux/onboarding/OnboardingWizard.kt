@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.core.platform.SecretStorage
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uilocalization.SharedLocalization

/**
 * GTK onboarding wizard — a 7-step first-run experience.
 *
 * Uses GtkAssistant as the wizard container with one page per step.
 * On "apply" signal: writes `hasCompletedOnboarding = true` to
 * SettingsPersistence, saves settings, and closes the wizard.
 *
 * Steps (adapted from macOS onboarding):
 * 1. Welcome — informational
 * 2. Audio Check — soft PipeWire/PulseAudio probe
 * 3. Model Selection — pick default transcription model
 * 4. Model Download — placeholder for download progress
 * 5. Hotkey Setup — display hotkeys with Linux limitation notes
 * 6. AI Config — optional AI enhancement setup
 * 7. Ready — confirmation and summary
 *
 * Created on 2026-03-29.
 */
class OnboardingWizard(
    private val settings: SettingsPersistence,
    private val secrets: SecretStorage,
    private val parentWindow: CPointer<GtkWidget>?,
    private val locale: String
) {
    private val assistant: CPointer<GtkWidget>? = gtk_assistant_new()
    private val selfRef = StableRef.create(this)

    /** Callback invoked when the wizard completes (apply). */
    var onFinished: (() -> Unit)? = null

    /** The 7 steps. */
    private val steps: List<OnboardingStep> = listOf(
        WelcomeStep(locale),
        AudioCheckStep(locale),
        ModelSelectionStep(settings, locale),
        ModelDownloadStep(locale),
        HotkeySetupStep(settings, locale),
        AIConfigStep(settings, secrets, locale),
        ReadyStep(settings, locale),
    )

    init {
        setupAssistant()
    }

    /**
     * Configure the GtkAssistant: set size, modal, pages.
     */
    private fun setupAssistant() {
        // Window properties
        gtk_window_set_title(assistant?.reinterpret(), "Pindrop Setup")
        gtk_window_set_default_size(assistant?.reinterpret(), 600, 450)
        gtk_window_set_modal(assistant?.reinterpret(), 1)
        if (parentWindow != null) {
            gtk_window_set_transient_for(assistant?.reinterpret(), parentWindow?.reinterpret())
        }

        // Add each step as a page
        for ((index, step) in steps.withIndex()) {
            val content = step.createContent()
            if (content != null) {
                gtk_assistant_append_page(assistant?.reinterpret(), content)
                gtk_assistant_set_page_title(
                    assistant?.reinterpret(),
                    content,
                    step.title(locale)
                )

                // Page type: CONTENT for all pages except the last (CONFIRM)
                val pageType = if (index == steps.lastIndex) {
                    GTK_ASSISTANT_PAGE_CONFIRM
                } else {
                    GTK_ASSISTANT_PAGE_CONTENT
                }
                gtk_assistant_set_page_type(assistant?.reinterpret(), content, pageType)

                // All pages are complete by default (soft gates)
                gtk_assistant_set_page_complete(assistant?.reinterpret(), content, 1)
            }
        }

        // Connect "apply" signal for the final page
        g_signal_connect_data(
            assistant,
            "apply",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    val wizard = data.asStableRef<OnboardingWizard>().get()
                    wizard.handleApply()
                }
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u
        )

        // Connect "cancel" signal
        g_signal_connect_data(
            assistant,
            "cancel",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    val wizard = data.asStableRef<OnboardingWizard>().get()
                    wizard.handleCancel()
                }
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u
        )

        // Connect "close" signal
        g_signal_connect_data(
            assistant,
            "close",
            staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
                if (data != null) {
                    val wizard = data.asStableRef<OnboardingWizard>().get()
                    wizard.handleClose()
                }
            }.reinterpret(),
            selfRef.asCPointer(),
            null,
            0u
        )
    }

    /**
     * Show the onboarding wizard.
     */
    fun show() {
        gtk_window_present(assistant?.reinterpret())
    }

    /**
     * Handle the "apply" signal — wizard completed successfully.
     * Persist onboarding state and notify coordinator.
     */
    private fun handleApply() {
        // Call onComplete on all steps
        for (step in steps) {
            step.onComplete()
        }

        // Mark onboarding as completed
        settings.setBool(SettingsKeys.hasCompletedOnboarding, true)
        settings.save()

        // Notify coordinator
        onFinished?.invoke()

        // Close the wizard
        gtk_window_close(assistant?.reinterpret())
    }

    /**
     * Handle the "cancel" signal — user cancelled wizard.
     * Still allow the app to run (just don't mark onboarding complete).
     */
    private fun handleCancel() {
        // Don't mark onboarding complete — will show again on next launch
        gtk_window_close(assistant?.reinterpret())
    }

    /**
     * Handle the "close" signal.
     */
    private fun handleClose() {
        gtk_window_close(assistant?.reinterpret())
    }

    /**
     * Clean up resources.
     */
    fun destroy() {
        selfRef.dispose()
    }
}
