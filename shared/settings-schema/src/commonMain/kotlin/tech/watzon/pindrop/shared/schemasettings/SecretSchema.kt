package tech.watzon.pindrop.shared.schemasettings

/**
 * Schema definitions for secrets stored in the Keychain (macOS) or
 * equivalent secure storage on other platforms.
 *
 * Provider definitions match the Swift Keychain account naming patterns:
 * - "api-key-openai", "api-key-anthropic", etc.
 * - "api-endpoint", "api-endpoint-custom-ollama", etc.
 */
object SecretSchema {

    const val keychainServiceName: String = "com.pindrop.settings"

    data class ProviderSecretDefinition(
        val providerId: String,
        val needsApiKey: Boolean,
        val needsEndpoint: Boolean,
        val apiKeyAccount: String,
        val endpointAccount: String,
        val apiKeyOptional: Boolean = false,
    )

    data class CustomProviderSecretDefinition(
        val providerId: String,
        val storageKey: String,
        val needsApiKey: Boolean,
        val supportsModelListing: Boolean,
        val defaultEndpoint: String,
    )

    private val providerDefinitions = listOf(
        ProviderSecretDefinition(
            providerId = "openai",
            needsApiKey = true,
            needsEndpoint = false,
            apiKeyAccount = "api-key-openai",
            endpointAccount = "api-endpoint",
        ),
        ProviderSecretDefinition(
            providerId = "anthropic",
            needsApiKey = true,
            needsEndpoint = false,
            apiKeyAccount = "api-key-anthropic",
            endpointAccount = "api-endpoint",
        ),
        ProviderSecretDefinition(
            providerId = "google",
            needsApiKey = true,
            needsEndpoint = false,
            apiKeyAccount = "api-key-google",
            endpointAccount = "api-endpoint",
        ),
        ProviderSecretDefinition(
            providerId = "openrouter",
            needsApiKey = true,
            needsEndpoint = false,
            apiKeyAccount = "api-key-openrouter",
            endpointAccount = "api-endpoint",
        ),
        ProviderSecretDefinition(
            providerId = "custom",
            needsApiKey = true,
            needsEndpoint = true,
            apiKeyAccount = "api-key-custom",
            endpointAccount = "api-endpoint-custom-custom",
            apiKeyOptional = true,
        ),
    )

    private val customProviderDefinitions = listOf(
        CustomProviderSecretDefinition(
            providerId = "custom",
            storageKey = "custom",
            needsApiKey = true,
            supportsModelListing = false,
            defaultEndpoint = "",
        ),
        CustomProviderSecretDefinition(
            providerId = "ollama",
            storageKey = "ollama",
            needsApiKey = false,
            supportsModelListing = true,
            defaultEndpoint = "http://localhost:11434/v1/chat/completions",
        ),
        CustomProviderSecretDefinition(
            providerId = "lm-studio",
            storageKey = "lm-studio",
            needsApiKey = false,
            supportsModelListing = true,
            defaultEndpoint = "http://localhost:1234/v1/chat/completions",
        ),
    )

    fun providers(): List<ProviderSecretDefinition> = providerDefinitions

    fun customProviders(): List<CustomProviderSecretDefinition> = customProviderDefinitions

    fun apiKeyAccount(provider: String, customSubtype: String? = null): String {
        val customSub = customSubtype?.trim()?.lowercase()
        return if (customSub != null && customSub.isNotEmpty()) {
            "api-key-$provider-$customSub"
        } else {
            "api-key-$provider"
        }
    }

    fun endpointAccount(provider: String, customSubtype: String? = null): String {
        val customSub = customSubtype?.trim()?.lowercase()
        return if (customSub != null && customSub.isNotEmpty()) {
            "api-endpoint-custom-$customSub"
        } else {
            "api-endpoint"
        }
    }
}
