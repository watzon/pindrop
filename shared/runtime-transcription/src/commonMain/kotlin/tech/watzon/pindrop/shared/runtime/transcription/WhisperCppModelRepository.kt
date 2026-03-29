package tech.watzon.pindrop.shared.runtime.transcription

import tech.watzon.pindrop.shared.core.TranscriptionModelId

class WhisperCppRemoteModelRepository : RemoteModelRepositoryPort {
    override fun artifactsFor(model: LocalModelDescriptor): List<RemoteModelArtifact> {
        if (model.family != LocalModelFamily.WHISPER) {
            return emptyList()
        }

        val curatedModel = curatedModelsById[model.id] ?: return emptyList()
        return listOf(
            RemoteModelArtifact(
                fileName = curatedModel.fileName,
                downloadUrl = curatedModel.downloadUrl,
            ),
        )
    }

    companion object {
        private val curatedModelsById = listOf(
            curated("openai_whisper-tiny", "tiny"),
            curated("openai_whisper-tiny.en", "tiny.en"),
            curated("openai_whisper-base", "base"),
            curated("openai_whisper-base.en", "base.en"),
            curated("openai_whisper-small", "small"),
            curated("openai_whisper-small.en", "small.en"),
            curated("openai_whisper-medium", "medium"),
            curated("openai_whisper-medium.en", "medium.en"),
            curated("openai_whisper-large-v2", "large-v2"),
            curated("openai_whisper-large-v3", "large-v3"),
            curated("openai_whisper-large-v3_turbo", "large-v3-turbo"),
            curated("openai_whisper-small_216MB", "small-q5_1"),
            curated("openai_whisper-small.en_217MB", "small.en-q5_1"),
            curated("openai_whisper-large-v3_turbo_954MB", "large-v3-turbo-q8_0"),
        ).associateBy { it.modelId }

        val curatedModelIds: Set<TranscriptionModelId> = curatedModelsById.keys

        private fun curated(
            localModelId: String,
            whisperCppModelName: String,
            repositoryBaseUrl: String = DEFAULT_MODEL_REPOSITORY_BASE_URL,
        ): CuratedWhisperCppModel {
            val fileName = "ggml-$whisperCppModelName.bin"
            return CuratedWhisperCppModel(
                modelId = TranscriptionModelId(localModelId),
                fileName = fileName,
                downloadUrl = "$repositoryBaseUrl/$fileName",
            )
        }

        private const val DEFAULT_MODEL_REPOSITORY_BASE_URL =
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    }
}

private data class CuratedWhisperCppModel(
    val modelId: TranscriptionModelId,
    val fileName: String,
    val downloadUrl: String,
)
