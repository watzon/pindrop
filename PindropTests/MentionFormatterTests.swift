//
//  MentionFormatterTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import XCTest
@testable import Pindrop

@MainActor
final class MentionFormatterTests: XCTestCase {

    var sut: MentionFormatter!

    override func setUp() async throws {
        sut = MentionFormatter()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Helpers

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

    private func makeCandidate(
        relativePath: String = "Pindrop/Services/AppCoordinator.swift",
        score: Double = 0.9
    ) -> PathCandidate {
        let file = makeIndexedFile(
            absolutePath: "/workspace/\(relativePath)",
            relativePath: relativePath
        )
        return PathCandidate(file: file, score: score)
    }

    private var cursorCapabilities: AppAdapterCapabilities {
        CursorAdapter().capabilities
    }

    private var vscodeCapabilities: AppAdapterCapabilities {
        VSCodeAdapter().capabilities
    }

    private var zedCapabilities: AppAdapterCapabilities {
        ZedAdapter().capabilities
    }

    private var fallbackCapabilities: AppAdapterCapabilities {
        FallbackAdapter().capabilities
    }

    // MARK: - Resolved Mention Formatting

    func testFormatsResolvedMentionForSupportedApp() {
        let candidate = makeCandidate(score: 0.9)
        let result = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(candidate),
            capabilities: cursorCapabilities
        )

        guard case .formatted(let text, let path, let confidence) = result else {
            XCTFail("Expected .formatted, got \(result)")
            return
        }

        XCTAssertEqual(text, "@Pindrop/Services/AppCoordinator.swift")
        XCTAssertEqual(path, "Pindrop/Services/AppCoordinator.swift")
        XCTAssertEqual(confidence, 0.9)
    }

    // MARK: - Low Confidence Gating

    func testSkipsRewriteWhenConfidenceLow() {
        let candidate = makeCandidate(score: 0.2)
        let result = sut.formatMention(
            originalText: "maybe this file",
            resolution: .resolved(candidate),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            XCTFail("Expected .preserved, got \(result)")
            return
        }

        XCTAssertEqual(text, "maybe this file")
        guard case .lowConfidence(let score, let threshold) = reason else {
            XCTFail("Expected .lowConfidence, got \(reason)")
            return
        }
        XCTAssertEqual(score, 0.2)
        XCTAssertEqual(threshold, 0.5)
    }

    // MARK: - Unresolved Mention

    func testPreservesUnresolvedMention() {
        let result = sut.formatMention(
            originalText: "nonexistent file",
            resolution: .unresolved(query: "nonexistent file"),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            XCTFail("Expected .preserved, got \(result)")
            return
        }

        XCTAssertEqual(text, "nonexistent file")
        XCTAssertEqual(reason, .unresolved)
    }

    // MARK: - Ambiguous Mention in Strict Mode

    func testPreservesAmbiguousMentionInStrictMode() {
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
            XCTFail("Expected .preserved, got \(result)")
            return
        }

        XCTAssertEqual(text, "button")
        XCTAssertEqual(reason, .ambiguousInStrictMode(candidateCount: 2))
    }

    // MARK: - Ambiguous Mention in Permissive Mode

    func testFormatsAmbiguousMentionInPermissiveMode() {
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
            XCTFail("Expected .formatted, got \(result)")
            return
        }

        XCTAssertEqual(text, "@src/Button.swift")
        XCTAssertEqual(path, "src/Button.swift")
        XCTAssertEqual(confidence, 0.8)
    }

    // MARK: - Idempotency

    func testIdempotentForAlreadyFormattedMention() {
        let result = sut.formatMention(
            originalText: "@Pindrop/Services/AppCoordinator.swift",
            resolution: .resolved(makeCandidate(score: 0.9)),
            capabilities: cursorCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            XCTFail("Expected .preserved, got \(result)")
            return
        }

        XCTAssertEqual(text, "@Pindrop/Services/AppCoordinator.swift")
        XCTAssertEqual(reason, .alreadyFormatted)
    }

    // MARK: - Unsupported Adapter

    func testPreservesMentionForUnsupportedAdapter() {
        let candidate = makeCandidate(score: 0.9)
        let result = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(candidate),
            capabilities: fallbackCapabilities
        )

        guard case .preserved(let text, let reason) = result else {
            XCTFail("Expected .preserved, got \(result)")
            return
        }

        XCTAssertEqual(text, "app coordinator")
        guard case .unsupportedByAdapter(let appName) = reason else {
            XCTFail("Expected .unsupportedByAdapter, got \(reason)")
            return
        }
        XCTAssertEqual(appName, "Unknown App")
    }

    // MARK: - Different Prefix Per App

    func testDifferentPrefixPerApp() {
        let candidate = makeCandidate(score: 0.9)

        let vscodeResult = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(candidate),
            capabilities: vscodeCapabilities
        )
        guard case .formatted(let vscodeText, _, _) = vscodeResult else {
            XCTFail("Expected .formatted for VSCode, got \(vscodeResult)")
            return
        }
        XCTAssertEqual(vscodeText, "#Pindrop/Services/AppCoordinator.swift")

        let zedResult = sut.formatMention(
            originalText: "app coordinator",
            resolution: .resolved(candidate),
            capabilities: zedCapabilities
        )
        guard case .formatted(let zedText, _, _) = zedResult else {
            XCTFail("Expected .formatted for Zed, got \(zedResult)")
            return
        }
        XCTAssertEqual(zedText, "/Pindrop/Services/AppCoordinator.swift")
    }

    // MARK: - Batch Format Report

    func testBatchFormatReport() {
        let mentions: [(originalText: String, resolution: PathResolutionResult)] = [
            ("app coordinator", .resolved(makeCandidate(score: 0.9))),
            ("nonexistent", .unresolved(query: "nonexistent")),
            ("low confidence", .resolved(makeCandidate(score: 0.1))),
        ]

        let report = sut.formatMentions(mentions, capabilities: cursorCapabilities)

        XCTAssertEqual(report.mentionResults.count, 3)
        XCTAssertEqual(report.formattedMentions.count, 1)
        XCTAssertEqual(report.preservedMentions.count, 2)
        XCTAssertTrue(report.hasPreservedMentions)
        XCTAssertTrue(report.formattedText.contains("@Pindrop/Services/AppCoordinator.swift"))
        XCTAssertTrue(report.formattedText.contains("nonexistent"))
        XCTAssertTrue(report.formattedText.contains("low confidence"))
    }
}
