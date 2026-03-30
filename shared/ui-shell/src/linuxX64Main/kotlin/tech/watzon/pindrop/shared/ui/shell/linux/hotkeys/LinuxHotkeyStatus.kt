package tech.watzon.pindrop.shared.ui.shell.linux.hotkeys

import platform.posix.getenv
import tech.watzon.pindrop.shared.feature.transcription.HotkeyBinding
import tech.watzon.pindrop.shared.feature.transcription.HotkeyMode
import tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyBindingRegistrationResult
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyBindingRuntimeStatus
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRequestedBinding
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeBackendId
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeCapabilities
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString

data class LinuxHotkeyBindingSnapshot(
    val backend: HotkeyRuntimeBackendId,
    val toggle: HotkeyBindingRuntimeStatus,
    val pushToTalk: HotkeyBindingRuntimeStatus,
    val guidance: String? = null,
) {
    val statuses: List<HotkeyBindingRuntimeStatus> = listOf(toggle, pushToTalk)
}

object LinuxHotkeyStatus {
    fun previewSnapshot(
        toggleHotkey: String?,
        pushToTalkHotkey: String?,
    ): LinuxHotkeyBindingSnapshot {
        val capability = HotkeyRuntimeCapabilities.selectBackend(
            display = displayEnv(),
            portalGlobalShortcutsSupported = portalGlobalShortcutsSupported(),
        )

        val toggleStatus = previewStatus(HotkeyMode.TOGGLE, toggleHotkey, capability.backend, capability.guidance)
        val pushToTalkStatus = previewStatus(HotkeyMode.PUSH_TO_TALK, pushToTalkHotkey, capability.backend, capability.guidance)
        return LinuxHotkeyBindingSnapshot(
            backend = capability.backend,
            toggle = toggleStatus,
            pushToTalk = pushToTalkStatus,
            guidance = capability.guidance ?: firstGuidance(toggleStatus, pushToTalkStatus),
        )
    }

    fun parseBinding(raw: String?): HotkeyBinding? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) {
            return null
        }

        val modifiers = mutableSetOf<HotkeyModifier>()
        var remainder = value
        val symbolicModifiers = listOf(
            "⌃" to HotkeyModifier.CTRL,
            "⌥" to HotkeyModifier.ALT,
            "⇧" to HotkeyModifier.SHIFT,
            "⌘" to HotkeyModifier.META,
        )

        var matchedSymbol = true
        while (matchedSymbol) {
            matchedSymbol = false
            for ((symbol, modifier) in symbolicModifiers) {
                if (remainder.startsWith(symbol)) {
                    modifiers += modifier
                    remainder = remainder.removePrefix(symbol).trim()
                    matchedSymbol = true
                }
            }
        }

        val tokens = remainder.split('+').map { it.trim() }.filter { it.isNotEmpty() }
        if (tokens.size > 1) {
            tokens.dropLast(1).forEach { token ->
                when (token.lowercase()) {
                    "ctrl", "control" -> modifiers += HotkeyModifier.CTRL
                    "alt", "option" -> modifiers += HotkeyModifier.ALT
                    "shift" -> modifiers += HotkeyModifier.SHIFT
                    "cmd", "command", "meta", "super" -> modifiers += HotkeyModifier.META
                }
            }
            remainder = tokens.last()
        }

        val normalizedKey = normalizeKey(remainder)
        if (normalizedKey.isEmpty()) {
            return null
        }

        return HotkeyBinding(
            key = normalizedKey,
            modifiers = modifiers,
        )
    }

    fun formatMenuLabel(title: String, status: HotkeyBindingRuntimeStatus): String {
        return "$title: ${status.statusLabel}${backendSuffix(status)}"
    }

    fun formatFallbackSummary(snapshot: LinuxHotkeyBindingSnapshot): String {
        return listOf(
            formatMenuLabel("Toggle Shortcut", snapshot.toggle),
            formatMenuLabel("Push-to-Talk", snapshot.pushToTalk),
        ).joinToString("\n")
    }

    fun formatSettingsLabel(title: String, status: HotkeyBindingRuntimeStatus): String {
        val message = status.message?.takeIf { it.isNotBlank() }
        return if (message == null) {
            formatMenuLabel(title, status)
        } else {
            "${formatMenuLabel(title, status)} — $message"
        }
    }

    @OptIn(ExperimentalForeignApi::class)
    fun displayEnv(): String? = getenv("DISPLAY")?.toKString()

    @OptIn(ExperimentalForeignApi::class)
    fun portalGlobalShortcutsSupported(): Boolean {
        val sessionType = getenv("XDG_SESSION_TYPE")?.toKString()?.lowercase()
        val hasDbus = getenv("DBUS_SESSION_BUS_ADDRESS")?.toKString()?.isNotBlank() == true
        return sessionType == "wayland" && hasDbus
    }

    private fun previewStatus(
        mode: HotkeyMode,
        rawBinding: String?,
        backend: HotkeyRuntimeBackendId,
        guidance: String?,
    ): HotkeyBindingRuntimeStatus {
        val requestedBinding = HotkeyRequestedBinding(mode = mode, binding = parseBinding(rawBinding))
        val result = when {
            requestedBinding.binding == null -> HotkeyBindingRegistrationResult.NotConfigured
            backend == HotkeyRuntimeBackendId.UNAVAILABLE -> HotkeyBindingRegistrationResult.Unavailable(
                guidance ?: "Use the tray or fallback window instead.",
            )
            backend == HotkeyRuntimeBackendId.PORTAL -> HotkeyBindingRegistrationResult.Unavailable(
                "Wayland shortcut activation depends on desktop portal support. Use the tray or fallback window if binding fails.",
            )
            else -> HotkeyBindingRegistrationResult.Active
        }
        return requestedBinding.toRuntimeStatus(backend = backend, result = result)
    }

    private fun backendSuffix(status: HotkeyBindingRuntimeStatus): String {
        return when (status.backend.id) {
            HotkeyRuntimeBackendId.X11 -> " (x11)"
            HotkeyRuntimeBackendId.PORTAL -> " (portal)"
            HotkeyRuntimeBackendId.UNAVAILABLE -> ""
        }
    }

    private fun normalizeKey(raw: String): String {
        val trimmed = raw.trim()
        return when {
            trimmed.equals("space", ignoreCase = true) -> "Space"
            trimmed.length == 1 -> trimmed.uppercase()
            else -> trimmed
        }
    }

    private fun firstGuidance(vararg statuses: HotkeyBindingRuntimeStatus): String? {
        return statuses.firstNotNullOfOrNull { it.message?.takeIf(String::isNotBlank) }
    }
}
