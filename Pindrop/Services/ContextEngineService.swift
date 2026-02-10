//
//  ContextEngineService.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import AppKit
import ApplicationServices
import Foundation
import os.log

// MARK: - AX Provider Protocol

/// Protocol abstracting Accessibility API calls for testability.
/// All methods are synchronous and non-throwing — failures return nil.
protocol AXProviderProtocol: Sendable {
    /// Whether the current process is trusted for Accessibility.
    func isProcessTrusted() -> Bool

    /// Returns the AXUIElement for the system-wide element.
    /// Used to query the frontmost app's focused element.
    func copyFrontmostApplication() -> AXUIElement?

    /// Returns a string attribute value from the given element, or nil.
    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String?

    /// Returns a nested AXUIElement attribute value, or nil.
    func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement?

    /// Returns the pid of the frontmost application, or nil.
    func frontmostAppPID() -> pid_t?
}

// MARK: - System AX Provider (Production)

/// Real Accessibility provider using macOS AX APIs.
final class SystemAXProvider: AXProviderProtocol, @unchecked Sendable {

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func copyFrontmostApplication() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        // AXUIElement is a CFTypeRef — check dynamically
        let typeID = CFGetTypeID(value!)
        guard typeID == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func frontmostAppPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

// MARK: - Context Engine Metrics

/// Lightweight aggregate counters for context capture observability.
/// All fields are numeric — no raw text or sensitive data is ever stored.
@MainActor
final class ContextEngineMetrics {
    private(set) var captureCount: Int = 0
    private(set) var permissionDeniedCount: Int = 0
    private(set) var lastCaptureLatencyMs: Double = 0
    private(set) var totalCaptureLatencyMs: Double = 0

    /// Average capture latency in milliseconds, or 0 if no captures yet.
    var averageCaptureLatencyMs: Double {
        captureCount > 0 ? totalCaptureLatencyMs / Double(captureCount) : 0
    }

    /// Rate of permission-denied outcomes as a fraction of total captures.
    var permissionDeniedRate: Double {
        captureCount > 0 ? Double(permissionDeniedCount) / Double(captureCount) : 0
    }

    func recordCapture(latencyMs: Double, permissionDenied: Bool) {
        captureCount += 1
        lastCaptureLatencyMs = latencyMs
        totalCaptureLatencyMs += latencyMs
        if permissionDenied {
            permissionDeniedCount += 1
        }
    }

    func reset() {
        captureCount = 0
        permissionDeniedCount = 0
        lastCaptureLatencyMs = 0
        totalCaptureLatencyMs = 0
    }
}

// MARK: - Context Engine Service

/// Service that captures structured AX-based UI context for the frontmost app.
///
/// - Permission-aware: returns partial snapshots + warnings when AX unavailable
/// - Never blocks the transcription pipeline
/// - Never captures secure field values
/// - Never dumps full AX tree
/// - Applies strict truncation and sanitization
@MainActor
final class ContextEngineService {

    // MARK: - Constants

    /// Maximum characters for any single text field captured via AX.
    static let maxAXFieldLength = 2048

    /// Maximum characters for selected text captured via AX.
    static let maxSelectedTextLength = 4096

    /// Roles considered "secure" — their values are never captured.
    static let secureRoles: Set<String> = [
        "AXSecureTextField",
        "AXTextField",  // Only blocked when subrole is AXSecureTextField
    ]

    /// Subroles that indicate a secure field.
    static let secureSubroles: Set<String> = [
        "AXSecureTextField",
    ]

    // MARK: - Properties

    private let axProvider: AXProviderProtocol
    let metrics = ContextEngineMetrics()

    // MARK: - Init

    init(axProvider: AXProviderProtocol = SystemAXProvider()) {
        self.axProvider = axProvider
    }

    // MARK: - Public API

    /// Captures the current AX-based app context.
    ///
    /// This method never throws. When AX permission is denied or data is unavailable,
    /// it returns a partial `AppContextInfo` (nil) with appropriate warnings.
    ///
    /// - Returns: Tuple of optional `AppContextInfo` and any capture warnings.
    func captureAppContext() -> (appContext: AppContextInfo?, warnings: [ContextCaptureWarning]) {
        let captureStart = CFAbsoluteTimeGetCurrent()
        var warnings: [ContextCaptureWarning] = []
        var permissionDenied = false

        // 1. Check AX trust
        guard axProvider.isProcessTrusted() else {
            permissionDenied = true
            Log.context.info("AX permission not granted, returning partial snapshot")
            warnings.append(.accessibilityPermissionDenied)

            let partialContext = captureNonAXAppMetadata()
            if partialContext != nil {
                warnings.append(.partialCapture(reason: "AX permission denied; only app metadata available"))
            }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - captureStart) * 1000
            metrics.recordCapture(latencyMs: latencyMs, permissionDenied: permissionDenied)
            Log.context.info("Context capture: latency=\(String(format: "%.1f", latencyMs))ms permissionDenied=true totalCaptures=\(self.metrics.captureCount) permDeniedRate=\(String(format: "%.2f", self.metrics.permissionDeniedRate))")
            return (appContext: partialContext, warnings: warnings)
        }

