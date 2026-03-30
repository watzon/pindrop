package tech.watzon.pindrop.shared.core.platform

/**
 * macOS build shim for the shared core.
 *
 * The shipped macOS app persists settings through native Swift stores, so this
 * actual only needs lightweight in-memory behavior for KMP compilation.
 */
actual class SettingsPersistence actual constructor(
    @Suppress("UNUSED_PARAMETER") private val configDir: String
) {
    private val store = mutableMapOf<String, Any?>()

    actual fun getString(key: String): String? = store[key] as? String

    actual fun setString(key: String, value: String) {
        store[key] = value
    }

    actual fun getBool(key: String): Boolean? = store[key] as? Boolean

    actual fun setBool(key: String, value: Boolean) {
        store[key] = value
    }

    actual fun getInt(key: String): Int? = store[key] as? Int

    actual fun setInt(key: String, value: Int) {
        store[key] = value
    }

    actual fun getDouble(key: String): Double? = store[key] as? Double

    actual fun setDouble(key: String, value: Double) {
        store[key] = value
    }

    actual fun remove(key: String) {
        store.remove(key)
    }

    actual fun load() {
        // No-op: macOS app persistence stays in native Swift code.
    }

    actual fun save() {
        // No-op: macOS app persistence stays in native Swift code.
    }

    actual fun allSettings(): Map<String, Any?> = store.toMap()
}
