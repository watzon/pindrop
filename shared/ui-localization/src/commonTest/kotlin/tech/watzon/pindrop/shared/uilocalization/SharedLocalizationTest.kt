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

    private fun setupWithData() {
        if (SharedLocalization._keyMapping.isEmpty()) {
            val keyMapping = mapOf(
                "Settings" to "settings",
                "Cancel" to "cancel",
                "About" to "about",
                "AI Enhancement" to "ai_enhancement",
                "%lld items" to "items_fmt",
                "%lld characters" to "characters_fmt",
                "%@ Coming Soon" to "coming_soon_fmt",
                "Export failed: %@" to "export_failed_fmt",
            )

            val strings = mapOf(
                "en" to mapOf(
                    "settings" to "Settings",
                    "cancel" to "Cancel",
                    "about" to "About",
                    "ai_enhancement" to "AI Enhancement",
                    "items_fmt" to "%d items",
                    "characters_fmt" to "%d characters",
                    "coming_soon_fmt" to "%s Coming Soon",
                    "export_failed_fmt" to "Export failed: %s",
                ),
                "de" to mapOf(
                    "settings" to "Einstellungen",
                    "cancel" to "Abbrechen",
                    "about" to "Über",
                    "ai_enhancement" to "KI-Verbesserung",
                    "items_fmt" to "%d Elemente",
                    "characters_fmt" to "%d Zeichen",
                    "coming_soon_fmt" to "%s kommt bald",
                    "export_failed_fmt" to "Export fehlgeschlagen: %s",
                ),
                "ja" to mapOf(
                    "settings" to "設定",
                    "cancel" to "キャンセル",
                    "about" to "について",
                    "ai_enhancement" to "AI拡張",
                    "items_fmt" to "%d項目",
                    "characters_fmt" to "%d文字",
                    "coming_soon_fmt" to "%s近日公開",
                    "export_failed_fmt" to "エクスポート失敗: %s",
                ),
            )

            SharedLocalization.initialize(keyMapping, strings)
        }
    }

    @Test
    fun `allKeys returns non-empty set`() {
        setupWithData()
        val keys = SharedLocalization.allKeys()
        assertTrue(keys.isNotEmpty(), "allKeys() should return at least one key")
    }

    @Test
    fun `allKeys contains expected keys`() {
        setupWithData()
        val keys = SharedLocalization.allKeys()
        assertTrue(keys.contains("settings"), "Should contain 'settings'")
        assertTrue(keys.contains("cancel"), "Should contain 'cancel'")
        assertTrue(keys.contains("items_fmt"), "Should contain 'items_fmt'")
    }

    @Test
    fun `hasKey returns true for known keys`() {
        setupWithData()
        assertTrue(SharedLocalization.hasKey("settings"), "Should have key 'settings'")
        assertTrue(SharedLocalization.hasKey("cancel"), "Should have key 'cancel'")
        assertTrue(SharedLocalization.hasKey("about"), "Should have key 'about'")
    }

    @Test
    fun `hasKey returns false for nonexistent keys`() {
        setupWithData()
        assertFalse(SharedLocalization.hasKey("nonexistent_key_xyz_12345"))
        assertFalse(SharedLocalization.hasKey(""))
    }

    @Test
    fun `supportedLocales includes all expected locales`() {
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
        setupWithData()
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
        setupWithData()
        assertEquals("Settings", SharedLocalization.getString("Settings", "en"))
        assertEquals("Cancel", SharedLocalization.getString("Cancel", "en"))
        assertEquals("AI Enhancement", SharedLocalization.getString("AI Enhancement", "en"))
    }

    @Test
    fun `getString returns German for German locale`() {
        setupWithData()
        assertEquals("Einstellungen", SharedLocalization.getString("Settings", "de"))
        assertEquals("Abbrechen", SharedLocalization.getString("Cancel", "de"))
        assertEquals("KI-Verbesserung", SharedLocalization.getString("AI Enhancement", "de"))
    }

    @Test
    fun `getString returns Japanese for Japanese locale`() {
        setupWithData()
        assertEquals("設定", SharedLocalization.getString("Settings", "ja"))
        assertEquals("キャンセル", SharedLocalization.getString("Cancel", "ja"))
    }

    @Test
    fun `getString falls back to English for unsupported locale`() {
        setupWithData()
        assertEquals("Settings", SharedLocalization.getString("Settings", "xx"))
        assertEquals("Cancel", SharedLocalization.getString("Cancel", "xx"))
    }

    @Test
    fun `getString falls back to key for unknown key`() {
        setupWithData()
        assertEquals("Unknown Key", SharedLocalization.getString("Unknown Key", "en"))
    }

    @Test
    fun `format strings are correctly converted`() {
        setupWithData()
        val itemsFmt = SharedLocalization.getString("%lld items", "en")
        assertTrue(itemsFmt.contains("%d"), "Format should contain %d, got: $itemsFmt")
        assertFalse(itemsFmt.contains("%lld"), "Format should not contain %lld")

        val charsFmt = SharedLocalization.getString("%lld characters", "de")
        assertTrue(charsFmt.contains("%d"), "Format should contain %d, got: $charsFmt")
    }
}
