//
//  PromptRoutingSignalTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct PromptRoutingSignalTests {
    @Test func buildSignalFromSnapshotWithAppContext() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appName: "Cursor",
            windowTitle: "main.swift — MyProject",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: "/Users/dev/MyProject/main.swift",
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: AppContextAdapterRegistry())

        #expect(signal.appBundleIdentifier == "com.todesktop.230313mzl4w4u92")
        #expect(signal.appName == "cursor")
        #expect(signal.windowTitle == "main.swift — MyProject")
        #expect(signal.workspacePath == "/Users/dev/MyProject")
        #expect(signal.browserDomain == nil)
        #expect(signal.isCodeEditorContext)
    }

    @Test func buildSignalUsesCaseInsensitiveAdapterLookupForCodeEditorContext() {
        let appContext = AppContextInfo(
            bundleIdentifier: "dev.zed.Zed",
            appName: "Zed",
            windowTitle: "nanoclaw — bootstrap-context.ts",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: AppContextAdapterRegistry())

        #expect(signal.appBundleIdentifier == "dev.zed.zed")
        #expect(signal.isCodeEditorContext)
    }

    @Test func buildSignalFromSnapshotWithUnknownApp() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "GitHub",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: "https://github.com/watzon/pindrop"
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: AppContextAdapterRegistry())

        #expect(signal.appBundleIdentifier == "com.apple.safari")
        #expect(signal.appName == "safari")
        #expect(signal.browserDomain == "github.com")
        #expect(signal.isCodeEditorContext == false)
    }

    @Test func buildSignalFromEmptySnapshot() {
        let signal = PromptRoutingSignal.from(snapshot: .empty)

        #expect(signal.appBundleIdentifier == nil)
        #expect(signal.appName == nil)
        #expect(signal.windowTitle == nil)
        #expect(signal.workspacePath == nil)
        #expect(signal.browserDomain == nil)
        #expect(signal.isCodeEditorContext == false)
    }

    @Test func buildSignalWithoutRegistryDefaultsToNotCodeEditor() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appName: "Cursor",
            windowTitle: nil,
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        #expect(signal.isCodeEditorContext == false)
    }

    @Test func buildSignalUsesDirectoryDocumentPathAsWorkspaceRoot() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: "shell",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: "~/Projects/personal/pindrop/",
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        #expect(signal.workspacePath == "~/Projects/personal/pindrop")
    }

    @Test func buildSignalUsesExistingDirectoryPathWithoutTrailingSlash() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let appContext = AppContextInfo(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: "shell",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: tempDirectory.path,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        #expect(signal.workspacePath == tempDirectory.path)
    }

    @Test func buildSignalDerivesWorkspaceFromTerminalWindowTitleWhenDocumentPathMissing() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: "dev@machine:~/Projects/personal/pindrop/",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.workspacePath == "~/Projects/personal/pindrop")
    }

    @Test func buildSignalDerivesWorkspaceFromTerminalFocusedValueWhenWindowTitleMissing() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: nil,
            focusedElementRole: "AXTextArea",
            focusedElementValue: "dev@machine:~/Projects/personal/pindrop/",
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.workspacePath == "~/Projects/personal/pindrop")
    }

    @Test func buildSignalDerivesWorkspaceFromHyperWindowTitleWhenDocumentPathMissing() {
        let appContext = AppContextInfo(
            bundleIdentifier: "co.zeit.hyper",
            appName: "Hyper",
            windowTitle: "dev@machine:~/Projects/personal/pindrop/",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.workspacePath == "~/Projects/personal/pindrop")
    }

    @Test func buildSignalDerivesWorkspaceFromTabbyFocusedValueWhenDocumentPathMissing() {
        let appContext = AppContextInfo(
            bundleIdentifier: "org.tabby",
            appName: "Tabby",
            windowTitle: nil,
            focusedElementRole: "AXTextArea",
            focusedElementValue: "dev@machine:~/Projects/personal/pindrop/",
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.workspacePath == "~/Projects/personal/pindrop")
    }

    @Test func buildSignalDoesNotUseTitlePathFallbackForNonTerminalApps() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "notes at ~/Projects/personal/pindrop/",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.workspacePath == nil)
    }

    @Test func buildSignalInfersTerminalProviderFromTitlePrefix() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty",
            windowTitle: "π session",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.terminalProviderIdentifier == "pi")
    }

    @Test func buildSignalInfersTerminalProviderFromFocusedValue() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.googlecode.iterm2",
            appName: "iTerm2",
            windowTitle: nil,
            focusedElementRole: "AXTextArea",
            focusedElementValue: "codex",
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.terminalProviderIdentifier == "codex")
    }

    @Test func buildSignalDoesNotInferTerminalProviderForNonTerminalApp() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "claude",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])

        let signal = PromptRoutingSignal.from(snapshot: snapshot)
        #expect(signal.terminalProviderIdentifier == nil)
    }

    @Test func manualPresetOverridesRoutingSuggestion() {
        let manualPresetId = "user-selected-preset-123"
        let resolver = NoOpPromptRoutingResolver()

        let appContext = AppContextInfo(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appName: "Cursor",
            windowTitle: nil,
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let snapshot = ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: [])
        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: AppContextAdapterRegistry())
        let suggestion = resolver.resolve(signal: signal)

        #expect(suggestion == .noSuggestion)
        #expect(manualPresetId == "user-selected-preset-123")
    }

    @Test func noOpResolverAlwaysReturnsNoSuggestion() {
        let resolver = NoOpPromptRoutingResolver()

        #expect(resolver.resolve(signal: .empty) == .noSuggestion)

        let appContext = AppContextInfo(
            bundleIdentifier: "dev.zed.Zed",
            appName: "Zed",
            windowTitle: "project",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let signalWithContext = PromptRoutingSignal.from(
            snapshot: ContextSnapshot(timestamp: Date(), appContext: appContext, clipboardText: nil, warnings: []),
            adapterRegistry: AppContextAdapterRegistry()
        )
        #expect(resolver.resolve(signal: signalWithContext) == .noSuggestion)
    }

    @Test func suggestionEquatable() {
        #expect(PromptRoutingSuggestion.noSuggestion == .noSuggestion)
        #expect(PromptRoutingSuggestion.suggestedPresetId("abc") == .suggestedPresetId("abc"))
        #expect(PromptRoutingSuggestion.noSuggestion != .suggestedPresetId("abc"))
        #expect(PromptRoutingSuggestion.suggestedPresetId("abc") != .suggestedPresetId("xyz"))
    }
}
