package tech.watzon.pindrop.shared.uitheme

import kotlin.math.roundToInt

enum class ThemeMode {
    SYSTEM,
    LIGHT,
    DARK,
}

enum class ThemeVariant {
    LIGHT,
    DARK,
}

enum class SurfaceStyle {
    SOLID,
    ELEVATED,
    MUTED,
    TRANSLUCENT,
    OVERLAY_STRONG,
}

enum class SidebarTreatment {
    SOLID,
    TRANSLUCENT,
}

enum class OverlayTreatment {
    SOLID,
    BLURRED,
    HIGH_CONTRAST,
}

enum class WindowChromeTreatment {
    STANDARD,
    UNIFIED,
    TRANSPARENT_TITLEBAR,
}

enum class TypographyDesign {
    ROUNDED,
    MONOSPACED,
}

data class ThemeProfile(
    val accentHex: String,
    val backgroundHex: String,
    val foregroundHex: String,
    val contrast: Double,
    val successHex: String,
    val warningHex: String,
    val dangerHex: String,
    val processingHex: String,
)

data class ThemePreset(
    val id: String,
    val title: String,
    val summary: String,
    val badgeText: String,
    val badgeBackgroundHex: String,
    val badgeForegroundHex: String,
    val lightTheme: ThemeProfile,
    val darkTheme: ThemeProfile,
) {
    fun profileFor(variant: ThemeVariant): ThemeProfile {
        return when (variant) {
            ThemeVariant.LIGHT -> lightTheme
            ThemeVariant.DARK -> darkTheme
        }
    }
}

data class ThemeSelection(
    val mode: ThemeMode,
    val lightPresetId: String,
    val darkPresetId: String,
)

data class ThemeCapabilities(
    val supportsTranslucentSidebar: Boolean,
    val supportsWindowMaterial: Boolean,
    val supportsOverlayBlur: Boolean,
    val supportsNativeVibrancy: Boolean,
    val supportsUnifiedTitlebar: Boolean,
)

data class ColorTokenValue(
    val red: Int,
    val green: Int,
    val blue: Int,
    val alpha: Int = 255,
)

data class ShadowTokenValue(
    val color: ColorTokenValue,
    val radius: Double,
    val x: Double,
    val y: Double,
)

data class TypographyTokenValue(
    val size: Double,
    val weight: Int,
    val design: TypographyDesign,
)

data class SpacingScale(
    val xxs: Double,
    val xs: Double,
    val sm: Double,
    val md: Double,
    val lg: Double,
    val xl: Double,
    val xxl: Double,
    val xxxl: Double,
    val huge: Double,
)

data class RadiusScale(
    val sm: Double,
    val md: Double,
    val lg: Double,
    val xl: Double,
    val full: Double,
)

data class ShadowScale(
    val sm: ShadowTokenValue,
    val md: ShadowTokenValue,
    val lg: ShadowTokenValue,
)

data class TypographyScale(
    val largeTitle: TypographyTokenValue,
    val title: TypographyTokenValue,
    val headline: TypographyTokenValue,
    val subheadline: TypographyTokenValue,
    val body: TypographyTokenValue,
    val bodySmall: TypographyTokenValue,
    val caption: TypographyTokenValue,
    val tiny: TypographyTokenValue,
    val mono: TypographyTokenValue,
    val monoSmall: TypographyTokenValue,
    val statLarge: TypographyTokenValue,
    val statMedium: TypographyTokenValue,
)

data class ThemePreviewModel(
    val presetId: String,
    val title: String,
    val summary: String,
    val badgeText: String,
    val badgeBackground: ColorTokenValue,
    val badgeForeground: ColorTokenValue,
    val background: ColorTokenValue,
    val foreground: ColorTokenValue,
    val accent: ColorTokenValue,
)

