package tech.watzon.pindrop.shared.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HistorySemanticsTest {

    data class TestRecord(
        val id: String,
        val text: String,
        val timestampMs: Long,
    )

    // --- sortTranscripts ---

    @Test
    fun sortTranscriptsByDateDescendingReturnsNewestFirst() {
        val records = listOf(
            TestRecord("a", "first", 1000),
            TestRecord("b", "second", 3000),
            TestRecord("c", "third", 2000),
        )
        val result = HistorySemantics.sortTranscripts(
            items = records,
            sortBy = HistorySemantics.SortOrder.DATE_DESC,
            timestampExtractor = { it.timestampMs },
        )
        assertEquals(listOf("b", "c", "a"), result.map { it.id })
    }

    @Test
    fun sortTranscriptsByDateAscendingReturnsOldestFirst() {
        val records = listOf(
            TestRecord("a", "first", 1000),
            TestRecord("b", "second", 3000),
            TestRecord("c", "third", 2000),
        )
        val result = HistorySemantics.sortTranscripts(
            items = records,
            sortBy = HistorySemantics.SortOrder.DATE_ASC,
            timestampExtractor = { it.timestampMs },
        )
        assertEquals(listOf("a", "c", "b"), result.map { it.id })
    }

    // --- searchTranscripts ---

    @Test
    fun searchTranscriptsMatchesCaseInsensitiveTextContent() {
        val records = listOf(
            TestRecord("a", "Hello World", 1000),
            TestRecord("b", "Goodbye Moon", 2000),
            TestRecord("c", "hello sun", 3000),
        )
        val result = HistorySemantics.searchTranscripts(
            items = records,
            query = "hello",
            textExtractor = { it.text },
        )
        assertEquals(listOf("a", "c"), result.map { it.id })
    }

    @Test
    fun emptySearchReturnsAllTranscripts() {
        val records = listOf(
            TestRecord("a", "First", 1000),
            TestRecord("b", "Second", 2000),
        )
        val result = HistorySemantics.searchTranscripts(
            items = records,
            query = "",
            textExtractor = { it.text },
        )
        assertEquals(2, result.size)
    }

    // --- deduplicateTranscripts ---

    @Test
    fun deduplicateTranscriptsRemovesEntriesWithIdenticalTextAndTimestamp() {
        val records = listOf(
            TestRecord("a", "Same text", 1000),
            TestRecord("b", "Same text", 1000),
            TestRecord("c", "Different text", 1000),
        )
        val result = HistorySemantics.deduplicateTranscripts(
            items = records,
            textExtractor = { it.text },
            timeExtractor = { it.timestampMs },
            windowMs = 5000,
        )
        assertEquals(2, result.size)
        assertTrue(result.map { it.id }.contains("a"))
        assertTrue(result.map { it.id }.contains("c"))
    }

    @Test
    fun deduplicateTranscriptsKeepsEntriesOutsideTimeWindow() {
        val records = listOf(
            TestRecord("a", "Same text", 1000),
            TestRecord("b", "Same text", 10000),
        )
        val result = HistorySemantics.deduplicateTranscripts(
            items = records,
            textExtractor = { it.text },
            timeExtractor = { it.timestampMs },
            windowMs = 5000,
        )
        assertEquals(2, result.size)
    }

    // --- RELEVANCE sort ---

    @Test
    fun sortTranscriptsByRelevanceMaintainsOriginalOrder() {
        val records = listOf(
            TestRecord("a", "first", 1000),
            TestRecord("b", "second", 3000),
            TestRecord("c", "third", 2000),
        )
        val result = HistorySemantics.sortTranscripts(
            items = records,
            sortBy = HistorySemantics.SortOrder.RELEVANCE,
            timestampExtractor = { it.timestampMs },
        )
        assertEquals(listOf("a", "b", "c"), result.map { it.id })
    }
}
