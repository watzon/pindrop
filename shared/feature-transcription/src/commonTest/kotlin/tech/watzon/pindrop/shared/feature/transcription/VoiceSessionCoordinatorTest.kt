package tech.watzon.pindrop.shared.feature.transcription

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import tech.watzon.pindrop.shared.core.ModelLanguageSupport
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.TranscriptionRequest
import tech.watzon.pindrop.shared.core.TranscriptionResult
import tech.watzon.pindrop.shared.runtime.transcription.BackendRegistryPort
import tech.watzon.pindrop.shared.runtime.transcription.InstalledModelIndexPort
import tech.watzon.pindrop.shared.runtime.transcription.InstalledModelRecord
import tech.watzon.pindrop.shared.runtime.transcription.LocalBackendId
import tech.watzon.pindrop.shared.runtime.transcription.LocalInferenceBackendPort
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelDescriptor
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelFamily
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelProvider
import tech.watzon.pindrop.shared.runtime.transcription.LocalPlatformId
import tech.watzon.pindrop.shared.runtime.transcription.LocalRuntimeErrorCode
import tech.watzon.pindrop.shared.runtime.transcription.LocalTranscriptionRuntime
import tech.watzon.pindrop.shared.runtime.transcription.ModelInstallProgress
import tech.watzon.pindrop.shared.runtime.transcription.ModelInstallState
import tech.watzon.pindrop.shared.runtime.transcription.ModelInstallerPort
import tech.watzon.pindrop.shared.runtime.transcription.ModelStorageLayout

