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

enum MainNavItem: String, Identifiable {
    case home = "Home"
    case history = "History"
    case transcribe = "Transcribe"
    case models = "Models"
    case notes = "Notes"
    case dictionary = "Dictionary"
    case settings = "Settings"

    static let primaryNavigationItems: [MainNavItem] = [
        .home,
        .history,
        .transcribe,
        .notes,
        .dictionary,
        .models,
        .settings
    ]

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        localized(rawValue, locale: locale)
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .transcribe: return "waveform"
        case .models: return "cpu"
        case .notes: return "note.text"
        case .dictionary: return "text.book.closed"
        case .settings: return "gearshape"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .settings:
            return "⌘,"
        default:
            return nil
        }
    }

    var isComingSoon: Bool { false }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToMainNavItem = Notification.Name("navigateToMainNavItem")
    static let navigateToSettingsTab = Notification.Name("navigateToSettingsTab")
}

final class TitlebarlessHostingView<Content: View>: NSHostingView<Content> {
    private let zeroSafeAreaLayoutGuide = NSLayoutGuide()

    required init(rootView: Content) {
        super.init(rootView: rootView)

        addLayoutGuide(zeroSafeAreaLayoutGuide)
        NSLayoutConstraint.activate([
            zeroSafeAreaLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            zeroSafeAreaLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            zeroSafeAreaLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            zeroSafeAreaLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var safeAreaRect: NSRect {
        bounds
    }

    override var safeAreaLayoutGuide: NSLayoutGuide {
        zeroSafeAreaLayoutGuide
    }
}

final class TitlebarlessHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = TitlebarlessHostingView(rootView: rootView)
    }
}

// MARK: - Main Window View

struct MainWindow: View {
    @ObservedObject private var theme = PindropThemeController.shared
    @ObservedObject var settingsStore: SettingsStore
    @State private var selectedNav: MainNavItem = .home
    @State private var selectedSettingsTab: SettingsTab = .general
    let mediaTranscriptionState: MediaTranscriptionFeatureState?
    let modelManager: ModelManager?
    let onImportMediaFiles: (([URL]) -> Void)?
    let onSubmitMediaLink: ((String) -> Void)?
    let onDownloadDiarizationModel: (() -> Void)?

    private func navigateTo(_ item: MainNavItem) {
        if item == .transcribe {
            mediaTranscriptionState?.showLibrary()
        }

        selectedNav = item
    }

    private func navigateToSettings(_ tab: SettingsTab) {
        selectedSettingsTab = tab
        selectedNav = .settings
    }

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            HStack(spacing: AppTheme.Window.sidebarContentGap) {
                sidebarPanel
                detailPanel
            }
            .ignoresSafeArea()
        }
        .frame(
            minWidth: AppTheme.Window.mainMinWidth,
            minHeight: AppTheme.Window.mainMinHeight
        )
        .environment(\.locale, settingsStore.selectedAppLanguage.locale)
        .themeRefresh()
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMainNavItem)) { notification in
            if let rawValue = notification.userInfo?["navItem"] as? String,
               let navItem = MainNavItem(rawValue: rawValue) {
                navigateTo(navItem)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettingsTab)) { notification in
            if let rawValue = notification.userInfo?["settingsTab"] as? String,
               let tab = SettingsTab(rawValue: rawValue) {
                navigateToSettings(tab)
            }
        }
    }

    private var sidebarPanel: some View {
        return MainSidebar(
            selectedNav: selectedNav,
            onSelect: navigateTo
        )
        .frame(width: AppTheme.Window.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, AppTheme.Window.sidebarTopInset)
    }

    private var detailPanel: some View {
        let panelShape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: AppTheme.Window.panelCornerRadius / 2,
                bottomLeading: AppTheme.Window.panelCornerRadius / 2,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )

        return detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                panelShape
                    .fill(AppColors.contentBackground)
            )
            .clipShape(panelShape)
            .hairlineBorder(panelShape, style: AppColors.border.opacity(0.8))
            .layoutPriority(1)
            .zIndex(1)
    }

    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .home:
            DashboardView(
                onOpenHotkeys: { navigateToSettings(.hotkeys) },
                onViewAllHistory: { navigateTo(.history) }
            )
        case .history:
            HistoryView()
        case .transcribe:
            if let mediaTranscriptionState,
               let modelManager,
               let onImportMediaFiles,
               let onSubmitMediaLink,
               let onDownloadDiarizationModel {
                TranscribeView(
                    featureState: mediaTranscriptionState,
                    modelManager: modelManager,
                    settingsStore: settingsStore,
                    onImportFiles: onImportMediaFiles,
                    onSubmitLink: onSubmitMediaLink,
                    onDownloadDiarizationModel: onDownloadDiarizationModel,
                    onOpenModels: { navigateTo(.models) }
                )
            } else {
                comingSoonView(for: selectedNav)
            }
        case .models:
            if let modelManager {
                ModelsSettingsView(settings: settingsStore, modelManager: modelManager)
            } else {
                comingSoonView(for: selectedNav)
            }
        case .notes:
            NotesView()
        case .dictionary:
            DictionaryView()
        case .settings:
            SettingsContainerView(settings: settingsStore, initialTab: selectedSettingsTab)
        }
    }
    
    private func comingSoonView(for item: MainNavItem) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: item.icon)
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(item.title(locale: settingsStore.selectedAppLanguage.locale))
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Coming Soon")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.contentBackground)
    }
    
}

