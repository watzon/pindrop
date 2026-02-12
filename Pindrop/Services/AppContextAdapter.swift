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
    let supportsFileMentions: Bool
    let supportsCodeContext: Bool
    let supportsDocsMentions: Bool
    let supportsDiffContext: Bool
    let supportsWebContext: Bool
    let supportsChatHistory: Bool
    let mentionPrefix: String
    /// Must contain "{path}".
    let mentionTemplate: String
    let displayName: String
    static let none = AppAdapterCapabilities(
        supportsFileMentions: false,
        supportsCodeContext: false,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "@",
        mentionTemplate: "@{path}",
        displayName: "Unknown App"
    )
    func renderMention(relativePath: String) -> String {
        mentionTemplate.replacingOccurrences(of: MentionTemplateCatalog.pathToken, with: relativePath)
    }
    func renderMention(path: String) -> String {
        renderMention(relativePath: path)
    }
    func withMentionFormatting(mentionPrefix: String, mentionTemplate: String) -> AppAdapterCapabilities {
        AppAdapterCapabilities(
            supportsFileMentions: supportsFileMentions,
            supportsCodeContext: supportsCodeContext,
            supportsDocsMentions: supportsDocsMentions,
            supportsDiffContext: supportsDiffContext,
            supportsWebContext: supportsWebContext,
            supportsChatHistory: supportsChatHistory,
            mentionPrefix: mentionPrefix,
            mentionTemplate: mentionTemplate,
            displayName: displayName
        )
    }
    func withMentionFormatting(prefix: String, template: String) -> AppAdapterCapabilities {
        withMentionFormatting(mentionPrefix: prefix, mentionTemplate: template)
    }
}
enum MentionTemplateCatalog {
    static let pathToken = "{path}"
    static let canonicalPlaceholder = "[[:{path}:]]"
    static let canonicalPlaceholderTemplate = canonicalPlaceholder
}
struct TerminalProviderDescriptor: Sendable, Equatable {
    let id: String
    let titlePrefixes: [String]
    let exactTitles: [String]
    let defaultMentionTemplate: String
    func matches(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if exactTitles.contains(where: { lower == $0.lowercased() }) {
            return true
        }
        return titlePrefixes.contains(where: { lower.hasPrefix($0.lowercased()) })
    }
}
enum TerminalProviderRegistry {
    static let descriptors: [TerminalProviderDescriptor] = [
        TerminalProviderDescriptor(id: "pi", titlePrefixes: ["π"], exactTitles: [], defaultMentionTemplate: "@{path}"),
        TerminalProviderDescriptor(id: "opencode", titlePrefixes: ["oc"], exactTitles: [], defaultMentionTemplate: "@{path}"),
        TerminalProviderDescriptor(id: "claude", titlePrefixes: ["claude"], exactTitles: ["claude"], defaultMentionTemplate: "@{path}"),
        TerminalProviderDescriptor(id: "codex", titlePrefixes: ["codex"], exactTitles: ["codex"], defaultMentionTemplate: "[@{path}]({path})"),
    ]
    static func detectProviderIdentifier(windowTitle: String?, focusedElementValue: String?) -> String? {
        let candidates = [windowTitle, focusedElementValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for candidate in candidates {
            if let descriptor = descriptors.first(where: { $0.matches(title: candidate) }) {
                return descriptor.id
            }
        }
        return nil
    }
    static func defaultMentionTemplate(for providerIdentifier: String?) -> String? {
        guard let providerIdentifier = providerIdentifier?.lowercased() else { return nil }
        return descriptors.first(where: { $0.id == providerIdentifier })?.defaultMentionTemplate
    }
}

struct AppRuntimeEnrichment: Equatable, Sendable {
    let activeFilePath: String?
    let activeFileConfidence: Double
    let workspacePath: String?
    let workspaceConfidence: Double
    let fileTagCandidates: [String]
    let styleSignals: [String]
    let codingSignals: [String]