        // 2. Get frontmost app AXUIElement
        guard let appElement = axProvider.copyFrontmostApplication() else {
            Log.context.warning("Could not get frontmost application AX element")
            warnings.append(.accessibilityDataUnavailable)
            let partialContext = captureNonAXAppMetadata()
            let latencyMs = (CFAbsoluteTimeGetCurrent() - captureStart) * 1000
            metrics.recordCapture(latencyMs: latencyMs, permissionDenied: false)
            Log.context.info("Context capture: latency=\(String(format: "%.1f", latencyMs))ms axUnavailable=true totalCaptures=\(self.metrics.captureCount)")
            return (appContext: partialContext, warnings: warnings)
        }

        // 3. Capture structured data from AX
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = frontmostApp?.bundleIdentifier
        let appName = frontmostApp?.localizedName
            ?? axProvider.stringAttribute(kAXTitleAttribute, of: appElement)
            ?? "Unknown"

        // Window title
        let windowTitle = captureWindowTitle(from: appElement)

        // Focused element
        let focusedElement = axProvider.elementAttribute(kAXFocusedUIElementAttribute, of: appElement)

        var focusedElementRole: String?
        var focusedElementValue: String?
        var selectedText: String?

        if let focused = focusedElement {
            focusedElementRole = axProvider.stringAttribute(kAXRoleAttribute, of: focused)
            let subrole = axProvider.stringAttribute(kAXSubroleAttribute, of: focused)

            // Check if this is a secure field — never capture its value
            if !isSecureField(role: focusedElementRole, subrole: subrole) {
                if let rawValue = axProvider.stringAttribute(kAXValueAttribute, of: focused) {
                    focusedElementValue = Self.sanitizeAndTruncate(
                        rawValue,
                        maxLength: Self.maxAXFieldLength,
                        fieldName: "focusedElementValue"
                    )
                }

                // Selected text
                if let rawSelected = axProvider.stringAttribute(kAXSelectedTextAttribute, of: focused) {
                    selectedText = Self.sanitizeAndTruncate(
                        rawSelected,
                        maxLength: Self.maxSelectedTextLength,
                        fieldName: "selectedText"
                    )
                }
            } else {
                Log.context.debug("Secure field detected, skipping value/selection capture")
            }
        }

        // Document path (from AX document attribute on the app or window)
        let documentPath = captureDocumentPath(from: appElement)

        // Browser URL (from AX, only for known browser bundle IDs)
        let browserURL = captureBrowserURL(
            from: appElement,
            bundleIdentifier: bundleIdentifier
        )

        let appContext = AppContextInfo(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            windowTitle: Self.sanitizeAndTruncate(
                windowTitle,
                maxLength: Self.maxAXFieldLength,
                fieldName: "windowTitle"
            ),
            focusedElementRole: focusedElementRole,
            focusedElementValue: focusedElementValue,
            selectedText: selectedText,
            documentPath: Self.redactHomePath(documentPath),
            browserURL: Self.redactSensitiveURLParams(browserURL)
        )

        let latencyMs = (CFAbsoluteTimeGetCurrent() - captureStart) * 1000
        metrics.recordCapture(latencyMs: latencyMs, permissionDenied: false)
        Log.context.info("Context capture: latency=\(String(format: "%.1f", latencyMs))ms hasDetail=\(appContext.hasDetailedContext) totalCaptures=\(self.metrics.captureCount) avgLatency=\(String(format: "%.1f", self.metrics.averageCaptureLatencyMs))ms")

        return (appContext: appContext, warnings: warnings)
    }

    // MARK: - Non-AX Metadata

    /// Captures basic app metadata without requiring AX permission.
    private func captureNonAXAppMetadata() -> AppContextInfo? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AppContextInfo(
            bundleIdentifier: frontmostApp.bundleIdentifier,
            appName: frontmostApp.localizedName ?? "Unknown",
            windowTitle: nil,
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
    }

    // MARK: - Window Title

    private func captureWindowTitle(from appElement: AXUIElement) -> String? {
        // Try focused window first
        if let focusedWindow = axProvider.elementAttribute(kAXFocusedWindowAttribute, of: appElement) {
            if let title = axProvider.stringAttribute(kAXTitleAttribute, of: focusedWindow) {
                return title
            }
        }
        // Fallback: app title attribute
        return axProvider.stringAttribute(kAXTitleAttribute, of: appElement)
    }

