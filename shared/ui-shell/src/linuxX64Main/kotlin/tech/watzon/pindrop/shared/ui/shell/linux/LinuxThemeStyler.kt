@file:OptIn(ExperimentalForeignApi::class)

package tech.watzon.pindrop.shared.ui.shell.linux

import kotlinx.cinterop.ExperimentalForeignApi
import tech.watzon.pindrop.shared.core.platform.SettingsPersistence
import tech.watzon.pindrop.shared.schemasettings.SettingsDefaults
import tech.watzon.pindrop.shared.schemasettings.SettingsKeys
import tech.watzon.pindrop.shared.schemasettings.ThemeMode as SettingsThemeMode
import tech.watzon.pindrop.shared.uitheme.ColorTokenValue
import tech.watzon.pindrop.shared.uitheme.ThemeCapabilities
import tech.watzon.pindrop.shared.uitheme.ThemeEngine
import tech.watzon.pindrop.shared.uitheme.ThemeMode
import tech.watzon.pindrop.shared.uitheme.ThemeSelection
import tech.watzon.pindrop.shared.uitheme.ThemeVariant
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gdk_display_get_default
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_css_provider_load_from_data
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_css_provider_new
import tech.watzon.pindrop.shared.uishell.cinterop.gtk4.gtk_style_context_add_provider_for_display
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.ADW_COLOR_SCHEME_DEFAULT
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.ADW_COLOR_SCHEME_FORCE_DARK
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.ADW_COLOR_SCHEME_FORCE_LIGHT
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.adw_style_manager_get_dark
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.adw_style_manager_get_default
import tech.watzon.pindrop.shared.uishell.cinterop.libadwaita.adw_style_manager_set_color_scheme

class LinuxThemeStyler(
    private val settings: SettingsPersistence,
) {
    private val provider = gtk_css_provider_new()
    private var installed = false

    fun apply() {
        val display = gdk_display_get_default() ?: return
        val manager = adw_style_manager_get_default() ?: return
        val modeRaw = settings.getString(SettingsKeys.themeMode) ?: SettingsDefaults.themeMode
        val lightPresetId = settings.getString(SettingsKeys.lightThemePresetID) ?: SettingsDefaults.lightThemePresetID
        val darkPresetId = settings.getString(SettingsKeys.darkThemePresetID) ?: SettingsDefaults.darkThemePresetID
        val mode = when (modeRaw) {
            SettingsThemeMode.LIGHT.rawValue -> ThemeMode.LIGHT
            SettingsThemeMode.DARK.rawValue -> ThemeMode.DARK
            else -> ThemeMode.SYSTEM
        }

        adw_style_manager_set_color_scheme(
            manager,
            when (mode) {
                ThemeMode.LIGHT -> ADW_COLOR_SCHEME_FORCE_LIGHT
                ThemeMode.DARK -> ADW_COLOR_SCHEME_FORCE_DARK
                ThemeMode.SYSTEM -> ADW_COLOR_SCHEME_DEFAULT
            },
        )

        val theme = ThemeEngine.resolveTheme(
            selection = ThemeSelection(
                mode = mode,
                lightPresetId = lightPresetId,
                darkPresetId = darkPresetId,
            ),
            systemVariant = if (adw_style_manager_get_dark(manager) == 1) ThemeVariant.DARK else ThemeVariant.LIGHT,
            capabilities = ThemeCapabilities(
                supportsTranslucentSidebar = false,
                supportsWindowMaterial = false,
                supportsOverlayBlur = false,
                supportsNativeVibrancy = false,
                supportsUnifiedTitlebar = false,
            ),
        )

        gtk_css_provider_load_from_data(provider, buildCss(theme.tokens), -1)
        if (!installed) {
            gtk_style_context_add_provider_for_display(
                display,
                provider?.reinterpret(),
                GTK_STYLE_PROVIDER_PRIORITY_APPLICATION.toUInt(),
            )
            installed = true
        }
    }

    private fun buildCss(tokens: tech.watzon.pindrop.shared.uitheme.ResolvedThemeTokens): String {
        val accentText = if (tokens.accent.red * 0.299 + tokens.accent.green * 0.587 + tokens.accent.blue * 0.114 > 160.0) {
            "#1A1714"
        } else {
            "#FFF8F2"
        }
        return """
            .pindrop-window {
                background: ${tokens.windowBackground.css()};
                color: ${tokens.textPrimary.css()};
            }

            .pindrop-window label {
                color: ${tokens.textPrimary.css()};
            }

            .pindrop-window .dim-label,
            .pindrop-window .caption {
                color: ${tokens.textSecondary.css()};
            }

            .pindrop-window separator {
                color: ${tokens.divider.css()};
                opacity: 0.8;
            }

            .pindrop-panel,
            .pindrop-toolbar,
            .pindrop-summary-card,
            .pindrop-onboarding-page,
            .pindrop-transcript-surface {
                background: ${tokens.surfaceBackground.css()};
                border: 1px solid ${tokens.border.css()};
                border-radius: ${tokens.radius.xl}px;
                box-shadow: 0 ${tokens.shadowScale.sm.y}px ${tokens.shadowScale.sm.radius}px ${tokens.shadow.css()};
            }

            .pindrop-onboarding-page,
            .pindrop-panel,
            .pindrop-transcript-surface {
                padding: ${tokens.spacing.xl}px;
            }

            .pindrop-toolbar {
                padding: ${tokens.spacing.sm}px ${tokens.spacing.md}px;
                background: ${tokens.elevatedSurface.css()};
            }

            .pindrop-summary-card {
                background: ${tokens.elevatedSurface.css()};
            }

            .pindrop-window button {
                min-height: 36px;
                padding: 0 ${tokens.spacing.md}px;
                border-radius: ${tokens.radius.full}px;
                border: 1px solid ${tokens.border.css()};
                background: ${tokens.elevatedSurface.css()};
                color: ${tokens.textPrimary.css()};
                box-shadow: none;
            }

            .pindrop-window button:hover {
                background: ${tokens.sidebarItemHover.css()};
            }

            .pindrop-window button:active {
                background: ${tokens.sidebarItemActive.css()};
            }

            .pindrop-window button.suggested-action {
                background: ${tokens.accent.css()};
                border-color: ${tokens.accentSecondary.css()};
                color: $accentText;
            }

            .pindrop-window entry,
            .pindrop-window textview,
            .pindrop-window text,
            .pindrop-window dropdown > button,
            .pindrop-window switch {
                background: ${tokens.inputBackground.css()};
                color: ${tokens.textPrimary.css()};
                border-color: ${tokens.inputBorder.css()};
                border-radius: ${tokens.radius.lg}px;
            }

            .pindrop-window entry:focus,
            .pindrop-window textview:focus,
            .pindrop-window dropdown > button:focus {
                border-color: ${tokens.inputBorderFocused.css()};
                box-shadow: 0 0 0 3px ${tokens.accentBackground.css()};
            }

            .pindrop-window switch:checked {
                background: ${tokens.accent.css()};
            }

            .pindrop-window .accent,
            .pindrop-window .success,
            .pindrop-window .warning {
                color: ${tokens.accent.css()};
            }
        """.trimIndent()
    }
}

private fun ColorTokenValue.css(): String {
    return if (alpha >= 255) {
        "#%02x%02x%02x".format(red, green, blue)
    } else {
        "rgba($red, $green, $blue, ${alpha / 255.0})"
    }
}
