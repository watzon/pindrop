package tech.watzon.pindrop.shared.uisettings

enum class AIProviderCore {
    OPENAI,
    GOOGLE,
    ANTHROPIC,
    OPENROUTER,
    CUSTOM,
}

enum class CustomProviderTypeCore {
    CUSTOM,
    OLLAMA,
    LM_STUDIO,
}

enum class PromptTypeCore {
    TRANSCRIPTION,
    NOTES,
}

data class AIProviderDefinition(
    val id: AIProviderCore,
    val displayName: String,
    val iconKey: String,
    val defaultEndpoint: String,
    val apiKeyPlaceholder: String,
    val isImplemented: Boolean,
)

data class CustomProviderDefinition(
    val id: CustomProviderTypeCore,
    val displayName: String,
    val iconKey: String,
    val storageKey: String,
    val requiresApiKey: Boolean,
    val supportsModelListing: Boolean,
    val defaultEndpoint: String,
    val defaultModelsEndpoint: String?,
    val apiKeyPlaceholder: String,
    val endpointPlaceholder: String,
    val modelPlaceholder: String,
)

data class AIModelSnapshot(
    val id: String,
    val name: String,
    val summary: String?,
)

data class PromptPresetSnapshot(
    val id: String,
    val name: String,
    val prompt: String,
    val isBuiltIn: Boolean,
    val sortOrder: Int,
)

data class AIProviderSelection(
    val provider: AIProviderCore,
    val customProvider: CustomProviderTypeCore,
)

data class AIEnhancementDraft(
    val selectedProvider: AIProviderCore,
    val selectedCustomProvider: CustomProviderTypeCore,
    val apiKey: String,
    val selectedModel: String,
    val customModel: String,
    val enhancementPrompt: String,
    val noteEnhancementPrompt: String,
    val selectedPromptType: PromptTypeCore,
    val selectedPresetId: String?,
    val customEndpointText: String,
    val availableModels: List<AIModelSnapshot>,
    val modelErrorMessage: String?,
    val isLoadingModels: Boolean,
    val aiEnhancementEnabled: Boolean,
)

data class AIEnhancementViewState(
    val canSave: Boolean,
    val isApiKeyOptional: Boolean,
    val currentApiKeyPlaceholder: String,
    val apiKeyHelpText: String?,
    val shouldShowCustomProviderPicker: Boolean,
    val shouldShowModelPicker: Boolean,
    val shouldShowCustomModelField: Boolean,
    val shouldShowCustomEndpointField: Boolean,
    val emptyModelsMessageKey: String,
    val selectedPresetId: String?,
    val validatedPresetId: String?,
    val isBuiltInPresetSelected: Boolean,
    val isSelectedPromptReadOnly: Boolean,
    val selectedPromptCharacterCount: Int,
)

data class PromptPresetManagementState(
    val builtInPresetIds: List<String>,
    val customPresetIds: List<String>,
    val canCreatePreset: Boolean,
    val canSaveEditingPreset: Boolean,
)

object AISettingsCatalog {
    private val providerDefinitions = listOf(
        AIProviderDefinition(
            id = AIProviderCore.OPENAI,
            displayName = "OpenAI",
            iconKey = "openai",
            defaultEndpoint = "https://api.openai.com/v1/chat/completions",
            apiKeyPlaceholder = "sk-...",
            isImplemented = true,
        ),
        AIProviderDefinition(
            id = AIProviderCore.GOOGLE,
            displayName = "Google",
            iconKey = "google",
            defaultEndpoint = "https://generativelanguage.googleapis.com/v1beta",
            apiKeyPlaceholder = "AIza...",
            isImplemented = false,
        ),
        AIProviderDefinition(
            id = AIProviderCore.ANTHROPIC,
            displayName = "Anthropic",
            iconKey = "anthropic",
            defaultEndpoint = "https://api.anthropic.com/v1/messages",
            apiKeyPlaceholder = "sk-ant-...",
            isImplemented = true,
        ),
        AIProviderDefinition(
            id = AIProviderCore.OPENROUTER,
            displayName = "OpenRouter",
            iconKey = "openrouter",
            defaultEndpoint = "https://openrouter.ai/api/v1/chat/completions",
            apiKeyPlaceholder = "sk-or-...",
            isImplemented = true,
        ),
        AIProviderDefinition(
            id = AIProviderCore.CUSTOM,
            displayName = "Custom/Local",
            iconKey = "server",
            defaultEndpoint = "",
            apiKeyPlaceholder = "Enter API key",
            isImplemented = true,
        ),
    )

