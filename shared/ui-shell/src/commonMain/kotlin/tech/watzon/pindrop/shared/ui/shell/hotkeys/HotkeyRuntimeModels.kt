package tech.watzon.pindrop.shared.ui.shell.hotkeys

import tech.watzon.pindrop.shared.feature.transcription.HotkeyBinding
import tech.watzon.pindrop.shared.feature.transcription.HotkeyMode

enum class HotkeyRuntimeBackendId(val id: String) {
    X11("x11"),
    PORTAL("portal"),
    UNAVAILABLE("unavailable"),
}

enum class HotkeyBindingRuntimeState {
    ACTIVE,
    UNAVAILABLE,
    FAILED_TO_BIND,
    NOT_CONFIGURED,
}

enum class HotkeyRuntimeActionId(val rawValue: String) {
    ToggleRecording("toggle-recording"),
    PushToTalk("push-to-talk"),
}

enum class HotkeyRuntimeEventPhase {
    ACTIVATED,
    DEACTIVATED,
}

sealed interface HotkeyRuntimeInvocation {
    data object ToggleRecording : HotkeyRuntimeInvocation
    data object PushToTalkPressed : HotkeyRuntimeInvocation
    data object PushToTalkReleased : HotkeyRuntimeInvocation
}

data class HotkeyRequestedBinding(
    val mode: HotkeyMode,
    val binding: HotkeyBinding?,
) {
    val actionId: HotkeyRuntimeActionId = when (mode) {
        HotkeyMode.TOGGLE -> HotkeyRuntimeActionId.ToggleRecording
        HotkeyMode.PUSH_TO_TALK -> HotkeyRuntimeActionId.PushToTalk
    }

    fun toRuntimeStatus(
        backend: HotkeyRuntimeBackendId,
        result: HotkeyBindingRegistrationResult,
    ): HotkeyBindingRuntimeStatus {
        val state = when (result) {
            HotkeyBindingRegistrationResult.Active -> HotkeyBindingRuntimeState.ACTIVE
            is HotkeyBindingRegistrationResult.Unavailable -> HotkeyBindingRuntimeState.UNAVAILABLE
            is HotkeyBindingRegistrationResult.Failed -> HotkeyBindingRuntimeState.FAILED_TO_BIND
            HotkeyBindingRegistrationResult.NotConfigured -> HotkeyBindingRuntimeState.NOT_CONFIGURED
        }

        val statusLabel = when (state) {
            HotkeyBindingRuntimeState.ACTIVE -> "Active"
            HotkeyBindingRuntimeState.UNAVAILABLE -> "Unavailable"
            HotkeyBindingRuntimeState.FAILED_TO_BIND -> "Failed to bind"
            HotkeyBindingRuntimeState.NOT_CONFIGURED -> "Not configured"
        }

        val message = when (result) {
            HotkeyBindingRegistrationResult.Active -> null
            is HotkeyBindingRegistrationResult.Unavailable -> result.reason
            is HotkeyBindingRegistrationResult.Failed -> result.reason
            HotkeyBindingRegistrationResult.NotConfigured -> "Set a shortcut to enable this action."
        }

        return HotkeyBindingRuntimeStatus(
            requestedBinding = this,
            backend = HotkeyBindingRuntimeBackend(backend),
            state = state,
            statusLabel = statusLabel,
            message = message,
        )
    }
}

data class HotkeyBindingRuntimeBackend(
    val id: HotkeyRuntimeBackendId,
)

data class HotkeyBindingRuntimeStatus(
    val requestedBinding: HotkeyRequestedBinding,
    val backend: HotkeyBindingRuntimeBackend,
    val state: HotkeyBindingRuntimeState,
    val statusLabel: String,
    val message: String?,
)

sealed interface HotkeyBindingRegistrationResult {
    data object Active : HotkeyBindingRegistrationResult
    data class Unavailable(val reason: String) : HotkeyBindingRegistrationResult
    data class Failed(val reason: String) : HotkeyBindingRegistrationResult
    data object NotConfigured : HotkeyBindingRegistrationResult
}

data class HotkeyBackendCapability(
    val backend: HotkeyRuntimeBackendId,
    val guidance: String? = null,
)

object HotkeyRuntimeCapabilities {
    private const val unsupportedGuidance =
        "Global shortcuts are unavailable in this environment. Use the tray or fallback window instead."

    fun selectBackend(
        display: String?,
        portalGlobalShortcutsSupported: Boolean,
    ): HotkeyBackendCapability {
        return when {
            !display.isNullOrBlank() -> HotkeyBackendCapability(backend = HotkeyRuntimeBackendId.X11)
            portalGlobalShortcutsSupported -> HotkeyBackendCapability(backend = HotkeyRuntimeBackendId.PORTAL)
            else -> HotkeyBackendCapability(
                backend = HotkeyRuntimeBackendId.UNAVAILABLE,
                guidance = unsupportedGuidance,
            )
        }
    }
}

object HotkeyRuntimeActions {
    fun route(actionId: String, phase: HotkeyRuntimeEventPhase): HotkeyRuntimeInvocation? {
        return when (actionId) {
            HotkeyRuntimeActionId.ToggleRecording.rawValue -> {
                if (phase == HotkeyRuntimeEventPhase.ACTIVATED) HotkeyRuntimeInvocation.ToggleRecording else null
            }

            HotkeyRuntimeActionId.PushToTalk.rawValue -> when (phase) {
                HotkeyRuntimeEventPhase.ACTIVATED -> HotkeyRuntimeInvocation.PushToTalkPressed
                HotkeyRuntimeEventPhase.DEACTIVATED -> HotkeyRuntimeInvocation.PushToTalkReleased
            }

            else -> null
        }
    }
}