data class ResolvedThemeTokens(
    val windowBackground: ColorTokenValue,
    val sidebarBackground: ColorTokenValue,
    val contentBackground: ColorTokenValue,
    val surfaceBackground: ColorTokenValue,
    val elevatedSurface: ColorTokenValue,
    val mutedSurface: ColorTokenValue,
    val inputBackground: ColorTokenValue,
    val inputBorder: ColorTokenValue,
    val inputBorderFocused: ColorTokenValue,
    val accent: ColorTokenValue,
    val accentSecondary: ColorTokenValue,
    val accentBackground: ColorTokenValue,
    val textPrimary: ColorTokenValue,
    val textSecondary: ColorTokenValue,
    val textTertiary: ColorTokenValue,
    val border: ColorTokenValue,
    val divider: ColorTokenValue,
    val success: ColorTokenValue,
    val successBackground: ColorTokenValue,
    val warning: ColorTokenValue,
    val warningBackground: ColorTokenValue,
    val error: ColorTokenValue,
    val errorBackground: ColorTokenValue,
    val recording: ColorTokenValue,
    val processing: ColorTokenValue,
    val sidebarItemHover: ColorTokenValue,
    val sidebarItemActive: ColorTokenValue,
    val overlaySurface: ColorTokenValue,
    val overlaySurfaceStrong: ColorTokenValue,
    val overlayLine: ColorTokenValue,
    val overlayTextPrimary: ColorTokenValue,
    val overlayTextSecondary: ColorTokenValue,
    val overlayWaveform: ColorTokenValue,
    val overlayRecording: ColorTokenValue,
    val overlayWarning: ColorTokenValue,
    val overlayTooltipAccent: ColorTokenValue,
    val shadow: ColorTokenValue,
    val spacing: SpacingScale,
    val radius: RadiusScale,
    val shadowScale: ShadowScale,
    val typography: TypographyScale,
)

data class ResolvedTheme(
    val effectiveVariant: ThemeVariant,
    val selectedPreset: ThemePreset,
    val requestedSidebarTreatment: SidebarTreatment,
    val adaptedSidebarTreatment: SidebarTreatment,
    val requestedOverlayTreatment: OverlayTreatment,
    val adaptedOverlayTreatment: OverlayTreatment,
    val requestedWindowChromeTreatment: WindowChromeTreatment,
    val adaptedWindowChromeTreatment: WindowChromeTreatment,
    val tokens: ResolvedThemeTokens,
)

object ThemeCatalog {
    const val defaultPresetId: String = "pindrop"

    private val presetList = listOf(
        ThemePreset(
            id = "pindrop",
            title = "Pindrop",
            summary = "Warm editorial surfaces with a copper signal accent.",
            badgeText = "Pd",
            badgeBackgroundHex = "#F7F1E8",
            badgeForegroundHex = "#C56E42",
            lightTheme = ThemeProfile("#C56E42", "#F7F1E8", "#221A14", 50.0, "#2E8B67", "#A9692D", "#C95452", "#4D78D6"),
            darkTheme = ThemeProfile("#E19260", "#15120F", "#F2E5D8", 66.0, "#53B48A", "#D09049", "#E5726E", "#74A2FF"),
        ),
        ThemePreset(
            id = "paper",
            title = "Paper",
            summary = "Quiet parchment tones with ink-forward contrast.",
            badgeText = "Aa",
            badgeBackgroundHex = "#FBF7EF",
            badgeForegroundHex = "#2E4E73",
            lightTheme = ThemeProfile("#2E4E73", "#FBF7EF", "#1A1712", 46.0, "#2D7D5A", "#9C6B24", "#BD514A", "#3A67C3"),
            darkTheme = ThemeProfile("#89A9D4", "#1A1816", "#F4EEE5", 62.0, "#58B48B", "#D09B53", "#E87C74", "#7FA7FF"),
        ),
        ThemePreset(
            id = "harbor",
            title = "Harbor",
            summary = "Cool blue-gray chrome with a crisp marine accent.",
            badgeText = "Hb",
            badgeBackgroundHex = "#EFF5F7",
            badgeForegroundHex = "#14708A",
            lightTheme = ThemeProfile("#14708A", "#EFF5F7", "#14232B", 48.0, "#2F8663", "#B0702D", "#C85652", "#2F78D0"),
            darkTheme = ThemeProfile("#5AB4D4", "#0F171C", "#E3F0F5", 67.0, "#5FB98C", "#D59A4F", "#E3716D", "#69A8FF"),
        ),
        ThemePreset(
            id = "evergreen",
            title = "Evergreen",
            summary = "Forest-tinted utility palette with a calm studio feel.",
            badgeText = "Eg",
            badgeBackgroundHex = "#F3F5EE",
            badgeForegroundHex = "#4D7A4A",
            lightTheme = ThemeProfile("#4D7A4A", "#F3F5EE", "#1C2019", 47.0, "#3A8B5B", "#AA6D26", "#B84F49", "#4A74C9"),
            darkTheme = ThemeProfile("#87B57D", "#101411", "#E6EEE1", 65.0, "#64BC85", "#D29648", "#DF6F68", "#7EA7FF"),
        ),
        ThemePreset(
            id = "graphite",
            title = "Graphite",
            summary = "Neutral monochrome with a high-signal cobalt edge.",
            badgeText = "Gr",
            badgeBackgroundHex = "#F4F5F7",
            badgeForegroundHex = "#4B65D6",
            lightTheme = ThemeProfile("#4B65D6", "#F4F5F7", "#16181D", 49.0, "#2C8A67", "#A66821", "#C34C50", "#507BFF"),
            darkTheme = ThemeProfile("#7D93FF", "#101114", "#ECEFF4", 70.0, "#5DBD93", "#D69D55", "#E77A80", "#87A7FF"),
        ),
        ThemePreset(
            id = "signal",
            title = "Signal",
            summary = "Dark broadcast palette with a vivid red-orange pulse.",
            badgeText = "Sg",
            badgeBackgroundHex = "#181211",
            badgeForegroundHex = "#F06D4F",
            lightTheme = ThemeProfile("#D95E45", "#FBF4F1", "#251816", 51.0, "#2C8863", "#AF6A21", "#C94E4B", "#466AD4"),
            darkTheme = ThemeProfile("#F06D4F", "#181211", "#F5E7E2", 72.0, "#53B98A", "#DD9745", "#F5847A", "#7EA4FF"),
        ),
    )

