@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.hotkeys

import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import platform.posix.usleep
import tech.watzon.pindrop.shared.feature.transcription.HotkeyBinding
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyBindingRegistrationResult
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRequestedBinding
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeBackendId
import tech.watzon.pindrop.shared.ui.shell.hotkeys.HotkeyRuntimeEventPhase
import tech.watzon.pindrop.shared.uishell.cinterop.x11.*

interface LinuxHotkeyBackend {
    val backendId: HotkeyRuntimeBackendId

    fun register(requestedBinding: HotkeyRequestedBinding): HotkeyBindingRegistrationResult

    fun unregisterAll()

    fun dispose()
}

class LinuxUnavailableHotkeyBackend(
    private val guidance: String,
) : LinuxHotkeyBackend {
    override val backendId: HotkeyRuntimeBackendId = HotkeyRuntimeBackendId.UNAVAILABLE

    override fun register(requestedBinding: HotkeyRequestedBinding): HotkeyBindingRegistrationResult {
        return HotkeyBindingRegistrationResult.Unavailable(guidance)
    }

    override fun unregisterAll() = Unit

    override fun dispose() = Unit
}

class LinuxPortalHotkeyBackend : LinuxHotkeyBackend {
    override val backendId: HotkeyRuntimeBackendId = HotkeyRuntimeBackendId.PORTAL

    override fun register(requestedBinding: HotkeyRequestedBinding): HotkeyBindingRegistrationResult {
        return HotkeyBindingRegistrationResult.Unavailable(
            "Wayland global shortcuts depend on the desktop portal implementation. Use the tray or fallback window if activation is unavailable.",
        )
    }

    override fun unregisterAll() = Unit

    override fun dispose() = Unit
}

class LinuxX11HotkeyBackend(
    private val displayName: String,
    private val onEvent: (String, HotkeyRuntimeEventPhase) -> Unit,
) : LinuxHotkeyBackend {
    override val backendId: HotkeyRuntimeBackendId = HotkeyRuntimeBackendId.X11

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val registrations = mutableMapOf<Pair<Int, UInt>, RegisteredBinding>()
    private val display = XOpenDisplay(displayName)
    private val rootWindow = display?.let { XDefaultRootWindow(it) }
    private var eventPump: Job? = null

    override fun register(requestedBinding: HotkeyRequestedBinding): HotkeyBindingRegistrationResult {
        val binding = requestedBinding.binding ?: return HotkeyBindingRegistrationResult.NotConfigured
        val openedDisplay = display ?: return HotkeyBindingRegistrationResult.Failed("Unable to open the X11 display.")
        val root = rootWindow ?: return HotkeyBindingRegistrationResult.Failed("Unable to access the X11 root window.")
        val keycode = binding.toKeycode(openedDisplay)
            ?: return HotkeyBindingRegistrationResult.Failed("The shortcut key '${binding.key}' is not available on this keyboard layout.")
        val modifierMask = binding.toModifierMask()

        bindingMasks(modifierMask).forEach { mask ->
            XGrabKey(openedDisplay, keycode, mask, root, 1, GrabModeAsync, GrabModeAsync)
        }
        XSelectInput(openedDisplay, root, KeyPressMask or KeyReleaseMask)
        XSync(openedDisplay, 0)

        registrations[keycode to normalizeMask(modifierMask)] = RegisteredBinding(
            actionId = requestedBinding.actionId.rawValue,
            keycode = keycode,
            modifiers = modifierMask,
        )
        ensureEventPump()
        return HotkeyBindingRegistrationResult.Active
    }

    override fun unregisterAll() {
        val openedDisplay = display ?: return
        val root = rootWindow ?: return
        registrations.values.forEach { binding ->
            bindingMasks(binding.modifiers).forEach { mask ->
                XUngrabKey(openedDisplay, binding.keycode, mask, root)
            }
        }
        registrations.clear()
        XSync(openedDisplay, 0)
    }

    override fun dispose() {
        unregisterAll()
        eventPump?.cancel()
        scope.cancel()
        display?.let { XCloseDisplay(it) }
    }

    private fun ensureEventPump() {
        if (eventPump != null || display == null) {
            return
        }

        eventPump = scope.launch {
            while (isActive) {
                while (XPending(display) > 0) {
                    memScoped {
                        val event = alloc<XEvent>()
                        XNextEvent(display, event.ptr)
                        val normalizedMask = normalizeMask(event.xkey.state)
                        val registeredBinding = registrations[event.xkey.keycode to normalizedMask] ?: continue
                        when (event.type) {
                            KeyPress -> onEvent(registeredBinding.actionId, HotkeyRuntimeEventPhase.ACTIVATED)
                            KeyRelease -> onEvent(registeredBinding.actionId, HotkeyRuntimeEventPhase.DEACTIVATED)
                        }
                    }
                }
                usleep(10_000u)
                delay(10)
            }
        }
    }

    private fun HotkeyBinding.toKeycode(openedDisplay: CPointer<Display>): Int? {
        val keysymName = when (val normalized = key.trim()) {
            "Space" -> "space"
            else -> normalized.lowercase()
        }
        val keysym = XStringToKeysym(keysymName)
        if (keysym == NoSymbol.toULong()) {
            return null
        }
        val keycode = XKeysymToKeycode(openedDisplay, keysym)
        return if (keycode == 0) null else keycode
    }

    private fun HotkeyBinding.toModifierMask(): UInt {
        return modifiers.fold(0u) { mask, modifier ->
            mask or when (modifier) {
                tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier.SHIFT -> ShiftMask.toUInt()
                tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier.CTRL -> ControlMask.toUInt()
                tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier.ALT -> Mod1Mask.toUInt()
                tech.watzon.pindrop.shared.feature.transcription.HotkeyModifier.META -> Mod4Mask.toUInt()
            }
        }
    }

    private fun bindingMasks(mask: UInt): List<UInt> {
        val variants = listOf(0u, LockMask.toUInt(), Mod2Mask.toUInt(), LockMask.toUInt() or Mod2Mask.toUInt())
        return variants.map { mask or it }
    }

    private fun normalizeMask(mask: UInt): UInt {
        return mask and (ShiftMask.toUInt() or ControlMask.toUInt() or Mod1Mask.toUInt() or Mod4Mask.toUInt())
    }

    private data class RegisteredBinding(
        val actionId: String,
        val keycode: Int,
        val modifiers: UInt,
    )
}
