package tech.watzon.pindrop.shared.schemasettings

/**
 * Validation logic for settings values.
 *
 * Returns structured results ([SettingsValidationResult]) that can be
 * consumed by Swift for user-facing error messages.
 */
sealed class SettingsValidationResult {
    data object Valid : SettingsValidationResult()
    data class Invalid(val reason: String) : SettingsValidationResult()
}

object SettingsValidation {

    private val validOutputModes = OutputMode.entries.map { it.rawValue }.toSet()
    private val validThemeModes = ThemeMode.entries.map { it.rawValue }.toSet()
    private val validFloatingIndicatorTypes = FloatingIndicatorType.entries.map { it.rawValue }.toSet()
    private val validLanguages = AppLanguage.entries.map { it.rawValue }.toSet()
    private val validAIProviders = AIProvider.entries.map { it.rawValue }.toSet()
    private val validCustomProviderTypes = CustomProviderType.entries.map { it.rawValue }.toSet()

    fun validateSetting(key: String, value: Any?): SettingsValidationResult {
        return when (key) {
            SettingsKeys.outputMode -> validateOutputMode(value as? String ?: "")
            SettingsKeys.themeMode -> validateThemeMode(value as? String ?: "")
            SettingsKeys.floatingIndicatorType -> validateFloatingIndicatorType(value as? String ?: "")
            SettingsKeys.selectedLanguage -> validateLanguage(value as? String ?: "")
            SettingsKeys.aiModel -> validateAIModel(value as? String ?: "")
            SettingsKeys.aiProvider -> validateAIProvider(value as? String ?: "")
            SettingsKeys.customLocalProviderType -> validateCustomProviderType(value as? String ?: "")
            SettingsKeys.contextCaptureTimeoutSeconds -> validateContextTimeout(
                (value as? Number)?.toDouble() ?: 0.0
            )
            SettingsKeys.pillFloatingIndicatorOffsetX,
            SettingsKeys.pillFloatingIndicatorOffsetY -> validateDouble(value)
            else -> SettingsValidationResult.Valid
        }
    }

    fun validateOutputMode(value: String): SettingsValidationResult {
        return if (value in validOutputModes) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid output mode '$value'. Must be one of: ${validOutputModes.joinToString()}"
            )
        }
    }

    fun validateThemeMode(value: String): SettingsValidationResult {
        return if (value in validThemeModes) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid theme mode '$value'. Must be one of: ${validThemeModes.joinToString()}"
            )
        }
    }

    fun validateFloatingIndicatorType(value: String): SettingsValidationResult {
        return if (value in validFloatingIndicatorTypes) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid floating indicator type '$value'. Must be one of: ${validFloatingIndicatorTypes.joinToString()}"
            )
        }
    }

    fun validateLanguage(value: String): SettingsValidationResult {
        return if (value in validLanguages) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid language '$value'. Must be a valid language code."
            )
        }
    }

    fun validateAIModel(value: String): SettingsValidationResult {
        return if (value.isNotBlank()) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid("AI model must not be blank.")
        }
    }

    fun validateAIProvider(value: String): SettingsValidationResult {
        return if (value in validAIProviders) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid AI provider '$value'. Must be one of: ${validAIProviders.joinToString()}"
            )
        }
    }

    fun validateCustomProviderType(value: String): SettingsValidationResult {
        return if (value in validCustomProviderTypes) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid(
                "Invalid custom provider type '$value'. Must be one of: ${validCustomProviderTypes.joinToString()}"
            )
        }
    }

    fun validateContextTimeout(value: Double): SettingsValidationResult {
        return when {
            value <= 0 -> SettingsValidationResult.Invalid("Context timeout must be greater than 0.")
            value > 30 -> SettingsValidationResult.Invalid("Context timeout must be at most 30 seconds.")
            else -> SettingsValidationResult.Valid
        }
    }

    private fun validateDouble(value: Any?): SettingsValidationResult {
        return if (value is Number) {
            SettingsValidationResult.Valid
        } else {
            SettingsValidationResult.Invalid("Expected a numeric value.")
        }
    }
}
