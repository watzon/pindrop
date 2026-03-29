package tech.watzon.pindrop.shared.uishell

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ShellStateTest {
    @Test
    fun browseFallsBackToFirstVisibleSectionWhenSelectionFilteredOut() {
        val state = SettingsShell.browse(
            query = "palette",
            selectedSection = SettingsSection.GENERAL,
            initialSection = SettingsSection.GENERAL,
        )

        assertEquals(SettingsSection.THEME, state.selectedSection)
        assertEquals(listOf(SettingsSection.THEME), state.filteredSections)
    }

    @Test
    fun browseReturnsAllSectionsForEmptyQuery() {
        val state = SettingsShell.browse(
            query = "",
            selectedSection = null,
            initialSection = SettingsSection.GENERAL,
        )

        assertEquals(SettingsSection.GENERAL, state.selectedSection)
        assertEquals(SettingsShell.sections().size, state.matchCount)
    }

    @Test
    fun workspaceNavigationPromotesSettingsSectionSelection() {
        val state = MainWorkspaceNavigator.navigateToSettings(
            currentState = MainWorkspaceNavigator.initialState(),
            section = SettingsSection.AI,
        )

        assertEquals(MainNavigationItem.SETTINGS, state.selectedNavigationItem)
        assertEquals(SettingsSection.AI, state.selectedSettingsSection)
    }

    @Test
    fun sectionDefinitionsExposeStableAccessibilityIdentifiers() {
        assertTrue(SettingsShell.sections().any { it.accessibilityIdentifier == "settings.tab.theme" })
    }
}
