//
//  MainWindow.swift
//  Pindrop
//
//  Main application window with sidebar navigation
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Navigation

enum MainNavItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case notes = "Notes"
    case transcribe = "Transcribe"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .notes: return "note.text"
        case .transcribe: return "waveform"
        }
    }

    var isComingSoon: Bool {
        switch self {
        case .home, .history, .notes: return false
        case .transcribe: return true
        }
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToMainNavItem = Notification.Name("navigateToMainNavItem")
}

// MARK: - Main Window View

struct MainWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedNav: MainNavItem = .home
    @State private var isHoveringItem: MainNavItem? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var onOpenSettings: (() -> Void)?

    private func navigateTo(_ item: MainNavItem) {
        withAnimation(AppTheme.Animation.fast) {
            selectedNav = item
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: AppTheme.Window.sidebarWidth, max: 260)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.windowBackground)
        .frame(
            minWidth: AppTheme.Window.mainMinWidth,
            minHeight: AppTheme.Window.mainMinHeight
        )
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMainNavItem)) { notification in
            if let navItem = notification.userInfo?["navItem"] as? MainNavItem {
                navigateTo(navItem)
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // App branding header
            appHeader
            
            // Navigation items
            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(MainNavItem.allCases) { item in
                    sidebarItem(item)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
            
            Spacer()
            
            // Bottom section with settings
            bottomSection
        }
        .background(AppColors.sidebarBackground)
    }
    
    private var appHeader: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.accentBackground)
                    .frame(width: 36, height: 36)
                
                Image("PindropIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(AppColors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Pindrop")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
    }
    
    private func sidebarItem(_ item: MainNavItem) -> some View {
        let isSelected = selectedNav == item
        let isHovered = isHoveringItem == item
        let isDisabled = item.isComingSoon
        
        return Button {
            if !isDisabled {
                withAnimation(AppTheme.Animation.fast) {
                    selectedNav = item
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                
                Text(item.rawValue)
                    .font(AppTypography.body)
                
                Spacer()
                
                if item.isComingSoon {
                    Text("Soon")
                        .font(AppTypography.tiny)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppColors.border)
                        )
                }
            }
            .foregroundStyle(
                isDisabled ? AppColors.textTertiary :
                (isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            )
            .sidebarItemStyle(isSelected: isSelected && !isDisabled, isHovered: isHovered && !isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHoveringItem = hovering ? item : nil
        }
    }
    
    private var bottomSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Divider()
                .background(AppColors.divider)
            
            // Settings button
            Button {
                openSettings()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "gear")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20)
                    
                    Text("Settings")
                        .font(AppTypography.body)
                    
                    Spacer()
                    
                    Text("⌘,")
                        .font(AppTypography.monoSmall)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                // Could add hover state here
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .home:
            DashboardView(onOpenSettings: openSettings, onViewAllHistory: { navigateTo(.history) })
        case .history:
            HistoryView()
        case .notes:
            NotesView()
        case .transcribe:
            comingSoonView(for: selectedNav)
        }
    }
    
    private func comingSoonView(for item: MainNavItem) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: item.icon)
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(item.rawValue)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Coming Soon")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.contentBackground)
    }
    
    // MARK: - Actions
    
    private func openSettings() {
        onOpenSettings?()
    }
}

// MARK: - Main Window Controller

@MainActor
final class MainWindowController {

    private var window: NSWindow?
    private var modelContainer: ModelContainer?
    var onOpenSettings: (() -> Void)?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func show() {
        show(navigationItem: nil)
    }

    func showHistory() {
        show(navigationItem: .history)
    }

    private func show(navigationItem: MainNavItem?) {
        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot show MainWindow")
            return
        }

        if window == nil {
            let mainView = MainWindow(onOpenSettings: onOpenSettings)
                .modelContainer(container)
            let hostingController = NSHostingController(rootView: mainView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Pindrop"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(
                width: AppTheme.Window.mainDefaultWidth,
                height: AppTheme.Window.mainDefaultHeight
            ))
            window.minSize = NSSize(
                width: AppTheme.Window.mainMinWidth,
                height: AppTheme.Window.mainMinHeight
            )
            window.center()
            window.isReleasedWhenClosed = false
            window.appearance = nil

            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Navigate to the requested item if specified
        if let item = navigationItem {
            NotificationCenter.default.post(
                name: .navigateToMainNavItem,
                object: nil,
                userInfo: ["navItem": item]
            )
        }
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
    
    var isVisible: Bool {
        window?.isVisible == true
    }
}

#Preview("Main Window - Light") {
    MainWindow()
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.light)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}

#Preview("Main Window - Dark") {
    MainWindow()
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.dark)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}
