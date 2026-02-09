//
//  ContextEngineContracts.swift
//  Pindrop
//
//  Created on 2026-02-08.
//

import AppKit
import Foundation

// MARK: - Context Snapshot

/// Normalized snapshot of UI/app context captured at recording start.
/// Structured context payload for AI enhancement
/// and future prompt routing.
struct ContextSnapshot {
    let timestamp: Date
    let appContext: AppContextInfo?
    let clipboardText: String?
    let clipboardImage: NSImage?
    let warnings: [ContextCaptureWarning]

    /// Whether any meaningful context was captured
    var hasAnyContext: Bool {
        appContext != nil || clipboardText != nil || clipboardImage != nil
    }

    /// Convenience: build a legacy `CapturedContext` for backward compatibility
    /// during migration. Callers that still expect `CapturedContext` can use this.
    var asCapturedContext: CapturedContext {
        CapturedContext(
            clipboardText: clipboardText,
            clipboardImage: clipboardImage
        )
    }

    static let empty = ContextSnapshot(
        timestamp: Date(),
        appContext: nil,
        clipboardText: nil,
        clipboardImage: nil,
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
    case clipboardImage = "clipboard_image"
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

    /// Whether to capture clipboard images
    let enableClipboardImage: Bool

    static let `default` = ContextCaptureConfig(
        timeoutSeconds: 2.0,
        enableUIContext: true,
        enableClipboardText: false,
        enableClipboardImage: false
    )

    /// Disabled configuration — captures nothing
    static let disabled = ContextCaptureConfig(
        timeoutSeconds: 0,
        enableUIContext: false,
        enableClipboardText: false,
        enableClipboardImage: false
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
            workspacePath: app?.documentPath,
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
