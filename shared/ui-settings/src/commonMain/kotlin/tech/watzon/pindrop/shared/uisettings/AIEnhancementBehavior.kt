package tech.watzon.pindrop.shared.uisettings

import tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult

/**
 * Shared AI enhancement behavior rules.
 *
 * Provides pure functions for determining whether enhancement should run,
 * constructing enhancement requests, handling fallback behavior on failure,
 * and validating enhancement prompts. Consumed by all desktop clients.
 */
object AIEnhancementBehavior {

    /**
     * Error types that can occur during enhancement.
     */
    enum class ErrorType {
        API_ERROR,
        INVALID_ENDPOINT,
        INVALID_RESPONSE,
        TIMEOUT,
        NETWORK_ERROR,
    }

    /**
     * Structured error information for enhancement failures.
     */
    data class EnhancementError(
        val type: ErrorType,
        val message: String,
    )

    /**
     * A structured enhancement request ready for API submission.
     */
    data class EnhancementRequest(
        val text: String,
        val systemPrompt: String,
        val model: String,
        val provider: AIProviderCore,
    )

    /**
     * Result of an enhancement attempt.
     */
    data class EnhancementResult(
        val text: String,
        val wasEnhanced: Boolean,
        val error: EnhancementError?,
    )

    /** Maximum allowed prompt length. */
    private const val MAX_PROMPT_LENGTH = 10_000

    /**
     * Determine whether enhancement should be attempted.
     *
     * @param enhancementEnabled User preference for AI enhancement.
     * @param providerConfigured Whether an AI provider is configured.
     * @param hasApiKey Whether an API key is available.
     * @return True if enhancement should proceed.
     */
    fun shouldAttemptEnhancement(
        enhancementEnabled: Boolean,
        providerConfigured: Boolean,
        hasApiKey: Boolean,
    ): Boolean {
        return enhancementEnabled && providerConfigured && hasApiKey
    }

    /**
     * Construct a structured enhancement request.
     *
     * @param text The transcript text to enhance.
     * @param systemPrompt The system prompt for the AI model.
     * @param model The model identifier.
     * @param provider The AI provider to use.
     * @return A complete [EnhancementRequest].
     */
    fun buildEnhancementRequest(
        text: String,
        systemPrompt: String,
        model: String,
        provider: AIProviderCore,
    ): EnhancementRequest {
        return EnhancementRequest(
            text = text,
            systemPrompt = systemPrompt,
            model = model,
            provider = provider,
        )
    }

    /**
     * Handle enhancement failure by returning the original text.
     *
     * @param originalText The un-enhanced text to return.
     * @param error The error that occurred.
     * @return An [EnhancementResult] with the original text and error info.
     */
    fun fallbackBehavior(
        originalText: String,
        error: EnhancementError,
    ): EnhancementResult {
        return EnhancementResult(
            text = originalText,
            wasEnhanced = false,
            error = error,
        )
    }

    /**
     * Validate an enhancement prompt.
     *
     * @param prompt The prompt text to validate.
     * @return Valid if the prompt is acceptable, Invalid with a reason otherwise.
     */
    fun validatePrompt(prompt: String): SettingsValidationResult {
        return when {
            prompt.isBlank() -> SettingsValidationResult.Invalid(
                "Enhancement prompt must not be empty."
            )
            prompt.length > MAX_PROMPT_LENGTH -> SettingsValidationResult.Invalid(
                "Enhancement prompt exceeds maximum length of $MAX_PROMPT_LENGTH characters."
            )
            else -> SettingsValidationResult.Valid
        }
    }
}