    private val customProviderDefinitions = listOf(
        CustomProviderDefinition(
            id = CustomProviderTypeCore.CUSTOM,
            displayName = "Custom",
            iconKey = "server",
            storageKey = "custom",
            requiresApiKey = true,
            supportsModelListing = false,
            defaultEndpoint = "",
            defaultModelsEndpoint = null,
            apiKeyPlaceholder = "Enter API key",
            endpointPlaceholder = "https://your-api.com/v1/chat/completions",
            modelPlaceholder = "e.g., gpt-4o",
        ),
        CustomProviderDefinition(
            id = CustomProviderTypeCore.OLLAMA,
            displayName = "Ollama",
            iconKey = "hardDrive",
            storageKey = "ollama",
            requiresApiKey = false,
            supportsModelListing = true,
            defaultEndpoint = "http://localhost:11434/v1/chat/completions",
            defaultModelsEndpoint = "http://localhost:11434/v1/models",
            apiKeyPlaceholder = "Optional (usually not needed)",
            endpointPlaceholder = "http://localhost:11434/v1/chat/completions",
            modelPlaceholder = "e.g., llama3.2",
        ),
        CustomProviderDefinition(
            id = CustomProviderTypeCore.LM_STUDIO,
            displayName = "LM Studio",
            iconKey = "hardDrive",
            storageKey = "lm-studio",
            requiresApiKey = false,
            supportsModelListing = true,
            defaultEndpoint = "http://localhost:1234/v1/chat/completions",
            defaultModelsEndpoint = "http://localhost:1234/v1/models",
            apiKeyPlaceholder = "Optional unless auth is enabled",
            endpointPlaceholder = "http://localhost:1234/v1/chat/completions",
            modelPlaceholder = "e.g., local-model",
        ),
    )

    fun providers(): List<AIProviderDefinition> = providerDefinitions

    fun provider(id: AIProviderCore): AIProviderDefinition {
        return providerDefinitions.first { it.id == id }
    }

    fun customProviders(): List<CustomProviderDefinition> = customProviderDefinitions

    fun customProvider(id: CustomProviderTypeCore): CustomProviderDefinition {
        return customProviderDefinitions.first { it.id == id }
    }

    fun defaultModelIdentifier(provider: AIProviderCore): String = when (provider) {
        AIProviderCore.OPENROUTER -> "openai/gpt-4o-mini"
        AIProviderCore.OPENAI -> "gpt-4o-mini"
        AIProviderCore.ANTHROPIC -> "claude-haiku-4-5"
        else -> "gpt-4o-mini"
    }

    fun inferProviderSelection(
        endpoint: String?,
        fallbackCustomProvider: CustomProviderTypeCore,
        currentProviderIsCustom: Boolean,
    ): AIProviderSelection {
        val resolvedEndpoint = endpoint?.trim().orEmpty()
        return when {
            resolvedEndpoint.contains("openai.com", ignoreCase = true) ->
                AIProviderSelection(AIProviderCore.OPENAI, fallbackCustomProvider)
            resolvedEndpoint.contains("anthropic.com", ignoreCase = true) ->
                AIProviderSelection(AIProviderCore.ANTHROPIC, fallbackCustomProvider)
            resolvedEndpoint.contains("googleapis.com", ignoreCase = true) ->
                AIProviderSelection(AIProviderCore.GOOGLE, fallbackCustomProvider)
            resolvedEndpoint.contains("openrouter.ai", ignoreCase = true) ->
                AIProviderSelection(AIProviderCore.OPENROUTER, fallbackCustomProvider)
            resolvedEndpoint.isNotEmpty() ->
                AIProviderSelection(AIProviderCore.CUSTOM, inferCustomProvider(endpoint = resolvedEndpoint, fallback = fallbackCustomProvider))
            currentProviderIsCustom ->
                AIProviderSelection(AIProviderCore.CUSTOM, fallbackCustomProvider)
            else ->
                AIProviderSelection(AIProviderCore.OPENAI, fallbackCustomProvider)
        }
    }

    fun inferCustomProvider(
        endpoint: String?,
        fallback: CustomProviderTypeCore,
    ): CustomProviderTypeCore {
        val resolvedEndpoint = endpoint?.trim().orEmpty()
        return when {
            resolvedEndpoint.contains("localhost:11434", ignoreCase = true) -> CustomProviderTypeCore.OLLAMA
            resolvedEndpoint.contains("localhost:1234", ignoreCase = true) -> CustomProviderTypeCore.LM_STUDIO
            else -> fallback
        }
    }
}