class VoiceSessionCoordinatorTest {
    @Test
    fun initializeUsesInstalledSelectedModel() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
        )

        val result = fixture.coordinator.initialize()

        assertFalse(result.requiresModelInstallation)
        assertEquals("openai_whisper-base", result.startupModel?.updatedSelectedModelId?.value)
        assertEquals(VoiceSessionState.IDLE, fixture.eventSink.states.last().state)
    }

    @Test
    fun initializeFallsBackToInstalledModelWhenSelectionIsMissing() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "missing-model"),
            installed = listOf(installedRecord("openai_whisper-base")),
        )

        val result = fixture.coordinator.initialize()

        assertFalse(result.requiresModelInstallation)
        assertEquals("openai_whisper-base", result.startupModel?.updatedSelectedModelId?.value)
    }

    @Test
    fun initializeRequiresInstallationWhenNoModelIsInstalled() = runTest {
        val fixture = fixture(settings = defaultSettings(selectedModelId = "openai_whisper-base"))

        val result = fixture.coordinator.initialize()

        assertTrue(result.requiresModelInstallation)
        assertTrue(fixture.eventSink.states.last().requiresModelInstallation)
    }

    @Test
    fun startRecordingRequestsPermissionLazily() = runTest {
        val permissions = FakePermissionPort(
            status = PermissionStatus.NOT_DETERMINED,
            requestedStatus = PermissionStatus.GRANTED,
        )
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            permissions = permissions,
        )
        fixture.coordinator.initialize()

        val didStart = fixture.coordinator.startRecording()

        assertTrue(didStart)
        assertEquals(1, permissions.requestCalls)
        assertEquals(VoiceSessionState.RECORDING, fixture.eventSink.states.last().state)
    }

    @Test
    fun startRecordingFailsWhenPermissionDenied() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            permissions = FakePermissionPort(status = PermissionStatus.DENIED),
        )
        fixture.coordinator.initialize()

        val didStart = fixture.coordinator.startRecording()

        assertFalse(didStart)
        assertEquals(VoiceSessionError.MICROPHONE_PERMISSION_DENIED, fixture.eventSink.errors.single())
        assertEquals(VoiceSessionState.ERROR, fixture.eventSink.states.last().state)
    }

    @Test
    fun stopWithoutActiveRecordingFails() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
        )
        fixture.coordinator.initialize()

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.FAILED, result.reason)
        assertEquals(VoiceSessionError.AUDIO_STOP_FAILED, fixture.eventSink.errors.single())
    }

    @Test
    fun successfulTranscriptionCopiesTranscriptAndSavesHistory() = runTest {
        val history = FakeTranscriptHistoryPort()
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            audioCapture = FakeAudioCapturePort(stopAudio = byteArrayOf(1, 2, 3)),
            history = history,
            timestampProvider = FakeTimestampProvider(now = 2_000L),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()
        fixture.timestampProvider.now = 3_250L

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.TRANSCRIPT_READY, result.reason)
        assertEquals("transcribed text", result.transcript)
        assertEquals("transcribed text", fixture.clipboard.lastCopiedText)
        assertEquals("transcribed text", fixture.eventSink.transcripts.single())
        assertEquals("transcribed text", history.latest()?.text)
        assertEquals(1_250L, result.durationMs)
        assertEquals(VoiceSessionState.COMPLETED, fixture.eventSink.states.last().state)
    }

    @Test
    fun emptyAudioReturnsNoSpeechDetected() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            audioCapture = FakeAudioCapturePort(stopAudio = byteArrayOf()),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.NO_SPEECH_DETECTED, result.reason)
        assertNull(fixture.clipboard.lastCopiedText)
        assertTrue(fixture.eventSink.states.last().message?.contains("No speech detected") == true)
    }

    @Test
    fun blankTranscriptReturnsNoSpeechDetected() = runTest {
        val backend = FakeBackend(transcript = "[BLANK AUDIO]")
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            backend = backend,
            audioCapture = FakeAudioCapturePort(stopAudio = byteArrayOf(9, 9, 9)),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.NO_SPEECH_DETECTED, result.reason)
        assertNull(fixture.clipboard.lastCopiedText)
    }

    @Test
    fun clipboardFailureReturnsFailedResult() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            clipboard = FakeClipboardPort(shouldCopySucceed = false),
            audioCapture = FakeAudioCapturePort(stopAudio = byteArrayOf(1, 2, 3)),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.FAILED, result.reason)
        assertEquals(VoiceSessionError.CLIPBOARD_WRITE_FAILED, fixture.eventSink.errors.last())
    }

    @Test
    fun modelLoadFailureIsSurfacedAsError() = runTest {
        val backend = FakeBackend(loadError = IllegalStateException("load failed"))
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
            backend = backend,
            audioCapture = FakeAudioCapturePort(stopAudio = byteArrayOf(1, 2, 3)),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()

        val result = fixture.coordinator.stopRecording()

        assertEquals(VoiceSessionStopReason.FAILED, result.reason)
        assertEquals(VoiceSessionError.MODEL_LOAD_FAILED, fixture.eventSink.errors.last())
    }

    @Test
    fun concurrentStartRequestIsRejected() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
        )
        fixture.coordinator.initialize()

        val first = fixture.coordinator.startRecording()
        val second = fixture.coordinator.startRecording()

        assertTrue(first)
        assertFalse(second)
        assertEquals(VoiceSessionError.AUDIO_START_FAILED, fixture.eventSink.errors.last())
    }

    @Test
    fun cancelWhileRecordingResetsToIdle() = runTest {
        val fixture = fixture(
            settings = defaultSettings(selectedModelId = "openai_whisper-base"),
            installed = listOf(installedRecord("openai_whisper-base")),
        )
        fixture.coordinator.initialize()
        fixture.coordinator.startRecording()

        fixture.coordinator.cancelRecording()

        assertFalse(fixture.audioCapture.isCapturing())
        assertEquals(VoiceSessionState.IDLE, fixture.eventSink.states.last().state)
    }

    @Test
    fun settingsAreRestoredOnInitialize() = runTest {
        val settings = defaultSettings(
            selectedModelId = "openai_whisper-base",
            selectedLanguage = TranscriptionLanguage.GERMAN,
            preferredInputDeviceId = "usb-mic",
            outputMode = VoiceOutputMode.DIRECT_INSERT,
        )
        val fixture = fixture(
            settings = settings,
            installed = listOf(installedRecord("openai_whisper-base")),
        )

        val result = fixture.coordinator.initialize()

        assertEquals(settings, result.settings)
        fixture.coordinator.startRecording()
        assertEquals("usb-mic", fixture.audioCapture.preferredInputDeviceId)
    }

    private fun defaultSettings(
        selectedModelId: String,
        selectedLanguage: TranscriptionLanguage = TranscriptionLanguage.AUTOMATIC,
        preferredInputDeviceId: String? = null,
        outputMode: VoiceOutputMode = VoiceOutputMode.CLIPBOARD,
    ): VoiceSettingsSnapshot {
        return VoiceSettingsSnapshot(
            selectedModelId = TranscriptionModelId(selectedModelId),
            selectedLanguage = selectedLanguage,
            preferredInputDeviceId = preferredInputDeviceId,
            outputMode = outputMode,
        )
    }

    private fun installedRecord(modelId: String): InstalledModelRecord {
        return InstalledModelRecord(
            modelId = TranscriptionModelId(modelId),
            state = ModelInstallState.INSTALLED,
            storage = ModelStorageLayout("/tmp", "/tmp/$modelId"),
            installedProvider = LocalModelProvider.WCPP,
        )
    }

    private fun fixture(
        settings: VoiceSettingsSnapshot,
        installed: List<InstalledModelRecord> = emptyList(),
        backend: FakeBackend = FakeBackend(),
        audioCapture: FakeAudioCapturePort = FakeAudioCapturePort(stopAudio = byteArrayOf(1, 2, 3)),
        clipboard: FakeClipboardPort = FakeClipboardPort(),
        permissions: FakePermissionPort = FakePermissionPort(status = PermissionStatus.GRANTED),
        history: FakeTranscriptHistoryPort? = null,
        timestampProvider: FakeTimestampProvider = FakeTimestampProvider(now = 2_000L),
    ): Fixture {
        val backendRegistry = FakeBackendRegistry(
            preferredByModelId = mapOf("openai_whisper-base" to LocalBackendId.WHISPER_CPP),
            backends = mapOf(LocalBackendId.WHISPER_CPP to backend),
        )
        val runtime = LocalTranscriptionRuntime(
            platform = LocalPlatformId.LINUX,
            installedModelIndex = FakeInstalledModelIndex(installed),
            modelInstaller = FakeInstaller(installed.toMutableList()),
            backendRegistry = backendRegistry,
        )
        val eventSink = FakeVoiceSessionEventSink()
        val settingsStore = FakeSettingsStorePort(settings)
        val coordinator = VoiceSessionCoordinator(
            runtime = runtime,
            audioCapture = audioCapture,
            clipboard = clipboard,
            permissions = permissions,
            settingsStore = settingsStore,
            eventSink = eventSink,
            history = history,
            timestampProvider = timestampProvider,
        )
        return Fixture(
            coordinator = coordinator,
            audioCapture = audioCapture,
            clipboard = clipboard,
            eventSink = eventSink,
            timestampProvider = timestampProvider,
        )
    }

    private data class Fixture(
        val coordinator: VoiceSessionCoordinator,
        val audioCapture: FakeAudioCapturePort,
        val clipboard: FakeClipboardPort,
        val eventSink: FakeVoiceSessionEventSink,
        val timestampProvider: FakeTimestampProvider,
    )
}

