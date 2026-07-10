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
    case dictionary = "Dictionary"

    static let primaryNavigationItems: [MainNavItem] = [
        .home,
        .history,
        .transcribe,
        .dictionary,
        .models
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
        case .dictionary: return "text.book.closed"
        }
    }

    var isComingSoon: Bool { false }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToMainNavItem = Notification.Name("navigateToMainNavItem")
    static let openHistoryRecord = Notification.Name("openHistoryRecord")
    static let sidebarStateChanged = Notification.Name("sidebarStateChanged")
    static let mainNavItemDidChange = Notification.Name("mainNavItemDidChange")
    static let focusHistorySearch = Notification.Name("focusHistorySearch")
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
    let floatingIndicatorState: FloatingIndicatorState?
    let mediaTranscriptionState: MediaTranscriptionFeatureState?
    let modelManager: ModelManager?
    let onImportMediaFiles: (([URL], TranscriptionJobOptions) -> Void)?
    let onSubmitMediaLink: ((String, TranscriptionJobOptions) -> Void)?
    let onClearMediaQueue: (() -> Void)?
    let onDownloadDiarizationModel: (() -> Void)?
    let onNewTranscription: (() -> Void)?
    let onStartMeetingCapture: (() -> Void)?
    let onStartNoteCapture: (() -> Void)?
    let onOpenSettings: (SettingsTab) -> Void

    private func navigateTo(_ item: MainNavItem) {
        if item == .transcribe {
            mediaTranscriptionState?.showLibrary()
        }

        selectedNav = item
        NotificationCenter.default.post(
            name: .mainNavItemDidChange,
            object: nil,
            userInfo: ["navItem": item.rawValue]
        )
    }

    private func navigateToSettings(_ tab: SettingsTab) {
        onOpenSettings(tab)
    }

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if settingsStore.selectedSidebarPosition == .leading {
                    sidebarPanel
                        .environment(\.layoutDirection, settingsStore.selectedAppLocale.layoutDirection)
                }
                detailPanel
                    .environment(\.layoutDirection, settingsStore.selectedAppLocale.layoutDirection)
                if settingsStore.selectedSidebarPosition == .trailing {
                    sidebarPanel
                        .environment(\.layoutDirection, settingsStore.selectedAppLocale.layoutDirection)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .ignoresSafeArea()
        }
        .frame(
            minWidth: AppTheme.Window.mainMinWidth,
            minHeight: AppTheme.Window.mainMinHeight
        )
        .environment(\.locale, settingsStore.selectedAppLocale.locale)
        .environment(\.layoutDirection, settingsStore.selectedAppLocale.layoutDirection)
        .themeRefresh()
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMainNavItem)) { notification in
            if let rawValue = notification.userInfo?["navItem"] as? String,
               let navItem = MainNavItem(rawValue: rawValue) {
                navigateTo(navItem)
            }
        }
        .onChange(of: settingsStore.sidebarExpanded) { _, _ in
            NotificationCenter.default.post(name: .sidebarStateChanged, object: nil)
        }
        .onChange(of: settingsStore.sidebarPosition) { _, _ in
            NotificationCenter.default.post(name: .sidebarStateChanged, object: nil)
        }
    }

    private var sidebarPanel: some View {
        MainSidebar(
            isExpanded: $settingsStore.sidebarExpanded,
            position: settingsStore.selectedSidebarPosition,
            selectedNav: selectedNav,
            onSelect: navigateTo,
            onOpenSettings: { onOpenSettings(.general) }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var detailPanel: some View {
        return VStack(spacing: 0) {
            contentTitleBar
            detailContent
                .padding(.top, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.contentBackground)
        .layoutPriority(1)
        .zIndex(1)
    }

    private var contentTitleBar: some View {
        HStack {
            Spacer()
            Text("Pindrop")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
        .frame(height: AppTheme.Window.titleBarHeight)
    }

    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .home:
            DashboardView(
                floatingIndicatorState: floatingIndicatorState,
                settingsStore: settingsStore,
                onOpenHotkeys: { navigateToSettings(.shortcuts) },
                onViewAllHistory: { navigateTo(.history) },
                onNewTranscription: onNewTranscription,
                onTranscribeFile: { navigateTo(.transcribe) },
                onRecordMeeting: onStartMeetingCapture,
                onNewNote: onStartNoteCapture
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
                    onClearQueue: onClearMediaQueue ?? {},
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
        case .dictionary:
            DictionaryView()
        }
    }
    
    private func comingSoonView(for item: MainNavItem) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: item.icon)
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(item.title(locale: settingsStore.selectedAppLocale.locale))
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
    @Binding var isExpanded: Bool
    let position: SidebarPosition
    let selectedNav: MainNavItem
    let onSelect: (MainNavItem) -> Void
    let onOpenSettings: () -> Void

    @State private var hoveredItem: MainNavItem?
    @State private var isCollapseHovered: Bool = false
    @State private var isSettingsHovered: Bool = false

    private var currentWidth: CGFloat {
        isExpanded ? AppTheme.Window.sidebarWidth : AppTheme.Window.sidebarCollapsedWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            appHeader

            mainNavSection
                .padding(.top, AppTheme.Spacing.md)

            Spacer()

            bottomSection
        }
        .frame(width: currentWidth)
        .background(AppColors.sidebarBackground)
        .animation(AppTheme.Animation.smooth, value: isExpanded)
    }

    // MARK: - App Header

    private var appHeader: some View {
        Group {
            if isExpanded {
                HStack(spacing: AppTheme.Spacing.md) {
                    appIconBadge(size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pindrop")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("v\(Bundle.main.appShortVersionString)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
            } else {
                appIconBadge(size: 32)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, position == .leading ? AppTheme.Spacing.xl + 18 : AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private func appIconBadge(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(AppColors.accentBackground)
                .frame(width: size, height: size)
            Image("PindropIcon")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.6, height: size * 0.6)
                .foregroundStyle(AppColors.accent)
        }
    }

    // MARK: - Main Navigation

    private var mainNavSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ForEach(MainNavItem.primaryNavigationItems) { item in
                sidebarItem(item)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            collapseButton
            settingsButton
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Group {
                if isExpanded {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text(localized("Settings", locale: locale))
                            .font(AppTypography.body)
                        Spacer()
                        Text("⌘,")
                            .font(AppTypography.monoSmall)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                } else {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(AppColors.textSecondary)
            .sidebarItemStyle(isSelected: false, isHovered: isSettingsHovered)
        }
        .buttonStyle(.plain)
        .help(localized("Settings", locale: locale))
        .onHover { hovering in isSettingsHovered = hovering }
    }

    private var collapseButton: some View {
        let icon = position == .trailing
            ? (isExpanded ? "sidebar.right" : "sidebar.left")
            : (isExpanded ? "sidebar.left" : "sidebar.right")
        return Button {
            withAnimation(AppTheme.Animation.smooth) {
                isExpanded.toggle()
            }
        } label: {
            Group {
                if isExpanded {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text(localized("Collapse", locale: locale))
                            .font(AppTypography.body)
                        Spacer()
                    }
                    .foregroundStyle(AppColors.textSecondary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .sidebarItemStyle(isSelected: false, isHovered: isCollapseHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isCollapseHovered = hovering }
    }

    // MARK: - Sidebar Item

    private func sidebarItem(_ item: MainNavItem) -> some View {
        let isSelected = selectedNav == item
        let isHovered = hoveredItem == item
        let isDisabled = item.isComingSoon

        return Button {
            if !isDisabled { onSelect(item) }
        } label: {
            Group {
                if isExpanded {
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
                                .background(Capsule().fill(AppColors.border))
                        }
                    }
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20)
                        .frame(maxWidth: .infinity)
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
        .onHover { hovering in hoveredItem = hovering ? item : nil }
    }
}

// MARK: - Main Window Controller

@MainActor
final class MainWindowController {

    /// Stable identifier so list key monitors can require the *main* window
    /// (not Settings / Note Editor / other panels) to be key.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("tech.watzon.pindrop.main-window")

    /// Set when Find (⌘F) is requested before HistoryView is mounted; consumed
    /// when History appears so focus is not lost to a navigation race.
    static var pendingHistorySearchFocus = false

    private var window: NSWindow?
    private var modelContainer: ModelContainer?
    private var floatingIndicatorState: FloatingIndicatorState?
    private var mediaTranscriptionState: MediaTranscriptionFeatureState?
    private var modelManager: ModelManager?
    private var settingsStore: SettingsStore?
    private var sidebarObserver: Any?
    private var navObserver: Any?
    /// Last known main-window navigation destination (updated via notification).
    private(set) var currentNavigationItem: MainNavItem = .home
    var onImportMediaFiles: (([URL], TranscriptionJobOptions) -> Void)?
    var onSubmitMediaLink: ((String, TranscriptionJobOptions) -> Void)?
    var onClearMediaQueue: (() -> Void)?
    var onDownloadDiarizationModel: (() -> Void)?
    var onNewTranscription: (() -> Void)?
    var onStartMeetingCapture: (() -> Void)?
    var onStartNoteCapture: (() -> Void)?
    var onOpenSettings: ((SettingsTab) -> Void)?

    /// The main app window, if created. Used by list keyboard monitors for identity checks.
    var nsWindow: NSWindow? { window }

    var isWindowKey: Bool {
        window?.isKeyWindow == true
    }

    /// Whether `window` is the Pindrop main window and currently key.
    static func isMainWindowKey(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.identifier == windowIdentifier && window.isKeyWindow
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func configureMeetingCapture(
        floatingIndicatorState: FloatingIndicatorState,
        onNewTranscription: @escaping () -> Void,
        onStartMeetingCapture: @escaping () -> Void,
        onStartNoteCapture: @escaping () -> Void
    ) {
        self.floatingIndicatorState = floatingIndicatorState
        self.onNewTranscription = onNewTranscription
        self.onStartMeetingCapture = onStartMeetingCapture
        self.onStartNoteCapture = onStartNoteCapture
    }

    func configureTranscribeFeature(
        state: MediaTranscriptionFeatureState,
        modelManager: ModelManager,
        settingsStore: SettingsStore,
        onImportMediaFiles: @escaping ([URL], TranscriptionJobOptions) -> Void,
        onSubmitMediaLink: @escaping (String, TranscriptionJobOptions) -> Void,
        onClearMediaQueue: @escaping () -> Void,
        onDownloadDiarizationModel: @escaping () -> Void
    ) {
        self.mediaTranscriptionState = state
        self.modelManager = modelManager
        self.settingsStore = settingsStore
        self.onImportMediaFiles = onImportMediaFiles
        self.onSubmitMediaLink = onSubmitMediaLink
        self.onClearMediaQueue = onClearMediaQueue
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

    func showNavigationItem(_ item: MainNavItem) {
        show(navigationItem: item)
    }

    func showSettings(tab: SettingsTab = .general) {
        guard let onOpenSettings else {
            Log.ui.error("Settings presenter not set - cannot show settings")
            return
        }

        onOpenSettings(tab)
    }

    func focusHistorySearch() {
        // Pending flag covers the case where History is not yet mounted (nav race).
        Self.pendingHistorySearchFocus = true
        show(navigationItem: .history)
        // Notification covers the case where History is already visible.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusHistorySearch, object: nil)
        }
    }

    private func show(navigationItem: MainNavItem?) {
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
                floatingIndicatorState: floatingIndicatorState,
                mediaTranscriptionState: mediaTranscriptionState,
                modelManager: modelManager,
                onImportMediaFiles: onImportMediaFiles,
                onSubmitMediaLink: onSubmitMediaLink,
                onClearMediaQueue: onClearMediaQueue,
                onDownloadDiarizationModel: onDownloadDiarizationModel,
                onNewTranscription: onNewTranscription,
                onStartMeetingCapture: onStartMeetingCapture,
                onStartNoteCapture: onStartNoteCapture,
                onOpenSettings: onOpenSettings ?? { _ in
                    Log.ui.error("Settings presenter not set - cannot show settings")
                }
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
            window.identifier = Self.windowIdentifier
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
            applyInterfaceLayoutDirection(to: window, locale: settingsStore.selectedAppLocale.locale)

            self.window = window

            sidebarObserver = NotificationCenter.default.addObserver(
                forName: .sidebarStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.updateZoomButton() }

            navObserver = NotificationCenter.default.addObserver(
                forName: .mainNavItemDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let rawValue = notification.userInfo?["navItem"] as? String,
                      let item = MainNavItem(rawValue: rawValue) else { return }
                self?.currentNavigationItem = item
            }
        }

        PindropThemeController.shared.apply(to: window)
        if let window {
            applyInterfaceLayoutDirection(to: window, locale: settingsStore.selectedAppLocale.locale)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.positionTrafficLights() }

        if let item = navigationItem {
            currentNavigationItem = item
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToMainNavItem,
                    object: nil,
                    userInfo: ["navItem": item.rawValue]
                )
            }
        }
    }
    
    private func positionTrafficLights() {
        guard let window = window,
              let close = window.standardWindowButton(.closeButton),
              let mini  = window.standardWindowButton(.miniaturizeButton),
              let zoom  = window.standardWindowButton(.zoomButton),
              let superview = close.superview else { return }

        let pad: CGFloat = 14
        let gap: CGFloat = 6
        let bw = close.frame.width
        let bh = close.frame.height
        // In NSView coords (origin = bottom-left), place the button top `pad` from superview top.
        let y = superview.bounds.height - pad - bh

        close.setFrameOrigin(NSPoint(x: pad,                  y: y))
        mini.setFrameOrigin( NSPoint(x: pad + bw + gap,       y: y))
        zoom.setFrameOrigin( NSPoint(x: pad + 2 * (bw + gap), y: y))

        // Keep pinned to top-left when the superview resizes.
        for btn in [close, mini, zoom] {
            btn.autoresizingMask = [.minYMargin]
        }

        updateZoomButton()
    }

    private func updateZoomButton() {
        guard let zoom = window?.standardWindowButton(.zoomButton),
              let settingsStore else { return }
        let shouldHide = settingsStore.selectedSidebarPosition == .leading
            && !settingsStore.sidebarExpanded
        zoom.isHidden = shouldHide
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
        floatingIndicatorState: nil,
        mediaTranscriptionState: nil,
        modelManager: nil,
        onImportMediaFiles: nil,
        onSubmitMediaLink: nil,
        onClearMediaQueue: nil,
        onDownloadDiarizationModel: nil,
        onNewTranscription: nil,
        onStartMeetingCapture: nil,
        onStartNoteCapture: nil,
        onOpenSettings: { _ in }
    )
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.light)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}

#Preview("Main Window - Dark") {
    MainWindow(
        settingsStore: SettingsStore(),
        floatingIndicatorState: nil,
        mediaTranscriptionState: nil,
        modelManager: nil,
        onImportMediaFiles: nil,
        onSubmitMediaLink: nil,
        onClearMediaQueue: nil,
        onDownloadDiarizationModel: nil,
        onNewTranscription: nil,
        onStartMeetingCapture: nil,
        onStartNoteCapture: nil,
        onOpenSettings: { _ in }
    )
        .modelContainer(PreviewContainer.empty)
        .preferredColorScheme(.dark)
        .frame(width: AppTheme.Window.mainDefaultWidth, height: AppTheme.Window.mainDefaultHeight)
}
