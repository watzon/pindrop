package tech.watzon.pindrop.shared.core.platform

/**
 * Platform-agnostic secure credential storage interface.
 *
 * Each platform provides an `actual` implementation:
 * - macOS: Keychain Services
 * - Linux: libsecret (GNOME Keyring) with encrypted-file fallback
 * - Windows: Windows Credential Manager (future)
 */
expect class SecretStorage() {

    /**
     * Store a secret value for the given account and service.
     * @return true if the secret was stored successfully.
     */
    fun storeSecret(account: String, service: String, value: String): Boolean

    /**
     * Retrieve a secret value for the given account and service.
     * @return the secret value, or null if not found.
     */
    fun retrieveSecret(account: String, service: String): String?

    /**
     * Delete the secret for the given account and service.
     * @return true if the secret was deleted (or didn't exist).
     */
    fun deleteSecret(account: String, service: String): Boolean
}
