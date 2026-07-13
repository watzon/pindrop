import Foundation
import AppKit
import SwiftUI
import os.log

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    enum RecordingState {
        case idle
        case recording
        case processing
    }

    struct PromptPresetOption {
        let id: String
        let assignmentID: String
        let name: String
    }

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private let audioRecorder: AudioRecorder
    private let settingsStore: SettingsStore

    // MARK: - Menu Item References

    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    private var clearAudioBufferItem: NSMenuItem?
    private var cancelOperationItem: NSMenuItem?
    private var contextualItemsInserted = false

    private var transcriptsMenu: NSMenu?
    private var copyLastTranscriptItem: NSMenuItem?
    private var pasteLastTranscriptItem: NSMenuItem?
    private var exportLastTranscriptItem: NSMenuItem?

    private var openHistoryItem: NSMenuItem?

    private var promptPresetMenuItem: NSMenuItem?
    private var promptPresetMenu: NSMenu?
    private var promptPresetOptions: [PromptPresetOption] = []

    private var welcomePopover: NSPopover?

    // MARK: - Callbacks

    var onToggleRecording: (() async -> Void)?
    var onShowApp: (() -> Void)?
    var onCopyLastTranscript: (() async -> Void)?
    var onPasteLastTranscript: (() async -> Void)?
    var onExportLastTranscript: (() async -> Void)?
    var onClearAudioBuffer: (() async -> Void)?
    var onCancelOperation: (() async -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenSettings: ((SettingsTab) -> Void)?
    var onSelectPromptPreset: ((PromptPresetOption) -> Void)?
    var onMenuWillOpen: (() -> Void)?

    // Recent transcripts for submenu
    private(set) var recentTranscripts: [(id: UUID, text: String, timestamp: Date)] = []

    /// Shared CoreAudio-backed snapshot; status-row reads never re-enumerate devices.
    private let inputDeviceCache = AudioInputDeviceCache.shared
    /// Nonisolated lifecycle handle so `@MainActor` deinit can tear down listeners.
    private var inputDeviceCacheObservation: AudioInputDeviceCache.Observation?

    /// Locale-scoped formatter for recent-transcript timestamps (reused across rows).
    private var recentTranscriptTimeFormatter: DateFormatter?
    private var recentTranscriptTimeFormatterLocaleIdentifier: String?

    // MARK: - State

    private var currentState: RecordingState = .idle {
        didSet {
            updateStatusBarIcon()
            updateMenuState()
        }
    }

    init(audioRecorder: AudioRecorder, settingsStore: SettingsStore) {
        self.audioRecorder = audioRecorder
        self.settingsStore = settingsStore
        super.init()
        startInputDeviceCacheObservation()
        setupStatusItem()
        setupMenu()
    }

    deinit {
        // Explicit, idempotent listener teardown (safe from nonisolated deinit).
        inputDeviceCacheObservation?.tearDown()
    }

    func showSettings(tab: SettingsTab = .general) {
        guard let onOpenSettings else {
            Log.ui.error("Settings presenter not set - cannot show settings")
            return
        }

        onOpenSettings(tab)
    }

    func reloadLocalizedStrings() {
        Log.ui.infoVisible("Rebuilding status bar menu for locale=\(locale.identifier)")
        // setupMenu → updateMenuState resolves the status row once; avoid a second pass.
        setupMenu()
        updateRecentTranscriptsMenu()
    }

    func updateRecentTranscripts(_ transcripts: [(id: UUID, text: String, timestamp: Date)]) {
        self.recentTranscripts = Array(transcripts.prefix(5))
        updateRecentTranscriptsMenu()
    }

    private var locale: Locale {
        settingsStore.selectedAppLocale.locale
    }

    // MARK: - Setup

    private func setupStatusItem() {
        if let existingStatusItem = statusItem {
            NSStatusBar.system.removeStatusItem(existingStatusItem)
        }

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = newStatusItem

        guard let button = newStatusItem.button else {
            Log.ui.error("Failed to create status bar button; retrying on next run loop")
            DispatchQueue.main.async { [weak self] in
                self?.ensureStatusItem()
            }
            return
        }

        configureStatusButton(button)
        newStatusItem.menu = menu
    }

    func ensureStatusItem() {
        guard let statusItem else {
            setupStatusItem()
            return
        }

        guard let button = statusItem.button else {
            Log.ui.error("Status item exists without a button; recreating")
            setupStatusItem()
            return
        }

        configureStatusButton(button)
        statusItem.menu = menu
        updateStatusBarIcon()
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        button.imagePosition = .imageOnly
        button.appearsDisabled = false

        button.image = getBaseIcon()
        button.image?.isTemplate = true

        button.toolTip = "Pindrop"
    }

    private func setupMenu() {
        menu.removeAllItems()
        menu.delegate = self
        contextualItemsInserted = false

        // === STATUS ROW ===
        recordingStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recordingStatusItem?.isEnabled = false
        menu.addItem(recordingStatusItem!)

        // === START/STOP RECORDING ===
        toggleRecordingItem = NSMenuItem(
            title: localized("Start Recording", locale: locale),
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleRecordingItem?.target = self
        toggleRecordingItem?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(toggleRecordingItem!)

        // Contextual items (Clear Audio Buffer / Cancel Operation) are created here but only
        // inserted into the menu while recording/processing — see updateMenuState().
        clearAudioBufferItem = NSMenuItem(
            title: localized("Clear Audio Buffer", locale: locale),
            action: #selector(clearAudioBuffer),
            keyEquivalent: ""
        )
        clearAudioBufferItem?.target = self
        clearAudioBufferItem?.isEnabled = false
        clearAudioBufferItem?.image = NSImage(systemSymbolName: "clear", accessibilityDescription: nil)

        cancelOperationItem = NSMenuItem(
            title: localized("Cancel Operation", locale: locale),
            action: #selector(cancelOperation),
            keyEquivalent: ""
        )
        cancelOperationItem?.target = self
        cancelOperationItem?.isEnabled = false
        cancelOperationItem?.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)

        menu.addItem(NSMenuItem.separator())

        // === COPY LAST TRANSCRIPT ===
        copyLastTranscriptItem = NSMenuItem(
            title: localized("Copy Last Transcript", locale: locale),
            action: #selector(copyLastTranscript),
            keyEquivalent: ""
        )
        copyLastTranscriptItem?.target = self
        menu.addItem(copyLastTranscriptItem!)

        // === RECENT TRANSCRIPTS SUBMENU ===
        // Recent transcript entries are inserted at the top of this submenu by
        // updateRecentTranscriptsMenu(); this skeleton just holds the trailing actions.
        transcriptsMenu = NSMenu()
        transcriptsMenu?.addItem(NSMenuItem.separator())

        pasteLastTranscriptItem = NSMenuItem(
            title: localized("Paste Last Transcript", locale: locale),
            action: #selector(pasteLastTranscript),
            keyEquivalent: ""
        )
        pasteLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(pasteLastTranscriptItem!)

        exportLastTranscriptItem = NSMenuItem(
            title: localized("Export Last Transcript...", locale: locale),
            action: #selector(exportLastTranscript),
            keyEquivalent: ""
        )
        exportLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(exportLastTranscriptItem!)

        let recentMenuItem = NSMenuItem(title: localized("Recent Transcripts", locale: locale), action: nil, keyEquivalent: "")
        recentMenuItem.submenu = transcriptsMenu
        recentMenuItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(recentMenuItem)

        menu.addItem(NSMenuItem.separator())

        // === PROMPT PRESET ===
        promptPresetMenu = NSMenu()
        promptPresetMenuItem = NSMenuItem(
            title: localized("Prompt Preset", locale: locale),
            action: nil,
            keyEquivalent: ""
        )
        promptPresetMenuItem?.submenu = promptPresetMenu
        promptPresetMenuItem?.image = NSImage(
            systemSymbolName: "text.bubble",
            accessibilityDescription: nil
        )
        menu.addItem(promptPresetMenuItem!)
        rebuildPromptPresetMenu()

        menu.addItem(NSMenuItem.separator())

        // === OPEN HISTORY / SHOW APP ===
        openHistoryItem = NSMenuItem(
            title: localized("Open Library", locale: locale),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        openHistoryItem?.target = self
        openHistoryItem?.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(openHistoryItem!)

        let showAppItem = NSMenuItem(
            title: localized("Show App", locale: locale),
            action: #selector(showApp),
            keyEquivalent: ""
        )
        showAppItem.target = self
        showAppItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(showAppItem)

        menu.addItem(NSMenuItem.separator())

        // === SETTINGS / QUIT ===
        let settingsItem = NSMenuItem(
            title: localized("Settings...", locale: locale),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: localized("Quit Pindrop", locale: locale),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        // updateMenuState resolves the status row once (state + cached device label).
        updateMenuState()
        applyInterfaceLayoutDirection(to: menu, locale: locale)
    }

    /// Inserts the contextual "Clear Audio Buffer" / "Cancel Operation" rows directly
    /// after the Start/Stop Recording row. No-ops if already inserted.
    private func insertContextualItemsIfNeeded() {
        guard !contextualItemsInserted,
              let toggleRecordingItem,
              let clearAudioBufferItem,
              let cancelOperationItem else { return }

        let toggleIndex = menu.index(of: toggleRecordingItem)
        guard toggleIndex >= 0 else { return }

        menu.insertItem(clearAudioBufferItem, at: toggleIndex + 1)
        menu.insertItem(cancelOperationItem, at: toggleIndex + 2)
        contextualItemsInserted = true
    }

    /// Removes the contextual "Clear Audio Buffer" / "Cancel Operation" rows. No-ops if
    /// not currently inserted.
    private func removeContextualItemsIfNeeded() {
        guard contextualItemsInserted,
              let clearAudioBufferItem,
              let cancelOperationItem else { return }

        menu.removeItem(clearAudioBufferItem)
        menu.removeItem(cancelOperationItem)
        contextualItemsInserted = false
    }

    private func updateRecentTranscriptsMenu() {
        guard let transcriptsMenu = transcriptsMenu else { return }

        // Remove old recent items
        let itemsToRemove = transcriptsMenu.items.filter { item in
            guard let identifier = item.identifier?.rawValue else { return false }
            return identifier.starts(with: "recent_")
        }
        itemsToRemove.forEach { transcriptsMenu.removeItem($0) }

        // Insert the current recents at the top of the submenu, most recent first.
        let timeFormatter = recentTranscriptFormatter()
        for (index, transcript) in recentTranscripts.enumerated() {
            let truncatedText = String(transcript.text.prefix(40))
            let displayText = truncatedText.isEmpty ? localized("(Empty)", locale: locale) : truncatedText

            let item = NSMenuItem(
                title: "\(displayText)... (\(timeFormatter.string(from: transcript.timestamp)))",
                action: #selector(copyRecentTranscript(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier("recent_\(transcript.id)")
            transcriptsMenu.insertItem(item, at: index)
        }
    }

    func updatePromptPresets(_ presets: [PromptPresetOption]) {
        promptPresetOptions = presets
        rebuildPromptPresetMenu()
    }

    private func rebuildPromptPresetMenu() {
        guard let promptPresetMenu else { return }

        promptPresetMenu.removeAllItems()

        for option in promptPresetOptions {
            let item = NSMenuItem(
                title: option.name,
                action: #selector(selectPromptPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier("preset_\(option.id)")
            item.representedObject = option
            promptPresetMenu.addItem(item)
        }

        updatePromptPresetItems()
        applyInterfaceLayoutDirection(to: promptPresetMenu, locale: locale)
    }

    private func updatePromptPresetItems() {
        let assignment = settingsStore.assignment(for: .transcriptionEnhancement)
        let activePresetID = assignment?.promptOverride == nil
            ? assignment?.promptPresetID
            : nil

        promptPresetMenuItem?.isEnabled = assignment != nil && !promptPresetOptions.isEmpty

        for item in promptPresetMenu?.items ?? [] {
            guard let option = item.representedObject as? PromptPresetOption else { continue }
            item.isEnabled = assignment != nil
            item.state = option.assignmentID == activePresetID ? .on : .off
        }
    }

    func promptPresetMenuForTesting() -> NSMenu? {
        promptPresetMenu
    }

    func promptPresetMenuItemForTesting() -> NSMenuItem? {
        promptPresetMenuItem
    }

    /// Cached short-time formatter for the active app locale.
    private func recentTranscriptFormatter() -> DateFormatter {
        let currentLocale = locale
        if let recentTranscriptTimeFormatter,
           recentTranscriptTimeFormatterLocaleIdentifier == currentLocale.identifier {
            return recentTranscriptTimeFormatter
        }

        let formatter = DateFormatter()
        formatter.locale = currentLocale
        formatter.timeStyle = .short
        recentTranscriptTimeFormatter = formatter
        recentTranscriptTimeFormatterLocaleIdentifier = currentLocale.identifier
        return formatter
    }

    func updateDynamicItems() {
        updateStatusRow()
        updatePromptPresetItems()
    }

    private func startInputDeviceCacheObservation() {
        inputDeviceCacheObservation?.tearDown()
        inputDeviceCacheObservation = inputDeviceCache.makeObservation { [weak self] in
            // Cache already notifies on the main queue; hop keeps MainActor isolation.
            Task { @MainActor in
                self?.updateStatusRow()
            }
        }
    }

    /// Resolves the display name for the currently selected input device, falling back
    /// to the localized "System Default" label when no device is selected or the
    /// previously selected device is no longer available.
    ///
    /// Uses the listener-maintained snapshot — never performs a full CoreAudio
    /// enumeration on the status-row render path.
    private func currentInputDeviceDisplayName() -> String {
        let selectedUID = settingsStore.selectedInputDeviceUID
        guard !selectedUID.isEmpty else {
            return localized("System Default", locale: locale)
        }

        guard let device = inputDeviceCache.device(uid: selectedUID) else {
            return localized("System Default", locale: locale)
        }

        return device.displayName
    }

    private func statusRowBaseText(for state: RecordingState) -> String {
        switch state {
        case .idle:
            return localized("● Ready", locale: locale)
        case .recording:
            return localized("🔴 Recording", locale: locale)
        case .processing:
            return localized("⏳ Processing", locale: locale)
        }
    }

    private func statusRowColor(for state: RecordingState) -> NSColor {
        switch state {
        case .idle:
            return .secondaryLabelColor
        case .recording:
            return .systemRed
        case .processing:
            return .systemBlue
        }
    }

    private func updateStatusRow() {
        let title = "\(statusRowBaseText(for: currentState)) — \(currentInputDeviceDisplayName())"
        recordingStatusItem?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: statusRowColor(for: currentState)]
        )
    }

    func updateMenuState() {
        switch currentState {
        case .recording:
            toggleRecordingItem?.title = localized("Stop Recording", locale: locale)
            toggleRecordingItem?.isEnabled = true
            insertContextualItemsIfNeeded()
            clearAudioBufferItem?.isEnabled = true
            cancelOperationItem?.isEnabled = true
        case .processing:
            toggleRecordingItem?.title = localized("Processing...", locale: locale)
            toggleRecordingItem?.isEnabled = false
            insertContextualItemsIfNeeded()
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = true
        case .idle:
            toggleRecordingItem?.title = localized("Start Recording", locale: locale)
            toggleRecordingItem?.isEnabled = true
            removeContextualItemsIfNeeded()
        }
        updateStatusRow()
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task {
            await onToggleRecording?()
        }
    }

    @objc private func copyLastTranscript() {
        Task {
            await onCopyLastTranscript?()
        }
    }

    @objc private func pasteLastTranscript() {
        Task {
            await onPasteLastTranscript?()
        }
    }

    @objc private func exportLastTranscript() {
        Task {
            await onExportLastTranscript?()
        }
    }

    @objc private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString.replacingOccurrences(of: "recent_", with: "")),
              let transcript = recentTranscripts.first(where: { $0.id == id }) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([transcript.text as NSString])
    }

    @objc private func clearAudioBuffer() {
        Task {
            await onClearAudioBuffer?()
        }
    }

    @objc private func cancelOperation() {
        Task {
            await onCancelOperation?()
        }
    }

    @objc private func selectPromptPreset(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? PromptPresetOption else { return }
        onSelectPromptPreset?(option)
        updatePromptPresetItems()
    }

    @objc private func openHistory() {
        onOpenHistory?()
    }

    @objc private func showApp() {
        onShowApp?()
    }

    @objc private func openSettings() {
        showSettings(tab: .general)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }

        onMenuWillOpen?()
        updateDynamicItems()
    }

    private var cachedBaseIcon: NSImage?

    private func getBaseIcon() -> NSImage? {
        if let cached = cachedBaseIcon {
            return cached
        }

        guard let customIcon = NSImage(named: "PindropIcon") else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
        }

        let targetSize: CGFloat = 18

        let resizedIcon = NSImage(size: NSSize(width: targetSize, height: targetSize))
        resizedIcon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        customIcon.draw(
            in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
            from: NSRect(origin: .zero, size: customIcon.size),
            operation: .copy,
            fraction: 1.0
        )
        resizedIcon.unlockFocus()
        resizedIcon.isTemplate = true

        cachedBaseIcon = resizedIcon
        return resizedIcon
    }

    /// Returns a small center-dot-only image for use during recording/processing
    /// when the static rings are replaced by animated expanding ones.
    private var cachedDotIcon: NSImage?

    private func getDotIcon() -> NSImage? {
        if let cached = cachedDotIcon { return cached }

        let size: CGFloat = 18
        let dotRadius: CGFloat = 2.0

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(
            x: (size - dotRadius * 2) / 2,
            y: (size - dotRadius * 2) / 2,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        NSColor.black.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true

        cachedDotIcon = image
        return image
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }

        removeRippleAnimation(from: button)

        button.contentTintColor = nil
        button.alphaValue = 1.0

        switch currentState {
        case .idle:
            button.image = getBaseIcon()
            button.image?.isTemplate = true

        case .recording:
            button.image = getDotIcon()
            button.image?.isTemplate = true
            addRippleAnimation(to: button, color: NSColor.systemOrange)

        case .processing:
            button.image = getDotIcon()
            button.image?.isTemplate = true
            addRippleAnimation(to: button, color: NSColor.systemYellow)
        }
    }

    // MARK: - Ripple Animation

    private func addRippleAnimation(to button: NSStatusBarButton, color: NSColor) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let bounds = button.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxRadius: CGFloat = bounds.width * 0.48

        // Two expanding rings offset by half cycle, matching the animated SVG
        for i in 0..<2 {
            let ring = CAShapeLayer()
            ring.name = "rippleRing"
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = 1.5
            ring.opacity = 0

            let startPath = CGPath(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2), transform: nil)
            let endPath = CGPath(ellipseIn: CGRect(x: center.x - maxRadius, y: center.y - maxRadius, width: maxRadius * 2, height: maxRadius * 2), transform: nil)

            ring.path = endPath
            layer.addSublayer(ring)

            let duration: CFTimeInterval = 2.0
            let beginTime = CACurrentMediaTime() + Double(i) * (duration / 2.0)

            let pathAnim = CABasicAnimation(keyPath: "path")
            pathAnim.fromValue = startPath
            pathAnim.toValue = endPath

            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnim.values = [0.0, 0.7, 0.0]
            opacityAnim.keyTimes = [0.0, 0.15, 1.0]

            let widthAnim = CABasicAnimation(keyPath: "lineWidth")
            widthAnim.fromValue = 2.0
            widthAnim.toValue = 0.3

            let group = CAAnimationGroup()
            group.animations = [pathAnim, opacityAnim, widthAnim]
            group.duration = duration
            group.beginTime = beginTime
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0, 0.35, 1)

            ring.add(group, forKey: "ripple")
        }
    }

    private func removeRippleAnimation(from button: NSStatusBarButton) {
        button.layer?.sublayers?
            .filter { $0.name == "rippleRing" }
            .forEach { $0.removeFromSuperlayer() }
        button.layer?.removeAllAnimations()
    }

    func setRecordingState() {
        currentState = .recording
    }

    func setProcessingState() {
        currentState = .processing
    }

    func setIdleState() {
        currentState = .idle
    }

    func showWelcomePopover() {
        guard let button = statusItem?.button else { return }

        if welcomePopover == nil {
            let popover = NSPopover()
            popover.contentViewController = NSHostingController(rootView: WelcomePopoverView {
                self.welcomePopover?.performClose(nil)
            }
            .environment(\.locale, locale)
            .environment(\.layoutDirection, settingsStore.selectedAppLocale.layoutDirection))
            popover.behavior = .transient
            popover.animates = true
            if let contentView = popover.contentViewController?.view {
                applyInterfaceLayoutDirection(to: contentView, locale: locale)
            }
            welcomePopover = popover
        }

        welcomePopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

struct WelcomePopoverView: View {
    @Environment(\.locale) private var locale
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconView(icon: .hand, size: 24)
                    .foregroundStyle(.yellow)

                Text(localized("You're all set!", locale: locale))
                    .font(.headline)
            }

            Text(localized("Click this icon anytime to:", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                popoverItem(icon: .record, text: localized("Start/stop recording", locale: locale))
                popoverItem(icon: .settings, text: localized("Open settings", locale: locale))
                popoverItem(icon: .clock, text: localized("View library", locale: locale))
            }

            Divider()

            HStack {
                Text(localized("Or just use your hotkey!", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(localized("Got it", locale: locale)) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func popoverItem(icon: Icon, text: String) -> some View {
        HStack(spacing: 8) {
            IconView(icon: icon, size: 12)
                .foregroundStyle(AppColors.accent)
                .frame(width: 16)

            Text(text)
                .font(.subheadline)
        }
    }
}