    fun presets(): List<ThemePreset> = presetList

    fun preset(id: String?): ThemePreset {
        return presetList.firstOrNull { it.id == id }
            ?: presetList.firstOrNull { it.id == defaultPresetId }
            ?: presetList.first()
    }

    fun previewModels(variant: ThemeVariant): List<ThemePreviewModel> {
        return presetList.map { preset ->
            val profile = preset.profileFor(variant)
            ThemePreviewModel(
                presetId = preset.id,
                title = preset.title,
                summary = preset.summary,
                badgeText = preset.badgeText,
                badgeBackground = colorFromHex(preset.badgeBackgroundHex) ?: colorFromHex("#FFFFFF")!!,
                badgeForeground = colorFromHex(preset.badgeForegroundHex) ?: colorFromHex("#000000")!!,
                background = colorFromHex(profile.backgroundHex) ?: colorFromHex("#FFFFFF")!!,
                foreground = colorFromHex(profile.foregroundHex) ?: colorFromHex("#000000")!!,
                accent = colorFromHex(profile.accentHex) ?: colorFromHex("#FF7A00")!!,
            )
        }
    }
}

object ThemeEngine {
    fun resolveTheme(
        selection: ThemeSelection,
        systemVariant: ThemeVariant,
        capabilities: ThemeCapabilities,
    ): ResolvedTheme {
        val effectiveVariant = when (selection.mode) {
            ThemeMode.SYSTEM -> systemVariant
            ThemeMode.LIGHT -> ThemeVariant.LIGHT
            ThemeMode.DARK -> ThemeVariant.DARK
        }
        val presetId = when (effectiveVariant) {
            ThemeVariant.LIGHT -> selection.lightPresetId
            ThemeVariant.DARK -> selection.darkPresetId
        }
        val preset = ThemeCatalog.preset(presetId)
        val profile = preset.profileFor(effectiveVariant)
        val requestedSidebarTreatment = SidebarTreatment.TRANSLUCENT
        val requestedOverlayTreatment = OverlayTreatment.BLURRED
        val requestedWindowChromeTreatment = WindowChromeTreatment.TRANSPARENT_TITLEBAR

        return ResolvedTheme(
            effectiveVariant = effectiveVariant,
            selectedPreset = preset,
            requestedSidebarTreatment = requestedSidebarTreatment,
            adaptedSidebarTreatment = if (capabilities.supportsTranslucentSidebar) {
                requestedSidebarTreatment
            } else {
                SidebarTreatment.SOLID
            },
            requestedOverlayTreatment = requestedOverlayTreatment,
            adaptedOverlayTreatment = if (capabilities.supportsOverlayBlur) {
                requestedOverlayTreatment
            } else {
                OverlayTreatment.HIGH_CONTRAST
            },
            requestedWindowChromeTreatment = requestedWindowChromeTreatment,
            adaptedWindowChromeTreatment = when {
                capabilities.supportsUnifiedTitlebar && capabilities.supportsWindowMaterial -> WindowChromeTreatment.TRANSPARENT_TITLEBAR
                capabilities.supportsUnifiedTitlebar -> WindowChromeTreatment.UNIFIED
                else -> WindowChromeTreatment.STANDARD
            },
            tokens = resolveTokens(profile, effectiveVariant == ThemeVariant.DARK),
        )
    }

