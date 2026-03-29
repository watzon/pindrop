package tech.watzon.pindrop.shared.feature.transcription

import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelSelectionAction
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelSelectionResolution
import tech.watzon.pindrop.shared.runtime.transcription.LocalRuntimeErrorCode
import tech.watzon.pindrop.shared.runtime.transcription.LocalTranscriptionRuntime

enum class VoiceOutputMode {
    CLIPBOARD,
    DIRECT_INSERT,
}

enum class PermissionStatus {
    GRANTED,
    DENIED,
    NOT_DETERMINED,
    RESTRICTED,
    UNSUPPORTED,
}

enum class HotkeyModifier {
    CTRL,
    ALT,
    SHIFT,
    META,
}

enum class HotkeyMode {
    TOGGLE,
    PUSH_TO_TALK,
}

data class HotkeyBinding(
    val key: String,
    val modifiers: Set<HotkeyModifier> = emptySet(),
)

data class VoiceSettingsSnapshot(
    val selectedModelId: TranscriptionModelId,
    val selectedLanguage: TranscriptionLanguage = TranscriptionLanguage.AUTOMATIC,
    val preferredInputDeviceId: String? = null,
    val outputMode: VoiceOutputMode = VoiceOutputMode.CLIPBOARD,
    val toggleHotkey: HotkeyBinding? = null,
    val pushToTalkHotkey: HotkeyBinding? = null,
    val launchOnStartupEnabled: Boolean = false,
    val hasCompletedOnboarding: Boolean = false,
)

data class TranscriptHistoryEntry(
    val id: String,
    val timestampEpochMillis: Long,
    val text: String,
    val durationMs: Long,
    val modelId: TranscriptionModelId,
)

enum class VoiceSessionState {
    IDLE,
    STARTING,
    RECORDING,
    PROCESSING,
    COMPLETED,
    ERROR,
}

enum class VoiceSessionError {
    MICROPHONE_PERMISSION_DENIED,
    AUDIO_START_FAILED,
    AUDIO_STOP_FAILED,
    MODEL_NOT_INSTALLED,
    MODEL_LOAD_FAILED,
    TRANSCRIPTION_FAILED,
    CLIPBOARD_WRITE_FAILED,
    UNSUPPORTED_PLATFORM_INTEGRATION,
}

data class VoiceSessionUiState(
    val state: VoiceSessionState,
    val activeModelId: TranscriptionModelId? = null,
    val requiresModelInstallation: Boolean = false,
    val canRecord: Boolean = true,
    val message: String? = null,
)

data class VoiceSessionBootstrapResult(
    val settings: VoiceSettingsSnapshot,
    val startupModel: LocalModelSelectionResolution?,
    val requiresModelInstallation: Boolean,
)

enum class VoiceSessionStopReason {
    TRANSCRIPT_READY,
    NO_SPEECH_DETECTED,
    MODEL_INSTALL_REQUIRED,
    FAILED,
}

data class VoiceSessionStopResult(
    val reason: VoiceSessionStopReason,
    val transcript: String? = null,
    val modelId: TranscriptionModelId? = null,
    val durationMs: Long = 0,
)

interface AudioCapturePort {
    suspend fun startCapture()
    suspend fun stopCapture(): ByteArray
    suspend fun cancelCapture()
    fun isCapturing(): Boolean
    fun setPreferredInputDevice(deviceId: String?)
}

interface ClipboardPort {
    fun copyText(text: String): Boolean
}

interface HotkeyRegistrationPort {
    fun register(binding: HotkeyBinding, actionId: String, mode: HotkeyMode)
    fun unregisterAll()
}

interface SettingsStorePort {
    fun load(): VoiceSettingsSnapshot
    fun save(snapshot: VoiceSettingsSnapshot)
}

interface TranscriptHistoryPort {
    suspend fun save(entry: TranscriptHistoryEntry)
    suspend fun latest(): TranscriptHistoryEntry?
}

