@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.settings

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.core.platform.AutostartManager
import tech.watzon.pindrop.shared.core.platform.SecretStorage
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.ui.shell.linux.models.LinuxModelController
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsValidation
import tech.watzon.pindrop.shared.schemasettings.SettingsValidationResult
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*

class SettingsDialog(
    private val settings: SettingsPersistence,
    private val secrets: SecretStorage,
    private val autostart: AutostartManager,
    private val parentWindow: CPointer<GtkWidget>,
    private val locale: String,
    private val onSaved: (() -> Unit)? = null,
    private val onClosed: (() -> Unit)? = null,
) {
    private val window = gtk_window_new()
    private val stack = gtk_stack_new()
    private val selfRef = StableRef.create(this)
    private var hasClosed = false

    private val generalPage = GeneralSettingsPage(
        locale = locale,
        initialLanguage = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.selectedLanguage) ?: SettingsDefaults.selectedLanguage,
        initialThemeMode = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.themeMode) ?: SettingsDefaults.themeMode,
        initialLaunchAtLogin = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.launchAtLogin) ?: SettingsDefaults.launchAtLogin,
        initialShowInDock = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.showInDock) ?: SettingsDefaults.showInDock,
    )
    private val hotkeysPage = HotkeysSettingsPage(
        locale = locale,
        initialToggleHotkey = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.Hotkeys.toggleHotkey) ?: SettingsDefaults.Hotkeys.toggleHotkey,
        initialPushToTalkHotkey = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.Hotkeys.pushToTalkHotkey) ?: SettingsDefaults.Hotkeys.pushToTalkHotkey,
        initialCopyLastTranscriptHotkey = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.Hotkeys.copyLastTranscriptHotkey) ?: SettingsDefaults.Hotkeys.copyLastTranscriptHotkey,
    )
    private val outputPage = OutputSettingsPage(
        locale = locale,
        initialOutputMode = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.outputMode) ?: SettingsDefaults.outputMode,
        initialAddTrailingSpace = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.addTrailingSpace) ?: SettingsDefaults.addTrailingSpace,
        initialFloatingIndicatorEnabled = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.floatingIndicatorEnabled) ?: SettingsDefaults.floatingIndicatorEnabled,
        initialFloatingIndicatorType = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.floatingIndicatorType) ?: SettingsDefaults.floatingIndicatorType,
        initialOffsetX = settings.getDouble(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.pillFloatingIndicatorOffsetX) ?: SettingsDefaults.pillFloatingIndicatorOffsetX,
        initialOffsetY = settings.getDouble(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.pillFloatingIndicatorOffsetY) ?: SettingsDefaults.pillFloatingIndicatorOffsetY,
    )
    private val modelsPage = ModelsSettingsPage(
        locale = locale,
        modelController = modelController,
        initialSelectedModel = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.selectedModel) ?: SettingsDefaults.selectedModel,
        initialSelectedLanguage = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.selectedLanguage) ?: SettingsDefaults.selectedLanguage,
    )
    private val aiPage = AISettingsPage(
        locale = locale,
        secrets = secrets,
        initialEnabled = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.aiEnhancementEnabled) ?: SettingsDefaults.aiEnhancementEnabled,
        initialProvider = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.aiProvider) ?: SettingsDefaults.aiProvider,
        initialCustomProvider = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.customLocalProviderType) ?: SettingsDefaults.customLocalProviderType,
        initialModel = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.aiModel) ?: SettingsDefaults.aiModel,
        initialPrompt = settings.getString(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.aiEnhancementPrompt) ?: SettingsDefaults.aiEnhancementPrompt,
    )
    private val dictionaryPage = DictionarySettingsPage(
        locale = locale,
        initialAutomaticDictionaryLearningEnabled = settings.getBool(tech.watzon.pindrop.shared.schemasettings.SettingsKeys.automaticDictionaryLearningEnabled)
            ?: SettingsDefaults.automaticDictionaryLearningEnabled,
    )

    init {
        gtk_window_set_title(window?.reinterpret(), "Pindrop Settings")
        gtk_window_set_default_size(window?.reinterpret(), 820, 620)
        gtk_window_set_modal(window?.reinterpret(), 1)
        gtk_window_set_transient_for(window?.reinterpret(), parentWindow.reinterpret())
        gtk_widget_add_css_class(window, "pindrop-window")

        g_signal_connect_data(window, "close-request", staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
            if (data != null) {
                data.asStableRef<SettingsDialog>().get().notifyClosed()
            }
            0
        }.reinterpret(), selfRef.asCPointer(), null, 0u)

        val root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
        gtk_widget_add_css_class(root, "pindrop-panel")
        gtk_widget_set_margin_start(root, 16)
        gtk_widget_set_margin_end(root, 16)
        gtk_widget_set_margin_top(root, 16)
        gtk_widget_set_margin_bottom(root, 16)

        val switcher = gtk_stack_switcher_new()
        gtk_widget_add_css_class(switcher, "pindrop-toolbar")
        gtk_stack_switcher_set_stack(switcher?.reinterpret(), stack?.reinterpret())
        gtk_box_append(root?.reinterpret(), switcher)

        addPage(generalPage.title(), generalPage.build())
        addPage(hotkeysPage.title(), hotkeysPage.build())
        addPage(outputPage.title(), outputPage.build())
        addPage(modelsPage.title(), modelsPage.build())
        addPage(aiPage.title(), aiPage.build())
        addPage(dictionaryPage.title(), dictionaryPage.build())
        gtk_widget_set_vexpand(stack, 1)
        gtk_box_append(root?.reinterpret(), stack)

        val actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_widget_set_halign(actions, GTK_ALIGN_END)
        val saveButton = gtk_button_new_with_label("Save")
        val closeButton = gtk_button_new_with_label("Close")
        g_signal_connect_data(closeButton, "clicked", staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
            if (data != null) {
                data.asStableRef<SettingsDialog>().get().close()
            }
        }.reinterpret(), selfRef.asCPointer(), null, 0u)
        g_signal_connect_data(saveButton, "clicked", staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
            if (data != null) {
                val dialog = data.asStableRef<SettingsDialog>().get()
                if (dialog.save()) {
                    dialog.close()
                }
            }
        }.reinterpret(), selfRef.asCPointer(), null, 0u)
        gtk_box_append(actions?.reinterpret(), closeButton)
        gtk_box_append(actions?.reinterpret(), saveButton)
        gtk_box_append(root?.reinterpret(), actions)

        gtk_window_set_child(window?.reinterpret(), root)
    }

    fun show() {
        gtk_window_present(window?.reinterpret())
    }

    fun close() {
        gtk_window_close(window?.reinterpret())
    }

    fun destroy() {
        notifyClosed()
        selfRef.dispose()
    }

    fun save(): Boolean {
        val pending = linkedMapOf<String, Any>()
        pending.putAll(generalPage.values())
        pending.putAll(hotkeysPage.values())
        pending.putAll(outputPage.values())
        pending.putAll(modelsPage.values())
        pending.putAll(aiPage.values())
        pending.putAll(dictionaryPage.values())

        for ((key, value) in pending) {
            when (val validation = SettingsValidation.validateSetting(key, value)) {
                SettingsValidationResult.Valid -> Unit
                is SettingsValidationResult.Invalid -> return false
            }
        }

        for ((key, value) in pending) {
            when (value) {
                is String -> settings.setString(key, value)
                is Boolean -> settings.setBool(key, value)
                is Int -> settings.setInt(key, value)
                is Double -> settings.setDouble(key, value)
            }
        }

        val launchAtLogin = pending[tech.watzon.pindrop.shared.schemasettings.SettingsKeys.launchAtLogin] as? Boolean ?: false
        if (launchAtLogin) autostart.enableAutostart() else autostart.disableAutostart()
        aiPage.saveSecrets()
        settings.save()
        onSaved?.invoke()
        return true
    }

    private fun notifyClosed() {
        if (hasClosed) return
        hasClosed = true
        onClosed?.invoke()
    }

    private fun addPage(title: String, content: CPointer<GtkWidget>?) {
        if (content != null) {
            gtk_stack_add_titled(stack?.reinterpret(), content, title.lowercase(), title)
        }
    }
}

