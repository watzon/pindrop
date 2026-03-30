package tech.watzon.pindrop.shared.ui.shell.linux.transcription

import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.feature.transcription.ClipboardPort
import tech.watzon.pindrop.shared.feature.transcription.PermissionPort
import tech.watzon.pindrop.shared.feature.transcription.PermissionStatus
import tech.watzon.pindrop.shared.feature.transcription.SettingsStorePort
import tech.watzon.pindrop.shared.feature.transcription.TimestampProvider
import tech.watzon.pindrop.shared.feature.transcription.VoiceOutputMode
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionCoordinator
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionError
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionEventSink
import tech.watzon.pindrop.shared.feature.transcription.VoiceSessionUiState
import tech.watzon.pindrop.shared.feature.transcription.VoiceSettingsSnapshot
import tech.watzon.pindrop.shared.runtime.transcription.LinuxWhisperRuntimeBootstrap
import tech.watzon.pindrop.shared.runtime.transcription.LocalPlatformId
import tech.watzon.pindrop.shared.schemasettings.OutputMode
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys

data class LinuxVoiceSessionHandle(
    val coordinator: VoiceSessionCoordinator,
    val events: LinuxVoiceSessionEvents,
)

class LinuxVoiceSessionEvents : VoiceSessionEventSink {
    var currentState: VoiceSessionUiState? = null
        private set
    var lastError: VoiceSessionError? = null
        private set
    var lastTranscript: String? = null
        private set

    var onStateChangedCallback: ((VoiceSessionUiState) -> Unit)? = null
    var onErrorCallback: ((VoiceSessionError) -> Unit)? = null
    var onTranscriptReadyCallback: ((String) -> Unit)? = null

    override fun onStateChanged(state: VoiceSessionUiState) {
        currentState = state
        onStateChangedCallback?.invoke(state)
    }

    override fun onError(error: VoiceSessionError) {
        lastError = error
        onErrorCallback?.invoke(error)
    }

    override fun onTranscriptReady(text: String) {
        lastTranscript = text
        onTranscriptReadyCallback?.invoke(text)
    }
}

object LinuxVoiceSessionFactory {
    fun create(settings: SettingsPersistence): LinuxVoiceSessionHandle {
        val events = LinuxVoiceSessionEvents()
        val coordinator = VoiceSessionCoordinator(
            runtime = LinuxWhisperRuntimeBootstrap.create(),
            audioCapture = LinuxAudioCapture(),
            clipboard = InMemoryClipboardPort(),
            permissions = LinuxPermissionPort(),
            settingsStore = LinuxVoiceSettingsStore(settings),
            eventSink = events,
            timestampProvider = TimestampProvider { platform.posix.time(null) * 1000L },
            supportsDirectInsert = false,
        )

        return LinuxVoiceSessionHandle(
            coordinator = coordinator,
            events = events,
        )
    }
}

private class LinuxPermissionPort : PermissionPort {
    override suspend fun microphoneStatus(): PermissionStatus = PermissionStatus.GRANTED
    override suspend fun requestMicrophonePermission(): PermissionStatus = PermissionStatus.GRANTED
}

private class InMemoryClipboardPort : ClipboardPort {
    var lastCopiedText: String? = null
    override fun copyText(text: String): Boolean {
        lastCopiedText = text
        return true
    }
}

private class LinuxVoiceSettingsStore(
    private val settings: SettingsPersistence,
) : SettingsStorePort {
    override fun load(): VoiceSettingsSnapshot {
        return VoiceSettingsSnapshot(
            selectedModelId = TranscriptionModelId(settings.getString(SettingsKeys.selectedModel) ?: SettingsDefaults.selectedModel),
            selectedLanguage = mapLanguage(settings.getString(SettingsKeys.selectedLanguage) ?: SettingsDefaults.selectedLanguage),
            preferredInputDeviceId = settings.getString(SettingsKeys.selectedInputDeviceUID),
            outputMode = when (settings.getString(SettingsKeys.outputMode) ?: SettingsDefaults.outputMode) {
                OutputMode.DIRECT_INSERT.rawValue -> VoiceOutputMode.DIRECT_INSERT
                else -> VoiceOutputMode.CLIPBOARD
            },
            hasCompletedOnboarding = settings.getBool(SettingsKeys.hasCompletedOnboarding) ?: SettingsDefaults.hasCompletedOnboarding,
        )
    }

    override fun save(snapshot: VoiceSettingsSnapshot) {
        settings.setString(SettingsKeys.selectedModel, snapshot.selectedModelId.value)
        settings.setString(SettingsKeys.selectedLanguage, snapshot.selectedLanguage.toSettingsValue())
        snapshot.preferredInputDeviceId?.let { settings.setString(SettingsKeys.selectedInputDeviceUID, it) }
        settings.setString(
            SettingsKeys.outputMode,
            if (snapshot.outputMode == VoiceOutputMode.DIRECT_INSERT) OutputMode.DIRECT_INSERT.rawValue else OutputMode.CLIPBOARD.rawValue,
        )
        settings.setBool(SettingsKeys.hasCompletedOnboarding, snapshot.hasCompletedOnboarding)
        settings.save()
    }

    private fun mapLanguage(raw: String): TranscriptionLanguage = when (raw) {
        "en" -> TranscriptionLanguage.ENGLISH
        "zh-Hans" -> TranscriptionLanguage.SIMPLIFIED_CHINESE
        "es" -> TranscriptionLanguage.SPANISH
        "fr" -> TranscriptionLanguage.FRENCH
        "de" -> TranscriptionLanguage.GERMAN
        "tr" -> TranscriptionLanguage.TURKISH
        "ja" -> TranscriptionLanguage.JAPANESE
        "pt-BR" -> TranscriptionLanguage.PORTUGUESE_BRAZIL
        "it" -> TranscriptionLanguage.ITALIAN
        "nl" -> TranscriptionLanguage.DUTCH
        "ko" -> TranscriptionLanguage.KOREAN
        else -> TranscriptionLanguage.AUTOMATIC
    }

    private fun TranscriptionLanguage.toSettingsValue(): String = when (this) {
        TranscriptionLanguage.ENGLISH -> "en"
        TranscriptionLanguage.SIMPLIFIED_CHINESE -> "zh-Hans"
        TranscriptionLanguage.SPANISH -> "es"
        TranscriptionLanguage.FRENCH -> "fr"
        TranscriptionLanguage.GERMAN -> "de"
        TranscriptionLanguage.TURKISH -> "tr"
        TranscriptionLanguage.JAPANESE -> "ja"
        TranscriptionLanguage.PORTUGUESE_BRAZIL -> "pt-BR"
        TranscriptionLanguage.ITALIAN -> "it"
        TranscriptionLanguage.DUTCH -> "nl"
        TranscriptionLanguage.KOREAN -> "ko"
        TranscriptionLanguage.AUTOMATIC -> SettingsDefaults.selectedLanguage
    }
}
