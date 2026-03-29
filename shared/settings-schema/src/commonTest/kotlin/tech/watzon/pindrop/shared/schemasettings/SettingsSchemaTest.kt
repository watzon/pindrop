package tech.watzon.pindrop.shared.schemasettings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Tests that every setting key and default value in the KMP schema
 * matches the original Swift Defaults enum exactly.
 */
class SettingsSchemaTest {

    // -- Test 1: Key strings match expected values --------------------------------

    @Test
    fun everySettingKeyHasCorrectKeyString() {
        assertEquals("selectedModel", SettingsKeys.selectedModel)
        assertEquals("selectedLanguage", SettingsKeys.selectedLanguage)
        assertEquals("selectedInputDeviceUID", SettingsKeys.selectedInputDeviceUID)
        assertEquals("outputMode", SettingsKeys.outputMode)
        assertEquals("addTrailingSpace", SettingsKeys.addTrailingSpace)
        assertEquals("themeMode", SettingsKeys.themeMode)
        assertEquals("lightThemePresetID", SettingsKeys.lightThemePresetID)
        assertEquals("darkThemePresetID", SettingsKeys.darkThemePresetID)
        assertEquals("floatingIndicatorEnabled", SettingsKeys.floatingIndicatorEnabled)
        assertEquals("floatingIndicatorType", SettingsKeys.floatingIndicatorType)
        assertEquals("pillFloatingIndicatorOffsetX", SettingsKeys.pillFloatingIndicatorOffsetX)
        assertEquals("pillFloatingIndicatorOffsetY", SettingsKeys.pillFloatingIndicatorOffsetY)
        assertEquals("aiEnhancementEnabled", SettingsKeys.aiEnhancementEnabled)
        assertEquals("aiProvider", SettingsKeys.aiProvider)
        assertEquals("customLocalProviderType", SettingsKeys.customLocalProviderType)
        assertEquals("aiModel", SettingsKeys.aiModel)
        assertEquals("aiEnhancementPrompt", SettingsKeys.aiEnhancementPrompt)
        assertEquals("noteEnhancementPrompt", SettingsKeys.noteEnhancementPrompt)
        assertEquals("selectedPresetId", SettingsKeys.selectedPresetId)
        assertEquals("openRouterModelsCacheTimestamp", SettingsKeys.openRouterModelsCacheTimestamp)
        assertEquals("openAIModelsCacheTimestamp", SettingsKeys.openAIModelsCacheTimestamp)
        assertEquals("enableClipboardContext", SettingsKeys.enableClipboardContext)
        assertEquals("enableUIContext", SettingsKeys.enableUIContext)
        assertEquals("contextCaptureTimeoutSeconds", SettingsKeys.contextCaptureTimeoutSeconds)
        assertEquals("vibeLiveSessionEnabled", SettingsKeys.vibeLiveSessionEnabled)
        assertEquals("vadFeatureEnabled", SettingsKeys.vadFeatureEnabled)
        assertEquals("diarizationFeatureEnabled", SettingsKeys.diarizationFeatureEnabled)
        assertEquals("streamingFeatureEnabled", SettingsKeys.streamingFeatureEnabled)
        assertEquals("hasCompletedOnboarding", SettingsKeys.hasCompletedOnboarding)
        assertEquals("currentOnboardingStep", SettingsKeys.currentOnboardingStep)
        assertEquals("automaticDictionaryLearningEnabled", SettingsKeys.automaticDictionaryLearningEnabled)
        assertEquals("showInDock", SettingsKeys.showInDock)
        assertEquals("launchAtLogin", SettingsKeys.launchAtLogin)
        assertEquals("pauseMediaOnRecording", SettingsKeys.pauseMediaOnRecording)
        assertEquals("muteAudioDuringRecording", SettingsKeys.muteAudioDuringRecording)
        assertEquals("mentionTemplateOverridesJSON", SettingsKeys.mentionTemplateOverridesJSON)
    }

