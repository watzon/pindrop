//
//  Theme.swift
//  Pindrop
//
//  Design system foundation for Wispr Flow-inspired UI
//

import SwiftUI

// MARK: - App Theme

/// Central theme configuration supporting light/dark modes
/// Inspired by Wispr Flow's clean, minimal aesthetic
enum AppTheme {
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    
    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        static let md = ShadowStyle(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        static let lg = ShadowStyle(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Window Dimensions
    
    enum Window {
        static let mainMinWidth: CGFloat = 900
        static let mainMinHeight: CGFloat = 600
        static let mainDefaultWidth: CGFloat = 1186
        static let mainDefaultHeight: CGFloat = 753
        
        static let sidebarWidth: CGFloat = 220
        static let sidebarCollapsedWidth: CGFloat = 64
        
        static let settingsMinWidth: CGFloat = 700
        static let settingsMinHeight: CGFloat = 500
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let fast: SwiftUI.Animation = .easeOut(duration: 0.15)
        static let normal: SwiftUI.Animation = .easeInOut(duration: 0.25)
        static let smooth: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.8)
        static let bouncy: SwiftUI.Animation = .spring(response: 0.4, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - App Colors

/// Semantic color system with light/dark mode support
enum AppColors {
    
    // MARK: - Backgrounds
    
    /// Main window background
    static var windowBackground: Color {
        Color("WindowBackground", bundle: nil)
    }
    
    /// Sidebar background - slightly different from main content
    static var sidebarBackground: Color {
        Color("SidebarBackground", bundle: nil)
    }
    
    /// Content area background
    static var contentBackground: Color {
        Color("ContentBackground", bundle: nil)
    }
    
    /// Card/surface background
    static var surfaceBackground: Color {
        Color("SurfaceBackground", bundle: nil)
    }
    
    /// Elevated surface (cards, popovers)
    static var elevatedSurface: Color {
        Color("ElevatedSurface", bundle: nil)
    }
    
    // MARK: - Accents
    
    /// Primary accent - warm yellow/amber for highlights (like Wispr Flow)
    static var accent: Color {
        Color("AccentPrimary", bundle: nil)
    }
    
    /// Secondary accent - softer variant
    static var accentSecondary: Color {
        Color("AccentSecondary", bundle: nil)
    }
    
    /// Accent background - for highlighted cards/sections
    static var accentBackground: Color {
        Color("AccentBackground", bundle: nil)
    }
    
    // MARK: - Text
    
    /// Primary text color
    static var textPrimary: Color {
        Color("TextPrimary", bundle: nil)
    }
    
    /// Secondary/muted text
    static var textSecondary: Color {
        Color("TextSecondary", bundle: nil)
    }
    
    /// Tertiary/disabled text
    static var textTertiary: Color {
        Color("TextTertiary", bundle: nil)
    }
    
    // MARK: - Borders & Dividers
    
    /// Subtle border color
    static var border: Color {
        Color("Border", bundle: nil)
    }
    
    /// Divider lines
    static var divider: Color {
        Color("Divider", bundle: nil)
    }
    
    // MARK: - Semantic Colors
    
    /// Success state
    static var success: Color {
        Color.green
    }
    
    /// Warning state
    static var warning: Color {
        Color.orange
    }
    
    /// Error state
    static var error: Color {
        Color.red
    }
    
    /// Recording indicator
    static var recording: Color {
        Color.red
    }
    
    /// Processing indicator
    static var processing: Color {
        Color.blue
    }
    
    // MARK: - Sidebar
    
    /// Sidebar item hover/selection background
    static var sidebarItemHover: Color {
        Color("SidebarItemHover", bundle: nil)
    }
    
    /// Sidebar item active/selected background
    static var sidebarItemActive: Color {
        Color("SidebarItemActive", bundle: nil)
    }
}

// MARK: - Typography

enum AppTypography {
    
    // MARK: - Headlines
    
    /// Large title - Dashboard welcome
    static let largeTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
    
    /// Section title
    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    
    /// Card title
    static let headline = Font.system(size: 16, weight: .semibold, design: .default)
    
    /// Subheadline
    static let subheadline = Font.system(size: 14, weight: .medium, design: .default)
    
    // MARK: - Body
    
    /// Primary body text
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Secondary body text
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // MARK: - Supporting
    
    /// Captions, metadata
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    
    /// Tiny labels
    static let tiny = Font.system(size: 11, weight: .regular, design: .default)
    
    // MARK: - Monospace
    
    /// Code, keyboard shortcuts
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    
    /// Small mono
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    
    // MARK: - Stats
    
    /// Large stat numbers
    static let statLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    
    /// Medium stat numbers
    static let statMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
}

// MARK: - View Modifiers

extension View {
    
    /// Apply card styling with optional elevation
    func cardStyle(elevated: Bool = false) -> some View {
        self
            .background(elevated ? AppColors.elevatedSurface : AppColors.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(AppColors.border, lineWidth: 0.5)
            )
    }
    
    /// Apply shadow based on style
    func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
    
    /// Sidebar item styling
    func sidebarItemStyle(isSelected: Bool, isHovered: Bool) -> some View {
        self
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? AppColors.sidebarItemActive : (isHovered ? AppColors.sidebarItemHover : Color.clear))
            )
    }
    
    /// Highlighted card (like the hotkey reminder in Wispr Flow)
    func highlightedCardStyle() -> some View {
        self
            .background(AppColors.accentBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
    }
}

// MARK: - Preview

#Preview("Theme Colors - Light") {
    ThemePreviewView()
        .preferredColorScheme(.light)
}

#Preview("Theme Colors - Dark") {
    ThemePreviewView()
        .preferredColorScheme(.dark)
}

struct ThemePreviewView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Text("Pindrop Theme")
                .font(AppTypography.largeTitle)
            
            HStack(spacing: AppTheme.Spacing.md) {
                colorSwatch("Window BG", AppColors.windowBackground)
                colorSwatch("Sidebar BG", AppColors.sidebarBackground)
                colorSwatch("Surface", AppColors.surfaceBackground)
                colorSwatch("Elevated", AppColors.elevatedSurface)
            }
            
            HStack(spacing: AppTheme.Spacing.md) {
                colorSwatch("Accent", AppColors.accent)
                colorSwatch("Accent 2", AppColors.accentSecondary)
                colorSwatch("Accent BG", AppColors.accentBackground)
            }
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Primary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Secondary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                Text("Tertiary Text")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding()
            .cardStyle()
            
            VStack(spacing: AppTheme.Spacing.md) {
                Text("Highlighted Card")
                    .font(AppTypography.headline)
                Text("This is accent-tinted content")
                    .font(AppTypography.body)
            }
            .padding()
            .highlightedCardStyle()
        }
        .padding(AppTheme.Spacing.xxl)
        .background(AppColors.windowBackground)
    }
    
    func colorSwatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            Text(name)
                .font(AppTypography.tiny)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
