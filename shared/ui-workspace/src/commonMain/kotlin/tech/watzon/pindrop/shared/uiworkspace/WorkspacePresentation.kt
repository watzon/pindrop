package tech.watzon.pindrop.shared.uiworkspace

import kotlin.math.max

data class DashboardRecordSnapshot(
    val text: String,
    val durationSeconds: Double,
)

data class DashboardViewState(
    val greetingKey: String,
    val totalSessions: Int,
    val totalWords: Int,
    val totalDurationSeconds: Double,
    val averageWordsPerMinute: Double,
    val shouldShowHotkeyReminder: Boolean,
)

object DashboardPresenter {
    fun present(
        records: List<DashboardRecordSnapshot>,
        currentHour: Int,
        hasDismissedHotkeyReminder: Boolean,
    ): DashboardViewState {
        val totalSessions = records.size
        val totalWords = records.sumOf { record ->
            record.text.trim()
                .split(Regex("\\s+"))
                .count { token -> token.isNotEmpty() }
        }
        val totalDurationSeconds = records.sumOf(DashboardRecordSnapshot::durationSeconds)
        val minutes = totalDurationSeconds / 60.0
        val averageWordsPerMinute = if (totalDurationSeconds > 0) {
            totalWords.toDouble() / max(minutes, 1.0)
        } else {
            0.0
        }

        return DashboardViewState(
            greetingKey = greetingKeyForHour(currentHour),
            totalSessions = totalSessions,
            totalWords = totalWords,
            totalDurationSeconds = totalDurationSeconds,
            averageWordsPerMinute = averageWordsPerMinute,
            shouldShowHotkeyReminder = !hasDismissedHotkeyReminder,
        )
    }

    private fun greetingKeyForHour(currentHour: Int): String = when (currentHour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Good night"
    }
}

enum class MediaLibrarySortModeCore {
    NEWEST,
    OLDEST,
    NAME_ASCENDING,
    NAME_DESCENDING,
}

data class MediaFolderSnapshot(
    val id: String,
    val name: String,
    val itemCount: Int,
)

data class MediaRecordSnapshot(
    val id: String,
    val folderId: String?,
    val timestampEpochMillis: Long,
    val searchText: String,
    val sortName: String,
)

enum class MediaLibraryEmptyStateKind {
    NONE,
    LIBRARY_EMPTY,
    SEARCH_EMPTY,
    FOLDER_EMPTY,
    FOLDER_SEARCH_EMPTY,
}

data class MediaLibraryBrowseState(
    val trimmedSearchText: String,
    val selectedFolderId: String?,
    val visibleFolderIds: List<String>,
    val visibleRecordIds: List<String>,
    val filteredFolderCount: Int,
    val filteredRecordCount: Int,
    val totalRecordCountForSelectedFolder: Int,
    val emptyStateKind: MediaLibraryEmptyStateKind,
)

object MediaLibraryPresenter {
    fun browse(
        folders: List<MediaFolderSnapshot>,
        records: List<MediaRecordSnapshot>,
        selectedFolderId: String?,
        searchText: String,
        sortMode: MediaLibrarySortModeCore,
    ): MediaLibraryBrowseState {
        val trimmedSearchText = searchText.trim()
        val selectedFolder = folders.firstOrNull { it.id == selectedFolderId }

        val visibleFolders = if (selectedFolder == null) {
            if (trimmedSearchText.isEmpty()) {
                folders
            } else {
                folders.filter { folder ->
                    folder.name.contains(trimmedSearchText, ignoreCase = true)
                }
            }
        } else {
            emptyList()
        }

        val visibleRecords = records
            .asSequence()
            .filter { record ->
                when {
                    selectedFolder == null -> record.folderId == null
                    else -> record.folderId == selectedFolder.id
                }
            }
            .filter { record ->
                trimmedSearchText.isEmpty() ||
                    record.searchText.contains(trimmedSearchText, ignoreCase = true)
            }
            .sortedWith(sortComparator(sortMode))
            .toList()

        val totalRecordCountForSelectedFolder = records.count { it.folderId == selectedFolder?.id }
        val emptyStateKind = when {
            visibleFolders.isNotEmpty() || visibleRecords.isNotEmpty() -> MediaLibraryEmptyStateKind.NONE
            selectedFolder != null && trimmedSearchText.isNotEmpty() -> MediaLibraryEmptyStateKind.FOLDER_SEARCH_EMPTY
            selectedFolder != null -> MediaLibraryEmptyStateKind.FOLDER_EMPTY
            trimmedSearchText.isNotEmpty() -> MediaLibraryEmptyStateKind.SEARCH_EMPTY
            else -> MediaLibraryEmptyStateKind.LIBRARY_EMPTY
        }

        return MediaLibraryBrowseState(
            trimmedSearchText = trimmedSearchText,
            selectedFolderId = selectedFolder?.id,
            visibleFolderIds = visibleFolders.map(MediaFolderSnapshot::id),
            visibleRecordIds = visibleRecords.map(MediaRecordSnapshot::id),
            filteredFolderCount = visibleFolders.size,
            filteredRecordCount = visibleRecords.size,
            totalRecordCountForSelectedFolder = totalRecordCountForSelectedFolder,
            emptyStateKind = emptyStateKind,
        )
    }

