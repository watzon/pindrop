package tech.watzon.pindrop.shared.core.platform

/**
 * Platform-agnostic settings persistence interface.
 *
 * Each platform provides an `actual` implementation that reads/writes
 * settings from the platform's native store:
 * - macOS: UserDefaults (via @AppStorage)
 * - Linux: TOML file at ~/.config/pindrop/settings.toml
 * - Windows: Registry or JSON file (future)
 *
 * @param configDir Platform-specific config directory path.
 *   - Linux: ~/.config/pindrop
 *   - JVM tests: temp directory
 */
expect class SettingsPersistence(configDir: String) {

    fun getString(key: String): String?

    fun setString(key: String, value: String)

    fun getBool(key: String): Boolean?

    fun setBool(key: String, value: Boolean)

    fun getInt(key: String): Int?

    fun setInt(key: String, value: Int)

    fun getDouble(key: String): Double?

    fun setDouble(key: String, value: Double)

    fun remove(key: String)

    /**
     * Read all settings from the backing store into memory.
     */
    fun load()

    /**
     * Write all in-memory settings to the backing store.
     */
    fun save()

    /**
     * Return all currently loaded key-value pairs.
     */
    fun allSettings(): Map<String, Any?>
}
