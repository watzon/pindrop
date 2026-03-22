//
//  MentionFormatterTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct MentionFormatterTests {
    private func makeIndexedFile(
        absolutePath: String = "/workspace/Pindrop/Services/AppCoordinator.swift",
        relativePath: String = "Pindrop/Services/AppCoordinator.swift",
        workspaceRoot: String = "/workspace"
    ) -> IndexedFile {
        let filename = (absolutePath as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let segments = relativePath.split(separator: "/").map(String.init)

        return IndexedFile(
            absolutePath: absolutePath,
            relativePath: relativePath,
            workspaceRoot: workspaceRoot,
            stem: stem,
            filename: filename,
            fileExtension: ext,
            pathSegments: segments,
            lowercasedFilename: filename.lowercased(),
            lowercasedStem: stem.lowercased()
        )
    }

    private func makeCandidate(relativePath: String = "Pindrop/Services/AppCoordinator.swift", score: Double = 0.9) -> PathCandidate {
        let file = makeIndexedFile(absolutePath: "/workspace/\(relativePath)", relativePath: relativePath)
        return PathCandidate(file: file, score: score)
    }

    private var sut: MentionFormatter { MentionFormatter() }
    private var cursorCapabilities: AppAdapterCapabilities { CursorAdapter().capabilities }
    private var vscodeCapabilities: AppAdapterCapabilities { VSCodeAdapter().capabilities }
    private var zedCapabilities: AppAdapterCapabilities { ZedAdapter().capabilities }
    private var codexCapabilities: AppAdapterCapabilities { CodexAdapter().capabilities }
    private var fallbackCapabilities: AppAdapterCapabilities { FallbackAdapter().capabilities }

    @Test func formatsResolvedMentionForSupportedApp() {
        let result = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(makeCandidate(score: 0.9)),
            capabilities: cursorCapabilities
        )

        guard case .formatted(let text, let path, let confidence) = result else {
            Issue.record("Expected .formatted, got \(result)")
            return
        }

        #expect(text == "@Pindrop/Services/AppCoordinator.swift")
        #expect(path == "Pindrop/Services/AppCoordinator.swift")
        #expect(confidence == 0.9)
    }

    @Test func skipsRewriteWhenConfidenceLow() {
        let result = sut.formatMention(
            originalText: "maybe this file",
            resolution: .resolved(makeCandidate(score: 0.2)),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            Issue.record("Expected .preserved, got \(result)")
            return
        }

        #expect(text == "maybe this file")
        guard case .lowConfidence(let score, let threshold) = reason else {
            Issue.record("Expected .lowConfidence, got \(reason)")
            return
        }
        #expect(score == 0.2)
        #expect(threshold == 0.5)
    }

    @Test func preservesUnresolvedMention() {
        let result = sut.formatMention(
            originalText: "nonexistent file",
            resolution: .unresolved(query: "nonexistent file"),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            Issue.record("Expected .preserved, got \(result)")
            return
        }

        #expect(text == "nonexistent file")
        #expect(reason == .unresolved)
    }

    @Test func preservesAmbiguousMentionInStrictMode() {
        let candidates = [
            makeCandidate(relativePath: "src/Button.swift", score: 0.8),
            makeCandidate(relativePath: "lib/Button.swift", score: 0.75),
        ]
        let result = sut.formatMention(
            originalText: "button",
            resolution: .ambiguous(candidates),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            Issue.record("Expected .preserved, got \(result)")
            return
        }

        #expect(text == "button")
        #expect(reason == .ambiguousInStrictMode(candidateCount: 2))
    }

    @Test func formatsAmbiguousMentionInPermissiveMode() {
        let permissiveSut = MentionFormatter(config: .permissive)
        let candidates = [
            makeCandidate(relativePath: "src/Button.swift", score: 0.8),
            makeCandidate(relativePath: "lib/Button.swift", score: 0.75),
        ]
        let result = permissiveSut.formatMention(
            originalText: "button",
            resolution: .ambiguous(candidates),
            capabilities: cursorCapabilities
        )

        guard case .formatted(let text, let path, let confidence) = result else {
            Issue.record("Expected .formatted, got \(result)")
            return
        }

        #expect(text == "@src/Button.swift")
        #expect(path == "src/Button.swift")
        #expect(confidence == 0.8)
    }

    @Test func idempotentForAlreadyFormattedMention() {
        let result = sut.formatMention(
            originalText: "@Pindrop/Services/AppCoordinator.swift",
            resolution: .resolved(makeCandidate(score: 0.9)),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            Issue.record("Expected .preserved, got \(result)")
            return
        }

        #expect(text == "@Pindrop/Services/AppCoordinator.swift")
        #expect(reason == .alreadyFormatted)
    }

    @Test func preservesMentionForUnsupportedAdapter() {
        let result = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(makeCandidate(score: 0.9)),
            capabilities: fallbackCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            Issue.record("Expected .preserved, got \(result)")
            return
        }

        #expect(text == "app coordinator")
        guard case .unsupportedByAdapter(let appName) = reason else {
            Issue.record("Expected .unsupportedByAdapter, got \(reason)")
            return
        }
        #expect(appName == "Unknown App")
    }

    @Test func differentPrefixPerApp() {
        let candidate = makeCandidate(score: 0.9)

        let vscodeResult = sut.formatMention(originalText: "app coordinator", resolution: .resolved(candidate), capabilities: vscodeCapabilities)
        guard case .formatted(let vscodeText, _, _) = vscodeResult else {
            Issue.record("Expected .formatted for VSCode, got \(vscodeResult)")
            return
        }
        #expect(vscodeText == "@Pindrop/Services/AppCoordinator.swift")

        let zedResult = sut.formatMention(originalText: "app coordinator", resolution: .resolved(candidate), capabilities: zedCapabilities)
        guard case .formatted(let zedText, _, _) = zedResult else {
            Issue.record("Expected .formatted for Zed, got \(zedResult)")
            return
        }
        #expect(zedText == "/Pindrop/Services/AppCoordinator.swift")
    }

    @Test func codexFormatsResolvedMentionAsMarkdownLink() {
        let result = sut.formatMention(
            originalText: "readme",
            resolution: .resolved(makeCandidate(relativePath: "README.md", score: 0.9)),
            capabilities: codexCapabilities
        )

        guard case .formatted(let text, let path, let confidence) = result else {
            Issue.record("Expected .formatted, got \(result)")
            return
        }

        #expect(text == "[@README.md](README.md)")
        #expect(path == "README.md")
        #expect(confidence == 0.9)
    }

    @Test func batchFormatReport() {
        let mentions: [(originalText: String, resolution: PathResolutionResult)] = [
            ("app coordinator", .resolved(makeCandidate(score: 0.9))),
            ("nonexistent", .unresolved(query: "nonexistent")),
            ("low confidence", .resolved(makeCandidate(score: 0.1))),
        ]

        let report = sut.formatMentions(mentions, capabilities: cursorCapabilities)

        #expect(report.mentionResults.count == 3)
        #expect(report.formattedMentions.count == 1)
        #expect(report.preservedMentions.count == 2)
        #expect(report.hasPreservedMentions)
        #expect(report.formattedText.contains("@Pindrop/Services/AppCoordinator.swift"))
        #expect(report.formattedText.contains("nonexistent"))
        #expect(report.formattedText.contains("low confidence"))
    }
}
