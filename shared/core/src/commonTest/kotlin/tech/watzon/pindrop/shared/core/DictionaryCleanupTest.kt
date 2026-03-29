package tech.watzon.pindrop.shared.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DictionaryCleanupTest {

    // --- applyCustomReplacements ---

    @Test
    fun applyCustomReplacementsReplacesConfiguredWords() {
        val replacements = mapOf("hello" to "Hi", "world" to "Earth")
        val result = DictionaryCleanup.applyCustomReplacements(
            text = "hello world",
            customWords = replacements,
            caseInsensitive = false,
        )
        assertEquals("Hi Earth", result)
    }

    @Test
    fun applyCustomReplacementsIsCaseInsensitiveWhenConfigured() {
        val replacements = mapOf("hello" to "Hi")
        val result = DictionaryCleanup.applyCustomReplacements(
            text = "Hello HELLO HeLLo",
            customWords = replacements,
            caseInsensitive = true,
        )
        assertEquals("Hi Hi Hi", result)
    }

    @Test
    fun automaticLearningAddsNewWordsToDictionary() {
        val existing = mapOf("foo" to "bar")
        val result = DictionaryCleanup.learnFromTranscript(
            originalText = "I said teh quick brown fox",
            enhancedText = "I said the quick brown fox",
            existingDictionary = existing,
        )
        assertEquals("bar", result["foo"])
        assertEquals("the", result["teh"])
    }

    @Test
    fun cleanupPreservesOriginalTextStructureAndLength() {
        val text = "Hello,  world!\nNew line."
        val result = DictionaryCleanup.applyCustomReplacements(
            text = text,
            customWords = emptyMap(),
            caseInsensitive = false,
        )
        assertEquals(text, result)
    }

    // --- validateDictionaryEntry ---

    @Test
    fun validateDictionaryEntryRejectsEmptyWord() {
        val result = DictionaryCleanup.validateDictionaryEntry(
            word = "",
            replacement = "something",
        )
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Invalid)
    }

    @Test
    fun validateDictionaryEntryRejectsEmptyReplacement() {
        val result = DictionaryCleanup.validateDictionaryEntry(
            word = "test",
            replacement = "",
        )
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Invalid)
    }

    @Test
    fun validateDictionaryEntryAcceptsValidEntry() {
        val result = DictionaryCleanup.validateDictionaryEntry(
            word = "teh",
            replacement = "the",
        )
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Valid)
    }

    @Test
    fun validateDictionaryEntryRejectsCyclicReplacement() {
        val result = DictionaryCleanup.validateDictionaryEntry(
            word = "hello",
            replacement = "hello",
        )
        assertTrue(result is tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult.Invalid)
    }
}
