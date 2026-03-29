package tech.watzon.pindrop.shared.uisettings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AISettingsPresentationTest {
    @Test
    fun aiPresenterHandlesCustomProviderValidationAndFallbackMessages() {
        val state = AIEnhancementPresenter.present(
            draft = AIEnhancementDraft(
                selectedProvider = AIProviderCore.CUSTOM,
                selectedCustomProvider = CustomProviderTypeCore.OLLAMA,
                apiKey = "",
                selectedModel = "",
                customModel = "",
                enhancementPrompt = "Prompt",
                noteEnhancementPrompt = "Note prompt",
                selectedPromptType = PromptTypeCore.TRANSCRIPTION,
                selectedPresetId = null,
                customEndpointText = "http://localhost:11434/v1/chat/completions",
                availableModels = emptyList(),
                modelErrorMessage = null,
                isLoadingModels = false,
                aiEnhancementEnabled = true,
            ),
            presets = emptyList(),
        )

        assertFalse(state.canSave)
        assertTrue(state.isApiKeyOptional)
        assertTrue(state.shouldShowCustomProviderPicker)
        assertTrue(state.shouldShowModelPicker)
        assertEquals("No models available. Try Refresh or enter a model ID manually.", state.emptyModelsMessageKey)
    }

    @Test
    fun aiPresenterTreatsBuiltInTranscriptionPresetAsReadOnly() {
        val state = AIEnhancementPresenter.present(
            draft = AIEnhancementDraft(
                selectedProvider = AIProviderCore.OPENAI,
                selectedCustomProvider = CustomProviderTypeCore.CUSTOM,
                apiKey = "sk-test",
                selectedModel = "gpt-4o-mini",
                customModel = "",
                enhancementPrompt = "Prompt",
                noteEnhancementPrompt = "Note prompt",
                selectedPromptType = PromptTypeCore.TRANSCRIPTION,
                selectedPresetId = "builtin",
                customEndpointText = "",
                availableModels = emptyList(),
                modelErrorMessage = null,
                isLoadingModels = false,
                aiEnhancementEnabled = true,
            ),
            presets = listOf(
                PromptPresetSnapshot(
                    id = "builtin",
                    name = "Built In",
                    prompt = "Prompt",
                    isBuiltIn = true,
                    sortOrder = 0,
                )
            ),
        )

        assertTrue(state.isBuiltInPresetSelected)
        assertTrue(state.isSelectedPromptReadOnly)
        assertEquals("builtin", state.validatedPresetId)
    }

    @Test
    fun promptPresetPresenterBuildsSectionsAndValidation() {
        val state = PromptPresetPresenter.present(
            presets = listOf(
                PromptPresetSnapshot("b", "Built In", "One", true, 0),
                PromptPresetSnapshot("c", "Custom", "Two", false, 1),
            ),
            newName = "New Preset",
            newPrompt = "Prompt",
            editingPresetId = "c",
            editName = "Updated",
            editPrompt = "Updated prompt",
        )

        assertEquals(listOf("b"), state.builtInPresetIds)
        assertEquals(listOf("c"), state.customPresetIds)
        assertTrue(state.canCreatePreset)
        assertTrue(state.canSaveEditingPreset)
    }
}
