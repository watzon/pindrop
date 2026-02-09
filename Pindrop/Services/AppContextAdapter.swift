//
//  AppContextAdapter.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation

// MARK: - Adapter Capability Model

/// Explicit capabilities that an app adapter declares.
/// Used by downstream consumers (mention formatter, prompt builder) to decide
/// what context features are available for a given app.
struct AppAdapterCapabilities: Equatable, Sendable {

    /// Whether the app supports `@file` / `@Files & Folders` style mentions.
    let supportsFileMentions: Bool

    /// Whether the app supports `@code` / inline code context references.
    let supportsCodeContext: Bool

    /// Whether the app supports `@docs` / documentation references.
    let supportsDocsMentions: Bool

    /// Whether the app supports diff / changeset references (`@diff`, `@git`).
    let supportsDiffContext: Bool

    /// Whether the app supports web/URL context (`@web`, `@url`).
    let supportsWebContext: Bool

    /// Whether the app supports chat/conversation history references.
    let supportsChatHistory: Bool

    /// The prefix token used for mention syntax (e.g. "@" for Cursor, "#" for VS Code Copilot).
    let mentionPrefix: String

    /// Human-readable app display name for logging / diagnostics.
    let displayName: String

    /// A default/fallback capability set with no features enabled.
    static let none = AppAdapterCapabilities(
        supportsFileMentions: false,
        supportsCodeContext: false,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "@",
        displayName: "Unknown App"
    )
}

// MARK: - Adapter Protocol

/// Protocol for app-specific context adapters.
///
/// Each adapter declares its capabilities and the bundle identifiers it handles.
/// Adapters are stateless value objects — they describe *what* an app supports,
/// not *how* to capture context (that's the context engine's job).
protocol AppContextAdapter: Sendable {

    /// The app's primary bundle identifier(s).
    /// An adapter may handle multiple bundle IDs (e.g. VS Code variants).
    var bundleIdentifiers: [String] { get }

    /// Explicit capability declaration for this app.
    var capabilities: AppAdapterCapabilities { get }
}

// MARK: - Concrete Adapters

/// Cursor IDE adapter.
/// Supports: @Files & Folders, @Code, @Docs, @Past Chats
struct CursorAdapter: AppContextAdapter {
    let bundleIdentifiers = ["com.todesktop.230313mzl4w4u92"]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: true,
        supportsDocsMentions: true,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: true,
        mentionPrefix: "@",
        displayName: "Cursor"
    )
}

/// Windsurf (Codeium) IDE adapter.
/// Supports: @ mentions, @diff, @web, @docs
struct WindsurfAdapter: AppContextAdapter {
    let bundleIdentifiers = ["com.exafunction.windsurf"]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: true,
        supportsDocsMentions: true,
        supportsDiffContext: true,
        supportsWebContext: true,
        supportsChatHistory: false,
        mentionPrefix: "@",
        displayName: "Windsurf"
    )
}

/// Visual Studio Code adapter.
/// Supports: # context tools, @ participants
struct VSCodeAdapter: AppContextAdapter {
    let bundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCode.helper"
    ]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: true,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "#",
        displayName: "Visual Studio Code"
    )
}

/// Zed editor adapter.
/// Supports: agent panel, slash-context commands, MCP extensibility
struct ZedAdapter: AppContextAdapter {
    let bundleIdentifiers = [
        "dev.zed.Zed",
        "dev.zed.Zed-Preview"
    ]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: true,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "/",
        displayName: "Zed"
    )
}

/// Antigravity app adapter.
/// Basic file mention support.
struct AntigravityAdapter: AppContextAdapter {
    let bundleIdentifiers = ["com.antigravity.app"]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: false,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "@",
        displayName: "Antigravity"
    )
}

/// OpenAI Codex CLI / app adapter.
/// Supports: @file references, local/cloud context controls
struct CodexAdapter: AppContextAdapter {
    let bundleIdentifiers = ["com.openai.codex"]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: true,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "@",
        displayName: "Codex"
    )
}

/// Fallback adapter for unrecognized apps.
/// Declares no special capabilities — downstream consumers use safe defaults.
struct FallbackAdapter: AppContextAdapter {
    let bundleIdentifiers: [String] = []

    let capabilities: AppAdapterCapabilities

    init(bundleIdentifier: String? = nil) {
        let name = bundleIdentifier.map { "Unknown (\($0))" } ?? "Unknown App"
        self.capabilities = AppAdapterCapabilities(
            supportsFileMentions: false,
            supportsCodeContext: false,
            supportsDocsMentions: false,
            supportsDiffContext: false,
            supportsWebContext: false,
            supportsChatHistory: false,
            mentionPrefix: "@",
            displayName: name
        )
    }
}

// MARK: - Adapter Registry

/// Registry that maps app bundle identifiers to their context adapters.
///
/// Thread-safe, deterministic lookup. Unknown bundle IDs resolve to a
/// `FallbackAdapter` — never nil, never crashes.
final class AppContextAdapterRegistry: Sendable {

    /// All registered adapters, in registration order.
    let registeredAdapters: [any AppContextAdapter]

    /// Pre-built lookup table: bundleID → adapter index in `registeredAdapters`.
    private let lookupTable: [String: Int]

    /// Creates a registry with the default set of known app adapters.
    init() {
        let adapters: [any AppContextAdapter] = [
            CursorAdapter(),
            WindsurfAdapter(),
            VSCodeAdapter(),
            ZedAdapter(),
            AntigravityAdapter(),
            CodexAdapter(),
        ]
        self.registeredAdapters = adapters
        self.lookupTable = Self.buildLookupTable(from: adapters)
    }

    /// Creates a registry with a custom set of adapters (useful for testing).
    init(adapters: [any AppContextAdapter]) {
        self.registeredAdapters = adapters
        self.lookupTable = Self.buildLookupTable(from: adapters)
    }

    /// Resolves the adapter for a given bundle identifier.
    ///
    /// - Parameter bundleIdentifier: The frontmost app's bundle ID.
    /// - Returns: The matching adapter, or a `FallbackAdapter` for unknown apps.
    ///
    /// This method never returns nil and never throws.
    func adapter(for bundleIdentifier: String) -> any AppContextAdapter {
        if let index = lookupTable[bundleIdentifier] {
            return registeredAdapters[index]
        }
        return FallbackAdapter(bundleIdentifier: bundleIdentifier)
    }

    /// Checks whether a bundle identifier has a dedicated (non-fallback) adapter.
    func hasAdapter(for bundleIdentifier: String) -> Bool {
        lookupTable[bundleIdentifier] != nil
    }

    /// Returns all bundle identifiers that have registered adapters.
    var knownBundleIdentifiers: Set<String> {
        Set(lookupTable.keys)
    }

    // MARK: - Private

    private static func buildLookupTable(from adapters: [any AppContextAdapter]) -> [String: Int] {
        var table: [String: Int] = [:]
        for (index, adapter) in adapters.enumerated() {
            for bundleID in adapter.bundleIdentifiers {
                // First registration wins — no silent overwrites
                if table[bundleID] == nil {
                    table[bundleID] = index
                }
            }
        }
        return table
    }
}
