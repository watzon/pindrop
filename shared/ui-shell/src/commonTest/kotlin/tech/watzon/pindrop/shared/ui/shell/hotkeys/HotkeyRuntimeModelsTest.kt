package tech.watzon.pindrop.shared.ui.shell.hotkeys

import tech.watzon.pindrop.shared.feature.transcription.HotkeyBinding
import tech.watzon.pindrop.shared.feature.transcription.HotkeyMode
import tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HotkeyRuntimeModelsTest {
    @Test
    fun requestedBindingsMapToVisibleRuntimeStates() {
        val toggle = HotkeyRequestedBinding(
            mode = HotkeyMode.TOGGLE,
            binding = HotkeyBinding(
                key = "R",
                modifiers = setOf(HotkeyModifier.CTRL, HotkeyModifier.SHIFT),
            ),
        )
        val pushToTalk = HotkeyRequestedBinding(
            mode = HotkeyMode.PUSH_TO_TALK,
            binding = HotkeyBinding(key = "Space"),
        )

        val active = toggle.toRuntimeStatus(
            backend = HotkeyRuntimeBackendId.X11,
            result = HotkeyBindingRegistrationResult.Active,
        )
        val unavailable = pushToTalk.toRuntimeStatus(
            backend = HotkeyRuntimeBackendId.UNAVAILABLE,
            result = HotkeyBindingRegistrationResult.Unavailable("Use the tray or fallback window on this desktop session."),
        )
        val failed = toggle.toRuntimeStatus(
            backend = HotkeyRuntimeBackendId.PORTAL,
            result = HotkeyBindingRegistrationResult.Failed("Shortcut is already in use by another app."),
        )
        val notConfigured = HotkeyRequestedBinding(
            mode = HotkeyMode.PUSH_TO_TALK,
            binding = null,
        ).toRuntimeStatus(
            backend = HotkeyRuntimeBackendId.UNAVAILABLE,
            result = HotkeyBindingRegistrationResult.NotConfigured,
        )

        assertEquals(HotkeyBindingRuntimeState.ACTIVE, active.state)
        assertEquals(HotkeyRuntimeBackendId.X11, active.backend.id)
        assertEquals("Active", active.statusLabel)
        assertEquals(HotkeyBindingRuntimeState.UNAVAILABLE, unavailable.state)
        assertEquals(HotkeyRuntimeBackendId.UNAVAILABLE, unavailable.backend.id)
        assertTrue((unavailable.message ?: "").contains("tray or fallback", ignoreCase = true))
        assertEquals(HotkeyBindingRuntimeState.FAILED_TO_BIND, failed.state)
        assertEquals(HotkeyRuntimeBackendId.PORTAL, failed.backend.id)
        assertEquals("Failed to bind", failed.statusLabel)
        assertEquals(HotkeyBindingRuntimeState.NOT_CONFIGURED, notConfigured.state)
        assertEquals("Not configured", notConfigured.statusLabel)
    }

    @Test
    fun actionRoutingDistinguishesToggleFromPushToTalkPressAndRelease() {
        assertEquals(
            HotkeyRuntimeInvocation.ToggleRecording,
            HotkeyRuntimeActions.route(
                actionId = HotkeyRuntimeActionId.ToggleRecording.rawValue,
                phase = HotkeyRuntimeEventPhase.ACTIVATED,
            ),
        )
        assertNull(
            HotkeyRuntimeActions.route(
                actionId = HotkeyRuntimeActionId.ToggleRecording.rawValue,
                phase = HotkeyRuntimeEventPhase.DEACTIVATED,
            ),
        )
        assertEquals(
            HotkeyRuntimeInvocation.PushToTalkPressed,
            HotkeyRuntimeActions.route(
                actionId = HotkeyRuntimeActionId.PushToTalk.rawValue,
                phase = HotkeyRuntimeEventPhase.ACTIVATED,
            ),
        )
        assertEquals(
            HotkeyRuntimeInvocation.PushToTalkReleased,
            HotkeyRuntimeActions.route(
                actionId = HotkeyRuntimeActionId.PushToTalk.rawValue,
                phase = HotkeyRuntimeEventPhase.DEACTIVATED,
            ),
        )
    }

    @Test
    fun capabilitySelectionPrefersX11ThenPortalThenUnavailableGuidance() {
        val x11 = HotkeyRuntimeCapabilities.selectBackend(
            display = ":0",
            portalGlobalShortcutsSupported = true,
        )
        val portal = HotkeyRuntimeCapabilities.selectBackend(
            display = null,
            portalGlobalShortcutsSupported = true,
        )
        val unavailable = HotkeyRuntimeCapabilities.selectBackend(
            display = null,
            portalGlobalShortcutsSupported = false,
        )

        assertEquals(HotkeyRuntimeBackendId.X11, x11.backend)
        assertEquals(HotkeyRuntimeBackendId.PORTAL, portal.backend)
        assertEquals(HotkeyRuntimeBackendId.UNAVAILABLE, unavailable.backend)
        assertTrue((unavailable.guidance ?: "").contains("tray", ignoreCase = true))
    }
}
