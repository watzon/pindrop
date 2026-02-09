//
//  PathMentionResolverTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import XCTest
@testable import Pindrop

// MARK: - Mock File System

struct MockFileSystemProvider: FileSystemProvider {
    var directories: Set<String> = []
    var filesByRoot: [String: [String]] = [:]

    func enumerateFiles(under root: String) throws -> [String] {
        filesByRoot[root] ?? []
    }

    func directoryExists(at path: String) -> Bool {
        directories.contains(path)
    }
}

// MARK: - Tests

@MainActor
final class PathMentionResolverTests: XCTestCase {

    var sut: PathMentionResolver!
    var index: WorkspaceFileIndexService!
    var mockFS: MockFileSystemProvider!

    override func setUp() async throws {
        mockFS = MockFileSystemProvider()
        mockFS.directories = ["/workspace"]
        mockFS.filesByRoot = [
            "/workspace": [
                "/workspace/Pindrop/Services/AppCoordinator.swift",
                "/workspace/Pindrop/Services/AudioRecorder.swift",
                "/workspace/Pindrop/Services/TranscriptionService.swift",
                "/workspace/Pindrop/UI/Settings/SettingsWindow.swift",
                "/workspace/Pindrop/UI/Main/MainWindow.swift",
                "/workspace/Pindrop/Utils/Logger.swift",
                "/workspace/Pindrop/Models/TranscriptionRecord.swift",
                "/workspace/PindropTests/AudioRecorderTests.swift",
                "/workspace/README.md",
            ]
        ]

        index = WorkspaceFileIndexService(fileSystem: mockFS)
        try await index.buildIndex(roots: ["/workspace"])

        sut = PathMentionResolver()
    }

    override func tearDown() async throws {
        sut = nil
        index = nil
        mockFS = nil
    }

    // MARK: - Required Test: Nested Mentions → Canonical Relative Path

    func testResolvesNestedMentionsToCanonicalRelativePath() {
        let result = sut.resolve(mention: "AppCoordinator.swift", in: index)

        guard case .resolved(let candidate) = result else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }

        XCTAssertEqual(candidate.file.relativePath, "Pindrop/Services/AppCoordinator.swift")
        XCTAssertEqual(candidate.file.filename, "AppCoordinator.swift")
        XCTAssertTrue(candidate.score >= PathScoringWeights.exactFilenameMatch)
    }

    // MARK: - Required Test: Ambiguous Mentions → Candidates Not Fabricated Path

    func testAmbiguousMentionsReturnCandidatesNotFabricatedPath() async throws {
        var ambiguousFS = MockFileSystemProvider()
        ambiguousFS.directories = ["/workspace"]
        ambiguousFS.filesByRoot = [
            "/workspace": [
                "/workspace/src/components/Button.swift",
                "/workspace/src/views/Button.swift",
                "/workspace/lib/Button.swift",
            ]
        ]

        let ambiguousIndex = WorkspaceFileIndexService(fileSystem: ambiguousFS)
        try await ambiguousIndex.buildIndex(roots: ["/workspace"])

        let result = sut.resolve(mention: "Button.swift", in: ambiguousIndex)

        guard case .ambiguous(let candidates) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }

        XCTAssertGreaterThanOrEqual(candidates.count, 2)

        for candidate in candidates {
            XCTAssertTrue(
                candidate.file.absolutePath.hasSuffix("Button.swift"),
                "Candidate should be a real file, got: \(candidate.file.absolutePath)"
            )
        }

        let paths = candidates.map { $0.file.relativePath }
        XCTAssertFalse(paths.contains("Button.swift"),
                       "Should return full relative paths, not bare filenames")
    }

    // MARK: - Exact Stem Match

    func testExactStemMatchWithoutExtension() {
        let result = sut.resolve(mention: "AppCoordinator", in: index)

        guard case .resolved(let candidate) = result else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }

        XCTAssertEqual(candidate.file.filename, "AppCoordinator.swift")
        XCTAssertTrue(candidate.score >= PathScoringWeights.exactStemMatch)
    }

    // MARK: - Spoken "dot" Normalization

    func testSpokenDotNormalization() {
        let result = sut.resolve(mention: "app coordinator dot swift", in: index)

        guard case .resolved(let candidate) = result else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }

        XCTAssertEqual(candidate.file.stem, "AppCoordinator")
    }

    // MARK: - Tokenized Segment Match

    func testTokenizedSegmentMatchByCamelCase() {
        let result = sut.resolve(mention: "audio recorder", in: index)

        switch result {
        case .resolved(let candidate):
            XCTAssertTrue(
                candidate.file.stem.lowercased().contains("audiorecorder"),
                "Should match AudioRecorder via camelCase split"
            )
        case .ambiguous(let candidates):
            // "audio recorder" may match both AudioRecorder.swift and
            // AudioRecorderTests.swift via camelCase tokenization — both are valid.
            XCTAssertTrue(
                candidates.contains { $0.file.stem == "AudioRecorder" },
                "Ambiguous candidates should include AudioRecorder"
            )
        case .unresolved:
            XCTFail("Should resolve via tokenized segment match, got .unresolved")
        }
    }

    // MARK: - Unresolved Query

    func testUnresolvedForNonsenseMention() {
        let result = sut.resolve(mention: "xyzzy_nonexistent_file", in: index)

        guard case .unresolved(let query) = result else {
            XCTFail("Expected .unresolved, got \(result)")
            return
        }

        XCTAssertEqual(query, "xyzzy_nonexistent_file")
    }

    func testEmptyMentionReturnsUnresolved() {
        let result = sut.resolve(mention: "   ", in: index)

        guard case .unresolved = result else {
            XCTFail("Expected .unresolved for empty mention, got \(result)")
            return
        }
    }

    // MARK: - Deterministic Ordering

    func testDeterministicOrderingIsStable() async throws {
        var stableFS = MockFileSystemProvider()
        stableFS.directories = ["/workspace"]
        stableFS.filesByRoot = [
            "/workspace": [
                "/workspace/b/Config.swift",
                "/workspace/a/Config.swift",
            ]
        ]

        let stableIndex = WorkspaceFileIndexService(fileSystem: stableFS)
        try await stableIndex.buildIndex(roots: ["/workspace"])

        let result1 = sut.resolve(mention: "Config.swift", in: stableIndex)
        let result2 = sut.resolve(mention: "Config.swift", in: stableIndex)

        XCTAssertEqual(result1, result2, "Resolution must be deterministic across runs")
    }

    // MARK: - Recency Boost

    func testRecencyBoostInfluencesResolution() async throws {
        var twoFileFS = MockFileSystemProvider()
        twoFileFS.directories = ["/workspace"]
        twoFileFS.filesByRoot = [
            "/workspace": [
                "/workspace/old/Helper.swift",
                "/workspace/new/Helper.swift",
            ]
        ]

        let twoFileIndex = WorkspaceFileIndexService(fileSystem: twoFileFS)
        try await twoFileIndex.buildIndex(roots: ["/workspace"])

        let newFile = twoFileIndex.allFiles.first { $0.absolutePath.contains("new/") }!
        sut.recordAccess(for: newFile, at: Date())

        let result = sut.resolve(mention: "Helper.swift", in: twoFileIndex)

        switch result {
        case .resolved(let candidate):
            XCTAssertTrue(candidate.file.absolutePath.contains("new/"),
                          "Recency boost should favor recently accessed file")
        case .ambiguous(let candidates):
            XCTAssertTrue(candidates[0].file.absolutePath.contains("new/"),
                          "Top ambiguous candidate should be the recently accessed file")
        case .unresolved:
            XCTFail("Should not be unresolved")
        }
    }

    // MARK: - Index Building

    func testIndexBuildCountsFiles() async throws {
        let count = try await index.buildIndex(roots: ["/workspace"])
        XCTAssertEqual(count, 9)
    }

    func testIndexBuildWithInvalidRootThrows() async {
        var emptyFS = MockFileSystemProvider()
        emptyFS.directories = []
        let emptyIndex = WorkspaceFileIndexService(fileSystem: emptyFS)

        do {
            try await emptyIndex.buildIndex(roots: ["/nonexistent"])
            XCTFail("Expected error for invalid root")
        } catch is WorkspaceFileIndexError {
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Mention Normalization

    func testNormalizeMentionHandlesSpokenDot() {
        XCTAssertEqual(sut.normalizeMention("app dot swift"), "app.swift")
    }

    func testNormalizeMentionHandlesSpokenSlash() {
        XCTAssertEqual(sut.normalizeMention("services slash app"), "services/app")
    }

    func testNormalizeMentionLowercases() {
        XCTAssertEqual(sut.normalizeMention("AppCoordinator"), "appcoordinator")
    }
}