    static let none = AppRuntimeEnrichment(
        activeFilePath: nil,
        activeFileConfidence: 0,
        workspacePath: nil,
        workspaceConfidence: 0,
        fileTagCandidates: [],
        styleSignals: [],
        codingSignals: []
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

extension AppContextAdapter {
    func runtimeEnrichment(snapshot: ContextSnapshot, routingSignal: PromptRoutingSignal) -> AppRuntimeEnrichment {
        let inferredActiveFilePath = inferredFilename(from: snapshot.appContext?.windowTitle)
        let activeFilePath = normalizedContextValue(snapshot.appContext?.documentPath) ?? inferredActiveFilePath
        let hasDocumentPath = normalizedContextValue(snapshot.appContext?.documentPath) != nil
        let workspacePath = normalizedContextValue(routingSignal.workspacePath)
        var activeFileConfidence = 0.0
        if hasDocumentPath {
            activeFileConfidence = 1.0
        } else if inferredActiveFilePath != nil {
            activeFileConfidence = 0.45
        } else if languageSignal(for: snapshot.appContext?.windowTitle) != nil {
            activeFileConfidence = 0.45
        }
        var workspaceConfidence = 0.0
        if workspacePath != nil {
            workspaceConfidence = capabilities.supportsCodeContext ? 0.9 : 0.65
        } else if capabilities.supportsCodeContext {
            workspaceConfidence = 0.25
        }
        var fileTagCandidates: [String] = []
        if let activeFilePath {
            fileTagCandidates.append(activeFilePath)
            let filename = (activeFilePath as NSString).lastPathComponent
            if !filename.isEmpty {
                fileTagCandidates.append(filename)
            }
            if let workspacePath,
               activeFilePath.hasPrefix(workspacePath) {
                let relative = String(activeFilePath.dropFirst(workspacePath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relative.isEmpty {
                    fileTagCandidates.append(relative)
                }
            }
        } else if let windowTitle = normalizedContextValue(snapshot.appContext?.windowTitle),
                  windowTitle.contains(".") {
            fileTagCandidates.append(windowTitle)
        }
        var dedupedCandidates: [String] = []
        var seenCandidates = Set<String>()
        for candidate in fileTagCandidates {
            if seenCandidates.insert(candidate).inserted {
                dedupedCandidates.append(candidate)
            }
        }
        var styleSignals: [String] = []
        if let languageSignal = languageSignal(for: activeFilePath ?? snapshot.appContext?.windowTitle) {
            styleSignals.append(languageSignal)
        }
        var codingSignals: [String] = [
            capabilities.supportsCodeContext ? "code_editor_context" : "limited_code_context",
            "mention_prefix:\(capabilities.mentionPrefix)"
        ]
        if capabilities.supportsDiffContext {
            codingSignals.append("diff_context_supported")
        }
        if capabilities.supportsDocsMentions {
            codingSignals.append("docs_context_supported")
        }
        if capabilities.supportsWebContext {
            codingSignals.append("web_context_supported")
        }
        if capabilities.supportsChatHistory {
            codingSignals.append("chat_history_supported")
        }
        return AppRuntimeEnrichment(
            activeFilePath: activeFilePath,
            activeFileConfidence: activeFileConfidence,
            workspacePath: workspacePath,
            workspaceConfidence: workspaceConfidence,
            fileTagCandidates: Array(dedupedCandidates.prefix(8)),
            styleSignals: styleSignals,
            codingSignals: codingSignals
        )
    }

    private func normalizedContextValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func inferredFilename(from windowTitle: String?) -> String? {
        guard let windowTitle = normalizedContextValue(windowTitle) else { return nil }

        let separators = [" — ", " – ", " - ", " · ", " • ", " | "]
        for separator in separators where windowTitle.contains(separator) {
            let segments = windowTitle.components(separatedBy: separator)
            for segment in segments.reversed() {
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if isLikelyFilenameToken(trimmed) {
                    return trimmed
                }
            }
        }

        return isLikelyFilenameToken(windowTitle) ? windowTitle : nil
    }

    private func isLikelyFilenameToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lastPathComponent = (trimmed as NSString).lastPathComponent
        let ext = (lastPathComponent as NSString).pathExtension
        if !ext.isEmpty {
            return ext.count <= 10 && !ext.contains(" ")
        }

        let lower = lastPathComponent.lowercased()
        return ["readme", "makefile", "dockerfile", "justfile", "license", "procfile", "gemfile", "rakefile", "podfile"].contains(lower)
    }

    private func languageSignal(for path: String?) -> String? {
        guard let path = normalizedContextValue(path) else { return nil }

        let fileExtension = (path as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "swift":
            return "style:swift"
        case "ts", "tsx":
            return "style:typescript"
        case "js", "jsx":
            return "style:javascript"
        case "py":
            return "style:python"
        case "go":
            return "style:go"
        case "rs":
            return "style:rust"
        case "md":
            return "style:markdown"
        case "json":
            return "style:json"
        case "yaml", "yml":
            return "style:yaml"
        default:
            return nil
        }
    }
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
        mentionTemplate: "@{path}",
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
        mentionTemplate: "@{path}",
        displayName: "Windsurf"
    )
}

/// Visual Studio Code adapter.
/// Supports: file mentions and code-context references in chat workflows
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
        mentionPrefix: "@",
        mentionTemplate: "@{path}",
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
        mentionTemplate: "/{path}",
        displayName: "Zed"
    )
}

/// Antigravity app adapter.
/// Basic file mention support.
    struct AntigravityAdapter: AppContextAdapter {
    let bundleIdentifiers = ["com.antigravity.app", "com.google.antigravity"]