    // -- Test 2: Defaults match Swift Defaults enum exactly -----------------------

    @Test
    fun stringDefaultsMatchSwift() {
        assertEquals("openai_whisper-base", SettingsDefaults.selectedModel)
        assertEquals("auto", SettingsDefaults.selectedLanguage)
        assertEquals("", SettingsDefaults.selectedInputDeviceUID)
        assertEquals("clipboard", SettingsDefaults.outputMode)
        assertEquals("system", SettingsDefaults.themeMode)
        assertEquals("pindrop", SettingsDefaults.lightThemePresetID)
        assertEquals("pindrop", SettingsDefaults.darkThemePresetID)
        assertEquals("pill", SettingsDefaults.floatingIndicatorType)
        assertEquals("OpenAI", SettingsDefaults.aiProvider)
        assertEquals("Custom", SettingsDefaults.customLocalProviderType)
        assertEquals("openai/gpt-4o-mini", SettingsDefaults.aiModel)
        assertEquals("{}", SettingsDefaults.mentionTemplateOverridesJSON)
    }

    @Test
    fun booleanDefaultsMatchSwift() {
        assertEquals(true, SettingsDefaults.addTrailingSpace)
        assertEquals(true, SettingsDefaults.floatingIndicatorEnabled)
        assertEquals(false, SettingsDefaults.aiEnhancementEnabled)
        assertEquals(false, SettingsDefaults.showInDock)
        assertEquals(false, SettingsDefaults.launchAtLogin)
        assertEquals(false, SettingsDefaults.pauseMediaOnRecording)
        assertEquals(false, SettingsDefaults.muteAudioDuringRecording)
        assertEquals(true, SettingsDefaults.automaticDictionaryLearningEnabled)
        assertEquals(false, SettingsDefaults.enableClipboardContext)
        assertEquals(false, SettingsDefaults.enableUIContext)
        assertEquals(true, SettingsDefaults.vibeLiveSessionEnabled)
        assertEquals(false, SettingsDefaults.vadFeatureEnabled)
        assertEquals(false, SettingsDefaults.diarizationFeatureEnabled)
        assertEquals(false, SettingsDefaults.streamingFeatureEnabled)
        assertEquals(false, SettingsDefaults.hasCompletedOnboarding)
    }

    @Test
    fun numericDefaultsMatchSwift() {
        assertEquals(0.0, SettingsDefaults.pillFloatingIndicatorOffsetX)
        assertEquals(0.0, SettingsDefaults.pillFloatingIndicatorOffsetY)
        assertEquals(2.0, SettingsDefaults.contextCaptureTimeoutSeconds)
        assertEquals(0.0, SettingsDefaults.openRouterModelsCacheTimestamp)
        assertEquals(0.0, SettingsDefaults.openAIModelsCacheTimestamp)
        assertEquals(0, SettingsDefaults.currentOnboardingStep)
    }

    @Test
    fun promptDefaultsMatchSwift() {
        assertTrue(SettingsDefaults.aiEnhancementPrompt.startsWith("You are a text enhancement assistant"))
        assertTrue(SettingsDefaults.noteEnhancementPrompt.startsWith("You are a note formatting assistant"))
    }

    // -- Test 3: Hotkey defaults match Swift exactly ------------------------------