    private fun resolveTokens(profile: ThemeProfile, isDark: Boolean): ResolvedThemeTokens {
        val background = colorFromHex(profile.backgroundHex)
            ?: if (isDark) color(20, 20, 23) else color(247, 245, 240)
        val foreground = colorFromHex(profile.foregroundHex)
            ?: if (isDark) color(255, 255, 255) else color(0, 0, 0)
        val accentBase = colorFromHex(profile.accentHex) ?: color(255, 122, 0)
        val successBase = colorFromHex(profile.successHex) ?: color(52, 199, 89)
        val warningBase = colorFromHex(profile.warningHex) ?: color(255, 149, 0)
        val dangerBase = colorFromHex(profile.dangerHex) ?: color(255, 59, 48)
        val processingBase = colorFromHex(profile.processingHex) ?: color(0, 122, 255)
        val contrast = profile.contrast.coerceIn(20.0, 80.0) / 100.0

        val colors = if (isDark) {
            DarkTokens(
                windowBackground = background,
                sidebarBackground = background.lighter(0.035),
                contentBackground = background.lighter(0.015),
                surfaceBackground = background.lighter(0.055 + contrast * 0.035),
                elevatedSurface = background.lighter(0.09 + contrast * 0.045),
                mutedSurface = foreground.withAlpha(0.06 + contrast * 0.02),
                inputBackground = background.lighter(0.075 + contrast * 0.03),
                inputBorder = foreground.withAlpha(0.14 + contrast * 0.06),
                inputBorderFocused = accentBase.withAlpha(0.78),
                accent = accentBase,
                accentSecondary = accentBase.mixed(foreground, 0.22),
                accentBackground = accentBase.mixed(background, 0.86),
                textPrimary = foreground,
                textSecondary = foreground.withAlpha(0.72),
                textTertiary = foreground.withAlpha(0.48),
                border = foreground.withAlpha(0.11 + contrast * 0.05),
                divider = foreground.withAlpha(0.08 + contrast * 0.04),
                success = successBase,
                successBackground = successBase.mixed(background, 0.88),
                warning = warningBase,
                warningBackground = warningBase.mixed(background, 0.88),
                error = dangerBase,
                errorBackground = dangerBase.mixed(background, 0.89),
                recording = dangerBase,
                processing = processingBase,
                sidebarItemHover = foreground.withAlpha(0.065),
                sidebarItemActive = accentBase.mixed(background, 0.82),
                overlaySurface = background.darker(0.24),
                overlaySurfaceStrong = background.darker(0.32),
                overlayLine = foreground.withAlpha(0.18),
                overlayTextPrimary = color(255, 255, 255).withAlpha(0.96),
                overlayTextSecondary = color(255, 255, 255).withAlpha(0.74),
                overlayWaveform = accentBase.mixed(color(255, 255, 255), 0.24),
                overlayRecording = dangerBase.mixed(color(255, 255, 255), 0.12),
                overlayWarning = warningBase,
                overlayTooltipAccent = accentBase.mixed(color(255, 255, 255), 0.3),
                shadow = color(0, 0, 0),
            )
        } else {
            DarkTokens(
                windowBackground = background,
                sidebarBackground = background.darker(0.018),
                contentBackground = background.lighter(0.005),
                surfaceBackground = background.lighter(0.025),
                elevatedSurface = background.darker(0.02 + contrast * 0.01),
                mutedSurface = foreground.withAlpha(0.045 + contrast * 0.02),
                inputBackground = background.lighter(0.015),
                inputBorder = foreground.withAlpha(0.14 + contrast * 0.04),
                inputBorderFocused = accentBase.withAlpha(0.72),
                accent = accentBase,
                accentSecondary = accentBase.mixed(foreground, 0.18),
                accentBackground = accentBase.mixed(background, 0.92),
                textPrimary = foreground,
                textSecondary = foreground.withAlpha(0.7),
                textTertiary = foreground.withAlpha(0.48),
                border = foreground.withAlpha(0.1 + contrast * 0.04),
                divider = foreground.withAlpha(0.07 + contrast * 0.03),
                success = successBase,
                successBackground = successBase.mixed(background, 0.93),
                warning = warningBase,
                warningBackground = warningBase.mixed(background, 0.93),
                error = dangerBase,
                errorBackground = dangerBase.mixed(background, 0.94),
                recording = dangerBase,
                processing = processingBase,
                sidebarItemHover = foreground.withAlpha(0.05),
                sidebarItemActive = accentBase.mixed(background, 0.87),
                overlaySurface = background.darker(0.82),
                overlaySurfaceStrong = background.darker(0.9),
                overlayLine = color(255, 255, 255).withAlpha(0.14),
                overlayTextPrimary = color(255, 255, 255).withAlpha(0.96),
                overlayTextSecondary = color(255, 255, 255).withAlpha(0.74),
                overlayWaveform = accentBase.mixed(color(255, 255, 255), 0.42),
                overlayRecording = dangerBase.mixed(color(255, 255, 255), 0.18),
                overlayWarning = warningBase.mixed(color(255, 255, 255), 0.18),
                overlayTooltipAccent = accentBase.mixed(color(255, 255, 255), 0.42),
                shadow = foreground,
            )
        }

        val spacing = SpacingScale(4.0, 6.0, 10.0, 14.0, 18.0, 24.0, 32.0, 40.0, 56.0)
        val radius = RadiusScale(8.0, 12.0, 18.0, 24.0, 9999.0)
        val shadowScale = ShadowScale(
            sm = ShadowTokenValue(colors.shadow.withAlpha(0.08), 6.0, 0.0, 2.0),
            md = ShadowTokenValue(colors.shadow.withAlpha(0.14), 16.0, 0.0, 8.0),
            lg = ShadowTokenValue(colors.shadow.withAlpha(0.2), 30.0, 0.0, 18.0),
        )
        val typography = TypographyScale(
            largeTitle = TypographyTokenValue(30.0, 600, TypographyDesign.ROUNDED),
            title = TypographyTokenValue(21.0, 600, TypographyDesign.ROUNDED),
            headline = TypographyTokenValue(16.0, 600, TypographyDesign.ROUNDED),
            subheadline = TypographyTokenValue(14.0, 600, TypographyDesign.ROUNDED),
            body = TypographyTokenValue(14.0, 400, TypographyDesign.ROUNDED),
            bodySmall = TypographyTokenValue(13.0, 400, TypographyDesign.ROUNDED),
            caption = TypographyTokenValue(12.0, 500, TypographyDesign.ROUNDED),
            tiny = TypographyTokenValue(11.0, 500, TypographyDesign.ROUNDED),
            mono = TypographyTokenValue(13.0, 500, TypographyDesign.MONOSPACED),
            monoSmall = TypographyTokenValue(11.0, 500, TypographyDesign.MONOSPACED),
            statLarge = TypographyTokenValue(32.0, 700, TypographyDesign.ROUNDED),
            statMedium = TypographyTokenValue(24.0, 600, TypographyDesign.ROUNDED),
        )

        return ResolvedThemeTokens(
            windowBackground = colors.windowBackground,
            sidebarBackground = colors.sidebarBackground,
            contentBackground = colors.contentBackground,
            surfaceBackground = colors.surfaceBackground,
            elevatedSurface = colors.elevatedSurface,
            mutedSurface = colors.mutedSurface,
            inputBackground = colors.inputBackground,
            inputBorder = colors.inputBorder,
            inputBorderFocused = colors.inputBorderFocused,
            accent = colors.accent,
            accentSecondary = colors.accentSecondary,
            accentBackground = colors.accentBackground,
            textPrimary = colors.textPrimary,
            textSecondary = colors.textSecondary,
            textTertiary = colors.textTertiary,
            border = colors.border,
            divider = colors.divider,
            success = colors.success,
            successBackground = colors.successBackground,
            warning = colors.warning,
            warningBackground = colors.warningBackground,
            error = colors.error,
            errorBackground = colors.errorBackground,
            recording = colors.recording,
            processing = colors.processing,
            sidebarItemHover = colors.sidebarItemHover,
            sidebarItemActive = colors.sidebarItemActive,
            overlaySurface = colors.overlaySurface,
            overlaySurfaceStrong = colors.overlaySurfaceStrong,
            overlayLine = colors.overlayLine,
            overlayTextPrimary = colors.overlayTextPrimary,
            overlayTextSecondary = colors.overlayTextSecondary,
            overlayWaveform = colors.overlayWaveform,
            overlayRecording = colors.overlayRecording,
            overlayWarning = colors.overlayWarning,
            overlayTooltipAccent = colors.overlayTooltipAccent,
            shadow = colors.shadow,
            spacing = spacing,
            radius = radius,
            shadowScale = shadowScale,
            typography = typography,
        )
    }
}

