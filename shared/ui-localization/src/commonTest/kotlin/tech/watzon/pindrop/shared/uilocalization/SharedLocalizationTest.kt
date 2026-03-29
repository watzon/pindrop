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
import kotlin.test.assertEquals

class SharedLocalizationTest {

    @Test
    fun `allKeys returns non-empty set`() {
        val keys = SharedLocalization.allKeys()
        assertTrue(keys.isNotEmpty(), "allKeys() should return at least one key")
    }

    @Test
    fun `allKeys contains expected minimum count`() {
        val keys = SharedLocalization.allKeys()
        // The xcstrings catalog has 606 keys
        assertTrue(
            keys.size >= 500,
            "Expected at least 500 keys, got ${keys.size}"
        )
    }

    @Test
    fun `hasKey returns true for known short keys`() {
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
        assertTrue(
            keys.any { it.contains("items") },
            "Should contain a key for items format"
        )
        assertTrue(
            keys.any { it.contains("characters") },
            "Should contain a key for characters format"
        )
    }

    @Test
    fun `supportedLocales includes all 11 locales`() {
        val locales = SharedLocalization.supportedLocales()
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
        assertEquals(11, locales.size, "Should have exactly 11 locales")
    }

    @Test
    fun `keyMapping is bidirectional`() {
        val mapping = SharedLocalization.keyMapping()
        for ((xcKey, kmpId) in mapping) {
            assertTrue(
                kmpId.matches(Regex("[a-z][a-z0-9_]*")),
                "KMP identifier '$kmpId' for key '${xcKey.take(40)}' should be valid snake_case"
            )
        }
    }

    @Test
    fun `getString returns English for English locale`() {
        assertEquals("Settings", SharedLocalization.getString("Settings", "en"))
        assertEquals("Cancel", SharedLocalization.getString("Cancel", "en"))
    }

    @Test
    fun `getString returns German for German locale`() {
        assertEquals("Einstellungen", SharedLocalization.getString("Settings", "de"))
        assertEquals("Abbrechen", SharedLocalization.getString("Cancel", "de"))
    }

    @Test
    fun `getString returns Japanese for Japanese locale`() {
        assertEquals("設定", SharedLocalization.getString("Settings", "ja"))
        assertEquals("キャンセル", SharedLocalization.getString("Cancel", "ja"))
    }

    @Test
    fun `getString falls back to English for unsupported locale`() {
        assertEquals("Settings", SharedLocalization.getString("Settings", "xx"))
        assertEquals("Cancel", SharedLocalization.getString("Cancel", "xx"))
    }

    @Test
    fun `getString falls back to key for unknown key`() {
        assertEquals("Unknown Key", SharedLocalization.getString("Unknown Key", "en"))
    }

    @Test
    fun `format specifiers correctly converted`() {
        val itemsValue = SharedLocalization.getString("%lld items", "en")
        assertTrue(itemsValue.contains("%d"), "Should contain %d, got: $itemsValue")
        assertFalse(itemsValue.contains("%lld"), "Should not contain %lld")
    }
}