object AIEnhancementPresenter {
    fun present(
        draft: AIEnhancementDraft,
        presets: List<PromptPresetSnapshot>,
    ): AIEnhancementViewState {
        val provider = AISettingsCatalog.provider(draft.selectedProvider)
        val customProvider = AISettingsCatalog.customProvider(draft.selectedCustomProvider)
        val validatedPresetId = draft.selectedPresetId?.takeIf { selectedId ->
            presets.any { it.id == selectedId }
        }
        val selectedPreset = validatedPresetId?.let { selectedId ->
            presets.firstOrNull { it.id == selectedId }
        }
        val selectedPromptCharacterCount = when (draft.selectedPromptType) {
            PromptTypeCore.TRANSCRIPTION -> draft.enhancementPrompt.length
            PromptTypeCore.NOTES -> draft.noteEnhancementPrompt.length
        }
        val isBuiltInPresetSelected = selectedPreset?.isBuiltIn == true
        val isSelectedPromptReadOnly =
            draft.selectedPromptType == PromptTypeCore.TRANSCRIPTION && isBuiltInPresetSelected
        val canSave = when {
            !provider.isImplemented -> false
            requiresApiKey(draft.selectedProvider, draft.selectedCustomProvider) &&
                draft.apiKey.isBlank() -> false
            draft.selectedProvider == AIProviderCore.CUSTOM &&
                draft.customEndpointText.isBlank() -> false
            draft.selectedProvider == AIProviderCore.CUSTOM &&
                selectedModelText(draft).isBlank() -> false
            draft.selectedProvider in setOf(AIProviderCore.OPENROUTER, AIProviderCore.OPENAI, AIProviderCore.ANTHROPIC) &&
                draft.selectedModel.isBlank() -> false
            else -> true
        }

        return AIEnhancementViewState(
            canSave = canSave,
            isApiKeyOptional = draft.selectedProvider == AIProviderCore.CUSTOM && !customProvider.requiresApiKey,
            currentApiKeyPlaceholder = if (draft.selectedProvider == AIProviderCore.CUSTOM) {
                customProvider.apiKeyPlaceholder
            } else {
                provider.apiKeyPlaceholder
            },
            apiKeyHelpText = when {
                draft.selectedProvider != AIProviderCore.CUSTOM -> null
                draft.selectedCustomProvider == CustomProviderTypeCore.OLLAMA ->
                    "Ollama usually does not require authentication for local requests."
                draft.selectedCustomProvider == CustomProviderTypeCore.LM_STUDIO ->
                    "LM Studio only needs a token if local server authentication is enabled."
                else -> null
            },
            shouldShowCustomProviderPicker = draft.selectedProvider == AIProviderCore.CUSTOM,
            shouldShowModelPicker = shouldShowModelPicker(draft),
            shouldShowCustomModelField = draft.selectedProvider == AIProviderCore.CUSTOM && !customProvider.supportsModelListing,
            shouldShowCustomEndpointField = draft.selectedProvider == AIProviderCore.CUSTOM,
            emptyModelsMessageKey = emptyModelsMessageKey(draft),
            selectedPresetId = draft.selectedPresetId,
            validatedPresetId = validatedPresetId,
            isBuiltInPresetSelected = isBuiltInPresetSelected,
            isSelectedPromptReadOnly = isSelectedPromptReadOnly,
            selectedPromptCharacterCount = selectedPromptCharacterCount,
        )
    }

    private fun shouldShowModelPicker(draft: AIEnhancementDraft): Boolean {
        val customProvider = AISettingsCatalog.customProvider(draft.selectedCustomProvider)
        return draft.selectedProvider in setOf(
            AIProviderCore.OPENROUTER,
            AIProviderCore.OPENAI,
            AIProviderCore.ANTHROPIC,
        ) || (draft.selectedProvider == AIProviderCore.CUSTOM && customProvider.supportsModelListing)
    }

    private fun emptyModelsMessageKey(draft: AIEnhancementDraft): String = when {
        draft.isLoadingModels -> "Loading models..."
        draft.selectedProvider == AIProviderCore.OPENAI && draft.apiKey.isBlank() ->
            "Enter an OpenAI API key to load models."
        !draft.modelErrorMessage.isNullOrBlank() ->
            "Unable to load models. Try refresh."
        draft.selectedProvider == AIProviderCore.CUSTOM &&
            AISettingsCatalog.customProvider(draft.selectedCustomProvider).supportsModelListing ->
            "No models available. Try Refresh or enter a model ID manually."
        else -> "No models available."
    }

    private fun requiresApiKey(
        provider: AIProviderCore,
        customProvider: CustomProviderTypeCore,
    ): Boolean {
        return when (provider) {
            AIProviderCore.CUSTOM -> AISettingsCatalog.customProvider(customProvider).requiresApiKey
            AIProviderCore.OPENAI, AIProviderCore.OPENROUTER, AIProviderCore.ANTHROPIC, AIProviderCore.GOOGLE -> true
        }
    }

    private fun selectedModelText(draft: AIEnhancementDraft): String {
        val customProvider = AISettingsCatalog.customProvider(draft.selectedCustomProvider)
        return if (customProvider.supportsModelListing) draft.selectedModel else draft.customModel
    }
}

object PromptPresetPresenter {
    fun present(
        presets: List<PromptPresetSnapshot>,
        newName: String,
        newPrompt: String,
        editingPresetId: String?,
        editName: String,
        editPrompt: String,
    ): PromptPresetManagementState {
        val sortedPresets = presets.sortedBy(PromptPresetSnapshot::sortOrder)
        return PromptPresetManagementState(
            builtInPresetIds = sortedPresets.filter(PromptPresetSnapshot::isBuiltIn).map(PromptPresetSnapshot::id),
            customPresetIds = sortedPresets.filterNot(PromptPresetSnapshot::isBuiltIn).map(PromptPresetSnapshot::id),
            canCreatePreset = newName.isNotBlank() && newPrompt.isNotBlank(),
            canSaveEditingPreset = editingPresetId != null && editName.isNotBlank() && editPrompt.isNotBlank(),
        )
    }
}
