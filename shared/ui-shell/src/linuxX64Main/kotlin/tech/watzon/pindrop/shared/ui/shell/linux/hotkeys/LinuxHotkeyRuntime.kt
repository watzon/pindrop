package tech.watzon.pindrop.shared.ui.shell.linux.hotkeys

import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyBindingRuntimeStatus
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeActions
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeCapabilities
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeInvocation
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeBackendId
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRequestedBinding
import tech.watzon.pindrop.shared.feature.transcription.HotkeyMode

class LinuxHotkeyRuntime(
    private val onInvocation: (HotkeyRuntimeInvocation) -> Unit,
) {
    private val capability = HotkeyRuntimeCapabilities.selectBackend(
        display = LinuxHotkeyStatus.displayEnv(),
        portalGlobalShortcutsSupported = LinuxHotkeyStatus.portalGlobalShortcutsSupported(),
    )

    private val backend: LinuxHotkeyBackend = when (capability.backend) {
        HotkeyRuntimeBackendId.X11 -> LinuxX11HotkeyBackend(
            displayName = LinuxHotkeyStatus.displayEnv() ?: ":0",
            onEvent = ::dispatchEvent,
        )
        HotkeyRuntimeBackendId.PORTAL -> LinuxPortalHotkeyBackend()
        HotkeyRuntimeBackendId.UNAVAILABLE -> LinuxUnavailableHotkeyBackend(
            capability.guidance ?: "Use the tray or fallback window instead.",
        )
    }

    var snapshot: LinuxHotkeyBindingSnapshot = LinuxHotkeyStatus.previewSnapshot(
        toggleHotkey = null,
        pushToTalkHotkey = null,
    )
        private set

    fun refreshBindings(toggleHotkey: String?, pushToTalkHotkey: String?): LinuxHotkeyBindingSnapshot {
        backend.unregisterAll()

        val toggleStatus = registerBinding(HotkeyMode.TOGGLE, toggleHotkey)
        val pushToTalkStatus = registerBinding(HotkeyMode.PUSH_TO_TALK, pushToTalkHotkey)
        snapshot = LinuxHotkeyBindingSnapshot(
            backend = backend.backendId,
            toggle = toggleStatus,
            pushToTalk = pushToTalkStatus,
            guidance = capability.guidance ?: listOf(toggleStatus, pushToTalkStatus).firstNotNullOfOrNull { it.message },
        )
        return snapshot
    }

    fun dispose() {
        backend.dispose()
    }

    private fun registerBinding(mode: HotkeyMode, rawBinding: String?): HotkeyBindingRuntimeStatus {
        val requestedBinding = HotkeyRequestedBinding(
            mode = mode,
            binding = LinuxHotkeyStatus.parseBinding(rawBinding),
        )
        val result = when {
            requestedBinding.binding == null -> tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyBindingRegistrationResult.NotConfigured
            else -> backend.register(requestedBinding)
        }
        return requestedBinding.toRuntimeStatus(backend = backend.backendId, result = result)
    }

    private fun dispatchEvent(actionId: String, phase: tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeEventPhase) {
        HotkeyRuntimeActions.route(actionId = actionId, phase = phase)?.let(onInvocation)
    }
}
