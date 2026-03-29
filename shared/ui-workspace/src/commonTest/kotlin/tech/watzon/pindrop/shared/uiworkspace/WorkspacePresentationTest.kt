package tech.watzon.pindrop.shared.uiworkspace

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WorkspacePresentationTest {
    @Test
    fun dashboardPresenterCalculatesGreetingAndStats() {
        val state = DashboardPresenter.present(
            records = listOf(
                DashboardRecordSnapshot(text = "one two three", durationSeconds = 30.0),
                DashboardRecordSnapshot(text = "four five", durationSeconds = 30.0),
            ),
            currentHour = 9,
            hasDismissedHotkeyReminder = false,
        )

        assertEquals("Good morning", state.greetingKey)
        assertEquals(2, state.totalSessions)
        assertEquals(5, state.totalWords)
        assertEquals(5.0, state.averageWordsPerMinute)
        assertTrue(state.shouldShowHotkeyReminder)
    }

    @Test
    fun mediaLibraryPresenterFiltersFoldersAndRecords() {
        val state = MediaLibraryPresenter.browse(
            folders = listOf(
                MediaFolderSnapshot(id = "folder-a", name = "Calls", itemCount = 1),
                MediaFolderSnapshot(id = "folder-b", name = "Meetings", itemCount = 1),
            ),
            records = listOf(
                MediaRecordSnapshot(
                    id = "record-1",
                    folderId = null,
                    timestampEpochMillis = 30,
                    searchText = "Quarterly planning review",
                    sortName = "Quarterly planning review",
                ),
                MediaRecordSnapshot(
                    id = "record-2",
                    folderId = "folder-a",
                    timestampEpochMillis = 20,
                    searchText = "Call summary",
                    sortName = "Call summary",
                ),
            ),
            selectedFolderId = null,
            searchText = "plan",
            sortMode = MediaLibrarySortModeCore.NEWEST,
        )

        assertEquals(emptyList(), state.visibleFolderIds)
        assertEquals(listOf("record-1"), state.visibleRecordIds)
        assertEquals(MediaLibraryEmptyStateKind.NONE, state.emptyStateKind)
    }

    @Test
    fun mediaLibraryPresenterReportsFolderEmptyStates() {
        val state = MediaLibraryPresenter.browse(
            folders = listOf(MediaFolderSnapshot(id = "folder-a", name = "Calls", itemCount = 0)),
            records = emptyList(),
            selectedFolderId = "folder-a",
            searchText = "",
            sortMode = MediaLibrarySortModeCore.NEWEST,
        )

        assertEquals(MediaLibraryEmptyStateKind.FOLDER_EMPTY, state.emptyStateKind)
        assertFalse(state.visibleRecordIds.isNotEmpty())
    }

    @Test
    fun historyPresenterDerivesSectionsAndEmptyStates() {
        val now = 1_700_000_000_000L
        val state = HistoryPresenter.present(
            records = listOf(
                HistoryRecordSnapshot(id = "today", timestampEpochMillis = now),
                HistoryRecordSnapshot(id = "yesterday", timestampEpochMillis = now - 86_400_000L),
                HistoryRecordSnapshot(id = "older", timestampEpochMillis = now - (2 * 86_400_000L)),
            ),
            totalTranscriptionsCount = 3,
            searchText = "",
            selectedRecordId = "yesterday",
            hasLoadedInitialPage = true,
            isLoadingPage = false,
            errorMessage = null,
            nowEpochMillis = now,
            timeZoneOffsetMinutes = 0,
        )

        assertEquals(HistoryContentStateKind.POPULATED, state.contentStateKind)
        assertEquals("yesterday", state.selectedRecordId)
        assertEquals(3, state.sections.size)
        assertEquals(HistorySectionKind.TODAY, state.sections[0].kind)
        assertEquals(HistorySectionKind.YESTERDAY, state.sections[1].kind)
        assertEquals(HistorySectionKind.DATE, state.sections[2].kind)
    }

    @Test
    fun historyPresenterReportsSearchEmptyState() {
        val state = HistoryPresenter.present(
            records = emptyList(),
            totalTranscriptionsCount = 0,
            searchText = "plan",
            selectedRecordId = null,
            hasLoadedInitialPage = true,
            isLoadingPage = false,
            errorMessage = null,
            nowEpochMillis = 0,
            timeZoneOffsetMinutes = 0,
        )

        assertEquals(HistoryContentStateKind.EMPTY_SEARCH, state.contentStateKind)
        assertFalse(state.canExport)
    }

    @Test
    fun dictionaryPresenterSortsEntriesAndValidatesAddForm() {
        val state = DictionaryPresenter.present(
            selectedSection = DictionarySectionCore.REPLACEMENTS,
            replacements = listOf(
                ReplacementEntrySnapshot(id = "b", originals = listOf("beta"), replacement = "B", sortOrder = 2),
                ReplacementEntrySnapshot(id = "a", originals = listOf("alpha"), replacement = "A", sortOrder = 1),
            ),
            vocabularyWords = listOf(VocabularyWordSnapshot(id = "v1", word = "Zebra")),
            primaryInput = "source",
            secondaryInput = "target",
            errorMessage = null,
        )

        assertEquals(3, state.totalItemCount)
        assertEquals(listOf("a", "b"), state.visibleReplacementIds)
        assertTrue(state.canAdd)
        assertEquals(DictionaryContentStateKind.POPULATED, state.contentStateKind)
    }

    @Test
    fun notesPresenterFiltersAndTracksEmptySearchState() {
        val state = NotesPresenter.present(
            notes = listOf(
                NoteSnapshot(
                    id = "1",
                    title = "Meeting Notes",
                    content = "Quarterly planning session",
                    tags = listOf("planning"),
                    updatedAtEpochMillis = 20,
                ),
                NoteSnapshot(
                    id = "2",
                    title = "Ideas",
                    content = "Ship desktop rewrite",
                    tags = listOf("product"),
                    updatedAtEpochMillis = 10,
                ),
            ),
            searchText = "quarterly",
            sortOrder = NotesSortOrderCore.DESCENDING,
            selectedNoteId = "2",
            errorMessage = null,
        )

        assertEquals(listOf("1"), state.visibleNoteIds)
        assertEquals(null, state.selectedNoteId)
        assertEquals(NotesContentStateKind.POPULATED, state.contentStateKind)

        val emptyState = NotesPresenter.present(
            notes = emptyList(),
            searchText = "missing",
            sortOrder = NotesSortOrderCore.ASCENDING,
            selectedNoteId = null,
            errorMessage = null,
        )

        assertEquals(NotesContentStateKind.EMPTY_SEARCH, emptyState.contentStateKind)
    }

    @Test
    fun modelsPresenterFiltersUsingSharedCatalogRules() {
        val state = ModelsPresenter.browse(
            models = listOf(
                ModelCatalogEntrySnapshot(
                    id = "recommended-local",
                    name = "recommended-local",
                    displayName = "Recommended Local",
                    description = "fast local model",
                    providerName = "WhisperKit",
                    isLocal = true,
                    isRecommended = true,
                    availability = "available",
                ),
                ModelCatalogEntrySnapshot(
                    id = "cloud",
                    name = "cloud",
                    displayName = "Cloud",
                    description = "remote model",
                    providerName = "OpenAI",
                    isLocal = false,
                    isRecommended = false,
                    availability = "available",
                ),
            ),
            selectedFilter = ModelsFilterCore.RECOMMENDED,
            searchText = "",
        )

        assertEquals(ModelsFilterCore.RECOMMENDED, state.effectiveFilter)
        assertEquals(listOf("recommended-local"), state.visibleModelIds)

        val searched = ModelsPresenter.browse(
            models = emptyList(),
            selectedFilter = ModelsFilterCore.ALL,
            searchText = "missing",
        )
        assertEquals(ModelsContentStateKind.EMPTY_SEARCH, searched.contentStateKind)
    }

    @Test
    fun transcribeLibraryPresenterDerivesEmptyStateAndActions() {
        val browseState = MediaLibraryBrowseState(
            trimmedSearchText = "",
            selectedFolderId = "folder-1",
            visibleFolderIds = emptyList(),
            visibleRecordIds = emptyList(),
            filteredFolderCount = 0,
            filteredRecordCount = 0,
            totalRecordCountForSelectedFolder = 0,
            emptyStateKind = MediaLibraryEmptyStateKind.FOLDER_EMPTY,
        )

        val state = TranscribeLibraryPresenter.present(
            selectedFolderId = "folder-1",
            selectedFolderName = "Calls",
            draftLink = " https://example.com/video ",
            librarySearchText = "",
            browseState = browseState,
        )

        assertTrue(state.shouldShowBackButton)
        assertTrue(state.canSubmitDraftLink)
        assertTrue(state.shouldShowLibraryEmptyState)
        assertEquals("No items in %@", state.emptyStateTitleKey)
        assertEquals("folder.badge.questionmark", state.emptyStateIconName)
    }
}