private data class DarkTokens(
    val windowBackground: ColorTokenValue,
    val sidebarBackground: ColorTokenValue,
    val contentBackground: ColorTokenValue,
    val surfaceBackground: ColorTokenValue,
    val elevatedSurface: ColorTokenValue,
    val mutedSurface: ColorTokenValue,
    val inputBackground: ColorTokenValue,
    val inputBorder: ColorTokenValue,
    val inputBorderFocused: ColorTokenValue,
    val accent: ColorTokenValue,
    val accentSecondary: ColorTokenValue,
    val accentBackground: ColorTokenValue,
    val textPrimary: ColorTokenValue,
    val textSecondary: ColorTokenValue,
    val textTertiary: ColorTokenValue,
    val border: ColorTokenValue,
    val divider: ColorTokenValue,
    val success: ColorTokenValue,
    val successBackground: ColorTokenValue,
    val warning: ColorTokenValue,
    val warningBackground: ColorTokenValue,
    val error: ColorTokenValue,
    val errorBackground: ColorTokenValue,
    val recording: ColorTokenValue,
    val processing: ColorTokenValue,
    val sidebarItemHover: ColorTokenValue,
    val sidebarItemActive: ColorTokenValue,
    val overlaySurface: ColorTokenValue,
    val overlaySurfaceStrong: ColorTokenValue,
    val overlayLine: ColorTokenValue,
    val overlayTextPrimary: ColorTokenValue,
    val overlayTextSecondary: ColorTokenValue,
    val overlayWaveform: ColorTokenValue,
    val overlayRecording: ColorTokenValue,
    val overlayWarning: ColorTokenValue,
    val overlayTooltipAccent: ColorTokenValue,
    val shadow: ColorTokenValue,
)

