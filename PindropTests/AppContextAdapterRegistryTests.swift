//
//  AppContextAdapterRegistryTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import XCTest
@testable import Pindrop

final class AppContextAdapterRegistryTests: XCTestCase {

    var sut: AppContextAdapterRegistry!

    override func setUp() async throws {
        try await super.setUp()
        sut = AppContextAdapterRegistry()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Known Bundle ID Resolution

    func testKnownBundleIDsResolveExpectedAdapter() {
        let expectations: [(bundleID: String, expectedName: String)] = [
            ("com.todesktop.230313mzl4w4u92", "Cursor"),
            ("com.exafunction.windsurf", "Windsurf"),
            ("com.microsoft.VSCode", "Visual Studio Code"),
            ("com.microsoft.VSCodeInsiders", "Visual Studio Code"),
            ("com.microsoft.VSCode.helper", "Visual Studio Code"),
            ("dev.zed.Zed", "Zed"),
            ("dev.zed.Zed-Preview", "Zed"),
            ("com.antigravity.app", "Antigravity"),
            ("com.google.antigravity", "Antigravity"),
            ("com.openai.codex", "Codex"),
        ]

        for (bundleID, expectedName) in expectations {
            let adapter = sut.adapter(for: bundleID)
            XCTAssertEqual(
                adapter.capabilities.displayName,
                expectedName,
                "Bundle ID \(bundleID) should resolve to \(expectedName)"
            )
        }
    }

    // MARK: - Unknown Bundle ID Fallback

    func testUnknownBundleUsesMetadataFallback() {
        let adapter = sut.adapter(for: "com.unknown.app")

        XCTAssertTrue(adapter is FallbackAdapter, "Unknown bundle ID should return FallbackAdapter")
        XCTAssertEqual(adapter.capabilities.displayName, "Unknown (com.unknown.app)")
        XCTAssertFalse(adapter.capabilities.supportsFileMentions)
        XCTAssertFalse(adapter.capabilities.supportsCodeContext)
        XCTAssertFalse(adapter.capabilities.supportsDocsMentions)
        XCTAssertFalse(adapter.capabilities.supportsDiffContext)
        XCTAssertFalse(adapter.capabilities.supportsWebContext)
        XCTAssertFalse(adapter.capabilities.supportsChatHistory)
        XCTAssertEqual(adapter.capabilities.mentionPrefix, "@")
    }

    func testFallbackAdapterAlwaysReturnsNonNilResult() {
        // Ensure adapter(for:) never returns nil — it always returns *some* adapter
        let randomBundleIDs = [
            "com.totally.random",
            "",
            "a.b.c.d.e.f",
            "com.apple.Safari",
        ]

        for bundleID in randomBundleIDs {
            let adapter = sut.adapter(for: bundleID)
            XCTAssertNotNil(adapter.capabilities, "adapter(for:) must never return nil for \(bundleID)")
        }
    }

    // MARK: - Capabilities Verification

    func testCursorCapabilities() {
        let adapter = sut.adapter(for: "com.todesktop.230313mzl4w4u92")
        let caps = adapter.capabilities

        XCTAssertTrue(caps.supportsFileMentions)
        XCTAssertTrue(caps.supportsCodeContext)
        XCTAssertTrue(caps.supportsDocsMentions)
        XCTAssertFalse(caps.supportsDiffContext)
        XCTAssertFalse(caps.supportsWebContext)
        XCTAssertTrue(caps.supportsChatHistory)
        XCTAssertEqual(caps.mentionPrefix, "@")
    }

    func testWindsurfCapabilities() {
        let adapter = sut.adapter(for: "com.exafunction.windsurf")
        let caps = adapter.capabilities

        XCTAssertTrue(caps.supportsFileMentions)
        XCTAssertTrue(caps.supportsCodeContext)
        XCTAssertTrue(caps.supportsDocsMentions)
        XCTAssertTrue(caps.supportsDiffContext)
        XCTAssertTrue(caps.supportsWebContext)
        XCTAssertFalse(caps.supportsChatHistory)
        XCTAssertEqual(caps.mentionPrefix, "@")
    }

    func testVSCodeUsesDifferentMentionPrefix() {
        let adapter = sut.adapter(for: "com.microsoft.VSCode")
        XCTAssertEqual(adapter.capabilities.mentionPrefix, "#")
    }

    func testZedUsesSlashPrefix() {
        let adapter = sut.adapter(for: "dev.zed.Zed")
        XCTAssertEqual(adapter.capabilities.mentionPrefix, "/")
    }

    // MARK: - Multi-Bundle-ID Resolution

    func testMultiBundleIDAdapterResolvesToSameCapabilities() {
        let vscodeBundles = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCode.helper",
        ]

        let referenceCapabilities = sut.adapter(for: vscodeBundles[0]).capabilities

        for bundleID in vscodeBundles.dropFirst() {
            let caps = sut.adapter(for: bundleID).capabilities
            XCTAssertEqual(caps, referenceCapabilities,
                           "All VS Code bundle IDs should have identical capabilities")
        }
    }