    @Test
    fun hotkeyDefaultsMatchSwift() {
        // Toggle hotkey
        assertEquals("⌥Space", SettingsDefaults.Hotkeys.toggleHotkey)
        assertEquals(49, SettingsDefaults.Hotkeys.toggleHotkeyCode)
        assertEquals(0x800, SettingsDefaults.Hotkeys.toggleHotkeyModifiers)

        // Push to talk hotkey
        assertEquals("⌘/", SettingsDefaults.Hotkeys.pushToTalkHotkey)
        assertEquals(44, SettingsDefaults.Hotkeys.pushToTalkHotkeyCode)
        assertEquals(0x100, SettingsDefaults.Hotkeys.pushToTalkHotkeyModifiers)

        // Copy last transcript hotkey
        assertEquals("⇧⌘C", SettingsDefaults.Hotkeys.copyLastTranscriptHotkey)
        assertEquals(8, SettingsDefaults.Hotkeys.copyLastTranscriptHotkeyCode)
        assertEquals(0x300, SettingsDefaults.Hotkeys.copyLastTranscriptHotkeyModifiers)

        // Quick capture PTT hotkey
        assertEquals("⇧⌥Space", SettingsDefaults.Hotkeys.quickCapturePTTHotkey)
        assertEquals(49, SettingsDefaults.Hotkeys.quickCapturePTTHotkeyCode)
        assertEquals(0xA00, SettingsDefaults.Hotkeys.quickCapturePTTHotkeyModifiers)

        // Quick capture toggle hotkey
        assertEquals("", SettingsDefaults.Hotkeys.quickCaptureToggleHotkey)
        assertEquals(0, SettingsDefaults.Hotkeys.quickCaptureToggleHotkeyCode)
        assertEquals(0, SettingsDefaults.Hotkeys.quickCaptureToggleHotkeyModifiers)
    }

    // -- Test 4: Enums have correct raw values ------------------------------------

    @Test
    fun outputModeEnumMatchesSwift() {
        assertEquals("clipboard", OutputMode.CLIPBOARD.rawValue)
        assertEquals("directInsert", OutputMode.DIRECT_INSERT.rawValue)
    }

    @Test
    fun floatingIndicatorTypeEnumMatchesSwift() {
        assertEquals("notch", FloatingIndicatorType.NOTCH.rawValue)
        assertEquals("pill", FloatingIndicatorType.PILL.rawValue)
        assertEquals("bubble", FloatingIndicatorType.BUBBLE.rawValue)
    }

    @Test
    fun themeModeEnumMatchesSwift() {
        assertEquals("system", ThemeMode.SYSTEM.rawValue)
        assertEquals("light", ThemeMode.LIGHT.rawValue)
        assertEquals("dark", ThemeMode.DARK.rawValue)
    }

    @Test
    fun appLanguageEnumMatchesSwift() {
        assertEquals("auto", AppLanguage.AUTOMATIC.rawValue)
        assertEquals("en", AppLanguage.ENGLISH.rawValue)
        assertEquals("zh-Hans", AppLanguage.SIMPLIFIED_CHINESE.rawValue)
        assertEquals("es", AppLanguage.SPANISH.rawValue)
        assertEquals("fr", AppLanguage.FRENCH.rawValue)
        assertEquals("de", AppLanguage.GERMAN.rawValue)
        assertEquals("tr", AppLanguage.TURKISH.rawValue)
        assertEquals("ja", AppLanguage.JAPANESE.rawValue)
        assertEquals("pt-BR", AppLanguage.PORTUGUESE_BRAZIL.rawValue)
        assertEquals("it", AppLanguage.ITALIAN.rawValue)
        assertEquals("nl", AppLanguage.DUTCH.rawValue)
        assertEquals("ko", AppLanguage.KOREAN.rawValue)
    }

    @Test
    fun aiProviderEnumMatchesSwift() {
        assertEquals("OpenAI", AIProvider.OPENAI.rawValue)
        assertEquals("Google", AIProvider.GOOGLE.rawValue)
        assertEquals("Anthropic", AIProvider.ANTHROPIC.rawValue)
        assertEquals("OpenRouter", AIProvider.OPENROUTER.rawValue)
        assertEquals("Custom", AIProvider.CUSTOM.rawValue)
    }

    @Test
    fun customProviderTypeEnumMatchesSwift() {
        assertEquals("Custom", CustomProviderType.CUSTOM.rawValue)
        assertEquals("custom", CustomProviderType.CUSTOM.storageKey)
        assertEquals("Ollama", CustomProviderType.OLLAMA.rawValue)
        assertEquals("ollama", CustomProviderType.OLLAMA.storageKey)
        assertEquals("LM Studio", CustomProviderType.LM_STUDIO.rawValue)
        assertEquals("lm-studio", CustomProviderType.LM_STUDIO.storageKey)
    }

