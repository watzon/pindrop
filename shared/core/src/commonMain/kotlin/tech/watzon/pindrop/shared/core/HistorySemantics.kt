package tech.watzon.pindrop.shared.core

/**
 * Shared history/search semantics for transcript management.
 *
 * Provides pure functions for sorting, searching, and deduplicating
 * transcript records. Uses generics so the logic works with any data
 * class that provides text and timestamp extractors.
 */
object HistorySemantics {

    /**
     * Sort order for transcript lists.
     */
    enum class SortOrder {
        DATE_DESC,
        DATE_ASC,
        RELEVANCE,
    }

    /**
     * Sort transcripts by the given order.
     *
     * @param items List of transcript-like records.
     * @param sortBy The sort order to apply.
     * @param timestampExtractor Function to extract a timestamp (epoch millis) from each item.
     * @return Sorted list (new list, original unmodified).
     */
    fun <T> sortTranscripts(
        items: List<T>,
        sortBy: SortOrder,
        timestampExtractor: (T) -> Long,
    ): List<T> {
        return when (sortBy) {
            SortOrder.DATE_DESC -> items.sortedByDescending(timestampExtractor)
            SortOrder.DATE_ASC -> items.sortedBy(timestampExtractor)
            SortOrder.RELEVANCE -> items.toList() // preserve original order
        }
    }

    /**
     * Search transcripts by text content (case-insensitive).
     *
     * @param items List of transcript-like records.
     * @param query Search query. Empty query returns all items.
     * @param textExtractor Function to extract searchable text from each item.
     * @return Filtered list matching the query.
     */
    fun <T> searchTranscripts(
        items: List<T>,
        query: String,
        textExtractor: (T) -> String,
    ): List<T> {
        if (query.isBlank()) return items.toList()
        return items.filter { item ->
            textExtractor(item).contains(query, ignoreCase = true)
        }
    }

    /**
     * Remove near-duplicate transcripts within a time window.
     *
     * Two records are considered duplicates if they have identical text
     * and their timestamps fall within [windowMs] of each other.
     * The first occurrence is kept.
     *
     * @param items List of transcript-like records.
     * @param textExtractor Function to extract text for comparison.
     * @param timeExtractor Function to extract timestamp for window comparison.
     * @param windowMs Time window in milliseconds within which duplicates are detected.
     * @return Deduplicated list.
     */
    fun <T> deduplicateTranscripts(
        items: List<T>,
        textExtractor: (T) -> String,
        timeExtractor: (T) -> Long,
        windowMs: Long = 5000,
    ): List<T> {
        val result = mutableListOf<T>()
        for (item in items) {
            val itemText = textExtractor(item)
            val itemTime = timeExtractor(item)
            val isDuplicate = result.any { existing ->
                textExtractor(existing) == itemText &&
                    kotlin.math.abs(timeExtractor(existing) - itemTime) <= windowMs
            }
            if (!isDuplicate) {
                result.add(item)
            }
        }
        return result
    }
}
