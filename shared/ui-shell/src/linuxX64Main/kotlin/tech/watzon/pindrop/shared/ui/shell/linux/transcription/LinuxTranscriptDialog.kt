@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux.transcription

import kotlinx.cinterop.*
import platform.posix.pclose
import platform.posix.popen
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*

class LinuxTranscriptDialog(
    private val parentWindow: CPointer<GtkWidget>,
    private val transcript: String,
) {
    private val window = gtk_window_new()
    private val selfRef = StableRef.create(this)

    init {
        gtk_window_set_title(window?.reinterpret(), "Transcript")
        gtk_window_set_default_size(window?.reinterpret(), 640, 420)
        gtk_window_set_modal(window?.reinterpret(), 1)
        gtk_window_set_transient_for(window?.reinterpret(), parentWindow.reinterpret())
        gtk_widget_add_css_class(window, "pindrop-window")

        val root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
        gtk_widget_add_css_class(root, "pindrop-transcript-surface")
        gtk_widget_set_margin_top(root, 16)
        gtk_widget_set_margin_bottom(root, 16)
        gtk_widget_set_margin_start(root, 16)
        gtk_widget_set_margin_end(root, 16)

        val textView = gtk_text_view_new()
        gtk_text_view_set_editable(textView?.reinterpret(), 0)
        gtk_text_view_set_wrap_mode(textView?.reinterpret(), GTK_WRAP_WORD_CHAR)
        val buffer = gtk_text_view_get_buffer(textView?.reinterpret())
        gtk_text_buffer_set_text(buffer, transcript, transcript.length)
        gtk_widget_set_vexpand(textView, 1)
        gtk_box_append(root?.reinterpret(), textView)

        val actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_widget_set_halign(actions, GTK_ALIGN_END)
        val copyButton = gtk_button_new_with_label("Copy")
        val closeButton = gtk_button_new_with_label("Close")
        g_signal_connect_data(copyButton, "clicked", staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
            data?.asStableRef<LinuxTranscriptDialog>()?.get()?.copyTranscript()
        }.reinterpret(), selfRef.asCPointer(), null, 0u)
        g_signal_connect_data(closeButton, "clicked", staticCFunction { _: CPointer<*>?, data: CPointer<*>? ->
            data?.asStableRef<LinuxTranscriptDialog>()?.get()?.close()
        }.reinterpret(), selfRef.asCPointer(), null, 0u)
        gtk_box_append(actions?.reinterpret(), copyButton)
        gtk_box_append(actions?.reinterpret(), closeButton)
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
        selfRef.dispose()
    }

    private fun copyTranscript() {
        tryCopyWithCommand("wl-copy") || tryCopyWithCommand("xclip -selection clipboard") || tryCopyWithCommand("xsel --clipboard --input")
    }

    private fun tryCopyWithCommand(command: String): Boolean {
        val process = popen(command, "w") ?: return false
        return try {
            transcript.forEach { ch -> platform.posix.fputc(ch.code, process) }
            true
        } finally {
            pclose(process)
        }
    }
}