    // -- Test 5: Secret schema matches Swift Keychain naming ----------------------

    @Test
    fun secretSchemaDefinesCorrectProviderAccounts() {
        val providers = SecretSchema.providers()
        assertEquals(5, providers.size)

        val openai = providers.first { it.providerId == "openai" }
        assertEquals("api-key-openai", openai.apiKeyAccount)
        assertTrue(openai.needsApiKey)

        val anthropic = providers.first { it.providerId == "anthropic" }
        assertEquals("api-key-anthropic", anthropic.apiKeyAccount)

        val google = providers.first { it.providerId == "google" }
        assertEquals("api-key-google", google.apiKeyAccount)

        val openrouter = providers.first { it.providerId == "openrouter" }
        assertEquals("api-key-openrouter", openrouter.apiKeyAccount)

        val custom = providers.first { it.providerId == "custom" }
        assertEquals("api-key-custom", custom.apiKeyAccount)
        assertTrue(custom.needsEndpoint)
        assertTrue(custom.apiKeyOptional)
    }

    @Test
    fun secretSchemaDefinesCustomProviders() {
        val customs = SecretSchema.customProviders()
        assertEquals(3, customs.size)

        val ollama = customs.first { it.storageKey == "ollama" }
        assertEquals("ollama", ollama.providerId)
        assertEquals(false, ollama.needsApiKey)
        assertEquals(true, ollama.supportsModelListing)

        val lmStudio = customs.first { it.storageKey == "lm-studio" }
        assertEquals("lm-studio", lmStudio.providerId)
        assertEquals(false, lmStudio.needsApiKey)
    }

    @Test
    fun secretSchemaAccountHelpers() {
        assertEquals("api-key-openai", SecretSchema.apiKeyAccount("openai"))
        assertEquals("api-key-custom-ollama", SecretSchema.apiKeyAccount("custom", "ollama"))
        assertEquals("api-key-custom-lm-studio", SecretSchema.apiKeyAccount("custom", "lm-studio"))

        assertEquals("api-endpoint", SecretSchema.endpointAccount("openai"))
        assertEquals("api-endpoint-custom-ollama", SecretSchema.endpointAccount("custom", "ollama"))
        assertEquals("api-endpoint-custom-lm-studio", SecretSchema.endpointAccount("custom", "lm-studio"))
        assertEquals("api-endpoint-custom-custom", SecretSchema.endpointAccount("custom", "custom"))
    }

    @Test
    fun keychainServiceNameMatchesSwift() {
        assertEquals("com.pindrop.settings", SecretSchema.keychainServiceName)
    }

    // -- Test 6: Key-defaults coverage (every key has a default) ------------------

    @Test
    fun everyKeyHasCorrespondingDefault() {
        // Verify that for every key string we've defined, a default exists.
        // This isn't exhaustive compile-time, but covers the critical ones.
        val keysWithDefaults = mapOf(
            SettingsKeys.selectedModel to SettingsDefaults.selectedModel,
            SettingsKeys.selectedLanguage to SettingsDefaults.selectedLanguage,
            SettingsKeys.outputMode to SettingsDefaults.outputMode,
            SettingsKeys.themeMode to SettingsDefaults.themeMode,
            SettingsKeys.floatingIndicatorType to SettingsDefaults.floatingIndicatorType,
            SettingsKeys.aiModel to SettingsDefaults.aiModel,
            SettingsKeys.aiProvider to SettingsDefaults.aiProvider,
        )
        keysWithDefaults.forEach { (key, default) ->
            assertTrue(key.isNotBlank(), "Key should not be blank")
            assertTrue(default.isNotBlank(), "Default for $key should not be blank")
        }
    }
}
