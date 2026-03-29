package tech.watzon.pindrop.shared.uitheme

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ThemeEngineTest {
    private val macCapabilities = ThemeCapabilities(
        supportsTranslucentSidebar = true,
        supportsWindowMaterial = true,
        supportsOverlayBlur = true,
        supportsNativeVibrancy = true,
        supportsUnifiedTitlebar = true,
    )

    @Test
    fun presetLookupFallsBackToDefault() {
        assertEquals(ThemeCatalog.defaultPresetId, ThemeCatalog.preset("missing").id)
    }

    @Test
    fun resolveThemeUsesSystemVariantWhenModeIsSystem() {
        val resolved = ThemeEngine.resolveTheme(
            selection = ThemeSelection(ThemeMode.SYSTEM, "paper", "signal"),
            systemVariant = ThemeVariant.DARK,
            capabilities = macCapabilities,
        )

        assertEquals(ThemeVariant.DARK, resolved.effectiveVariant)
        assertEquals("signal", resolved.selectedPreset.id)
    }

    @Test
    fun resolveThemeClampsContrastAndProducesOpaqueWindowBackground() {
        val preset = ThemePreset(
            id = "contrast-test",
            title = "Contrast",
            summary = "Contrast",
            badgeText = "Ct",
            badgeBackgroundHex = "#FFFFFF",
            badgeForegroundHex = "#000000",
            lightTheme = ThemeProfile("#445566", "#EEEEEE", "#111111", 500.0, "#00FF00", "#FFAA00", "#FF0000", "#0000FF"),
            darkTheme = ThemeProfile("#445566", "#111111", "#EEEEEE", -100.0, "#00FF00", "#FFAA00", "#FF0000", "#0000FF"),
        )

        assertEquals("contrast-test", preset.id)

        val resolved = ThemeEngine.resolveTheme(
            selection = ThemeSelection(ThemeMode.LIGHT, "contrast-test", "contrast-test"),
            systemVariant = ThemeVariant.LIGHT,
            capabilities = macCapabilities,
        )

        assertEquals(255, resolved.tokens.windowBackground.alpha)
        assertTrue(resolved.tokens.border.alpha > 0)
    }

    @Test
    fun unsupportedCapabilitiesProduceDeterministicFallbackTreatments() {
        val resolved = ThemeEngine.resolveTheme(
            selection = ThemeSelection(ThemeMode.DARK, "pindrop", "signal"),
            systemVariant = ThemeVariant.DARK,
            capabilities = ThemeCapabilities(
                supportsTranslucentSidebar = false,
                supportsWindowMaterial = false,
                supportsOverlayBlur = false,
                supportsNativeVibrancy = false,
                supportsUnifiedTitlebar = false,
            ),
        )

        assertEquals(SidebarTreatment.SOLID, resolved.adaptedSidebarTreatment)
        assertEquals(OverlayTreatment.HIGH_CONTRAST, resolved.adaptedOverlayTreatment)
        assertEquals(WindowChromeTreatment.STANDARD, resolved.adaptedWindowChromeTreatment)
    }

    @Test
    fun previewModelsExposeStablePaletteMetadata() {
        val previews = ThemeCatalog.previewModels(ThemeVariant.LIGHT)

        assertFalse(previews.isEmpty())
        assertTrue(previews.any { it.presetId == ThemeCatalog.defaultPresetId })
    }
}
