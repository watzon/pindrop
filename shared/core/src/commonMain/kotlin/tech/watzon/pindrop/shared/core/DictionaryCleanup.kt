package tech.watzon.pindrop.shared.core

import tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult

/**
 * Shared dictionary cleanup business logic.
 *
 * Provides pure functions for applying custom word replacements,
 * auto-learning corrections from enhancement diffs, and validating
 * dictionary entries. Consumed by all desktop clients (macOS, Linux,
 * future Windows).
 */
object DictionaryCleanup {

    /**
     * Apply custom word replacements to transcript text.
     *
     * @param text The original transcript text.
     * @param customWords Map of word-to-replacement pairs.
     * @param caseInsensitive If true, matching ignores case differences.
     * @return Text with replacements applied.
     */
    fun applyCustomReplacements(
        text: String,
        customWords: Map<String, String>,
        caseInsensitive: Boolean = false,
    ): String {
        if (customWords.isEmpty()) return text

        var result = text
        for ((word, replacement) in customWords) {
            result = if (caseInsensitive) {
                result.replace(word, replacement, ignoreCase = true)
            } else {
                result.replace(word, replacement)
            }
        }
        return result
    }

    /**
     * Auto-learn corrections from an enhancement diff.
     *
     * Compares original and enhanced text word-by-word. When a single-word
     * original differs from its enhanced counterpart, the pair is added to
     * the dictionary for future automatic correction.
     *
     * @param originalText The raw transcript text.
     * @param enhancedText The AI-enhanced text (null if enhancement was skipped).
     * @param existingDictionary Current dictionary entries to preserve.
     * @return Updated dictionary including any newly learned corrections.
     */
    fun learnFromTranscript(
        originalText: String,
        enhancedText: String?,
        existingDictionary: Map<String, String>,
    ): Map<String, String> {
        if (enhancedText == null) return existingDictionary

        val result = existingDictionary.toMutableMap()
        val originalWords = originalText.split(Regex("\\s+"))
        val enhancedWords = enhancedText.split(Regex("\\s+"))

        val pairs = minOf(originalWords.size, enhancedWords.size)
        for (i in 0 until pairs) {
            val original = originalWords[i].trim()
            val enhanced = enhancedWords[i].trim()
            if (original.isNotEmpty() && enhanced.isNotEmpty() &&
                original != enhanced &&
                original.all { it.isLetter() } &&
                enhanced.all { it.isLetter() }
            ) {
                // Don't overwrite existing entries
                if (!result.containsKey(original)) {
                    result[original] = enhanced
                }
            }
        }
        return result
    }

    /**
     * Validate a dictionary entry.
     *
     * @param word The original word to be replaced.
     * @param replacement The replacement text.
     * @return Valid if the entry is acceptable, Invalid with a reason otherwise.
     */
    fun validateDictionaryEntry(
        word: String,
        replacement: String,
    ): SettingsValidationResult {
        return when {
            word.isBlank() -> SettingsValidationResult.Invalid(
                "Word must not be empty."
            )
            replacement.isBlank() -> SettingsValidationResult.Invalid(
                "Replacement must not be empty."
            )
            word == replacement -> SettingsValidationResult.Invalid(
                "Word and replacement must differ (cyclic replacement)."
            )
            else -> SettingsValidationResult.Valid
        }
    }
}
