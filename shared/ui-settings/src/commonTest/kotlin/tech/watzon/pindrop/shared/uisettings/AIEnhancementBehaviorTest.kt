package tech.watzon.pindrop.shared.uisettings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AIEnhancementBehaviorTest {

    // --- shouldAttemptEnhancement ---

    @Test
    fun shouldAttemptEnhancementReturnsTrueWhenEnabledAndProviderConfigured() {
        val result = AIEnhancementBehavior.shouldAttemptEnhancement(
            enhancementEnabled = true,
            providerConfigured = true,
            hasApiKey = true,
        )
        assertTrue(result)
    }

    @Test
    fun shouldAttemptEnhancementReturnsFalseWhenDisabled() {
        val result = AIEnhancementBehavior.shouldAttemptEnhancement(
            enhancementEnabled = false,
            providerConfigured = true,
            hasApiKey = true,
        )
        assertFalse(result)
    }

    @Test
    fun shouldAttemptEnhancementReturnsFalseWhenNoApiKey() {
        val result = AIEnhancementBehavior.shouldAttemptEnhancement(
            enhancementEnabled = true,
            providerConfigured = true,
            hasApiKey = false,
        )
        assertFalse(result)
    }

    @Test
    fun shouldAttemptEnhancementReturnsFalseWhenProviderNotConfigured() {
        val result = AIEnhancementBehavior.shouldAttemptEnhancement(
            enhancementEnabled = true,
            providerConfigured = false,
            hasApiKey = true,
        )
        assertFalse(result)
    }

    // --- buildEnhancementRequest ---

    @Test
    fun buildEnhancementRequestConstructsCorrectPrompt() {
        val request = AIEnhancementBehavior.buildEnhancementRequest(
            text = "Hello world",
            systemPrompt = "Enhance this",
            model = "gpt-4o-mini",
            provider = AIProviderCore.OPENAI,
        )
        assertEquals("Hello world", request.text)
        assertEquals("Enhance this", request.systemPrompt)
        assertEquals("gpt-4o-mini", request.model)
        assertEquals(AIProviderCore.OPENAI, request.provider)
    }

    // --- fallbackBehavior ---

    @Test
    fun fallbackBehaviorReturnsOriginalTextOnFailure() {
        val error = AIEnhancementBehavior.EnhancementError(
            type = AIEnhancementBehavior.ErrorType.API_ERROR,
            message = "Connection failed",
        )
        val result = AIEnhancementBehavior.fallbackBehavior(
            originalText = "Original text",
            error = error,
        )
        assertEquals("Original text", result.text)
        assertFalse(result.wasEnhanced)
        assertEquals(error, result.error)
    }

    // --- validatePrompt ---

    @Test
    fun validatePromptAcceptsNonEmptyPrompt() {
        val result = AIEnhancementBehavior.validatePrompt("Valid prompt text")
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Valid)
    }

    @Test
    fun validatePromptRejectsEmptyPrompt() {
        val result = AIEnhancementBehavior.validatePrompt("")
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Invalid)
    }

    @Test
    fun validatePromptRejectsExcessivelyLongPrompt() {
        val longPrompt = "x".repeat(10001)
        val result = AIEnhancementBehavior.validatePrompt(longPrompt)
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Invalid)
    }
}