private struct MainSidebar: View {
    @Environment(\.locale) private var locale
    let selectedNav: MainNavItem
    let onSelect: (MainNavItem) -> Void

    @State private var hoveredItem: MainNavItem?

    var body: some View {
        VStack(spacing: 0) {
            appHeader

            navigationSection(items: MainNavItem.primaryNavigationItems)
                .padding(.top, AppTheme.Spacing.md)

            Spacer()
        }
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

                Text("v\(Bundle.main.appShortVersionString)")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func sidebarItem(_ item: MainNavItem) -> some View {
        let isSelected = selectedNav == item
        let isHovered = hoveredItem == item
        let isDisabled = item.isComingSoon

        return Button {
            if !isDisabled {
                onSelect(item)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)

                Text(item.title(locale: locale))
                    .font(AppTypography.body)

                Spacer()

                if item.isComingSoon {
                    Text(localized("Soon", locale: locale))
                        .font(AppTypography.tiny)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppColors.border)
                        )
                } else if let shortcutHint = item.shortcutHint {
                    Text(shortcutHint)
                        .font(AppTypography.monoSmall)
                        .foregroundStyle(AppColors.textTertiary)
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
        // Keep hover state local so the detail view is not invalidated on every mouse move.
        .onHover { hovering in
            hoveredItem = hovering ? item : nil
        }
    }

    private func navigationSection(items: [MainNavItem]) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(items) { item in
                    sidebarItem(item)
                }
            }
        }
        .padding(.leading, AppTheme.Spacing.md)
        .padding(.trailing, AppTheme.Spacing.xs)
    }
}

// MARK: - Main Window Controller

@MainActor
final class MainWindowController {

    private var window: NSWindow?
    private var modelContainer: ModelContainer?
    private var mediaTranscriptionState: MediaTranscriptionFeatureState?
    private var modelManager: ModelManager?
    private var settingsStore: SettingsStore?
    var onImportMediaFiles: (([URL]) -> Void)?
    var onSubmitMediaLink: ((String) -> Void)?
    var onDownloadDiarizationModel: (() -> Void)?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func configureTranscribeFeature(
        state: MediaTranscriptionFeatureState,
        modelManager: ModelManager,
        settingsStore: SettingsStore,
        onImportMediaFiles: @escaping ([URL]) -> Void,
        onSubmitMediaLink: @escaping (String) -> Void,
        onDownloadDiarizationModel: @escaping () -> Void
    ) {
        self.mediaTranscriptionState = state
        self.modelManager = modelManager
        self.settingsStore = settingsStore
        self.onImportMediaFiles = onImportMediaFiles
        self.onSubmitMediaLink = onSubmitMediaLink
        self.onDownloadDiarizationModel = onDownloadDiarizationModel
    }

    func show() {
        show(navigationItem: nil)
    }

    func showHistory() {
        show(navigationItem: .history)
    }

    func showTranscribe() {
        show(navigationItem: .transcribe)
    }

    func showModels() {
        show(navigationItem: .models)
    }

    func showSettings(tab: SettingsTab = .general) {
        show(navigationItem: .settings, settingsTab: tab)
    }

    private func show(navigationItem: MainNavItem?, settingsTab: SettingsTab? = nil) {
        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot show MainWindow")
            return
        }
        guard let settingsStore else {
            Log.ui.error("SettingsStore not set - cannot show MainWindow")
            return
        }

        if window == nil {
            let mainView = MainWindow(
                settingsStore: settingsStore,
                mediaTranscriptionState: mediaTranscriptionState,
                modelManager: modelManager,
                onImportMediaFiles: onImportMediaFiles,
                onSubmitMediaLink: onSubmitMediaLink,
                onDownloadDiarizationModel: onDownloadDiarizationModel
            )
                .modelContainer(container)
            let hostingController = TitlebarlessHostingController(rootView: mainView)

            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: AppTheme.Window.mainDefaultWidth,
                    height: AppTheme.Window.mainDefaultHeight
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.title = "Pindrop"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.toolbarStyle = .unifiedCompact
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
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
            PindropThemeController.shared.apply(to: window)

            self.window = window
        }

        PindropThemeController.shared.apply(to: window)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let settingsTab {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToSettingsTab,
                    object: nil,
                    userInfo: ["settingsTab": settingsTab.rawValue]
                )
            }
        } else if let item = navigationItem {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToMainNavItem,
                    object: nil,
                    userInfo: ["navItem": item.rawValue]
                )
            }
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
    MainWindow(
        settingsStore: SettingsStore(),
        mediaTranscriptionState: nil,
        modelManager: nil,
        onImportMediaFiles: nil,
        onSubmitMediaLink: nil,
        onDownloadDiarizationModel: nil
    )
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.light)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}

#Preview("Main Window - Dark") {
    MainWindow(
        settingsStore: SettingsStore(),
        mediaTranscriptionState: nil,
        modelManager: nil,
        onImportMediaFiles: nil,
        onSubmitMediaLink: nil,
        onDownloadDiarizationModel: nil
    )
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.dark)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}
