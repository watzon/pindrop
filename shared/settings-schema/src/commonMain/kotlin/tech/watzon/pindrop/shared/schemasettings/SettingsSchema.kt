package tech.watzon.pindrop.shared.schemasettings

/**
 * Central registry of all UserDefaults key strings used by Pindrop.
 *
 * Every key defined here must have a matching default in [SettingsDefaults].
 * The key strings are the authoritative identifiers — they are used directly
 * in @AppStorage on the Swift side and must never change (backward compat).
 */
object SettingsKeys {

    // -- Model ---------------------------------------------------------------
    const val selectedModel = "selectedModel"
    const val selectedLanguage = "selectedLanguage"
    const val selectedInputDeviceUID = "selectedInputDeviceUID"

    // -- Output --------------------------------------------------------------
    const val outputMode = "outputMode"
    const val addTrailingSpace = "addTrailingSpace"

    // -- Hotkeys -------------------------------------------------------------
    object Hotkeys {
        const val toggleHotkey = "toggleHotkey"
        const val toggleHotkeyCode = "toggleHotkeyCode"
        const val toggleHotkeyModifiers = "toggleHotkeyModifiers"

        const val pushToTalkHotkey = "pushToTalkHotkey"
        const val pushToTalkHotkeyCode = "pushToTalkHotkeyCode"
        const val pushToTalkHotkeyModifiers = "pushToTalkHotkeyModifiers"

        const val copyLastTranscriptHotkey = "copyLastTranscriptHotkey"
        const val copyLastTranscriptHotkeyCode = "copyLastTranscriptHotkeyCode"
        const val copyLastTranscriptHotkeyModifiers = "copyLastTranscriptHotkeyModifiers"

        const val quickCapturePTTHotkey = "quickCapturePTTHotkey"
        const val quickCapturePTTHotkeyCode = "quickCapturePTTHotkeyCode"
        const val quickCapturePTTHotkeyModifiers = "quickCapturePTTHotkeyModifiers"

        const val quickCaptureToggleHotkey = "quickCaptureToggleHotkey"
        const val quickCaptureToggleHotkeyCode = "quickCaptureToggleHotkeyCode"
        const val quickCaptureToggleHotkeyModifiers = "quickCaptureToggleHotkeyModifiers"
    }

    // -- Theme ---------------------------------------------------------------
    const val themeMode = "themeMode"
    const val lightThemePresetID = "lightThemePresetID"
    const val darkThemePresetID = "darkThemePresetID"

    // -- Floating Indicator --------------------------------------------------
    const val floatingIndicatorEnabled = "floatingIndicatorEnabled"
    const val floatingIndicatorType = "floatingIndicatorType"
    const val pillFloatingIndicatorOffsetX = "pillFloatingIndicatorOffsetX"
    const val pillFloatingIndicatorOffsetY = "pillFloatingIndicatorOffsetY"

    // -- AI Enhancement ------------------------------------------------------
    const val aiEnhancementEnabled = "aiEnhancementEnabled"
    const val aiProvider = "aiProvider"
    const val customLocalProviderType = "customLocalProviderType"
    const val aiModel = "aiModel"
    const val aiEnhancementPrompt = "aiEnhancementPrompt"
    const val noteEnhancementPrompt = "noteEnhancementPrompt"
    const val selectedPresetId = "selectedPresetId"
    const val openRouterModelsCacheTimestamp = "openRouterModelsCacheTimestamp"
    const val openAIModelsCacheTimestamp = "openAIModelsCacheTimestamp"

    // -- Context -------------------------------------------------------------
    const val enableClipboardContext = "enableClipboardContext"
    const val enableUIContext = "enableUIContext"
    const val contextCaptureTimeoutSeconds = "contextCaptureTimeoutSeconds"
    const val vibeLiveSessionEnabled = "vibeLiveSessionEnabled"

    // -- Feature Flags -------------------------------------------------------
    const val vadFeatureEnabled = "vadFeatureEnabled"
    const val diarizationFeatureEnabled = "diarizationFeatureEnabled"
    const val streamingFeatureEnabled = "streamingFeatureEnabled"

    // -- Onboarding ----------------------------------------------------------
    const val hasCompletedOnboarding = "hasCompletedOnboarding"
    const val currentOnboardingStep = "currentOnboardingStep"

    // -- Dictionary ----------------------------------------------------------
    const val automaticDictionaryLearningEnabled = "automaticDictionaryLearningEnabled"

    // -- Misc ----------------------------------------------------------------
    const val showInDock = "showInDock"
    const val launchAtLogin = "launchAtLogin"
    const val pauseMediaOnRecording = "pauseMediaOnRecording"
    const val muteAudioDuringRecording = "muteAudioDuringRecording"
    const val mentionTemplateOverridesJSON = "mentionTemplateOverridesJSON"
}

// -- Enums mirroring Swift types referenced in settings ----------------------

enum class OutputMode(val rawValue: String) {
    CLIPBOARD("clipboard"),
    DIRECT_INSERT("directInsert"),
}

enum class FloatingIndicatorType(val rawValue: String) {
    NOTCH("notch"),
    PILL("pill"),
    BUBBLE("bubble"),
}

enum class ThemeMode(val rawValue: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark"),
}

enum class AppLanguage(val rawValue: String) {
    AUTOMATIC("auto"),
    ENGLISH("en"),
    SIMPLIFIED_CHINESE("zh-Hans"),
    SPANISH("es"),
    FRENCH("fr"),
    GERMAN("de"),
    TURKISH("tr"),
    JAPANESE("ja"),
    PORTUGUESE_BRAZIL("pt-BR"),
    ITALIAN("it"),
    DUTCH("nl"),
    KOREAN("ko"),
}

enum class AIProvider(val rawValue: String) {
    OPENAI("OpenAI"),
    GOOGLE("Google"),
    ANTHROPIC("Anthropic"),
    OPENROUTER("OpenRouter"),
    CUSTOM("Custom"),
}

enum class CustomProviderType(val rawValue: String, val storageKey: String) {
    CUSTOM("Custom", "custom"),
    OLLAMA("Ollama", "ollama"),
    LM_STUDIO("LM Studio", "lm-studio"),
}
