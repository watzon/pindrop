//
//  SharedLocalization.kt
//  Pindrop
//
//  Created on 2026-03-29.
//

package tech.watzon.pindrop.shared.uilocalization

/**
 * Shared localization authority.
 *
 * Provides runtime verification of key coverage and locale support
 * for the KMP Multiplatform Resources-based localization system.
 * Actual string access is via generated `Res.string.*` accessors.
 */
object SharedLocalization {

    /**
     * Returns all KMP resource string identifiers generated from the xcstrings catalog.
     * These correspond to `Res.string.{identifier}` accessors.
     */
    fun allKeys(): Set<String> {
        return _keyMapping.values.toSet()
    }

    /**
     * Check if a given KMP identifier exists in the generated resources.
     */
    fun hasKey(key: String): Boolean {
        return _keyMapping.values.contains(key)
    }

    /**
     * Returns the set of supported locale codes.
     * Includes: en, de, es, fr, it, ja, ko, nl, pt-BR, tr, zh-Hans
     */
    fun supportedLocales(): Set<String> {
        return setOf(
            "en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "tr", "zh-Hans"
        )
    }

    /**
     * Returns the bidirectional mapping from xcstrings keys to KMP resource identifiers.
     * Key: original xcstrings key (English text or short identifier)
     * Value: generated KMP snake_case identifier (usable as Res.string.{value})
     */
    fun keyMapping(): Map<String, String> {
        return _keyMapping.toMap()
    }

    /**
     * Look up a KMP identifier from an xcstrings key.
     */
    fun kmpIdentifierForXcKey(xcKey: String): String? {
        return _keyMapping[xcKey]
    }

    /**
     * Look up an xcstrings key from a KMP identifier.
     */
    fun xcKeyForKmpIdentifier(kmpId: String): String? {
        return _reverseMapping[kmpId]
    }
}