    private fun sortComparator(sortMode: MediaLibrarySortModeCore): Comparator<MediaRecordSnapshot> = when (sortMode) {
        MediaLibrarySortModeCore.NEWEST -> compareByDescending(MediaRecordSnapshot::timestampEpochMillis)
        MediaLibrarySortModeCore.OLDEST -> compareBy(MediaRecordSnapshot::timestampEpochMillis)
        MediaLibrarySortModeCore.NAME_ASCENDING -> compareBy(String.CASE_INSENSITIVE_ORDER, MediaRecordSnapshot::sortName)
        MediaLibrarySortModeCore.NAME_DESCENDING -> compareByDescending(String.CASE_INSENSITIVE_ORDER, MediaRecordSnapshot::sortName)
    }
}

data class HistoryRecordSnapshot(
    val id: String,
    val timestampEpochMillis: Long,
)

enum class HistoryContentStateKind {
    LOADING,
    EMPTY_LIBRARY,
    EMPTY_SEARCH,
    POPULATED,
    ERROR,
}

enum class HistorySectionKind {
    TODAY,
    YESTERDAY,
    DATE,
}

data class HistorySectionState(
    val kind: HistorySectionKind,
    val representativeTimestampEpochMillis: Long,
    val recordIds: List<String>,
)

data class HistoryViewState(
    val trimmedSearchText: String,
    val totalTranscriptionsCount: Int,
    val selectedRecordId: String?,
    val contentStateKind: HistoryContentStateKind,
    val canExport: Boolean,
    val shouldShowLoadingMoreIndicator: Boolean,
    val sections: List<HistorySectionState>,
)

object HistoryPresenter {
    fun present(
        records: List<HistoryRecordSnapshot>,
        totalTranscriptionsCount: Int,
        searchText: String,
        selectedRecordId: String?,
        hasLoadedInitialPage: Boolean,
        isLoadingPage: Boolean,
        errorMessage: String?,
        nowEpochMillis: Long,
        timeZoneOffsetMinutes: Int,
    ): HistoryViewState {
        val trimmedSearchText = searchText.trim()
        val contentStateKind = when {
            !errorMessage.isNullOrBlank() -> HistoryContentStateKind.ERROR
            !hasLoadedInitialPage -> HistoryContentStateKind.LOADING
            totalTranscriptionsCount == 0 && trimmedSearchText.isNotEmpty() -> HistoryContentStateKind.EMPTY_SEARCH
            totalTranscriptionsCount == 0 -> HistoryContentStateKind.EMPTY_LIBRARY
            else -> HistoryContentStateKind.POPULATED
        }

        val visibleRecordIds = records.map(HistoryRecordSnapshot::id).toSet()
        val normalizedSelectedRecordId = selectedRecordId?.takeIf { visibleRecordIds.contains(it) }

        return HistoryViewState(
            trimmedSearchText = trimmedSearchText,
            totalTranscriptionsCount = totalTranscriptionsCount,
            selectedRecordId = normalizedSelectedRecordId,
            contentStateKind = contentStateKind,
            canExport = totalTranscriptionsCount > 0,
            shouldShowLoadingMoreIndicator = isLoadingPage && hasLoadedInitialPage && records.isNotEmpty(),
            sections = groupSections(records, nowEpochMillis, timeZoneOffsetMinutes),
        )
    }

