package tech.watzon.pindrop.shared.schemasettings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Tests for settings validation logic.
 */
class SettingsValidationTest {

    // -- Output mode validation ---------------------------------------------------

    @Test
    fun validateOutputModeAcceptsValidValues() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateOutputMode("clipboard"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateOutputMode("directInsert"))
    }

    @Test
    fun validateOutputModeRejectsInvalidValues() {
        val result = SettingsValidation.validateOutputMode("unknown")
        assertIs<SettingsValidationResult.Invalid>(result)
        assertTrue(result.reason.contains("unknown"))
    }

    // -- Theme mode validation ----------------------------------------------------

    @Test
    fun validateThemeModeAcceptsValidValues() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateThemeMode("system"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateThemeMode("light"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateThemeMode("dark"))
    }

    @Test
    fun validateThemeModeRejectsInvalidValues() {
        val result = SettingsValidation.validateThemeMode("neon")
        assertIs<SettingsValidationResult.Invalid>(result)
        assertTrue(result.reason.contains("neon"))
    }

    // -- Language validation ------------------------------------------------------

    @Test
    fun validateLanguageAcceptsValidValues() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateLanguage("auto"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateLanguage("en"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateLanguage("ja"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateLanguage("zh-Hans"))
    }

    @Test
    fun validateLanguageRejectsInvalidValues() {
        val result = SettingsValidation.validateLanguage("xx-unknown")
        assertIs<SettingsValidationResult.Invalid>(result)
    }

    // -- AI model validation ------------------------------------------------------

    @Test
    fun validateAIModelAcceptsNonBlank() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateAIModel("gpt-4o"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateAIModel("openai/gpt-4o-mini"))
    }

    @Test
    fun validateAIModelRejectsBlank() {
        val result = SettingsValidation.validateAIModel("")
        assertIs<SettingsValidationResult.Invalid>(result)
        assertTrue(result.reason.contains("blank"))
    }

    // -- Context timeout validation -----------------------------------------------

    @Test
    fun validateContextTimeoutAcceptsValidRange() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateContextTimeout(1.0))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateContextTimeout(15.0))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateContextTimeout(30.0))
    }

    @Test
    fun validateContextTimeoutRejectsZero() {
        val result = SettingsValidation.validateContextTimeout(0.0)
        assertIs<SettingsValidationResult.Invalid>(result)
        assertTrue(result.reason.contains("greater than 0"))
    }

    @Test
    fun validateContextTimeoutRejectsNegative() {
        val result = SettingsValidation.validateContextTimeout(-1.0)
        assertIs<SettingsValidationResult.Invalid>(result)
    }

    @Test
    fun validateContextTimeoutRejectsOverMax() {
        val result = SettingsValidation.validateContextTimeout(31.0)
        assertIs<SettingsValidationResult.Invalid>(result)
        assertTrue(result.reason.contains("30"))
    }

    // -- Generic validateSetting --------------------------------------------------

    @Test
    fun validateSettingRoutesToCorrectValidator() {
        val result1 = SettingsValidation.validateSetting(SettingsKeys.outputMode, "clipboard")
        assertIs<SettingsValidationResult.Valid>(result1)

        val result2 = SettingsValidation.validateSetting(SettingsKeys.themeMode, "system")
        assertIs<SettingsValidationResult.Valid>(result2)

        val result3 = SettingsValidation.validateSetting(SettingsKeys.selectedLanguage, "en")
        assertIs<SettingsValidationResult.Valid>(result3)

        val result4 = SettingsValidation.validateSetting(SettingsKeys.contextCaptureTimeoutSeconds, 5.0)
        assertIs<SettingsValidationResult.Valid>(result4)
    }

    @Test
    fun validateSettingReturnsValidForUnknownKey() {
        val result = SettingsValidation.validateSetting("someUnknownKey", "anyValue")
        assertIs<SettingsValidationResult.Valid>(result)
    }

    // -- Floating indicator type validation ----------------------------------------

    @Test
    fun validateFloatingIndicatorTypeAcceptsValidValues() {
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateFloatingIndicatorType("notch"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateFloatingIndicatorType("pill"))
        assertIs<SettingsValidationResult.Valid>(SettingsValidation.validateFloatingIndicatorType("bubble"))
    }

    @Test
    fun validateFloatingIndicatorTypeRejectsInvalidValues() {
        val result = SettingsValidation.validateFloatingIndicatorType("unknown")
        assertIs<SettingsValidationResult.Invalid>(result)
    }
}