internal fun settingsPageBox(): CPointer<GtkWidget>? {
    val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
    gtk_widget_set_margin_top(box, 8)
    gtk_widget_set_margin_bottom(box, 8)
    return box
}

internal fun pageHeading(title: String, subtitle: String): CPointer<GtkWidget>? {
    val box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)
    val titleLabel = gtk_label_new(title)
    gtk_widget_add_css_class(titleLabel, "title-3")
    gtk_widget_set_halign(titleLabel, GTK_ALIGN_START)
    val subtitleLabel = gtk_label_new(subtitle)
    gtk_label_set_wrap(subtitleLabel?.reinterpret(), 1)
    gtk_widget_add_css_class(subtitleLabel, "dim-label")
    gtk_widget_set_halign(subtitleLabel, GTK_ALIGN_START)
    gtk_box_append(box?.reinterpret(), titleLabel)
    gtk_box_append(box?.reinterpret(), subtitleLabel)
    return box
}

internal fun labeledRow(titleKey: String, control: CPointer<GtkWidget>?, locale: String): CPointer<GtkWidget>? {
    val row = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6)
    val label = gtk_label_new(tech.watzon.pindrop.shared.uilocalization.SharedLocalization.getString(titleKey, locale))
    gtk_widget_set_halign(label, GTK_ALIGN_START)
    gtk_box_append(row?.reinterpret(), label)
    if (control != null) {
        gtk_widget_set_hexpand(control, 1)
        gtk_box_append(row?.reinterpret(), control)
    }
    return row
}

internal fun dropDownStrings(values: List<String>): CValues<CPointer<ByteVar>?> = memScoped {
    allocArray<CPointerVar<ByteVar>>(values.size + 1).apply {
        values.forEachIndexed { index, value ->
            this[index] = value.cstr.getPointer(this@memScoped)
        }
        this[values.size] = null
    }.readValues()
}

internal fun textBufferString(buffer: CPointer<GtkTextBuffer>?): String = memScoped {
    val start = alloc<GtkTextIter>()
    val end = alloc<GtkTextIter>()
    gtk_text_buffer_get_bounds(buffer, start.ptr, end.ptr)
    gtk_text_buffer_get_text(buffer, start.ptr, end.ptr, 0)?.toKString().orEmpty()
}
    private val modelController = LinuxModelController(settings)