private fun color(red: Int, green: Int, blue: Int, alpha: Int = 255): ColorTokenValue {
    return ColorTokenValue(red, green, blue, alpha)
}

private fun colorFromHex(hex: String): ColorTokenValue? {
    val cleaned = hex.trim().removePrefix("#")
    if (cleaned.length != 6) return null
    val hexValue = cleaned.toIntOrNull(16) ?: return null
    return color(
        red = (hexValue shr 16) and 0xFF,
        green = (hexValue shr 8) and 0xFF,
        blue = hexValue and 0xFF,
    )
}

private fun ColorTokenValue.withAlpha(alpha: Double): ColorTokenValue {
    return copy(alpha = (alpha.coerceIn(0.0, 1.0) * 255.0).roundToInt())
}

private fun ColorTokenValue.mixed(other: ColorTokenValue, ratio: Double): ColorTokenValue {
    val clampedRatio = ratio.coerceIn(0.0, 1.0)
    val inverse = 1.0 - clampedRatio
    return color(
        red = ((red * inverse) + (other.red * clampedRatio)).roundToInt(),
        green = ((green * inverse) + (other.green * clampedRatio)).roundToInt(),
        blue = ((blue * inverse) + (other.blue * clampedRatio)).roundToInt(),
        alpha = ((alpha * inverse) + (other.alpha * clampedRatio)).roundToInt(),
    )
}

private fun ColorTokenValue.lighter(amount: Double): ColorTokenValue = mixed(color(255, 255, 255), amount)

private fun ColorTokenValue.darker(amount: Double): ColorTokenValue = mixed(color(0, 0, 0), amount)