    // MARK: - Document Path

    private func captureDocumentPath(from appElement: AXUIElement) -> String? {
        // Try the focused window's document attribute
        if let focusedWindow = axProvider.elementAttribute(kAXFocusedWindowAttribute, of: appElement),
           let candidate = axProvider.stringAttribute(kAXDocumentAttribute, of: focusedWindow),
           let normalized = normalizeDocumentPath(candidate) {
            return normalized
        }
        
        // Try the app's document attribute
        if let candidate = axProvider.stringAttribute(kAXDocumentAttribute, of: appElement),
           let normalized = normalizeDocumentPath(candidate) {
            return normalized
        }
        
        // Try the focused element's document attribute
        if let focusedElement = axProvider.elementAttribute(kAXFocusedUIElementAttribute, of: appElement),
           let candidate = axProvider.stringAttribute(kAXDocumentAttribute, of: focusedElement),
           let normalized = normalizeDocumentPath(candidate) {
            return normalized
        }
        
        return nil
    }
    
    /// Normalizes and validates a document path candidate.
    /// Accepts absolute paths and file:// URLs; rejects non-file URLs.
    /// - Parameter candidate: Raw path or URL string from AX attribute
    /// - Returns: Normalized absolute path, or nil if invalid
    private func normalizeDocumentPath(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Handle file:// URLs
        if trimmed.hasPrefix("file://") {
            let path = trimmed.replacingOccurrences(of: "file://", with: "")
            let decoded = path.removingPercentEncoding ?? path
            // Basic validation: must be absolute path
            guard decoded.hasPrefix("/") else { return nil }
            return decoded
        }
        
        // Reject non-file URLs (http://, https://, ftp://, etc.)
        if trimmed.contains("://") {
            return nil
        }
        
        // Accept absolute paths only
        guard trimmed.hasPrefix("/") else { return nil }
        return trimmed
    }

    // MARK: - Browser URL

    /// Known browser bundle identifiers.
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",  // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    private func captureBrowserURL(from appElement: AXUIElement, bundleIdentifier: String?) -> String? {
        guard let bundleID = bundleIdentifier,
              Self.browserBundleIDs.contains(bundleID) else {
            return nil
        }

        // Try AX URL attribute on focused window
        if let focusedWindow = axProvider.elementAttribute(kAXFocusedWindowAttribute, of: appElement) {
            if let url = axProvider.stringAttribute(kAXURLAttribute, of: focusedWindow) {
                return url
            }
        }

        // Try on the app element itself
        return axProvider.stringAttribute(kAXURLAttribute, of: appElement)
    }

    // MARK: - Secure Field Detection

    private func isSecureField(role: String?, subrole: String?) -> Bool {
        if let subrole, Self.secureSubroles.contains(subrole) {
            return true
        }
        if let role, role == "AXSecureTextField" {
            return true
        }
        return false
    }

    // MARK: - Sanitization & Truncation

    /// Sanitizes and truncates a text field value.
    /// - Strips leading/trailing whitespace
    /// - Truncates to maxLength with indicator
    /// - Returns nil for empty/whitespace-only strings
    static func sanitizeAndTruncate(_ text: String?, maxLength: Int, fieldName: String) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > maxLength {
            Log.context.debug("Truncating \(fieldName): \(trimmed.count) → \(maxLength) chars")
            return String(trimmed.prefix(maxLength)) + "…[truncated]"
        }
        return trimmed
    }

    /// Redacts the home directory path from document paths.
    /// e.g. "/Users/john/Projects/foo" → "~/Projects/foo"
    static func redactHomePath(_ path: String?) -> String? {
        guard let path else { return nil }
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        // Handle file:// URLs
        if path.hasPrefix("file://") {
            let filePath = path.replacingOccurrences(of: "file://", with: "")
            let decoded = filePath.removingPercentEncoding ?? filePath
            if decoded.hasPrefix(home) {
                return "~" + decoded.dropFirst(home.count)
            }
        }
        return path
    }

    /// Strips sensitive query parameters from URLs (tokens, keys, passwords).
    static func redactSensitiveURLParams(_ urlString: String?) -> String? {
        guard let urlString else { return nil }
        guard var components = URLComponents(string: urlString) else { return urlString }

        let sensitiveParams: Set<String> = [
            "token", "access_token", "refresh_token", "api_key", "apikey",
            "key", "secret", "password", "pwd", "auth", "session",
            "session_id", "sessionid", "code", "state",
        ]

        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                if sensitiveParams.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "REDACTED")
                }
                return item
            }
            // Remove empty query
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        }

        return components.string ?? urlString
    }
}
