//
//  ContextEngineContracts.swift
//  Pindrop
//
//  Created on 2026-02-08.
//

import Foundation

// MARK: - Context Snapshot

/// Normalized snapshot of UI/app context captured at recording start.
/// Structured context payload for AI enhancement
/// and future prompt routing.
struct ContextSnapshot {
    let timestamp: Date
    let appContext: AppContextInfo?
    let clipboardText: String?
    let warnings: [ContextCaptureWarning]

    /// Whether any meaningful context was captured
    var hasAnyContext: Bool {
        appContext != nil || clipboardText != nil
    }

    /// Convenience: build a legacy `CapturedContext` for backward compatibility
    /// during migration. Callers that still expect `CapturedContext` can use this.
    var asCapturedContext: CapturedContext {
        CapturedContext(
            clipboardText: clipboardText
        )
    }

    static let empty = ContextSnapshot(
        timestamp: Date(),
        appContext: nil,
        clipboardText: nil,
        warnings: []
    )
}

// MARK: - App Context Info

/// Structured information about the frontmost application and window,
/// captured via Accessibility APIs when available.
struct AppContextInfo {
    let bundleIdentifier: String?
    let appName: String
    let windowTitle: String?
    let focusedElementRole: String?
    let focusedElementValue: String?
    let selectedText: String?
    let documentPath: String?
    let browserURL: String?

    /// Whether this context has any meaningful AX-sourced data
    /// beyond just the app name.
    var hasDetailedContext: Bool {
        windowTitle != nil || focusedElementRole != nil ||
        selectedText != nil || documentPath != nil || browserURL != nil
    }
}

// MARK: - Context Source Type

/// Describes the type of context source for AI prompt assembly.
enum ContextSourceType: String, CaseIterable, Sendable {
    case clipboardText = "clipboard_text"
    case appMetadata = "app_metadata"
    case windowTitle = "window_title"
    case selectedText = "selected_text"
    case documentPath = "document_path"
    case browserURL = "browser_url"
}

// MARK: - Context Capture Errors

/// Non-fatal errors/warnings encountered during context capture.
/// These never block the transcription pipeline.
enum ContextCaptureWarning: Equatable, Sendable {
    case accessibilityPermissionDenied
    case accessibilityDataUnavailable
    case captureTimedOut(component: String)
    case adapterNotFound(bundleIdentifier: String)
    case partialCapture(reason: String)

    var localizedDescription: String {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission not granted; UI context unavailable"
        case .accessibilityDataUnavailable:
            return "Accessibility data could not be read from frontmost app"
        case .captureTimedOut(let component):
            return "Context capture timed out for: \(component)"
        case .adapterNotFound(let bundleIdentifier):
            return "No adapter found for app: \(bundleIdentifier)"
        case .partialCapture(let reason):
            return "Partial context captured: \(reason)"
        }
    }
}

/// Fatal context engine errors (should not occur in normal operation).
enum ContextEngineError: Error, LocalizedError {
    case engineNotReady
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .engineNotReady:
            return "Context engine is not ready"
        case .invalidConfiguration(let detail):
            return "Invalid context engine configuration: \(detail)"
        }
    }
}

// MARK: - Capture Configuration

/// Configuration for a single context capture pass.
struct ContextCaptureConfig: Sendable {
    /// Maximum time budget for the entire capture operation (seconds)
    let timeoutSeconds: TimeInterval

    /// Whether to attempt AX-based UI context capture
    let enableUIContext: Bool

    /// Whether to capture clipboard text
    let enableClipboardText: Bool

    static let `default` = ContextCaptureConfig(
        timeoutSeconds: 2.0,
        enableUIContext: true,
        enableClipboardText: false
    )

    /// Disabled configuration — captures nothing
    static let disabled = ContextCaptureConfig(
        timeoutSeconds: 0,
        enableUIContext: false,
        enableClipboardText: false
    )
}

// MARK: - Prompt Routing Signal

/// Normalized signal extracted from a `ContextSnapshot` that downstream
/// systems can use to select prompt presets or profiles automatically.
/// This is a foundation type; no auto-switch behavior is implemented yet.
struct PromptRoutingSignal {
    let appBundleIdentifier: String?
    let appName: String?
    let windowTitle: String?
    let workspacePath: String?
    let browserDomain: String?
    let isCodeEditorContext: Bool