private class FakeSettingsStorePort(
    private var snapshot: VoiceSettingsSnapshot,
) : SettingsStorePort {
    override fun load(): VoiceSettingsSnapshot = snapshot

    override fun save(snapshot: VoiceSettingsSnapshot) {
        this.snapshot = snapshot
    }
}

private class FakePermissionPort(
    private val status: PermissionStatus,
    private val requestedStatus: PermissionStatus = status,
) : PermissionPort {
    var requestCalls: Int = 0

    override suspend fun microphoneStatus(): PermissionStatus = status

    override suspend fun requestMicrophonePermission(): PermissionStatus {
        requestCalls += 1
        return requestedStatus
    }
}

private class FakeAudioCapturePort(
    private val stopAudio: ByteArray,
) : AudioCapturePort {
    private var capturing = false
    var preferredInputDeviceId: String? = null

    override suspend fun startCapture() {
        if (capturing) {
            error("already capturing")
        }
        capturing = true
    }

    override suspend fun stopCapture(): ByteArray {
        if (!capturing) {
            error("not capturing")
        }
        capturing = false
        return stopAudio
    }

    override suspend fun cancelCapture() {
        capturing = false
    }

    override fun isCapturing(): Boolean = capturing

    override fun setPreferredInputDevice(deviceId: String?) {
        preferredInputDeviceId = deviceId
    }
}

