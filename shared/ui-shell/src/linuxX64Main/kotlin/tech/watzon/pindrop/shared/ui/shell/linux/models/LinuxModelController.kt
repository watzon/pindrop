package tech.watzon.pindrop.shared.ui.shell.linux.models

import kotlinx.coroutines.runBlocking
import tech.watzon.pindrop.shared.core.TranscriptionLanguage
import tech.watzon.pindrop.shared.core.TranscriptionModelId
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.runtime.transcription.InstalledModelRecord
import tech.watzon.pindrop.shared.runtime.transcription.LinuxWhisperRuntimeBootstrap
import tech.watzon.pindrop.shared.runtime.transcription.LocalModelDescriptor
import tech.watzon.pindrop.shared.runtime.transcription.LocalTranscriptionRuntime
import tech.watzon.pindrop.shared.runtime.transcription.ModelInstallProgress
import tech.watzon.pindrop.shared.runtime.transcription.RuntimeObserver
import tech.watzon.pindrop.shared.runtime.transcription.ActiveLocalModel
import tech.watzon.pindrop.shared.runtime.transcription.LocalRuntimeErrorCode
import tech.watzon.pindrop.shared.runtime.transcription.LocalRuntimeState
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys

class LinuxModelController(
    private val settings: SettingsPersistence,
    private val runtimeProvider: (RuntimeObserver) -> LocalTranscriptionRuntime = { observer ->
        LinuxWhisperRuntimeBootstrap.create(observer = observer)
    },
) {
    private var installProgressListener: ((Double, String?) -> Unit)? = null
    private val observer = object : RuntimeObserver {
        override fun onStateChanged(state: LocalRuntimeState) = Unit

        override fun onActiveModelChanged(model: ActiveLocalModel?) = Unit

        override fun onInstallProgress(progress: ModelInstallProgress?) {
            progress?.let { installProgressListener?.invoke(it.progress, it.message) }
        }

        override fun onErrorChanged(errorCode: LocalRuntimeErrorCode?, message: String?) = Unit
    }
    private val runtime: LocalTranscriptionRuntime by lazy { runtimeProvider(observer) }

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

    fun allModels(): List<LocalModelDescriptor> = runtime.catalog()

    fun installedModels(): List<InstalledModelRecord> {
        return runBlocking { runtime.refreshInstalledModels() }
    }

    fun install(
        modelId: TranscriptionModelId,
        onProgress: (Double, String?) -> Unit,
    ): InstalledModelRecord {
        installProgressListener = onProgress
        onProgress(0.0, "Starting download")
        return runBlocking {
            runtime.installModel(modelId)
        }.also {
            settings.setString(SettingsKeys.selectedModel, modelId.value)
            settings.save()
            onProgress(1.0, "Install complete")
            installProgressListener = null
        }
    }

    fun delete(modelId: TranscriptionModelId) {
        runBlocking { runtime.deleteModel(modelId) }
    }

    fun load(modelId: TranscriptionModelId) {
        runBlocking {
            runtime.refreshInstalledModels()
            runtime.loadModel(modelId)
        }
        settings.setString(SettingsKeys.selectedModel, modelId.value)
        settings.save()
    }

    fun setSelectedModel(modelId: String) {
        settings.setString(SettingsKeys.selectedModel, modelId)
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
