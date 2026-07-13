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
    case stats = "Stats"
    case history = "History"
    case notes = "Notes"
    /// Unrouted as of U2 — kept for API compatibility; navigation redirects to Library.
    case transcribe = "Transcribe"
    case models = "Models"
    case dictionary = "Dictionary"

    /// Primary sidebar destinations after U2 restructure.
    /// Order: Home, Stats, Library, Notes, Dictionary, Models (⌘1–6).
    static let primaryNavigationItems: [MainNavItem] = [
        .home,
        .stats,
        .history,
        .notes,
        .dictionary,
        .models
    ]

    /// View-menu keyboard shortcut digit for each primary nav item ("1"..."5").
    static func viewMenuShortcut(for item: MainNavItem) -> String? {
        guard let index = primaryNavigationItems.firstIndex(of: item) else { return nil }
        return String(index + 1)
    }

    /// Resolves legacy / removed destinations onto a routed page.
    var resolvedDestination: MainNavItem {
        switch self {
        case .transcribe: return .history
        default: return self
        }
    }

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .history:
            return localized("Library", locale: locale)
        default:
            return localized(rawValue, locale: locale)
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .stats: return "chart.xyaxis.line"
        case .history: return "books.vertical"
        case .notes: return "note.text"
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

// MARK: - Window chrome metrics

enum MainWindowChrome {
    /// Space under standard traffic lights so top chrome/content never collides
    /// (button row + breathing room). Applied to whichever panel occupies top-left.
    static let trafficLightClearance: CGFloat = 36
}

// MARK: - Main Window View

struct MainWindow: View {
    @ObservedObject private var theme = PindropThemeController.shared
    @ObservedObject var settingsStore: SettingsStore
    @State private var selectedNav: MainNavItem = .home
    @State private var historyRecordIDToOpen: UUID?
    let floatingIndicatorState: FloatingIndicatorState?
    let mediaTranscriptionState: MediaTranscriptionFeatureState?
    let recordingState: RecordingFeatureState?
    let modelManager: ModelManager?
    let onImportMediaFiles: (([URL], TranscriptionJobOptions) -> Void)?
    let onSubmitMediaLink: ((String, TranscriptionJobOptions) -> Void)?
    let onClearMediaQueue: (() -> Void)?
    let onDownloadDiarizationModel: (() -> Void)?
    let onNewTranscription: (() -> Void)?
    let onStartMeetingCapture: ((Int?) -> Void)?
    let onStartNoteCapture: (() -> Void)?
    let onOpenSettings: (SettingsTab) -> Void