interface PermissionPort {
    suspend fun microphoneStatus(): PermissionStatus
    suspend fun requestMicrophonePermission(): PermissionStatus
}

interface VoiceSessionEventSink {
    fun onStateChanged(state: VoiceSessionUiState)
    fun onError(error: VoiceSessionError)
    fun onTranscriptReady(text: String)
}

fun interface TimestampProvider {
    fun nowEpochMillis(): Long
}

class VoiceSessionCoordinator(
    private val runtime: LocalTranscriptionRuntime,
    private val audioCapture: AudioCapturePort,
    private val clipboard: ClipboardPort,
    private val permissions: PermissionPort,
    private val settingsStore: SettingsStorePort,
    private val eventSink: VoiceSessionEventSink,
    private val history: TranscriptHistoryPort? = null,
    private val timestampProvider: TimestampProvider = TimestampProvider { 0L },
    private val supportsDirectInsert: Boolean = false,
) {
    private var currentSettings: VoiceSettingsSnapshot? = null
    private var startupModel: LocalModelSelectionResolution? = null
    private var activeModelId: TranscriptionModelId? = null
    private var recordingStartedAtEpochMillis: Long? = null
    private var initialized = false

    suspend fun initialize(): VoiceSessionBootstrapResult {
        val settings = settingsStore.load()
        currentSettings = settings
        runtime.refreshInstalledModels()

        val resolution = runtime.catalog().takeIf { it.isNotEmpty() }?.let {
            runtime.resolveStartupModel(
                selectedModelId = settings.selectedModelId,
                defaultModelId = settings.selectedModelId,
            )
        }
        startupModel = resolution
        activeModelId = when (resolution?.action) {
            LocalModelSelectionAction.LOAD_SELECTED,
            LocalModelSelectionAction.LOAD_FALLBACK,
            -> resolution.updatedSelectedModelId
            LocalModelSelectionAction.DOWNLOAD_SELECTED,
            null,
            -> null
        }
        initialized = true

        val requiresModelInstallation = resolution?.action == LocalModelSelectionAction.DOWNLOAD_SELECTED
        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.IDLE,
                activeModelId = activeModelId,
                requiresModelInstallation = requiresModelInstallation,
                canRecord = !requiresModelInstallation,
                message = if (requiresModelInstallation) {
                    "Install a local transcription model to begin."
                } else {
                    null
                },
            ),
        )

        return VoiceSessionBootstrapResult(
            settings = settings,
            startupModel = resolution,
            requiresModelInstallation = requiresModelInstallation,
        )
    }

    suspend fun startRecording(): Boolean {
        ensureInitialized()

        if (audioCapture.isCapturing()) {
            eventSink.onError(VoiceSessionError.AUDIO_START_FAILED)
            return false
        }

        val settings = currentSettings ?: settingsStore.load().also { currentSettings = it }
        if (startupModel?.action == LocalModelSelectionAction.DOWNLOAD_SELECTED || activeModelId == null) {
            transitionToError(
                VoiceSessionError.MODEL_NOT_INSTALLED,
                message = "Install a local transcription model before recording.",
            )
            return false
        }

        val microphoneStatus = permissions.microphoneStatus()
        val resolvedPermission = when (microphoneStatus) {
            PermissionStatus.NOT_DETERMINED -> permissions.requestMicrophonePermission()
            else -> microphoneStatus
        }
        if (resolvedPermission != PermissionStatus.GRANTED) {
            transitionToError(
                VoiceSessionError.MICROPHONE_PERMISSION_DENIED,
                message = "Microphone permission is required to start recording.",
            )
            return false
        }

        audioCapture.setPreferredInputDevice(settings.preferredInputDeviceId)
        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.STARTING,
                activeModelId = activeModelId,
                message = "Starting microphone capture…",
            ),
        )

        return runCatching {
            audioCapture.startCapture()
            recordingStartedAtEpochMillis = timestampProvider.nowEpochMillis()
            eventSink.onStateChanged(
                VoiceSessionUiState(
                    state = VoiceSessionState.RECORDING,
                    activeModelId = activeModelId,
                ),
            )
            true
        }.getOrElse {
            transitionToError(
                VoiceSessionError.AUDIO_START_FAILED,
                message = "Unable to start microphone capture.",
            )
            false
        }
    }

    suspend fun stopRecording(): VoiceSessionStopResult {
        ensureInitialized()

        if (!audioCapture.isCapturing()) {
            transitionToError(
                VoiceSessionError.AUDIO_STOP_FAILED,
                message = "Recording is not active.",
            )
            return VoiceSessionStopResult(reason = VoiceSessionStopReason.FAILED)
        }

        val settings = currentSettings ?: settingsStore.load().also { currentSettings = it }
        val modelId = activeModelId ?: startupModel?.updatedSelectedModelId
        if (modelId == null) {
            transitionToError(
                VoiceSessionError.MODEL_NOT_INSTALLED,
                message = "Install a local transcription model before recording.",
            )
            return VoiceSessionStopResult(reason = VoiceSessionStopReason.MODEL_INSTALL_REQUIRED)
        }

        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.PROCESSING,
                activeModelId = modelId,
                message = "Transcribing locally…",
            ),
        )

        val audioData = runCatching { audioCapture.stopCapture() }.getOrElse {
            transitionToError(
                VoiceSessionError.AUDIO_STOP_FAILED,
                activeModelId = modelId,
                message = "Unable to stop microphone capture.",
            )
            return VoiceSessionStopResult(reason = VoiceSessionStopReason.FAILED)
        }

        val durationMs = durationSinceStart()
        if (audioData.isEmpty()) {
            val result = VoiceSessionStopResult(
                reason = VoiceSessionStopReason.NO_SPEECH_DETECTED,
                modelId = modelId,
                durationMs = durationMs,
            )
            transitionToCompleted(
                activeModelId = modelId,
                message = "No speech detected.",
            )
            return result
        }

        if (runtime.activeModel?.descriptor?.id != modelId) {
            runCatching { runtime.loadModel(modelId) }.getOrElse {
                transitionToError(
                    mapRuntimeError(runtime.lastErrorCode),
                    activeModelId = modelId,
                    message = "Unable to load the selected transcription model.",
                )
                return VoiceSessionStopResult(reason = VoiceSessionStopReason.FAILED)
            }
            activeModelId = modelId
        }

        val normalizedTranscript = runCatching {
            runtime.transcribe(
                TranscriptionRequest(
                    audioData = audioData,
                    language = settings.selectedLanguage,
                ),
            ).text
        }.map {
            SharedTranscriptionOrchestrator.normalizeTranscriptionText(it)
        }.getOrElse {
            transitionToError(
                mapRuntimeError(runtime.lastErrorCode),
                activeModelId = modelId,
                message = "Transcription failed.",
            )
            return VoiceSessionStopResult(reason = VoiceSessionStopReason.FAILED)
        }

        if (SharedTranscriptionOrchestrator.isTranscriptionEffectivelyEmpty(normalizedTranscript)) {
            val result = VoiceSessionStopResult(
                reason = VoiceSessionStopReason.NO_SPEECH_DETECTED,
                modelId = modelId,
                durationMs = durationMs,
            )
            transitionToCompleted(
                activeModelId = modelId,
                message = "No speech detected.",
            )
            return result
        }

        val copied = when (settings.outputMode) {
            VoiceOutputMode.CLIPBOARD -> clipboard.copyText(normalizedTranscript)
            VoiceOutputMode.DIRECT_INSERT -> clipboard.copyText(normalizedTranscript)
        }

        if (!copied) {
            transitionToError(
                VoiceSessionError.CLIPBOARD_WRITE_FAILED,
                activeModelId = modelId,
                message = "Transcription completed, but copying to the clipboard failed.",
            )
            return VoiceSessionStopResult(reason = VoiceSessionStopReason.FAILED)
        }

        history?.save(
            TranscriptHistoryEntry(
                id = generatedTranscriptId(),
                timestampEpochMillis = timestampProvider.nowEpochMillis(),
                text = normalizedTranscript,
                durationMs = durationMs,
                modelId = modelId,
            ),
        )

        eventSink.onTranscriptReady(normalizedTranscript)
        transitionToCompleted(
            activeModelId = modelId,
            message = if (settings.outputMode == VoiceOutputMode.DIRECT_INSERT && !supportsDirectInsert) {
                "Direct insert is unavailable on this platform. Copied transcript to the clipboard instead."
            } else {
                "Copied transcript to the clipboard."
            },
        )

        return VoiceSessionStopResult(
            reason = VoiceSessionStopReason.TRANSCRIPT_READY,
            transcript = normalizedTranscript,
            modelId = modelId,
            durationMs = durationMs,
        )
    }

    suspend fun cancelRecording() {
        if (!audioCapture.isCapturing()) {
            return
        }

        audioCapture.cancelCapture()
        recordingStartedAtEpochMillis = null
        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.IDLE,
                activeModelId = activeModelId,
                message = "Recording canceled.",
            ),
        )
    }

    fun isRecording(): Boolean = audioCapture.isCapturing()

    private suspend fun ensureInitialized() {
        if (!initialized) {
            initialize()
        }
    }

    private fun transitionToCompleted(
        activeModelId: TranscriptionModelId?,
        message: String,
    ) {
        recordingStartedAtEpochMillis = null
        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.COMPLETED,
                activeModelId = activeModelId,
                message = message,
            ),
        )
    }

    private fun transitionToError(
        error: VoiceSessionError,
        activeModelId: TranscriptionModelId? = this.activeModelId,
        message: String,
    ) {
        recordingStartedAtEpochMillis = null
        eventSink.onError(error)
        eventSink.onStateChanged(
            VoiceSessionUiState(
                state = VoiceSessionState.ERROR,
                activeModelId = activeModelId,
                canRecord = error != VoiceSessionError.MODEL_NOT_INSTALLED,
                requiresModelInstallation = error == VoiceSessionError.MODEL_NOT_INSTALLED,
                message = message,
            ),
        )
    }

    private fun durationSinceStart(): Long {
        val startedAt = recordingStartedAtEpochMillis ?: return 0
        return (timestampProvider.nowEpochMillis() - startedAt).coerceAtLeast(0)
    }

    private fun mapRuntimeError(errorCode: LocalRuntimeErrorCode?): VoiceSessionError {
        return when (errorCode) {
            LocalRuntimeErrorCode.MODEL_NOT_FOUND,
            LocalRuntimeErrorCode.MODEL_NOT_INSTALLED,
            -> VoiceSessionError.MODEL_NOT_INSTALLED
            LocalRuntimeErrorCode.LOAD_FAILED,
            LocalRuntimeErrorCode.BACKEND_UNAVAILABLE,
            LocalRuntimeErrorCode.UNSUPPORTED_ON_PLATFORM,
            -> VoiceSessionError.MODEL_LOAD_FAILED
            LocalRuntimeErrorCode.TRANSCRIPTION_FAILED,
            LocalRuntimeErrorCode.INVALID_AUDIO_DATA,
            LocalRuntimeErrorCode.TRANSCRIPTION_ALREADY_IN_PROGRESS,
            LocalRuntimeErrorCode.ENGINE_SWITCH_DURING_TRANSCRIPTION,
            LocalRuntimeErrorCode.INSTALL_FAILED,
            LocalRuntimeErrorCode.DELETE_FAILED,
            null,
            -> VoiceSessionError.TRANSCRIPTION_FAILED
        }
    }

    private fun generatedTranscriptId(): String {
        val modelComponent = activeModelId?.value ?: "transcript"
        return "$modelComponent-${timestampProvider.nowEpochMillis()}"
    }
}