private class FakeClipboardPort(
    private val shouldCopySucceed: Boolean = true,
) : ClipboardPort {
    var lastCopiedText: String? = null

    override fun copyText(text: String): Boolean {
        if (!shouldCopySucceed) {
            return false
        }
        lastCopiedText = text
        return true
    }
}

private class FakeTranscriptHistoryPort : TranscriptHistoryPort {
    private val entries = mutableListOf<TranscriptHistoryEntry>()

    override suspend fun save(entry: TranscriptHistoryEntry) {
        entries += entry
    }

    override suspend fun latest(): TranscriptHistoryEntry? = entries.lastOrNull()
}

private class FakeVoiceSessionEventSink : VoiceSessionEventSink {
    val states = mutableListOf<VoiceSessionUiState>()
    val errors = mutableListOf<VoiceSessionError>()
    val transcripts = mutableListOf<String>()

    override fun onStateChanged(state: VoiceSessionUiState) {
        states += state
    }

    override fun onError(error: VoiceSessionError) {
        errors += error
    }

    override fun onTranscriptReady(text: String) {
        transcripts += text
    }
}

private class FakeTimestampProvider(
    var now: Long,
) : TimestampProvider {
    override fun nowEpochMillis(): Long = now
}

private class FakeInstalledModelIndex(
    private val installed: List<InstalledModelRecord>,
) : InstalledModelIndexPort {
    override suspend fun refreshInstalledModels(): List<InstalledModelRecord> = installed
}

private class FakeInstaller(
    private val installed: MutableList<InstalledModelRecord>,
) : ModelInstallerPort {
    override suspend fun installModel(
        model: LocalModelDescriptor,
        onProgress: (ModelInstallProgress) -> Unit,
    ): InstalledModelRecord {
        onProgress(
            ModelInstallProgress(
                modelId = model.id,
                progress = 1.0,
                state = ModelInstallState.INSTALLED,
            ),
        )
        return InstalledModelRecord(
            modelId = model.id,
            state = ModelInstallState.INSTALLED,
            storage = ModelStorageLayout("/tmp", "/tmp/${model.id.value}"),
            installedProvider = model.provider,
        ).also(installed::add)
    }

    override suspend fun deleteModel(model: LocalModelDescriptor) {
        installed.removeAll { it.modelId == model.id }
    }
}

private class FakeBackend(
    private val transcript: String = "transcribed text",
    private val loadError: Throwable? = null,
) : LocalInferenceBackendPort {
    override val backendId: LocalBackendId = LocalBackendId.WHISPER_CPP
    override val supportedFamilies: Set<LocalModelFamily> = setOf(LocalModelFamily.WHISPER)
    override val supportsPathLoading: Boolean = true

    override suspend fun loadModel(
        model: LocalModelDescriptor,
        installedRecord: InstalledModelRecord?,
    ) {
        loadError?.let { throw it }
    }

    override suspend fun loadModelFromPath(path: String) = Unit

    override suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult {
        return TranscriptionResult(text = transcript)
    }

    override suspend fun unloadModel() = Unit
}

private class FakeBackendRegistry(
    private val preferredByModelId: Map<String, LocalBackendId>,
    private val backends: Map<LocalBackendId, LocalInferenceBackendPort>,
) : BackendRegistryPort {
    override fun preferredBackend(model: LocalModelDescriptor): LocalBackendId? {
        return preferredByModelId[model.id.value]
    }

    override fun backend(id: LocalBackendId): LocalInferenceBackendPort? {
        return backends[id]
    }
}
