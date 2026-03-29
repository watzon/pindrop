package tech.watzon.pindrop.shared.core.platform

/**
 * JVM actual implementation of [SecretStorage] backed by an in-memory map.
 *
 * For JVM tests only. The production Linux implementation uses libsecret
 * (in linuxX64Main).
 */
actual class SecretStorage actual constructor() {

    private val store = mutableMapOf<Pair<String, String>, String>()

    actual fun storeSecret(account: String, service: String, value: String): Boolean {
        store[Pair(account, service)] = value
        return true
    }

    actual fun retrieveSecret(account: String, service: String): String? {
        return store[Pair(account, service)]
    }

    actual fun deleteSecret(account: String, service: String): Boolean {
        return store.remove(Pair(account, service)) != null
    }
}