    private func navigateTo(_ item: MainNavItem) {
        let destination = item.resolvedDestination
        selectedNav = destination
        NotificationCenter.default.post(
            name: .mainNavItemDidChange,
            object: nil,
            userInfo: ["navItem": destination.rawValue]
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

    private var isLeadingSidebar: Bool {
        settingsStore.selectedSidebarPosition == .leading
    }

    private var sidebarPanel: some View {
        MainSidebar(
            isExpanded: $settingsStore.sidebarExpanded,
            position: settingsStore.selectedSidebarPosition,
            selectedNav: selectedNav,
            floatingIndicatorState: floatingIndicatorState,
            hotkeyHint: settingsStore.toggleHotkey,
            /// Leading sidebar owns top-left → clear traffic lights; trailing does not.
            reservesTrafficLightClearance: isLeadingSidebar,
            onSelect: navigateTo,
            onOpenSettings: { onOpenSettings(.general) }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var detailPanel: some View {
        VStack(spacing: 0) {
            // Trailing sidebar: detail occupies top-left under the traffic lights.
            if !isLeadingSidebar {
                trafficLightDragStrip
            }
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.contentBackground)
        .layoutPriority(1)
        .zIndex(1)
    }

    /// Clear strip that stays window-draggable via `isMovableByWindowBackground`
    /// (pages that opt out of drag live below this, not inside it).
    private var trafficLightDragStrip: some View {
        Color.clear
            .frame(height: MainWindowChrome.trafficLightClearance)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .home:
            DashboardView(
                floatingIndicatorState: floatingIndicatorState,
                settingsStore: settingsStore,
                recordingState: recordingState,
                onOpenHotkeys: { navigateToSettings(.shortcuts) },
                onViewAllHistory: { navigateTo(.history) },
                onShowMoreStats: { navigateTo(.stats) },
                onOpenHistoryRecord: { recordID in
                    historyRecordIDToOpen = recordID
                    navigateTo(.history)
                },
                onNewTranscription: onNewTranscription,
                onTranscribeFile: { navigateTo(.history) },
                onRecordMeeting: onStartMeetingCapture,
                onNewNote: onStartNoteCapture,
                onDownloadDiarizationModel: onDownloadDiarizationModel
            )
        case .stats:
            StatsView()
        case .history:
            HistoryView(
                recordIDToOpen: historyRecordIDToOpen,
                mediaTranscriptionState: mediaTranscriptionState,
                recordingState: recordingState,
                settingsStore: settingsStore,
                onImportMediaFiles: onImportMediaFiles,
                onSubmitMediaLink: onSubmitMediaLink,
                onStartMeetingCapture: onStartMeetingCapture,
                onDownloadDiarizationModel: onDownloadDiarizationModel
            )
        case .notes:
            NotesView()
        case .transcribe:
            // Unreachable via primary nav; resolvedDestination maps .transcribe → .history.
            HistoryView(
                recordIDToOpen: historyRecordIDToOpen,
                mediaTranscriptionState: mediaTranscriptionState,
                recordingState: recordingState,
                settingsStore: settingsStore,
                onImportMediaFiles: onImportMediaFiles,
                onSubmitMediaLink: onSubmitMediaLink,
                onStartMeetingCapture: onStartMeetingCapture,
                onDownloadDiarizationModel: onDownloadDiarizationModel
            )
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

// MARK: - Meeting capture options

/// Shared speaker-count picker for Dashboard and Library "Record Meeting…" flows.
/// Start invokes the callback with `nil` (Automatic) or `1...20`; Cancel starts nothing.
struct MeetingCaptureOptionsSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let onStart: (Int?) -> Void

    /// `0` represents Automatic detection; `1...20` are exact speaker counts.
    @State private var selectedOption: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Record Meeting…", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Expected speakers", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Picker(localized("Expected speakers", locale: locale), selection: $selectedOption) {
                    Text(localized("Automatic", locale: locale)).tag(0)
                    ForEach(1...20, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("meetingExpectedSpeakerPicker")
            }

            HStack {
                Spacer()
                Button(localized("Cancel", locale: locale)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("meetingCaptureCancelButton")

                Button(localized("Start Recording", locale: locale)) {
                    let expectedCount = selectedOption == 0 ? nil : selectedOption
                    onStart(expectedCount)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("meetingCaptureStartButton")
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .accessibilityIdentifier("meetingCaptureOptionsSheet")
    }
}


// MARK: - Sidebar

private struct MainSidebar: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Binding var isExpanded: Bool
    let position: SidebarPosition
    let selectedNav: MainNavItem
    @ObservedObject private var indicatorState: FloatingIndicatorState
    let hotkeyHint: String
    /// When true, insert a draggable top strip so content clears traffic lights.
    let reservesTrafficLightClearance: Bool
    let onSelect: (MainNavItem) -> Void
    let onOpenSettings: () -> Void

    /// Aggregate library size only — never materialize TranscriptionRecord rows here.
    @State private var libraryCount = 0
    @State private var libraryCountRefreshGeneration: UInt = 0
    @State private var isCollapseHovered = false
    @State private var isSettingsHovered = false

    init(
        isExpanded: Binding<Bool>,
        position: SidebarPosition,
        selectedNav: MainNavItem,
        floatingIndicatorState: FloatingIndicatorState?,
        hotkeyHint: String,
        reservesTrafficLightClearance: Bool,
        onSelect: @escaping (MainNavItem) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self._isExpanded = isExpanded
        self.position = position
        self.selectedNav = selectedNav
        self._indicatorState = ObservedObject(wrappedValue: floatingIndicatorState ?? FloatingIndicatorState())
        self.hotkeyHint = hotkeyHint
        self.reservesTrafficLightClearance = reservesTrafficLightClearance
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
    }

    private var currentWidth: CGFloat {
        isExpanded ? AppTheme.Window.sidebarWidth : AppTheme.Window.sidebarCollapsedWidth
    }

    private var statusPhase: StatusCardPhase {
        StatusCardPhase(state: indicatorState)
    }

    /// Stable identity for the active SwiftData container so count reloads when it changes.
    private var modelContainerIdentity: ObjectIdentifier {
        ObjectIdentifier(modelContext.container)
    }

    var body: some View {
        VStack(spacing: 0) {
            if reservesTrafficLightClearance {
                // Window-draggable strip (no drag-blocker) under real traffic lights.
                Color.clear
                    .frame(height: MainWindowChrome.trafficLightClearance)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }

            appHeader

            mainNavSection
                .padding(.top, isExpanded ? 0 : AppTheme.Spacing.sm)

            Spacer(minLength: 8)

            bottomSection
        }
        .padding(.top, 16)
        .padding(.leading, isExpanded ? 16 : 8)
        .padding(.trailing, isExpanded ? 12 : 8)
        .padding(.bottom, 12)
        .frame(width: currentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.sidebarBackground)
        // Physical content-edge divider. Sidebar inherits locale layoutDirection
        // for labels; the overlay HStack is force-LTR so the 1 pt rule sits on the
        // absolute left/right edge (not the outer window edge under RTL).
        .overlay {
            HStack(spacing: 0) {
                if position == .trailing {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: 1)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: 1)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(false)
        }
        .appAnimation(.smooth, value: isExpanded)
        .task(id: modelContainerIdentity) {
            scheduleLibraryCountRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            scheduleLibraryCountRefresh()
        }
    }

    /// Coalesces bursty history notifications to a single latest-value count fetch.
    private func scheduleLibraryCountRefresh() {
        libraryCountRefreshGeneration &+= 1
        let generation = libraryCountRefreshGeneration
        Task { @MainActor in
            await Task.yield()
            guard generation == libraryCountRefreshGeneration else { return }
            refreshLibraryCount()
        }
    }

    private func refreshLibraryCount() {
        do {
            let count = try modelContext.fetchCount(FetchDescriptor<TranscriptionRecord>())
            if libraryCount != count {
                libraryCount = count
            }
        } catch {
            Log.ui.error("Failed to fetch library count: \(error.localizedDescription)")
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        Group {
            if isExpanded {
                Text("Pindrop")
                    .font(AppTypography.wordmark)
                    .tracking(AppTypography.wordmarkTracking)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
            } else {
                Image("PindropIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Main Navigation

    private var mainNavSection: some View {
        VStack(spacing: 2) {
            ForEach(MainNavItem.primaryNavigationItems) { item in
                SidebarItem(
                    title: item.title(locale: locale),
                    systemImage: item.icon,
                    count: item == .history && isExpanded ? libraryCount : nil,
                    isCollapsed: !isExpanded,
                    isSelected: selectedNav == item,
                    action: { onSelect(item) }
                )
            }
        }
        .padding(.trailing, isExpanded ? 4 : 0)
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: isExpanded ? 8 : 10) {
            statusFooter
            collapseButton
            settingsButton
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if isExpanded {
            StatusCard(state: indicatorState, hotkeyHint: hotkeyHint)
        } else {
            StatusCardDot(phase: statusPhase)
                .frame(maxWidth: .infinity)
        }
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Group {
                if isExpanded {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 18, height: 18)
                        Text(localized("Settings", locale: locale))
                            .font(AppTypography.labelStrong)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("⌘,")
                            .font(AppTypography.monoSmall)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                } else {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 18, height: 18)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSettingsHovered ? AppColors.sidebarItemHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Settings", locale: locale))
        .help(localized("Settings", locale: locale))
        .onHover { hovering in isSettingsHovered = hovering }
    }

    private var collapseButton: some View {
        let accessibilityTitle = localized(isExpanded ? "Collapse" : "Expand", locale: locale)
        let icon = position == .trailing
            ? (isExpanded ? "sidebar.right" : "sidebar.left")
            : (isExpanded ? "sidebar.left" : "sidebar.right")
        return Button {
            withAnimation(reduceMotion ? nil : AppTheme.Animation.smooth) {
                isExpanded.toggle()
            }
        } label: {
            Group {
                if isExpanded {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 18, height: 18)
                        Text(localized("Collapse", locale: locale))
                            .font(AppTypography.labelStrong)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 18, height: 18)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCollapseHovered ? AppColors.sidebarItemHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .help(accessibilityTitle)
        .onHover { hovering in isCollapseHovered = hovering }
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
    private var recordingState: RecordingFeatureState?
    private var modelManager: ModelManager?
    private var settingsStore: SettingsStore?
    private var navObserver: Any?
    /// Last known main-window navigation destination (updated via notification).
    private(set) var currentNavigationItem: MainNavItem = .home
    var onImportMediaFiles: (([URL], TranscriptionJobOptions) -> Void)?
    var onSubmitMediaLink: ((String, TranscriptionJobOptions) -> Void)?
    var onClearMediaQueue: (() -> Void)?
    var onDownloadDiarizationModel: (() -> Void)?
    var onNewTranscription: (() -> Void)?
    var onStartMeetingCapture: ((Int?) -> Void)?
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
        recordingState: RecordingFeatureState? = nil,
        onNewTranscription: @escaping () -> Void,
        onStartMeetingCapture: @escaping (Int?) -> Void,
        onStartNoteCapture: @escaping () -> Void
    ) {
        self.floatingIndicatorState = floatingIndicatorState
        self.recordingState = recordingState
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

    /// Transcribe page removed in U3 — open Library (inline import lives there).
    func showTranscribe() {
        show(navigationItem: .history)
    }

    func showModels() {
        show(navigationItem: .models)
    }

    func showNavigationItem(_ item: MainNavItem) {
        show(navigationItem: item.resolvedDestination)
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
                recordingState: recordingState,
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
            // Standard hosting controller — full-size transparent titlebar provides
            // correct traffic-light / drag regions without zeroing safe areas.
            let hostingController = NSHostingController(rootView: mainView)

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
            window.backgroundColor = NSColor(AppColors.windowBackground)
            window.isOpaque = true
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
            // Menu-bar app owns presentation; do not let AppKit restore this window.
            window.isRestorable = false
            PindropThemeController.shared.apply(to: window)
            applyInterfaceLayoutDirection(to: window, locale: settingsStore.selectedAppLocale.locale)

            self.window = window

            navObserver = NotificationCenter.default.addObserver(
                forName: .mainNavItemDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let rawValue = notification.userInfo?["navItem"] as? String,
                      let item = MainNavItem(rawValue: rawValue) else { return }
                self?.currentNavigationItem = item.resolvedDestination
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
            let destination = item.resolvedDestination
            currentNavigationItem = destination
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToMainNavItem,
                    object: nil,
                    userInfo: ["navItem": destination.rawValue]
                )
            }
        }
    }

    /// Positions standard traffic lights in the leading-sidebar top pad (spec §3).
    /// Real system controls — only origin is adjusted; size stays AppKit-native.
    private func positionTrafficLights() {
        guard let window = window,
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let superview = close.superview else { return }

        // Match sidebar leading/top pad (16) and design gap (8) between controls.
        let pad: CGFloat = 16
        let gap: CGFloat = 8
        let bw = close.frame.width
        let bh = close.frame.height
        // NSView coords: origin bottom-left; pin tops `pad` from superview top.
        let y = superview.bounds.height - pad - bh

        close.setFrameOrigin(NSPoint(x: pad, y: y))
        mini.setFrameOrigin(NSPoint(x: pad + bw + gap, y: y))
        zoom.setFrameOrigin(NSPoint(x: pad + 2 * (bw + gap), y: y))

        for btn in [close, mini, zoom] {
            btn.autoresizingMask = [.minYMargin]
        }
        zoom.isHidden = true
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
        recordingState: nil,
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
        recordingState: nil,
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
