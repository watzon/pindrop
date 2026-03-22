//
//  AppContextAdapterRegistryTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct AppContextAdapterRegistryTests {
    let sut = AppContextAdapterRegistry()

    @Test func knownBundleIDsResolveExpectedAdapter() {
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
            #expect(adapter.capabilities.displayName == expectedName)
        }
    }

    @Test func adapterLookupIsCaseInsensitive() {
        #expect(sut.adapter(for: "DEV.ZED.ZED").capabilities.displayName == "Zed")
        #expect(sut.adapter(for: "com.microsoft.vscode").capabilities.displayName == "Visual Studio Code")
        #expect(sut.hasAdapter(for: "DEV.ZED.ZED"))
    }

    @Test func enrichmentDerivesFilenameFromWindowTitleWhenDocumentPathMissing() {
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

        let signal = PromptRoutingSignal.from(snapshot: snapshot, adapterRegistry: sut)
        let enrichment = sut.enrichment(for: snapshot, routingSignal: signal)

        #expect(enrichment.activeFilePath == "bootstrap-context.ts")
        #expect(abs(enrichment.activeFileConfidence - 0.45) < 0.001)
        #expect(enrichment.fileTagCandidates.contains("bootstrap-context.ts"))
        #expect(!enrichment.fileTagCandidates.contains("nanoclaw — bootstrap-context.ts"))
    }

    @Test func unknownBundleUsesMetadataFallback() {
        let adapter = sut.adapter(for: "com.unknown.app")

        #expect(adapter is FallbackAdapter)
        #expect(adapter.capabilities.displayName == "Unknown (com.unknown.app)")
        #expect(adapter.capabilities.supportsFileMentions == false)
        #expect(adapter.capabilities.supportsCodeContext == false)
        #expect(adapter.capabilities.supportsDocsMentions == false)
        #expect(adapter.capabilities.supportsDiffContext == false)
        #expect(adapter.capabilities.supportsWebContext == false)
        #expect(adapter.capabilities.supportsChatHistory == false)
        #expect(adapter.capabilities.mentionPrefix == "@")
    }

    @Test func fallbackAdapterAlwaysReturnsNonNilResult() {
        let randomBundleIDs = ["com.totally.random", "", "a.b.c.d.e.f", "com.apple.Safari"]

        for bundleID in randomBundleIDs {
            let adapter = sut.adapter(for: bundleID)
            #expect(adapter.capabilities.displayName.isEmpty == false)
        }
    }

    @Test func cursorCapabilities() {
        let caps = sut.adapter(for: "com.todesktop.230313mzl4w4u92").capabilities
        #expect(caps.supportsFileMentions)
        #expect(caps.supportsCodeContext)
        #expect(caps.supportsDocsMentions)
        #expect(caps.supportsDiffContext == false)
        #expect(caps.supportsWebContext == false)
        #expect(caps.supportsChatHistory)
        #expect(caps.mentionPrefix == "@")
    }

    @Test func windsurfCapabilities() {
        let caps = sut.adapter(for: "com.exafunction.windsurf").capabilities
        #expect(caps.supportsFileMentions)
        #expect(caps.supportsCodeContext)
        #expect(caps.supportsDocsMentions)
        #expect(caps.supportsDiffContext)
        #expect(caps.supportsWebContext)
        #expect(caps.supportsChatHistory == false)
        #expect(caps.mentionPrefix == "@")
    }

    @Test func vscodeUsesAtMentionPrefix() {
        #expect(sut.adapter(for: "com.microsoft.VSCode").capabilities.mentionPrefix == "@")
    }

    @Test func codexUsesMarkdownMentionTemplate() {
        #expect(sut.adapter(for: "com.openai.codex").capabilities.mentionTemplate == "[@{path}]({path})")
    }

    @Test func terminalProviderRegistryDetectsProvidersFromTitleSignals() {
        #expect(TerminalProviderRegistry.detectProviderIdentifier(windowTitle: "π shell", focusedElementValue: nil) == "pi")
        #expect(TerminalProviderRegistry.detectProviderIdentifier(windowTitle: "oc", focusedElementValue: nil) == "opencode")
        #expect(TerminalProviderRegistry.detectProviderIdentifier(windowTitle: "claude", focusedElementValue: nil) == "claude")
        #expect(TerminalProviderRegistry.detectProviderIdentifier(windowTitle: nil, focusedElementValue: "codex") == "codex")
    }

    @Test func zedUsesSlashPrefix() {
        #expect(sut.adapter(for: "dev.zed.Zed").capabilities.mentionPrefix == "/")
    }

    @Test func multiBundleIDAdapterResolvesToSameCapabilities() {
        let vscodeBundles = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCode.helper",
        ]

        let referenceCapabilities = sut.adapter(for: vscodeBundles[0]).capabilities

        for bundleID in vscodeBundles.dropFirst() {
            let caps = sut.adapter(for: bundleID).capabilities
            #expect(caps == referenceCapabilities)
        }
    }

    @Test func zedBundleVariantsResolveSame() {
        let caps1 = sut.adapter(for: "dev.zed.Zed").capabilities
        let caps2 = sut.adapter(for: "dev.zed.Zed-Preview").capabilities
        #expect(caps1 == caps2)
    }

    @Test func hasAdapterReturnsTrueForKnownBundleIDs() {
        #expect(sut.hasAdapter(for: "com.todesktop.230313mzl4w4u92"))
        #expect(sut.hasAdapter(for: "com.exafunction.windsurf"))
        #expect(sut.hasAdapter(for: "com.microsoft.VSCode"))
        #expect(sut.hasAdapter(for: "dev.zed.Zed"))
        #expect(sut.hasAdapter(for: "com.antigravity.app"))
        #expect(sut.hasAdapter(for: "com.openai.codex"))
    }

    @Test func hasAdapterReturnsFalseForUnknownBundleIDs() {
        #expect(sut.hasAdapter(for: "com.unknown.app") == false)
        #expect(sut.hasAdapter(for: "") == false)
        #expect(sut.hasAdapter(for: "com.apple.Xcode") == false)
    }

    @Test func knownBundleIdentifiersContainsAllRegistered() {
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

        #expect(known == expectedIDs)
    }

    @Test func emptyRegistryFallsBackForEverything() {
        let emptyRegistry = AppContextAdapterRegistry(adapters: [])

        let adapter = emptyRegistry.adapter(for: "com.todesktop.230313mzl4w4u92")
        #expect(adapter is FallbackAdapter)
        #expect(emptyRegistry.hasAdapter(for: "com.todesktop.230313mzl4w4u92") == false)
        #expect(emptyRegistry.knownBundleIdentifiers.isEmpty)
    }

    @Test func customRegistryUsesProvidedAdapters() {
        let customRegistry = AppContextAdapterRegistry(adapters: [CursorAdapter()])

        #expect(customRegistry.hasAdapter(for: "com.todesktop.230313mzl4w4u92"))
        #expect(customRegistry.hasAdapter(for: "com.exafunction.windsurf") == false)
        #expect(customRegistry.knownBundleIdentifiers.count == 1)
    }

    @Test func capabilitiesNoneHasAllDisabled() {
        let caps = AppAdapterCapabilities.none

        #expect(caps.supportsFileMentions == false)
        #expect(caps.supportsCodeContext == false)
        #expect(caps.supportsDocsMentions == false)
        #expect(caps.supportsDiffContext == false)
        #expect(caps.supportsWebContext == false)
        #expect(caps.supportsChatHistory == false)
        #expect(caps.mentionPrefix == "@")
        #expect(caps.displayName == "Unknown App")
    }
}