    /// Build a routing signal from a normalized context snapshot.
    static func from(
        snapshot: ContextSnapshot,
        adapterRegistry: AppContextAdapterRegistry? = nil
    ) -> PromptRoutingSignal {
        let app = snapshot.appContext
        let bundleID = app?.bundleIdentifier?.lowercased()

        let isCodeEditor: Bool
        if let bundleID, let registry = adapterRegistry {
            let adapter = registry.adapter(for: bundleID)
            isCodeEditor = adapter.capabilities.supportsCodeContext && !(adapter is FallbackAdapter)
        } else {
            isCodeEditor = false
        }

        return PromptRoutingSignal(
            appBundleIdentifier: bundleID,
            appName: app?.appName.lowercased(),
            windowTitle: app?.windowTitle,
            workspacePath: Self.deriveWorkspaceRoot(
                documentPath: app?.documentPath,
                bundleIdentifier: bundleID,
                appName: app?.appName,
                windowTitle: app?.windowTitle,
                focusedElementValue: app?.focusedElementValue
            ),
            browserDomain: Self.extractDomain(from: app?.browserURL),
            isCodeEditorContext: isCodeEditor
        )
    }

    static let empty = PromptRoutingSignal(
        appBundleIdentifier: nil,
        appName: nil,
        windowTitle: nil,
        workspacePath: nil,
        browserDomain: nil,
        isCodeEditorContext: false
    )

    // MARK: - Private

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp-stable",
        "dev.warp.warp-preview",
        "dev.warp.warp-nightly",
        "com.github.wez.wezterm",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "co.zeit.hyper.helper",
        "org.tabby",
        "org.tabby.helper",
        "com.raphaelamorim.rio",
    ]

    private static let terminalNameHints: [String] = [
        "terminal",
        "iterm",
        "ghostty",
        "warp",
        "wezterm",
        "alacritty",
        "kitty",
        "hyper",
        "tabby",
    ]

    private static func deriveWorkspaceRoot(
        documentPath: String?,
        bundleIdentifier: String?,
        appName: String?,
        windowTitle: String?,
        focusedElementValue: String?
    ) -> String? {
        if let path = deriveWorkspaceRoot(from: documentPath) {
            return path
        }

        guard isTerminalContext(bundleIdentifier: bundleIdentifier, appName: appName) else {
            return nil
        }

        if let titlePath = extractTerminalPathCandidate(from: windowTitle),
           let path = deriveWorkspaceRoot(from: directoryHintPath(for: titlePath)) {
            return path
        }

        if let focusedValuePath = extractTerminalPathCandidate(from: focusedElementValue),
           let path = deriveWorkspaceRoot(from: directoryHintPath(for: focusedValuePath)) {
            return path
        }

        return nil
    }

    /// Derive a workspace root directory from a document path.
    ///
    /// - For file paths, returns the parent directory.
    /// - For directory paths (common in terminal apps), returns the directory itself.
    /// - Handles tilde-redacted paths (`~/...`) and `file://` URLs.
    private static func deriveWorkspaceRoot(from documentPath: String?) -> String? {
        guard let rawPath = documentPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        var normalized = rawPath
        if normalized.hasPrefix("file://") {
            if let url = URL(string: normalized) {
                normalized = url.path
            } else {
                normalized = String(normalized.dropFirst("file://".count))
            }
        }

        guard !normalized.isEmpty else { return nil }

        if isDirectoryPath(normalized) {
            return normalizeDirectoryPath(normalized)
        }

        let parent = (normalized as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private static func isTerminalContext(bundleIdentifier: String?, appName: String?) -> Bool {
        if let bundleIdentifier,
           terminalBundleIdentifiers.contains(bundleIdentifier.lowercased()) {
            return true
        }

        guard let appName else { return false }
        let lowerName = appName.lowercased()
        return terminalNameHints.contains { lowerName.contains($0) }
    }

    private static func extractTerminalPathCandidate(from text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let regex = try? NSRegularExpression(
                  pattern: #"(?:^|[\s:])((?:file://[^\s]+|~/[^\s]+|/[^\s]+))"#
              ) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }

            let candidate = String(text[range])
            if let sanitized = sanitizePathToken(candidate) {
                return sanitized
            }
        }

        return nil
    }

    private static func sanitizePathToken(_ token: String) -> String? {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`([{<"))
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`)]}>,;.!?"))

        while value.hasSuffix(":") {
            value.removeLast()
        }

        return value.isEmpty ? nil : value
    }

    private static func directoryHintPath(for path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private static func isDirectoryPath(_ path: String) -> Bool {
        if path == "/" {
            return true
        }

        if path.hasSuffix("/") {
            return true
        }

        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }

        return false
    }

    private static func normalizeDirectoryPath(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func extractDomain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        return host.lowercased()
    }
}

// MARK: - Prompt Routing Resolver

enum PromptRoutingSuggestion: Equatable {
    case noSuggestion
    case suggestedPresetId(String)
}

/// Advisory interface for resolving routing signals into preset suggestions.
/// Manual preset selection (`SettingsStore.selectedPresetId`) always takes priority.
protocol PromptRoutingResolver {
    func resolve(signal: PromptRoutingSignal) -> PromptRoutingSuggestion
}

struct NoOpPromptRoutingResolver: PromptRoutingResolver {
    func resolve(signal: PromptRoutingSignal) -> PromptRoutingSuggestion {
        return .noSuggestion
    }
}
