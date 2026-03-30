package tech.watzon.pindrop.shared.core.platform

/**
 * macOS build shim for the shared core.
 *
 * The shipped macOS app stores secrets through native Swift services, so this
 * actual exists to keep the shared XCFramework buildable on Apple targets.
 */
actual class SecretStorage actual constructor() {
    private val store = mutableMapOf<Pair<String, String>, String>()

    actual fun storeSecret(account: String, service: String, value: String): Boolean {
        store[service to account] = value
        return true
    }

    actual fun retrieveSecret(account: String, service: String): String? {
        return store[service to account]
    }

    actual fun deleteSecret(account: String, service: String): Boolean {
        return store.remove(service to account) != null
    }
}