    let capabilities = AppAdapterCapabilities(
        supportsFileMentions: true,
        supportsCodeContext: false,
        supportsDocsMentions: false,
        supportsDiffContext: false,
        supportsWebContext: false,
        supportsChatHistory: false,
        mentionPrefix: "@",
        mentionTemplate: "@{path}",
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
        mentionTemplate: "[@{path}]({path})",
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
            mentionTemplate: "@{path}",
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

    /// Pre-built lookup table: normalized bundleID (lowercased) → adapter index in `registeredAdapters`.
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
        let normalized = Self.normalizeBundleIdentifier(bundleIdentifier)
        if let index = lookupTable[normalized] {
            return registeredAdapters[index]
        }
        return FallbackAdapter(bundleIdentifier: bundleIdentifier)
    }

    func enrichment(
        for snapshot: ContextSnapshot,
        routingSignal: PromptRoutingSignal
    ) -> AppRuntimeEnrichment {
        guard let bundleIdentifier = snapshot.appContext?.bundleIdentifier else {
            return .none
        }

        let adapter = adapter(for: bundleIdentifier)
        return adapter.runtimeEnrichment(snapshot: snapshot, routingSignal: routingSignal)
    }


    /// Checks whether a bundle identifier has a dedicated (non-fallback) adapter.
    func hasAdapter(for bundleIdentifier: String) -> Bool {
        let normalized = Self.normalizeBundleIdentifier(bundleIdentifier)
        return lookupTable[normalized] != nil
    }

    /// Returns all bundle identifiers that have registered adapters.
    var knownBundleIdentifiers: Set<String> {
        Set(registeredAdapters.flatMap(\.bundleIdentifiers))
    }

    // MARK: - Private

    private static func buildLookupTable(from adapters: [any AppContextAdapter]) -> [String: Int] {
        var table: [String: Int] = [:]
        for (index, adapter) in adapters.enumerated() {
            for bundleID in adapter.bundleIdentifiers {
                let normalized = normalizeBundleIdentifier(bundleID)
                // First registration wins — no silent overwrites
                if table[normalized] == nil {
                    table[normalized] = index
                }
            }
        }
        return table
    }

    private static func normalizeBundleIdentifier(_ bundleIdentifier: String) -> String {
        bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
}
