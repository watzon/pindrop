package tech.watzon.pindrop.shared.core.platform

/**
 * macOS build shim for the shared core.
 *
 * The shipped macOS app owns launch-at-login natively in Swift, so this actual
 * only needs to satisfy shared-core native compilation.
 */
actual class AutostartManager actual constructor(
    @Suppress("UNUSED_PARAMETER") private val autostartDir: String
) {
    private var isEnabled = false

    actual fun enableAutostart(): Boolean {
        isEnabled = true
        return true
    }

    actual fun disableAutostart(): Boolean {
        isEnabled = false
        return true
    }

    actual fun isAutostartEnabled(): Boolean = isEnabled
}
