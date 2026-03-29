package tech.watzon.pindrop.shared.core.platform

import java.io.File
import java.util.Properties

/**
 * JVM actual implementation of [SettingsPersistence] backed by a properties file.
 *
 * For JVM tests and development. The production Linux implementation uses TOML
 * (in linuxX64Main).
 */
actual class SettingsPersistence actual constructor(
    private val configDir: String
) {
    private val store = mutableMapOf<String, Any?>()
    private val settingsFile: File
        get() = File(configDir, "settings.properties")

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
        store.clear()
        if (!settingsFile.exists()) return
        val props = Properties()
        settingsFile.inputStream().use { props.load(it) }
        for (name in props.stringPropertyNames()) {
            val raw = props.getProperty(name)
            // Try to infer type from the stored string representation
            when {
                raw == "true" || raw == "false" -> store[name] = raw.toBoolean()
                raw.contains(".") && raw.toDoubleOrNull() != null -> store[name] = raw.toDouble()
                raw.toIntOrNull() != null -> store[name] = raw.toInt()
                else -> store[name] = raw
            }
        }
    }

    actual fun save() {
        val dir = File(configDir)
        if (!dir.exists()) dir.mkdirs()
        val props = Properties()
        for ((key, value) in store) {
            props.setProperty(key, value.toString())
        }
        settingsFile.outputStream().use { props.store(it, "Pindrop Settings") }
    }

    actual fun allSettings(): Map<String, Any?> = store.toMap()
}