    private fun groupSections(
        records: List<HistoryRecordSnapshot>,
        nowEpochMillis: Long,
        timeZoneOffsetMinutes: Int,
    ): List<HistorySectionState> {
        if (records.isEmpty()) return emptyList()

        val todayDay = epochDay(nowEpochMillis, timeZoneOffsetMinutes)
        val grouped = linkedMapOf<Pair<HistorySectionKind, Long>, MutableList<HistoryRecordSnapshot>>()

        for (record in records.sortedByDescending(HistoryRecordSnapshot::timestampEpochMillis)) {
            val recordDay = epochDay(record.timestampEpochMillis, timeZoneOffsetMinutes)
            val kind = when (recordDay) {
                todayDay -> HistorySectionKind.TODAY
                todayDay - 1 -> HistorySectionKind.YESTERDAY
                else -> HistorySectionKind.DATE
            }
            val key = when (kind) {
                HistorySectionKind.TODAY -> kind to todayDay
                HistorySectionKind.YESTERDAY -> kind to (todayDay - 1)
                HistorySectionKind.DATE -> kind to recordDay
            }
            grouped.getOrPut(key) { mutableListOf() }.add(record)
        }

        return grouped.entries.map { (key, bucket) ->
            HistorySectionState(
                kind = key.first,
                representativeTimestampEpochMillis = bucket.first().timestampEpochMillis,
                recordIds = bucket.map(HistoryRecordSnapshot::id),
            )
        }
    }

    private fun epochDay(epochMillis: Long, timeZoneOffsetMinutes: Int): Long {
        val adjustedMillis = epochMillis + timeZoneOffsetMinutes.toLong() * 60_000L
        return floorDiv(adjustedMillis, 86_400_000L)
    }

    private fun floorDiv(value: Long, divisor: Long): Long {
        var quotient = value / divisor
        val remainder = value % divisor
        if (remainder != 0L && (value xor divisor) < 0) {
            quotient -= 1
        }
        return quotient
    }
}

enum class DictionarySectionCore {
    REPLACEMENTS,
    VOCABULARY,
}

enum class DictionaryContentStateKind {
    POPULATED,
    EMPTY,
    ERROR,
}

data class ReplacementEntrySnapshot(
    val id: String,
    val originals: List<String>,
    val replacement: String,
    val sortOrder: Int,
)

data class VocabularyWordSnapshot(
    val id: String,
    val word: String,
)

data class DictionaryViewState(
    val selectedSection: DictionarySectionCore,
    val totalItemCount: Int,
    val visibleReplacementIds: List<String>,
    val visibleVocabularyIds: List<String>,
    val canAdd: Boolean,
    val contentStateKind: DictionaryContentStateKind,
)

object DictionaryPresenter {
    fun present(
        selectedSection: DictionarySectionCore,
        replacements: List<ReplacementEntrySnapshot>,
        vocabularyWords: List<VocabularyWordSnapshot>,
        primaryInput: String,
        secondaryInput: String,
        errorMessage: String?,
    ): DictionaryViewState {
        val sortedReplacementIds = replacements
            .sortedBy(ReplacementEntrySnapshot::sortOrder)
            .map(ReplacementEntrySnapshot::id)
        val sortedVocabularyIds = vocabularyWords
            .sortedBy { it.word.lowercase() }
            .map(VocabularyWordSnapshot::id)
        val canAdd = when (selectedSection) {
            DictionarySectionCore.REPLACEMENTS -> primaryInput.trim().isNotEmpty() && secondaryInput.trim().isNotEmpty()
            DictionarySectionCore.VOCABULARY -> primaryInput.trim().isNotEmpty()
        }
        val selectedContentIsEmpty = when (selectedSection) {
            DictionarySectionCore.REPLACEMENTS -> sortedReplacementIds.isEmpty()
            DictionarySectionCore.VOCABULARY -> sortedVocabularyIds.isEmpty()
        }

        return DictionaryViewState(
            selectedSection = selectedSection,
            totalItemCount = replacements.size + vocabularyWords.size,
            visibleReplacementIds = sortedReplacementIds,
            visibleVocabularyIds = sortedVocabularyIds,
            canAdd = canAdd,
            contentStateKind = when {
                !errorMessage.isNullOrBlank() -> DictionaryContentStateKind.ERROR
                selectedContentIsEmpty -> DictionaryContentStateKind.EMPTY
                else -> DictionaryContentStateKind.POPULATED
            },
        )
    }
}

