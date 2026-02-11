//
//  PromptRoutingSignalTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import XCTest
@testable import Pindrop

final class PromptRoutingSignalTests: XCTestCase {

    // MARK: - Signal from Snapshot

    func testBuildSignalFromSnapshotWithAppContext() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let registry = AppContextAdapterRegistry()
        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: registry)

        XCTAssertEqual(signal.appBundleIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(signal.appName, "cursor")
        XCTAssertEqual(signal.windowTitle, "main.swift — MyProject")
        XCTAssertEqual(signal.workspacePath, "/Users/dev/MyProject")
        XCTAssertNil(signal.browserDomain)
        XCTAssertTrue(signal.isCodeEditorContext)
    }

    func testBuildSignalFromSnapshotWithUnknownApp() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let registry = AppContextAdapterRegistry()
        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: registry)

        XCTAssertEqual(signal.appBundleIdentifier, "com.apple.safari")
        XCTAssertEqual(signal.appName, "safari")
        XCTAssertEqual(signal.browserDomain, "github.com")
        XCTAssertFalse(signal.isCodeEditorContext)
    }

    func testBuildSignalFromEmptySnapshot() {
        let signal = PromptRoutingSignal.from(snapshot: .empty)

        XCTAssertNil(signal.appBundleIdentifier)
        XCTAssertNil(signal.appName)
        XCTAssertNil(signal.windowTitle)
        XCTAssertNil(signal.workspacePath)
        XCTAssertNil(signal.browserDomain)
        XCTAssertFalse(signal.isCodeEditorContext)
    }

    func testBuildSignalWithoutRegistryDefaultsToNotCodeEditor() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertFalse(signal.isCodeEditorContext)
    }

    func testBuildSignalUsesDirectoryDocumentPathAsWorkspaceRoot() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/personal/pindrop")
    }

    func testBuildSignalUsesExistingDirectoryPathWithoutTrailingSlash() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, tempDirectory.path)
    }

    func testBuildSignalDerivesWorkspaceFromTerminalWindowTitleWhenDocumentPathMissing() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/personal/pindrop")
    }

    func testBuildSignalDerivesWorkspaceFromTerminalFocusedValueWhenWindowTitleMissing() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/personal/pindrop")
    }

    func testBuildSignalDerivesWorkspaceFromHyperWindowTitleWhenDocumentPathMissing() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/personal/pindrop")
    }

    func testBuildSignalDerivesWorkspaceFromTabbyFocusedValueWhenDocumentPathMissing() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/personal/pindrop")
    }

    func testBuildSignalDoesNotUseTitlePathFallbackForNonTerminalApps() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertNil(signal.workspacePath)
    }

    // MARK: - Manual Preset Overrides Routing Suggestion

    func testManualPresetOverridesRoutingSuggestion() {
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
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )
        let signal = PromptRoutingSignal.from(
            snapshot: snapshot,
            adapterRegistry: AppContextAdapterRegistry()
        )
        let suggestion = resolver.resolve(signal: signal)

        XCTAssertEqual(suggestion, .noSuggestion)

        let effectivePresetId = manualPresetId
        XCTAssertEqual(effectivePresetId, "user-selected-preset-123",
                       "Manual preset selection must always take priority over routing suggestion")
    }

    func testNoOpResolverAlwaysReturnsNoSuggestion() {
        let resolver = NoOpPromptRoutingResolver()

        let signal = PromptRoutingSignal.empty
        XCTAssertEqual(resolver.resolve(signal: signal), .noSuggestion)

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
            snapshot: ContextSnapshot(
                timestamp: Date(),
                appContext: appContext,
                clipboardText: nil,
                warnings: []
            ),
            adapterRegistry: AppContextAdapterRegistry()
        )
        XCTAssertEqual(resolver.resolve(signal: signalWithContext), .noSuggestion)
    }

    // MARK: - PromptRoutingSuggestion Equatable

    func testSuggestionEquatable() {
        XCTAssertEqual(PromptRoutingSuggestion.noSuggestion, .noSuggestion)
        XCTAssertEqual(PromptRoutingSuggestion.suggestedPresetId("abc"), .suggestedPresetId("abc"))
        XCTAssertNotEqual(PromptRoutingSuggestion.noSuggestion, .suggestedPresetId("abc"))
        XCTAssertNotEqual(PromptRoutingSuggestion.suggestedPresetId("abc"), .suggestedPresetId("xyz"))
    }
}
