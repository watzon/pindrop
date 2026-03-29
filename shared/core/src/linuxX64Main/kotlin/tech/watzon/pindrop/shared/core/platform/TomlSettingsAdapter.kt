@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.core.platform

import kotlinx.cinterop.*
import platform.posix.*

/**
 * Linux actual implementation of [SettingsPersistence] using TOML at
 * ~/.config/pindrop/settings.toml.
 *
 * Uses a simple key=value format that is a valid TOML subset.
 * A full TOML library can be swapped in later if more complex structures are needed.
 */
actual class SettingsPersistence actual constructor(
    private val configDir: String
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
        store.clear()
        val filePath = "$configDir/settings.toml"
        val content = readFileContent(filePath) ?: return
        for (line in content.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
            val eqIdx = trimmed.indexOf('=')
            if (eqIdx < 0) continue
            val key = trimmed.substring(0, eqIdx).trim()
            val rawValue = trimmed.substring(eqIdx + 1).trim()
            val value = if (rawValue.startsWith("\"") && rawValue.endsWith("\"")) {
                rawValue.substring(1, rawValue.length - 1)
            } else {
                rawValue
            }
            when {
                value == "true" -> store[key] = true
                value == "false" -> store[key] = false
                value.contains(".") && value.toDoubleOrNull() != null -> store[key] = value.toDouble()
                value.toIntOrNull() != null -> store[key] = value.toInt()
                else -> store[key] = value
            }
        }
    }

    actual fun save() {
        val filePath = "$configDir/settings.toml"
        mkdirp(configDir)
        val lines = mutableListOf("# Pindrop Settings", "# Auto-generated", "")
        for (entry in store.entries.sortedBy { it.key }) {
            val serialized = when (val value = entry.value) {
                is String -> "\"$value\""
                is Boolean -> value.toString()
                is Number -> value.toString()
                else -> "\"$value\""
            }
            lines.add("${entry.key} = $serialized")
        }
        writeFileContent(filePath, lines.joinToString("\n"))
    }

    actual fun allSettings(): Map<String, Any?> = store.toMap()

    // --- File I/O helpers using Kotlin/Native POSIX ---

    private fun readFileContent(path: String): String? {
        val file = fopen(path, "r") ?: return null
        try {
            val builder = StringBuilder()
            val buffer = ByteArray(4096)
            buffer.usePinned { pinned ->
                while (true) {
                    val bytesRead = fread(pinned.addressOf(0), 1u, buffer.size.toULong(), file)
                    if (bytesRead == 0uL) break
                    builder.append(buffer.decodeToString(0, bytesRead.toInt()))
                }
            }
            return if (builder.isEmpty()) null else builder.toString()
        } finally {
            fclose(file)
        }
    }

    private fun writeFileContent(path: String, content: String) {
        val file = fopen(path, "w") ?: return
        try {
            val bytes = content.encodeToByteArray()
            bytes.usePinned { pinned ->
                fwrite(pinned.addressOf(0), 1u, bytes.size.toULong(), file)
            }
        } finally {
            fclose(file)
        }
    }

    private fun mkdirp(dirPath: String) {
        val parts = dirPath.split("/")
        var current = ""
        for (part in parts) {
            if (part.isEmpty()) continue
            current += "/$part"
            mkdir(current, 0x1EDu) // 0755 = rwxr-xr-x
        }
    }
}