enum class NotesSortOrderCore {
    ASCENDING,
    DESCENDING,
}

enum class NotesContentStateKind {
    POPULATED,
    EMPTY_LIBRARY,
    EMPTY_SEARCH,
    ERROR,
}

data class NoteSnapshot(
    val id: String,
    val title: String,
    val content: String,
    val tags: List<String>,
    val updatedAtEpochMillis: Long,
)

data class NotesViewState(
    val trimmedSearchText: String,
    val sortOrder: NotesSortOrderCore,
    val selectedNoteId: String?,
    val visibleNoteIds: List<String>,
    val totalVisibleCount: Int,
    val contentStateKind: NotesContentStateKind,
)

object NotesPresenter {
    fun present(
        notes: List<NoteSnapshot>,
        searchText: String,
        sortOrder: NotesSortOrderCore,
        selectedNoteId: String?,
        errorMessage: String?,
    ): NotesViewState {
        val trimmedSearchText = searchText.trim()
        val sortedNotes = when (sortOrder) {
            NotesSortOrderCore.ASCENDING -> notes.sortedBy(NoteSnapshot::updatedAtEpochMillis)
            NotesSortOrderCore.DESCENDING -> notes.sortedByDescending(NoteSnapshot::updatedAtEpochMillis)
        }
        val filteredNotes = if (trimmedSearchText.isEmpty()) {
            sortedNotes
        } else {
            sortedNotes.filter { note ->
                note.title.contains(trimmedSearchText, ignoreCase = true) ||
                    note.content.contains(trimmedSearchText, ignoreCase = true) ||
                    note.tags.any { tag -> tag.contains(trimmedSearchText, ignoreCase = true) }
            }
        }
        val visibleNoteIds = filteredNotes.map(NoteSnapshot::id)

        return NotesViewState(
            trimmedSearchText = trimmedSearchText,
            sortOrder = sortOrder,
            selectedNoteId = selectedNoteId?.takeIf { candidate -> visibleNoteIds.contains(candidate) },
            visibleNoteIds = visibleNoteIds,
            totalVisibleCount = visibleNoteIds.size,
            contentStateKind = when {
                !errorMessage.isNullOrBlank() -> NotesContentStateKind.ERROR
                visibleNoteIds.isNotEmpty() -> NotesContentStateKind.POPULATED
                trimmedSearchText.isNotEmpty() -> NotesContentStateKind.EMPTY_SEARCH
                else -> NotesContentStateKind.EMPTY_LIBRARY
            },
        )
    }
}

enum class ModelsFilterCore {
    RECOMMENDED,
    LOCAL,
    CLOUD,
    COMING_SOON,
    ALL,
}

enum class ModelsContentStateKind {
    POPULATED,
    EMPTY_LIBRARY,
    EMPTY_SEARCH,
}

data class ModelCatalogEntrySnapshot(
    val id: String,
    val name: String,
    val displayName: String,
    val description: String,
    val providerName: String,
    val isLocal: Boolean,
    val isRecommended: Boolean,
    val availability: String,
)

data class ModelsBrowseState(
    val trimmedSearchText: String,
    val selectedFilter: ModelsFilterCore,
    val effectiveFilter: ModelsFilterCore,
    val visibleModelIds: List<String>,
    val contentStateKind: ModelsContentStateKind,
)

object ModelsPresenter {
    fun browse(
        models: List<ModelCatalogEntrySnapshot>,
        selectedFilter: ModelsFilterCore,
        searchText: String,
    ): ModelsBrowseState {
        val trimmedSearchText = searchText.trim()
        val effectiveFilter = if (trimmedSearchText.isEmpty()) selectedFilter else ModelsFilterCore.ALL
        val filteredModels = models.filter { model ->
            matchesFilter(model, effectiveFilter) && matchesSearch(model, trimmedSearchText)
        }

        return ModelsBrowseState(
            trimmedSearchText = trimmedSearchText,
            selectedFilter = selectedFilter,
            effectiveFilter = effectiveFilter,
            visibleModelIds = filteredModels.map(ModelCatalogEntrySnapshot::id),
            contentStateKind = when {
                filteredModels.isNotEmpty() -> ModelsContentStateKind.POPULATED
                trimmedSearchText.isNotEmpty() -> ModelsContentStateKind.EMPTY_SEARCH
                else -> ModelsContentStateKind.EMPTY_LIBRARY
            },
        )
    }

