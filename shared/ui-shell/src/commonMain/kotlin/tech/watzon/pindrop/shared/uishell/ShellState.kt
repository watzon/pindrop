package tech.watzon.pindrop.shared.uishell

enum class MainNavigationItem {
    HOME,
    HISTORY,
    TRANSCRIBE,
    MODELS,
    NOTES,
    DICTIONARY,
    SETTINGS,
}

enum class SettingsSection {
    GENERAL,
    THEME,
    HOTKEYS,
    AI,
    UPDATE,
    ABOUT,
}

data class SettingsSectionDefinition(
    val id: SettingsSection,
    val titleKey: String,
    val subtitleKey: String,
    val systemIcon: String,
    val searchKeywords: List<String>,
    val accessibilityIdentifier: String,
)

data class SettingsBrowseState(
    val query: String,
    val selectedSection: SettingsSection,
    val filteredSections: List<SettingsSection>,
    val matchCount: Int,
)

data class MainWorkspaceState(
    val selectedNavigationItem: MainNavigationItem,
    val selectedSettingsSection: SettingsSection,
)

object SettingsShell {
    private val sectionDefinitions = listOf(
        SettingsSectionDefinition(
            id = SettingsSection.GENERAL,
            titleKey = "General",
            subtitleKey = "Output, audio, interface, and everyday behavior",
            systemIcon = "gear",
            searchKeywords = listOf(
                "output", "clipboard", "direct insert", "space", "microphone", "audio",
                "input", "floating indicator", "dictionary", "launch at login", "dock",
                "mute", "pause media", "reset", "language", "locale", "transcription language",
                "interface language"
            ),
            accessibilityIdentifier = "settings.tab.general",
        ),
        SettingsSectionDefinition(
            id = SettingsSection.THEME,
            titleKey = "Theme",
            subtitleKey = "Light, dark, and curated palette presets",
            systemIcon = "paintbrush",
            searchKeywords = listOf("appearance", "theme", "light", "dark", "system", "preset", "palette"),
            accessibilityIdentifier = "settings.tab.theme",
        ),
        SettingsSectionDefinition(
            id = SettingsSection.HOTKEYS,
            titleKey = "Hotkeys",
            subtitleKey = "Configure keyboard shortcuts for recording and note capture",
            systemIcon = "keyboard",
            searchKeywords = listOf("shortcut", "toggle recording", "push to talk", "copy last transcript", "note capture", "keyboard"),
            accessibilityIdentifier = "settings.tab.hotkeys",
        ),
        SettingsSectionDefinition(
            id = SettingsSection.AI,
            titleKey = "AI Enhancement",
            subtitleKey = "Providers, prompts, and vibe mode controls",
            systemIcon = "sparkles",
            searchKeywords = listOf(
                "provider", "api key", "endpoint", "prompt", "preset", "vibe mode",
                "clipboard context", "ui context", "model", "enhancement"
            ),
            accessibilityIdentifier = "settings.tab.ai-enhancement",
        ),
        SettingsSectionDefinition(
            id = SettingsSection.UPDATE,
            titleKey = "Update",
            subtitleKey = "Automatic updates and manual update checks",
            systemIcon = "arrow.triangle.2.circlepath",
            searchKeywords = listOf("updates", "automatic updates", "check now", "version"),
            accessibilityIdentifier = "settings.tab.update",
        ),
        SettingsSectionDefinition(
            id = SettingsSection.ABOUT,
            titleKey = "About",
            subtitleKey = "App info, acknowledgments, support, and logs",
            systemIcon = "info.circle",
            searchKeywords = listOf("support", "logs", "github", "license", "system info", "version"),
            accessibilityIdentifier = "settings.tab.about",
        ),
    )

    fun sections(): List<SettingsSectionDefinition> = sectionDefinitions

    fun section(id: SettingsSection): SettingsSectionDefinition {
        return sectionDefinitions.first { it.id == id }
    }

    fun browse(
        query: String,
        selectedSection: SettingsSection?,
        initialSection: SettingsSection,
    ): SettingsBrowseState {
        val normalizedQuery = query.trim()
        val filtered = if (normalizedQuery.isEmpty()) {
            sectionDefinitions.map { it.id }
        } else {
            val queryLower = normalizedQuery.lowercase()
            sectionDefinitions
                .filter { definition ->
                    val searchableText = buildString {
                        append(definition.titleKey)
                        append(' ')
                        append(definition.subtitleKey)
                        append(' ')
                        append(definition.searchKeywords.joinToString(" "))
                    }.lowercase()
                    searchableText.contains(queryLower)
                }
                .map { it.id }
        }

        val resolvedSelection = when {
            filtered.isEmpty() -> selectedSection ?: initialSection
            selectedSection != null && filtered.contains(selectedSection) -> selectedSection
            else -> filtered.first()
        }

        return SettingsBrowseState(
            query = query,
            selectedSection = resolvedSelection,
            filteredSections = filtered,
            matchCount = filtered.size,
        )
    }
}

object MainWorkspaceNavigator {
    fun initialState(): MainWorkspaceState {
        return MainWorkspaceState(
            selectedNavigationItem = MainNavigationItem.HOME,
            selectedSettingsSection = SettingsSection.GENERAL,
        )
    }

    fun navigateTo(
        currentState: MainWorkspaceState,
        item: MainNavigationItem,
    ): MainWorkspaceState {
        return currentState.copy(selectedNavigationItem = item)
    }

    fun navigateToSettings(
        currentState: MainWorkspaceState,
        section: SettingsSection,
    ): MainWorkspaceState {
        return currentState.copy(
            selectedNavigationItem = MainNavigationItem.SETTINGS,
            selectedSettingsSection = section,
        )
    }
}
