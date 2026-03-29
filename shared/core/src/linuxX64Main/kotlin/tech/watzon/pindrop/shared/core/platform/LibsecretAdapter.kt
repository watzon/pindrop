@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.core.platform

import kotlinx.cinterop.*
import platform.posix.*

/**
 * Linux actual implementation of [SecretStorage] using libsecret with encrypted-file fallback.
 *
 * Primary: libsecret via GNOME Keyring (requires building on Linux host).
 * Fallback: key=value file at ~/.config/pindrop/secrets.enc when no keyring daemon is available.
 *
 * NOTE: The fallback is NOT encrypted in this initial implementation.
 * Production code should use libsodium or AES for proper encryption.
 */
actual class SecretStorage actual constructor() {

    actual fun storeSecret(account: String, service: String, value: String): Boolean {
        return trySecretStore(account, service, value)
    }

    actual fun retrieveSecret(account: String, service: String): String? {
        return trySecretRetrieve(account, service)
    }

    actual fun deleteSecret(account: String, service: String): Boolean {
        return trySecretDelete(account, service)
    }

    // --- libsecret primary (requires cinterop, only works when built on Linux) ---
    // When built on macOS (cross-compile), these stubs delegate to fallback.
    // On Linux host with libsecret headers, cinterop generates real bindings.

    private fun trySecretStore(account: String, service: String, value: String): Boolean {
        // TODO: Call secret_password_store_sync via cinterop when available
        return fallbackStore(account, service, value)
    }

    private fun trySecretRetrieve(account: String, service: String): String? {
        // TODO: Call secret_password_lookup_sync via cinterop when available
        return fallbackRetrieve(account, service)
    }

    private fun trySecretDelete(account: String, service: String): Boolean {
        // TODO: Call secret_password_clear_sync via cinterop when available
        return fallbackDelete(account, service)
    }

    // --- Encrypted-file fallback ---
    // TODO: Add proper encryption for production use (libsodium or AES).
    // This is a simple key=value placeholder that stores secrets in a local file.

    private val fallbackDir: String
        get() = (getEnv("HOME") ?: "/tmp") + "/.config/pindrop"

    private val secretsPath: String
        get() = "$fallbackDir/secrets.enc"

    private fun fallbackStore(account: String, service: String, value: String): Boolean {
        mkdirp(fallbackDir)
        val key = "$service:$account"
        val content = if (fileExists(secretsPath)) {
            readFileContent(secretsPath) ?: ""
        } else ""
        val updated = content.lines()
            .filter { !it.startsWith("$key=") }
            .plus("$key=$value")
            .joinToString("\n")
        writeFileContent(secretsPath, updated)
        return true
    }

    private fun fallbackRetrieve(account: String, service: String): String? {
        if (!fileExists(secretsPath)) return null
        val key = "$service:$account"
        val content = readFileContent(secretsPath) ?: return null
        for (line in content.lines()) {
            val eqIdx = line.indexOf('=')
            if (eqIdx < 0) continue
            if (line.substring(0, eqIdx).trim() == key) {
                return line.substring(eqIdx + 1).trim()
            }
        }
        return null
    }

    private fun fallbackDelete(account: String, service: String): Boolean {
        if (!fileExists(secretsPath)) return false
        val key = "$service:$account"
        val content = readFileContent(secretsPath) ?: return false
        val remaining = content.lines().filter { !it.startsWith("$key=") }
        if (remaining.size == content.lines().size) return false
        writeFileContent(secretsPath, remaining.joinToString("\n"))
        return true
    }

    // --- Helpers ---

    private fun getEnv(name: String): String? {
        return getenv(name)?.toKString()
    }

    private fun fileExists(path: String): Boolean {
        return access(path, F_OK) == 0
    }

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
