@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.onboarding

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*

/**
 * Interface for a single step in the onboarding wizard.
 *
 * Each step provides a GTK widget to display, a localized title,
 * and a completion check. Informational steps that don't gate progress
 * should always return `true` from [isComplete].
 *
 * Created on 2026-03-29.
 */
interface OnboardingStep {
    /** Localized title for the assistant page header. */
    fun title(locale: String): String

    /**
     * Build and return the GTK widget content for this step.
     * Called once when the wizard is constructed.
     * The returned widget is owned by the wizard.
     */
    fun createContent(): CPointer<GtkWidget>?

    /**
     * Whether this step's requirements are satisfied and the user
     * can proceed to the next step.
     * Informational steps should always return `true`.
     */
    fun isComplete(): Boolean = true

    /**
     * Called when the user completes this step (moves past it).
     * Steps can use this to persist selections.
     */
    fun onComplete() {}
}
