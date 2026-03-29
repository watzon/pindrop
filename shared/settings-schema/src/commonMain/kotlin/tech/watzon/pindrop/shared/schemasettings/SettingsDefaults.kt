package tech.watzon.pindrop.shared.schemasettings

/**
 * Default values for every setting in the Pindrop app.
 *
 * These values are the single source of truth — the macOS Swift client
 * reads them from this object instead of maintaining its own copy.
 * Every value here must exactly match the former Swift `Defaults` enum.
 */
object SettingsDefaults {

    // -- Model ---------------------------------------------------------------
    const val selectedModel: String = "openai_whisper-base"
    const val selectedLanguage: String = "auto" // AppLanguage.automatic.rawValue
    const val selectedInputDeviceUID: String = ""

    // -- Output --------------------------------------------------------------
    const val outputMode: String = "clipboard"
    const val addTrailingSpace: Boolean = true

    // -- Theme ---------------------------------------------------------------
    const val themeMode: String = "system" // ThemeMode.SYSTEM.rawValue
    // The default preset ID is "pindrop" — matches PindropThemePresetCatalog.defaultPresetID
    const val lightThemePresetID: String = "pindrop"
    const val darkThemePresetID: String = "pindrop"

    // -- Floating Indicator --------------------------------------------------
    const val floatingIndicatorEnabled: Boolean = true
    const val floatingIndicatorType: String = "pill" // FloatingIndicatorType.pill.rawValue
    const val pillFloatingIndicatorOffsetX: Double = 0.0
    const val pillFloatingIndicatorOffsetY: Double = 0.0

    // -- AI Enhancement ------------------------------------------------------
    const val aiEnhancementEnabled: Boolean = false
    const val aiProvider: String = "OpenAI" // AIProvider.openai.rawValue
    const val customLocalProviderType: String = "Custom" // CustomProviderType.custom.rawValue
    const val aiModel: String = "openai/gpt-4o-mini"
    const val aiEnhancementPrompt: String =
        "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."
    const val noteEnhancementPrompt: String =
        "You are a note formatting assistant. Transform the transcribed text into a well-structured note.\n\nRules:\n- Fix grammar, punctuation, and spelling errors\n- For longer content (3+ paragraphs), add markdown formatting:\n  - Use headers (## or ###) to organize sections\n  - Use bullet points or numbered lists where appropriate\n  - Use **bold** for emphasis on key terms\n- For shorter content, keep it simple with minimal formatting\n- Preserve the original meaning and tone\n- Do not add content that wasn't in the original\n- Return only the formatted note without any commentary"
    val selectedPresetId: String? = null
    const val openRouterModelsCacheTimestamp: Double = 0.0
    const val openAIModelsCacheTimestamp: Double = 0.0

    // -- Context -------------------------------------------------------------
    const val enableClipboardContext: Boolean = false
    const val enableUIContext: Boolean = false
    const val contextCaptureTimeoutSeconds: Double = 2.0
    const val vibeLiveSessionEnabled: Boolean = true

    // -- Feature Flags -------------------------------------------------------
    const val vadFeatureEnabled: Boolean = false
    const val diarizationFeatureEnabled: Boolean = false
    const val streamingFeatureEnabled: Boolean = false

    // -- Onboarding ----------------------------------------------------------
    const val hasCompletedOnboarding: Boolean = false
    const val currentOnboardingStep: Int = 0

    // -- Dictionary ----------------------------------------------------------
    const val automaticDictionaryLearningEnabled: Boolean = true

    // -- Misc ----------------------------------------------------------------
    const val showInDock: Boolean = false
    const val launchAtLogin: Boolean = false
    const val pauseMediaOnRecording: Boolean = false
    const val muteAudioDuringRecording: Boolean = false
    const val mentionTemplateOverridesJSON: String = "{}"

    // -- Hotkeys (nested) ----------------------------------------------------
    object Hotkeys {
        const val toggleHotkey: String = "⌥Space"
        const val toggleHotkeyCode: Int = 49
        const val toggleHotkeyModifiers: Int = 2048 // 0x800

        const val pushToTalkHotkey: String = "⌘/"
        const val pushToTalkHotkeyCode: Int = 44
        const val pushToTalkHotkeyModifiers: Int = 256 // 0x100

        const val copyLastTranscriptHotkey: String = "⇧⌘C"
        const val copyLastTranscriptHotkeyCode: Int = 8
        const val copyLastTranscriptHotkeyModifiers: Int = 768 // 0x300

        const val quickCapturePTTHotkey: String = "⇧⌥Space"
        const val quickCapturePTTHotkeyCode: Int = 49
        const val quickCapturePTTHotkeyModifiers: Int = 2560 // 0xA00 = Shift + Option

        const val quickCaptureToggleHotkey: String = ""
        const val quickCaptureToggleHotkeyCode: Int = 0
        const val quickCaptureToggleHotkeyModifiers: Int = 0
    }
}