    private fun matchesFilter(model: ModelCatalogEntrySnapshot, filter: ModelsFilterCore): Boolean = when (filter) {
        ModelsFilterCore.RECOMMENDED -> model.isRecommended
        ModelsFilterCore.LOCAL -> model.isLocal && model.availability == "available"
        ModelsFilterCore.CLOUD -> !model.isLocal && model.availability == "available"
        ModelsFilterCore.COMING_SOON -> model.availability == "comingSoon"
        ModelsFilterCore.ALL -> true
    }

    private fun matchesSearch(model: ModelCatalogEntrySnapshot, query: String): Boolean {
        if (query.isEmpty()) return true
        return model.displayName.contains(query, ignoreCase = true) ||
            model.name.contains(query, ignoreCase = true) ||
            model.description.contains(query, ignoreCase = true) ||
            model.providerName.contains(query, ignoreCase = true)
    }
}

data class TranscribeJobSnapshot(
    val stage: String,
    val requestDisplayName: String,
    val progress: Double?,
    val errorMessage: String?,
    val detail: String,
)

data class TranscribeLibraryViewState(
    val selectedFolderId: String?,
    val selectedFolderName: String?,
    val trimmedSearchText: String,
    val filteredFolderCount: Int,
    val filteredRecordCount: Int,
    val totalRecordCountForSelectedFolder: Int,
    val shouldShowBackButton: Boolean,
    val canSubmitDraftLink: Boolean,
    val shouldShowDraftLinkClearButton: Boolean,
    val shouldShowLibraryEmptyState: Boolean,
    val emptyStateTitleKey: String,
    val emptyStateMessageKey: String,
    val emptyStateIconName: String,
)

object TranscribeLibraryPresenter {
    fun present(
        selectedFolderId: String?,
        selectedFolderName: String?,
        draftLink: String,
        librarySearchText: String,
        browseState: MediaLibraryBrowseState,
    ): TranscribeLibraryViewState {
        val trimmedDraftLink = draftLink.trim()
        val emptyStateTitleKey = when (browseState.emptyStateKind) {
            MediaLibraryEmptyStateKind.FOLDER_EMPTY -> "No items in %@"
            MediaLibraryEmptyStateKind.FOLDER_SEARCH_EMPTY,
            MediaLibraryEmptyStateKind.SEARCH_EMPTY,
            MediaLibraryEmptyStateKind.NONE -> "No results found"
            MediaLibraryEmptyStateKind.LIBRARY_EMPTY -> "No media transcriptions yet"
        }
        val emptyStateMessageKey = when (browseState.emptyStateKind) {
            MediaLibraryEmptyStateKind.FOLDER_EMPTY -> "Import or transcribe media while this folder is selected to save items here."
            MediaLibraryEmptyStateKind.FOLDER_SEARCH_EMPTY -> "Try a different search term in this folder."
            MediaLibraryEmptyStateKind.LIBRARY_EMPTY -> "Imported files and web links will appear here once processing completes."
            MediaLibraryEmptyStateKind.SEARCH_EMPTY,
            MediaLibraryEmptyStateKind.NONE -> "Try a different search term."
        }
        val emptyStateIconName = if (browseState.trimmedSearchText.isEmpty()) {
            "folder.badge.questionmark"
        } else {
            "magnifyingglass"
        }

        return TranscribeLibraryViewState(
            selectedFolderId = selectedFolderId,
            selectedFolderName = selectedFolderName,
            trimmedSearchText = librarySearchText.trim(),
            filteredFolderCount = browseState.filteredFolderCount,
            filteredRecordCount = browseState.filteredRecordCount,
            totalRecordCountForSelectedFolder = browseState.totalRecordCountForSelectedFolder,
            shouldShowBackButton = selectedFolderId != null,
            canSubmitDraftLink = trimmedDraftLink.isNotEmpty(),
            shouldShowDraftLinkClearButton = trimmedDraftLink.isNotEmpty(),
            shouldShowLibraryEmptyState = browseState.emptyStateKind != MediaLibraryEmptyStateKind.NONE,
            emptyStateTitleKey = emptyStateTitleKey,
            emptyStateMessageKey = emptyStateMessageKey,
            emptyStateIconName = emptyStateIconName,
        )
    }
}
