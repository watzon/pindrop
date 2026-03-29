@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.*
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.*
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.*

/**
 * Linux application entry point using GApplication / AdwApplication lifecycle.
 *
 * Creates an AdwApplication with app ID "tech.watzon.pindrop", connects the
 * "activate" signal to spawn the [LinuxCoordinator], and runs the GTK main loop.
 *
 * Created on 2026-03-29.
 */

private var coordinator: LinuxCoordinator? = null

fun main(args: Array<String>) {
    // Initialize libadwaita (registers Adw types with GObject)
    adw_init()

    val app = adw_application_new(
        "tech.watzon.pindrop",
        G_APPLICATION_FLAGS_NONE.toInt().toUInt()
    ) ?: error("Failed to create AdwApplication — is libadwaita installed?")

    // Connect "activate" signal — GApplication calls this on primary instance startup
    g_signal_connect_data(
        app.reinterpret(),
        "activate",
        staticCFunction { appPtr: CPointer<*>?, _ ->
            if (appPtr != null) {
                onActivate(appPtr.reinterpret())
            }
        }.reinterpret(),
        null,
        null,
        0u
    )

    // Run the GApplication main loop (blocks until g_application_quit)
    g_application_run(app.reinterpret(), args.size, null)

    // Cleanup after main loop exits
    coordinator = null
    g_object_unref(app.reinterpret())
}

/**
 * Called when the GApplication receives the "activate" signal.
 * Creates the main window and starts the lifecycle coordinator.
 */
private fun onActivate(app: CPointer<AdwApplication>) {
    val window = adw_application_window_new(app.reinterpret())
    gtk_window_set_title(window.reinterpret(), "Pindrop")
    gtk_window_set_default_size(window.reinterpret(), 400, 300)

    // Create and start the coordinator — loads settings, sets up tray
    val coord = LinuxCoordinator(
        app = app,
        window = window
    )
    coordinator = coord
    coord.start()
}
