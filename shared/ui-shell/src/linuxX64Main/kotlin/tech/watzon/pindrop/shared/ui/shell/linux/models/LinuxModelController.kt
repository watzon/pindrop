package tech.watzon.pindrop.shared.ui.shell.linux.models

import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.runtime.transcription.InstalledModelRecord
import tech.watzon.pindrop.shared.runtime.transcription.LinuxWhisperRuntimeBootstrap
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelDescriptor
import tech.watzon.pindrop.shared.runtime.transcription.LocalTranscriptionRuntime
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys

class LinuxModelController(
    private val settings: SettingsPersistence,
    private val runtimeProvider: () -> LocalTranscriptionRuntime = { LinuxWhisperRuntimeBootstrap.create() },
) {
    private val runtime: LocalTranscriptionRuntime by lazy(runtimeProvider)

    val selectedModelId: TranscriptionModelId
        get() = TranscriptionModelId(
            settings.getString(SettingsKeys.selectedModel) ?: SettingsDefaults.selectedModel,
        )

    fun catalog(language: TranscriptionLanguage = selectedLanguage()): List<LocalModelDescriptor> {
        val recommended = runtime.recommendedModels(language)
        return if (recommended.isNotEmpty()) {
            recommended
        } else {
            runtime.catalog()
        }
    }

    suspend fun installedModels(): List<InstalledModelRecord> {
        return runtime.refreshInstalledModels()
    }

    suspend fun install(
        modelId: TranscriptionModelId,
        onProgress: (Double, String?) -> Unit,
    ): InstalledModelRecord {
        return runtime.installModel(modelId).also {
            settings.setString(SettingsKeys.selectedModel, modelId.value)
            settings.save()
            onProgress(1.0, null)
        }
    }

    suspend fun delete(modelId: TranscriptionModelId) {
        runtime.deleteModel(modelId)
    }

    suspend fun load(modelId: TranscriptionModelId) {
        runtime.refreshInstalledModels()
        runtime.loadModel(modelId)
        settings.setString(SettingsKeys.selectedModel, modelId.value)
        settings.save()
    }

    fun selectedLanguage(): TranscriptionLanguage {
        return when (settings.getString(SettingsKeys.selectedLanguage) ?: SettingsDefaults.selectedLanguage) {
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
    }
}
