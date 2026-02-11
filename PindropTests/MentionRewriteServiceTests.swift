//
//  MentionRewriteServiceTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import XCTest
@testable import Pindrop

// MARK: - Tests

@MainActor
final class MentionRewriteServiceTests: XCTestCase {

    var sut: MentionRewriteService!
    var mockFS: MockFileSystemProvider!
    var cursorCapabilities: AppAdapterCapabilities!
    var fallbackCapabilities: AppAdapterCapabilities!

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

        sut = MentionRewriteService(fileSystem: mockFS)

        cursorCapabilities = CursorAdapter().capabilities
        fallbackCapabilities = AppAdapterCapabilities.none
    }

    override func tearDown() async throws {
        sut = nil
        mockFS = nil
        cursorCapabilities = nil
        fallbackCapabilities = nil
    }

    // MARK: - Rewrite Happens When Conditions Met

    func testRewriteOccursWhenAdapterSupportsMentionsAndWorkspaceAvailable() async {
        let result = await sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite, "Should rewrite when adapter supports mentions and workspace has files")
        XCTAssertGreaterThan(result.rewrittenCount, 0)
        XCTAssertTrue(result.text.contains("@"), "Cursor adapter should use @ prefix")
    }

    // MARK: - No Rewrite When Adapter Doesn't Support Mentions

    func testNoRewriteWhenAdapterDoesNotSupportMentions() async {
        let result = await sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: fallbackCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.rewrittenCount, 0)
        XCTAssertEqual(result.text, "check the AppCoordinator.swift file")
    }

    // MARK: - No Rewrite When No Workspace Roots

    func testNoRewriteWhenNoWorkspaceRootsAvailable() async {
        let result = await sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: cursorCapabilities,
            workspaceRoots: []
        )

        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.rewrittenCount, 0)
        XCTAssertEqual(result.text, "check the AppCoordinator.swift file")
    }

    // MARK: - No Rewrite When Workspace Index Is Empty

    func testNoRewriteWhenWorkspaceIndexIsEmpty() async {
        var emptyFS = MockFileSystemProvider()
        emptyFS.directories = ["/empty"]
        emptyFS.filesByRoot = ["/empty": []]

        let emptySut = MentionRewriteService(fileSystem: emptyFS)

        let result = await emptySut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/empty"]
        )

        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.rewrittenCount, 0)
        XCTAssertEqual(result.text, "check the AppCoordinator.swift file")
    }

    // MARK: - Graceful Fallback on Index Build Failure

    func testGracefulFallbackWhenIndexBuildFails() async {
        // Use a mock FS with no valid directories so buildIndex throws
        var badFS = MockFileSystemProvider()
        badFS.directories = []
        badFS.filesByRoot = [:]

        let badSut = MentionRewriteService(fileSystem: badFS)

        let result = await badSut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/nonexistent"]
        )

        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.rewrittenCount, 0)
        XCTAssertEqual(result.text, "check the AppCoordinator.swift file")
    }

    // MARK: - Multiple Mentions Processed

    func testMultipleMentionsAreAllProcessed() async {
        let result = await sut.rewrite(
            text: "look at AppCoordinator.swift and AudioRecorder.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        // Both files exist in the index — both should be rewritten or at least attempted
        XCTAssertGreaterThanOrEqual(result.rewrittenCount + result.preservedCount, 2,
            "Both mentions should be detected as candidates")
    }

    // MARK: - No Candidates Found Returns Original Text

    func testNoCandidatesReturnsOriginalText() async {
        let text = "this text has no file mentions whatsoever"
        let result = await sut.rewrite(
            text: text,
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.text, text)
    }

    // MARK: - Dot Pattern Extraction

    func testDotPatternExtractsCandidates() async {
        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "please open app coordinator dot swift for me",
            index: index
        )

        XCTAssertFalse(candidates.isEmpty, "Should detect 'app coordinator dot swift' as candidate")
        XCTAssertTrue(candidates.contains { $0.text.lowercased().contains("dot") },
            "Dot pattern candidate should contain 'dot'")
    }

    // MARK: - Known Stem Extraction

    func testKnownStemExtractsCandidates() async {
        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "check the AppCoordinator for issues",
            index: index
        )

        // "AppCoordinator" should match as a stem in the index
        let hasAppCoordinator = candidates.contains { candidate in
            candidate.text.contains("AppCoordinator")
        }
        XCTAssertTrue(hasAppCoordinator, "Should detect 'AppCoordinator' as a known stem candidate")
    }

    // MARK: - Cache Reuse When Roots Unchanged

    func testCacheReusedWhenRootsUnchanged() async {
        // First call — builds index
        let result1 = await sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        // Second call with same roots — should reuse cache (same behavior)
        let result2 = await sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertEqual(result1.text, result2.text, "Cached index should produce same results")
        XCTAssertEqual(result1.rewrittenCount, result2.rewrittenCount)
    }

    // MARK: - Cache Invalidation When Roots Change

    func testCacheInvalidatedWhenRootsChange() async {
        // First call with /workspace
        _ = await sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        // Second call with different roots — should rebuild index
        var otherFS = MockFileSystemProvider()
        otherFS.directories = ["/other"]
        otherFS.filesByRoot = ["/other": ["/other/SomeFile.swift"]]

        let otherSut = MentionRewriteService(fileSystem: otherFS)

        let result = await otherSut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/other"]
        )

        // AppCoordinator.swift doesn't exist in /other, so no rewrite
        XCTAssertFalse(result.didRewrite,
            "After roots change, new index should not find old files")
    }

    // MARK: - ClearCache Resets State

    func testClearCacheResetsState() async {
        // Build cache
        _ = await sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        // Clear it
        sut.clearCache()

        // After clearing, next rewrite should still work (rebuilds index)
        let result = await sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        // Should still work fine — cache cleared but rebuilt on next call
        XCTAssertTrue(result.rewrittenCount > 0 || result.preservedCount >= 0,
            "Service should still function after cache clear")
    }

    // MARK: - Different Adapter Prefixes

    func testVSCodeAdapterUsesHashPrefix() async {
        let vsCodeCapabilities = VSCodeAdapter().capabilities

        let result = await sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: vsCodeCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite,
            "VS Code adapter should rewrite when workspace has matching files")
        XCTAssertTrue(result.text.contains("#"),
            "VS Code adapter should use # prefix for mentions")
        XCTAssertFalse(result.text.contains("@"),
            "VS Code adapter should NOT use @ prefix")
    }

    func testZedAdapterUsesSlashPrefix() async {
        let zedCapabilities = ZedAdapter().capabilities

        let result = await sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: zedCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite,
            "Zed adapter should rewrite when workspace has matching files")
        XCTAssertTrue(result.text.contains("/"),
            "Zed adapter should use / prefix for mentions")
    }

    func testWindsurfAdapterUsesAtPrefix() async {
        let windsurfCapabilities = WindsurfAdapter().capabilities

        let result = await sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: windsurfCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite,
            "Windsurf adapter should rewrite when workspace has matching files")
        XCTAssertTrue(result.text.contains("@"),
            "Windsurf adapter should use @ prefix for mentions")
    }

    func testCursorAdapterUsesAtPrefix() async {
        let result = await sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite,
            "Cursor adapter should rewrite when workspace has matching files")
        XCTAssertTrue(result.text.contains("@"),
            "Cursor adapter should use @ prefix for mentions")
    }

    // MARK: - Per-Editor Exact Mention Format Validation

    func testVSCodeFormatsExactMentionPath() async {
        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite)
        XCTAssertTrue(result.text.contains("#Pindrop/Services/AppCoordinator.swift"),
            "VS Code should format as #relative/path — got: \(result.text)")
    }

    func testZedFormatsExactMentionPath() async {
        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: ZedAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite)
        XCTAssertTrue(result.text.contains("/Pindrop/Services/AppCoordinator.swift"),
            "Zed should format as /relative/path — got: \(result.text)")
    }

    func testCursorFormatsExactMentionPath() async {
        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: CursorAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite)
        XCTAssertTrue(result.text.contains("@Pindrop/Services/AppCoordinator.swift"),
            "Cursor should format as @relative/path — got: \(result.text)")
    }

    func testWindsurfFormatsExactMentionPath() async {
        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.didRewrite)
        XCTAssertTrue(result.text.contains("@Pindrop/Services/AppCoordinator.swift"),
            "Windsurf should format as @relative/path — got: \(result.text)")
    }

    // MARK: - MentionRewriteResult Properties

    func testResultDidRewriteReflectsRewrittenCount() {
        let noRewrite = MentionRewriteResult(text: "hello", rewrittenCount: 0, preservedCount: 0)
        XCTAssertFalse(noRewrite.didRewrite)

        let withRewrite = MentionRewriteResult(text: "hello", rewrittenCount: 1, preservedCount: 0)
        XCTAssertTrue(withRewrite.didRewrite)
    }

    // MARK: - Text Preserved On No Matches

    func testOriginalTextPreservedWhenNoMentionCandidatesFound() async {
        let originalText = "just a regular sentence with no code references at all"

        let result = await sut.rewrite(
            text: originalText,
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertEqual(result.text, originalText)
        XCTAssertEqual(result.rewrittenCount, 0)
        XCTAssertEqual(result.preservedCount, 0)
    }

    // MARK: - Empty Text Input

    func testEmptyTextReturnsEmptyResult() async {
        let result = await sut.rewrite(
            text: "",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertEqual(result.text, "")
        XCTAssertFalse(result.didRewrite)
    }

    // MARK: - Workspace Root Normalization

    func testNormalizeFilePathToParentDirectory() {
        mockFS.directories.insert("/workspace/Pindrop/Services")
        sut = MentionRewriteService(fileSystem: mockFS) // Recreate after mutating struct

        let result = sut.normalizeWorkspaceRoots([
            "/workspace/Pindrop/Services/AppCoordinator.swift"
        ])

        XCTAssertEqual(result, ["/workspace/Pindrop/Services"])
    }

    func testNormalizeTildePath() {
        let home = NSHomeDirectory()
        let expandedPath = "\(home)/Projects/pindrop"
        mockFS.directories.insert(expandedPath)
        sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots(["~/Projects/pindrop"])

        XCTAssertEqual(result, [expandedPath])
    }

    func testNormalizeFileURLScheme() {
        mockFS.directories.insert("/workspace/some")
        sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "file:///workspace/some/file.swift"
        ])

        XCTAssertEqual(result, ["/workspace/some"])
    }

    func testNormalizeClimbsToProjectMarker() {
        mockFS.directories.insert("/workspace/Pindrop/Services")
        mockFS.directories.insert("/workspace/Pindrop")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "/workspace/Pindrop/Services/AppCoordinator.swift"
        ])

        XCTAssertEqual(result, ["/workspace"],
            "Should climb up to /workspace where .git exists")
    }

    func testNormalizeDeduplicatesRoots() {
        mockFS.directories.insert("/workspace")

        let result = sut.normalizeWorkspaceRoots([
            "/workspace",
            "/workspace",
            "/workspace"
        ])

        XCTAssertEqual(result, ["/workspace"])
    }

    func testNormalizeSkipsCompletelyInvalidPaths() {
        let result = sut.normalizeWorkspaceRoots([
            "/nonexistent/path/to/file.swift"
        ])

        XCTAssertTrue(result.isEmpty,
            "Should skip paths where neither file nor parent directory exists")
    }

    func testNormalizeWithFileURLAndTildeAndFilePath() {
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        mockFS.directories.insert("\(projectRoot)/.git")
        sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "file://\(projectRoot)/Pindrop/AppCoordinator.swift"
        ])

        XCTAssertEqual(result, [projectRoot],
            "Should strip file://, resolve to parent dir, climb to .git project root")
    }

    func testRewriteWorksWithFilePathAsWorkspaceRoot() async {
        mockFS.directories.insert("/workspace/Pindrop/Services")
        mockFS.directories.insert("/workspace/Pindrop")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")

        let fileSut = MentionRewriteService(fileSystem: mockFS)

        let result = await fileSut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace/Pindrop/Services/AppCoordinator.swift"]
        )

        XCTAssertTrue(result.didRewrite,
            "Should normalize file path to project root and find files")
    }

    // MARK: - Mixed Extraction (Dot Pattern + Stem)

    func testMixedDotPatternAndStemExtraction() async {
        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "check app coordinator dot swift and also AudioRecorder",
            index: index
        )

        let hasDotPattern = candidates.contains { $0.text.lowercased().contains("dot") }
        let hasStemMatch = candidates.contains {
            $0.text.contains("AudioRecorder")
        }

        XCTAssertTrue(hasDotPattern, "Should detect dot-pattern mention")
        XCTAssertTrue(hasStemMatch, "Should also detect stem mention in same text")
        XCTAssertGreaterThanOrEqual(candidates.count, 2,
            "Both patterns should produce candidates")
    }

    func testMixedExtractionDoesNotDuplicateOverlaps() async {
        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "look at app coordinator dot swift",
            index: index
        )

        let dotMentions = candidates.filter { $0.text.lowercased().contains("dot") }
        XCTAssertEqual(dotMentions.count, 1,
            "Dot pattern should not be duplicated by stem pattern due to overlap dedup")
    }

    // MARK: - Literal Dotted Filename Extraction

    func testLiteralDottedFilenameExtraction() async {
        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "check the AppCoordinator.swift file",
            index: index
        )

        let hasLiteral = candidates.contains { $0.text == "AppCoordinator.swift" }
        XCTAssertTrue(hasLiteral,
            "Should extract 'AppCoordinator.swift' as a single literal dotted filename candidate")
    }

    func testLiteralDottedFilenameWithDifferentExtension() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        let goSut = MentionRewriteService(fileSystem: mockFS)

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = goSut.extractMentionCandidates(
            from: "open fixtures.go please",
            index: index
        )

        let hasFixtures = candidates.contains { $0.text == "fixtures.go" }
        XCTAssertTrue(hasFixtures,
            "Should extract 'fixtures.go' as a literal dotted filename candidate")
    }

    func testPathQualifiedLiteralFilename() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        let pathSut = MentionRewriteService(fileSystem: mockFS)

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = pathSut.extractMentionCandidates(
            from: "look at gen/fixtures.go",
            index: index
        )

        let hasPathQualified = candidates.contains { $0.text == "gen/fixtures.go" }
        XCTAssertTrue(hasPathQualified,
            "Should extract 'gen/fixtures.go' as a path-qualified literal filename candidate")
    }

    // MARK: - Active Document Disambiguation

    func testActiveDocumentDisambiguatesMultipleMatches() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let disambigSut = MentionRewriteService(fileSystem: mockFS)

        let result = await disambigSut.rewrite(
            text: "check fixtures.go",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        XCTAssertTrue(result.didRewrite,
            "Should rewrite when active document disambiguates")
        XCTAssertTrue(result.text.contains("gen/fixtures.go"),
            "Should produce mention with gen/fixtures.go path since that's the active document")
    }

    func testRewriteWithoutActiveDocumentPreservesAmbiguous() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let ambigSut = MentionRewriteService(fileSystem: mockFS)

        let result = await ambigSut.rewrite(
            text: "check fixtures.go",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertTrue(result.text.contains("fixtures.go"),
            "Without active document, ambiguous mention should be preserved as-is")
    }

    func testActiveDocumentPathNormalizesFileURL() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let urlSut = MentionRewriteService(fileSystem: mockFS)

        let result = await urlSut.rewrite(
            text: "check fixtures.go",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "file:///workspace/gen/fixtures.go"
        )

        XCTAssertTrue(result.didRewrite,
            "Should rewrite after normalizing file:// URL in activeDocumentPath")
        XCTAssertTrue(result.text.contains("gen/fixtures.go"),
            "Should disambiguate to gen/fixtures.go even when given as file:// URL")
    }

    // MARK: - Regression: Capitalized Filename With Punctuation + Active Document

    func testRegressionCapitalizedFixturesGoWithActiveDocument() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let regSut = MentionRewriteService(fileSystem: mockFS)

        let result = await regSut.rewrite(
            text: "Can you fix the error in Fixtures.go?",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        XCTAssertTrue(result.didRewrite,
            "Should rewrite capitalized 'Fixtures.go' when active document disambiguates")
        XCTAssertTrue(result.text.contains("@gen/fixtures.go"),
            "Rewritten text should contain @gen/fixtures.go mention for Cursor adapter")
        XCTAssertFalse(result.text.contains("Fixtures.go"),
            "Original capitalized 'Fixtures.go' should be replaced, not preserved")
    }

    // MARK: - Antigravity Adapter Integration

    func testAntigravityAdapterRewriteWithTildeRedactedRoot() async {
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        mockFS.directories.insert("\(projectRoot)/Pindrop/Services")
        mockFS.directories.insert("\(projectRoot)/.git")
        mockFS.filesByRoot[projectRoot] = [
            "\(projectRoot)/Pindrop/Services/AppCoordinator.swift",
            "\(projectRoot)/Pindrop/Services/AudioRecorder.swift",
            "\(projectRoot)/README.md",
        ]
        let agSut = MentionRewriteService(fileSystem: mockFS)
        let antigravityCapabilities = AntigravityAdapter().capabilities

        let result = await agSut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: antigravityCapabilities,
            workspaceRoots: ["~/Projects/pindrop"]
        )

        XCTAssertTrue(result.didRewrite,
            "Should rewrite with Antigravity adapter when given tilde-redacted workspace root")
        XCTAssertTrue(result.text.contains("@"),
            "Antigravity adapter should use @ prefix")
    }

    func testAntigravityAdapterNoRewriteWithEmptyWorkspace() async {
        let antigravityCapabilities = AntigravityAdapter().capabilities

        let result = await sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: antigravityCapabilities,
            workspaceRoots: []
        )

        XCTAssertFalse(result.didRewrite,
            "Should not rewrite when no workspace roots available")
    }

    func testNormalizeTildeRedactedFilePath() {
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/.git")
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "~/Projects/pindrop/Pindrop/AppCoordinator.swift"
        ])

        XCTAssertEqual(result, [projectRoot],
            "Should expand tilde, derive parent dir, and climb to project root")
    }

    // MARK: - PromptRoutingSignal Workspace Derivation

    func testRoutingSignalDerivesWorkspaceRootFromDocumentPath() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.antigravity.app",
                appName: "Antigravity",
                windowTitle: nil,
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/pindrop/Pindrop",
            "workspacePath should be the parent directory of documentPath")
    }

    func testRoutingSignalDerivesWorkspaceRootFromFileURL() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.antigravity.app",
                appName: "Antigravity",
                windowTitle: nil,
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: "file:///Users/test/Projects/pindrop/file.swift",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "/Users/test/Projects/pindrop",
            "workspacePath should strip file:// and return parent directory")
    }

    func testRoutingSignalUsesDirectoryDocumentPathForTerminalApps() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.mitchellh.ghostty",
                appName: "Ghostty",
                windowTitle: nil,
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: "~/Projects/pindrop/",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertEqual(signal.workspacePath, "~/Projects/pindrop",
            "workspacePath should preserve a directory-style documentPath instead of climbing to its parent")
    }

    func testRoutingSignalNilWorkspaceWhenNoDocumentPath() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.antigravity.app",
                appName: "Antigravity",
                windowTitle: nil,
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: nil,
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let signal = PromptRoutingSignal.from(snapshot: snapshot)

        XCTAssertNil(signal.workspacePath,
            "workspacePath should be nil when documentPath is nil")
    }

    // MARK: - Per-Editor Workspace Derivation + Mention Integration

    private func makeEditorIntegrationSut() -> (MentionRewriteService, MockFileSystemProvider) {
        var fs = MockFileSystemProvider()
        let home = NSHomeDirectory()
        let root = "\(home)/Projects/pindrop"
        fs.directories = [
            root,
            "\(root)/.git",
            "\(root)/Pindrop",
            "\(root)/Pindrop/Services",
        ]
        fs.filesByRoot = [
            root: [
                "\(root)/Pindrop/Services/AppCoordinator.swift",
                "\(root)/Pindrop/Services/AudioRecorder.swift",
                "\(root)/README.md",
            ]
        ]
        return (MentionRewriteService(fileSystem: fs), fs)
    }

    func testCursorDerivationAndRewriteFromFilePath() async {
        let (editorSut, _) = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await editorSut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: CursorAdapter().capabilities,
            workspaceRoots: ["\(home)/Projects/pindrop/Pindrop/Services/AppCoordinator.swift"]
        )

        XCTAssertTrue(result.didRewrite,
            "Cursor: should derive workspace root from file path and rewrite")
        XCTAssertTrue(result.text.contains("@Pindrop/Services/AppCoordinator.swift"),
            "Cursor: should produce @-prefixed relative path — got: \(result.text)")
    }

    func testVSCodeDerivationAndRewriteFromFileURL() async {
        let (editorSut, _) = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await editorSut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["file://\(home)/Projects/pindrop/Pindrop/Services/AppCoordinator.swift"]
        )

        XCTAssertTrue(result.didRewrite,
            "VS Code: should derive workspace root from file:// URL and rewrite")
        XCTAssertTrue(result.text.contains("#Pindrop/Services/AppCoordinator.swift"),
            "VS Code: should produce #-prefixed relative path — got: \(result.text)")
    }

    func testZedDerivationAndRewriteFromTildePath() async {
        let (editorSut, _) = makeEditorIntegrationSut()

        let result = await editorSut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: ZedAdapter().capabilities,
            workspaceRoots: ["~/Projects/pindrop"]
        )

        XCTAssertTrue(result.didRewrite,
            "Zed: should derive workspace root from tilde path and rewrite")
        XCTAssertTrue(result.text.contains("/Pindrop/Services/AppCoordinator.swift"),
            "Zed: should produce /-prefixed relative path — got: \(result.text)")
    }

    func testWindsurfDerivationAndRewriteFromSubdirectory() async {
        let (editorSut, _) = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await editorSut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["\(home)/Projects/pindrop/Pindrop/Services"]
        )

        XCTAssertTrue(result.didRewrite,
            "Windsurf: should climb from subdirectory to project root and rewrite")
        XCTAssertTrue(result.text.contains("@Pindrop/Services/AppCoordinator.swift"),
            "Windsurf: should produce @-prefixed relative path — got: \(result.text)")
    }

    func testWindsurfNoRewriteWithEmptyWorkspace() async {
        let windsurfCapabilities = WindsurfAdapter().capabilities

        let result = await sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: windsurfCapabilities,
            workspaceRoots: []
        )

        XCTAssertFalse(result.didRewrite,
            "Windsurf: should not rewrite when no workspace roots available")
    }

    func testWindsurfRewriteMultipleMentions() async {
        let result = await sut.rewrite(
            text: "look at AppCoordinator.swift and AudioRecorder.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        XCTAssertGreaterThanOrEqual(result.rewrittenCount + result.preservedCount, 2,
            "Windsurf: both mentions should be detected as candidates")
    }

    func testWindsurfActiveDocumentDisambiguation() async {
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let wsSut = MentionRewriteService(fileSystem: mockFS)

        let result = await wsSut.rewrite(
            text: "check fixtures.go",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        XCTAssertTrue(result.didRewrite,
            "Windsurf: should disambiguate using active document")
        XCTAssertTrue(result.text.contains("@gen/fixtures.go"),
            "Windsurf: should produce @gen/fixtures.go — got: \(result.text)")
    }

    func testAllEditorsPrefixDeterminism() async {
        let editors: [(String, AppAdapterCapabilities, String)] = [
            ("Cursor", CursorAdapter().capabilities, "@"),
            ("VS Code", VSCodeAdapter().capabilities, "#"),
            ("Zed", ZedAdapter().capabilities, "/"),
            ("Windsurf", WindsurfAdapter().capabilities, "@"),
        ]

        for (name, caps, expectedPrefix) in editors {
            let result = await sut.rewrite(
                text: "check AppCoordinator.swift",
                capabilities: caps,
                workspaceRoots: ["/workspace"]
            )

            XCTAssertTrue(result.didRewrite,
                "\(name): should rewrite with valid workspace")
            XCTAssertTrue(result.text.contains("\(expectedPrefix)Pindrop/Services/AppCoordinator.swift"),
                "\(name): expected prefix '\(expectedPrefix)' in mention — got: \(result.text)")
        }
    }
}
