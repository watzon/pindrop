package tech.watzon.pindrop.shared.core

enum class TranscriptionProviderId {
    WHISPER_KIT,
    PARAKEET,
    OPEN_AI,
    ELEVEN_LABS,
    GROQ,
}

data class TranscriptionModelId(val value: String)

enum class TranscriptionLanguage {
    AUTOMATIC,
    ENGLISH,
    SIMPLIFIED_CHINESE,
    SPANISH,
    FRENCH,
    GERMAN,
    TURKISH,
    JAPANESE,
    PORTUGUESE_BRAZIL,
    ITALIAN,
    DUTCH,
    KOREAN,
}

data class TranscriptionRequest(
    val audioData: ByteArray,
    val language: TranscriptionLanguage = TranscriptionLanguage.AUTOMATIC,
    val diarizationEnabled: Boolean = false,
    val customVocabularyWords: List<String> = emptyList(),
)

data class StreamingTranscriptionConfig(
    val modelId: TranscriptionModelId,
    val language: TranscriptionLanguage = TranscriptionLanguage.AUTOMATIC,
)

data class DiarizedSegment(
    val speakerId: String,
    val speakerLabel: String,
    val startTimeSeconds: Double,
    val endTimeSeconds: Double,
    val confidence: Float,
    val text: String,
)

data class TranscriptionResult(
    val text: String,
    val diarizedSegments: List<DiarizedSegment> = emptyList(),
)

data class EngineCapabilities(
    val supportsStreaming: Boolean,
    val supportsSpeakerDiarization: Boolean,
    val supportsWordTimestamps: Boolean,
    val supportsLanguageDetection: Boolean,
)

enum class ModelAvailability {
    AVAILABLE,
    COMING_SOON,
    REQUIRES_SETUP,
}

enum class ModelLanguageSupport {
    ENGLISH_ONLY,
    FULL_MULTILINGUAL,
    PARAKEET_V3_EUROPEAN,
}

data class ModelDescriptor(
    val id: TranscriptionModelId,
    val displayName: String,
    val provider: TranscriptionProviderId,
    val languageSupport: ModelLanguageSupport,
    val sizeInMb: Int,
    val description: String,
    val speedRating: Double,
    val accuracyRating: Double,
    val availability: ModelAvailability,
)

data class TranscriptionSettingsSnapshot(
    val selectedLanguage: TranscriptionLanguage,
    val selectedModelId: TranscriptionModelId,
    val aiEnhancementEnabled: Boolean,
    val streamingFeatureEnabled: Boolean,
    val diarizationFeatureEnabled: Boolean,
)

interface TranscriptionEnginePort {
    suspend fun loadModel(modelId: TranscriptionModelId, downloadBasePath: String? = null)
    suspend fun loadModelFromPath(path: String)
    suspend fun transcribe(request: TranscriptionRequest): TranscriptionResult
    suspend fun unloadModel()
}

interface StreamingTranscriptionEnginePort {
    suspend fun loadModel(config: StreamingTranscriptionConfig)
    suspend fun startStreaming()
    suspend fun processAudioChunk(samples: FloatArray)
    suspend fun stopStreaming(): String
    suspend fun cancelStreaming()
}

interface SpeakerDiarizerPort {
    suspend fun diarize(request: TranscriptionRequest): List<DiarizedSegment>
}

interface ModelCatalogPort {
    fun allModels(): List<ModelDescriptor>
    fun recommendedModels(language: TranscriptionLanguage): List<ModelDescriptor>
    fun isModelDownloaded(modelId: TranscriptionModelId): Boolean
}

interface SettingsSnapshotProvider {
    fun currentSettings(): TranscriptionSettingsSnapshot
}

interface TranscriptionEventSink {
    fun onStateChanged(state: SharedTranscriptionState)
    fun onPartialTranscript(text: String)
}

enum class SharedTranscriptionState {
    UNLOADED,
    LOADING,
    READY,
    TRANSCRIBING,
    STREAMING,
    ERROR,
}
