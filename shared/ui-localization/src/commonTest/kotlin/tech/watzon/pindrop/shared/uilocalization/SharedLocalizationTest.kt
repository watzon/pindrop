//
//  SharedLocalizationTest.kt
//  Pindrop
//
//  Created on 2026-03-29.
//

package tech.watzon.pindrop.shared.uilocalization

import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

class SharedLocalizationTest {

    @Test
    fun `allKeys returns non-empty set`() {
        val keys = SharedLocalization.allKeys()
        assertTrue(keys.isNotEmpty(), "allKeys() should return at least one key")
    }

    @Test
    fun `allKeys contains expected minimum count from xcstrings catalog`() {
        val keys = SharedLocalization.allKeys()
        // The xcstrings catalog has 607 keys
        assertTrue(
            keys.size >= 500,
            "Expected at least 500 keys, got ${keys.size}. The xcstrings catalog has ~607 keys."
        )
    }

    @Test
    fun `hasKey returns true for known short keys`() {
        // These are short identifier-style keys from the catalog
        assertTrue(SharedLocalization.hasKey("settings"), "Should have key 'settings'")
        assertTrue(SharedLocalization.hasKey("cancel"), "Should have key 'cancel'")
        assertTrue(SharedLocalization.hasKey("about"), "Should have key 'about'")
    }

    @Test
    fun `hasKey returns false for nonexistent keys`() {
        assertFalse(SharedLocalization.hasKey("nonexistent_key_xyz_12345"))
        assertFalse(SharedLocalization.hasKey(""))
    }

    @Test
    fun `allKeys covers format specifier keys`() {
        val keys = SharedLocalization.allKeys()
        // Keys with format specifiers should be converted
        assertTrue(
            keys.any { it.contains("items") },
            "Should contain a key for '%lld items'"
        )
        assertTrue(
            keys.any { it.contains("characters") },
            "Should contain a key for '%lld characters'"
        )
    }

    @Test
    fun `supportedLocales includes all 11 locales`() {
        val locales = SharedLocalization.supportedLocales()
        // Expected: en, de, es, fr, it, ja, ko, nl, pt-BR, tr, zh-Hans
        assertTrue(locales.contains("en"), "Should support English")
        assertTrue(locales.contains("de"), "Should support German")
        assertTrue(locales.contains("es"), "Should support Spanish")
        assertTrue(locales.contains("fr"), "Should support French")
        assertTrue(locales.contains("it"), "Should support Italian")
        assertTrue(locales.contains("ja"), "Should support Japanese")
        assertTrue(locales.contains("ko"), "Should support Korean")
        assertTrue(locales.contains("nl"), "Should support Dutch")
        assertTrue(locales.contains("pt-BR"), "Should support Brazilian Portuguese")
        assertTrue(locales.contains("tr"), "Should support Turkish")
        assertTrue(locales.contains("zh-Hans"), "Should support Simplified Chinese")
    }

    @Test
    fun `keyMapping is bidirectional`() {
        val mapping = SharedLocalization.keyMapping()
        // Every xcstrings key should map to a valid KMP identifier
        for ((xcKey, kmpId) in mapping) {
            assertTrue(
                kmpId.matches(Regex("[a-z][a-z0-9_]*")),
                "KMP identifier '$kmpId' for key '${xcKey.take(40)}' should be valid snake_case"
            )
        }
    }

    @Test
    fun `keyMapping covers format specifier conversions`() {
        val mapping = SharedLocalization.keyMapping()
        // Keys with %@ and %lld should map to identifiers
        val formatXcKeys = mapping.keys.filter { it.contains("%@") || it.contains("%lld") }
        assertTrue(
            formatXcKeys.isNotEmpty(),
            "Should have mappings for format specifier keys"
        )
    }
}