    func testZedBundleVariantsResolveSame() {
        let caps1 = sut.adapter(for: "dev.zed.Zed").capabilities
        let caps2 = sut.adapter(for: "dev.zed.Zed-Preview").capabilities
        XCTAssertEqual(caps1, caps2, "Zed and Zed-Preview should have identical capabilities")
    }

    // MARK: - hasAdapter

    func testHasAdapterReturnsTrueForKnownBundleIDs() {
        XCTAssertTrue(sut.hasAdapter(for: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(sut.hasAdapter(for: "com.exafunction.windsurf"))
        XCTAssertTrue(sut.hasAdapter(for: "com.microsoft.VSCode"))
        XCTAssertTrue(sut.hasAdapter(for: "dev.zed.Zed"))
        XCTAssertTrue(sut.hasAdapter(for: "com.antigravity.app"))
        XCTAssertTrue(sut.hasAdapter(for: "com.openai.codex"))
    }

    func testHasAdapterReturnsFalseForUnknownBundleIDs() {
        XCTAssertFalse(sut.hasAdapter(for: "com.unknown.app"))
        XCTAssertFalse(sut.hasAdapter(for: ""))
        XCTAssertFalse(sut.hasAdapter(for: "com.apple.Xcode"))
    }

    // MARK: - knownBundleIdentifiers

    func testKnownBundleIdentifiersContainsAllRegistered() {
        let known = sut.knownBundleIdentifiers

        let expectedIDs: Set<String> = [
            "com.todesktop.230313mzl4w4u92",
            "com.exafunction.windsurf",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCode.helper",
            "dev.zed.Zed",
            "dev.zed.Zed-Preview",
            "com.antigravity.app",
            "com.google.antigravity",
            "com.openai.codex",
        ]

        XCTAssertEqual(known, expectedIDs)
    }

    // MARK: - Empty Registry Edge Case

    func testEmptyRegistryFallsBackForEverything() {
        let emptyRegistry = AppContextAdapterRegistry(adapters: [])

        let adapter = emptyRegistry.adapter(for: "com.todesktop.230313mzl4w4u92")
        XCTAssertTrue(adapter is FallbackAdapter)
        XCTAssertFalse(emptyRegistry.hasAdapter(for: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(emptyRegistry.knownBundleIdentifiers.isEmpty)
    }

    // MARK: - Custom Registry (Test-Friendly Init)

    func testCustomRegistryUsesProvidedAdapters() {
        let customRegistry = AppContextAdapterRegistry(adapters: [CursorAdapter()])

        XCTAssertTrue(customRegistry.hasAdapter(for: "com.todesktop.230313mzl4w4u92"))
        XCTAssertFalse(customRegistry.hasAdapter(for: "com.exafunction.windsurf"))
        XCTAssertEqual(customRegistry.knownBundleIdentifiers.count, 1)
    }

    // MARK: - AppAdapterCapabilities.none

    func testCapabilitiesNoneHasAllDisabled() {
        let caps = AppAdapterCapabilities.none

        XCTAssertFalse(caps.supportsFileMentions)
        XCTAssertFalse(caps.supportsCodeContext)
        XCTAssertFalse(caps.supportsDocsMentions)
        XCTAssertFalse(caps.supportsDiffContext)
        XCTAssertFalse(caps.supportsWebContext)
        XCTAssertFalse(caps.supportsChatHistory)
        XCTAssertEqual(caps.mentionPrefix, "@")
        XCTAssertEqual(caps.displayName, "Unknown App")
    }
}
