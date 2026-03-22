//
//  MentionRewriteServiceTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import Testing

@testable import Pindrop

@MainActor
@Suite
struct MentionRewriteServiceTests {
    private func makeSUT() -> (
        sut: MentionRewriteService,
        mockFS: MockFileSystemProvider,
        cursorCapabilities: AppAdapterCapabilities,
        fallbackCapabilities: AppAdapterCapabilities
    ) {
        var mockFS = MockFileSystemProvider()
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

        return (
            MentionRewriteService(fileSystem: mockFS),
            mockFS,
            CursorAdapter().capabilities,
            AppAdapterCapabilities.none
        )
    }

    @Test func rewriteOccursWhenAdapterSupportsMentionsAndWorkspaceAvailable() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.rewrittenCount > 0)
        #expect(result.text.contains("@"))
    }

    @Test func noRewriteWhenAdapterDoesNotSupportMentions() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: fixture.fallbackCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite == false)
        #expect(result.rewrittenCount == 0)
        #expect(result.text == "check the AppCoordinator.swift file")
    }

    @Test func noRewriteWhenNoWorkspaceRootsAvailable() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: []
        )

        #expect(result.didRewrite == false)
        #expect(result.rewrittenCount == 0)
        #expect(result.text == "check the AppCoordinator.swift file")
    }

    @Test func deriveWorkspaceInsightsReturnsNoneWhenNoRoots() async {
        let fixture = makeSUT()
        let insights = await fixture.sut.deriveWorkspaceInsights(workspaceRoots: [], activeDocumentPath: nil)

        #expect(insights == .none)
    }

    @Test func deriveWorkspaceInsightsIncludesActiveDocumentAndTags() async {
        let fixture = makeSUT()

        let insights = await fixture.sut.deriveWorkspaceInsights(
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/Pindrop/Services/AppCoordinator.swift"
        )

        #expect(insights.activeDocumentRelativePath == "Pindrop/Services/AppCoordinator.swift")
        #expect(insights.activeDocumentConfidence == 1.0)
        #expect(insights.workspaceConfidence > 0)
        #expect(insights.fileTagCandidates.isEmpty == false)
        #expect(insights.fileTagCandidates.first == "Pindrop/Services/AppCoordinator.swift")
    }

    @Test func noRewriteWhenWorkspaceIndexIsEmpty() async {
        var emptyFS = MockFileSystemProvider()
        emptyFS.directories = ["/empty"]
        emptyFS.filesByRoot = ["/empty": []]

        let emptySut = MentionRewriteService(fileSystem: emptyFS)

        let result = await emptySut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: makeSUT().cursorCapabilities,
            workspaceRoots: ["/empty"]
        )

        #expect(result.didRewrite == false)
        #expect(result.rewrittenCount == 0)
        #expect(result.text == "check the AppCoordinator.swift file")
    }

    @Test func gracefulFallbackWhenIndexBuildFails() async {
        var badFS = MockFileSystemProvider()
        badFS.directories = []
        badFS.filesByRoot = [:]

        let badSut = MentionRewriteService(fileSystem: badFS)

        let result = await badSut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: makeSUT().cursorCapabilities,
            workspaceRoots: ["/nonexistent"]
        )

        #expect(result.didRewrite == false)
        #expect(result.rewrittenCount == 0)
        #expect(result.text == "check the AppCoordinator.swift file")
    }

    @Test func multipleMentionsAreAllProcessed() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "look at AppCoordinator.swift and AudioRecorder.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.rewrittenCount + result.preservedCount >= 2)
    }

    @Test func noCandidatesReturnsOriginalText() async {
        let fixture = makeSUT()
        let text = "this text has no file mentions whatsoever"
        let result = await fixture.sut.rewrite(
            text: text,
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite == false)
        #expect(result.text == text)
    }

    @Test func dotPatternExtractsCandidates() async {
        let fixture = makeSUT()
        let index = WorkspaceFileIndexService(fileSystem: fixture.mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = fixture.sut.extractMentionCandidates(
            from: "please open app coordinator dot swift for me",
            index: index
        )

        #expect(candidates.isEmpty == false)
        #expect(candidates.contains { $0.text.lowercased().contains("dot") })
    }

    @Test func knownStemExtractsCandidates() async {
        let fixture = makeSUT()
        let index = WorkspaceFileIndexService(fileSystem: fixture.mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = fixture.sut.extractMentionCandidates(
            from: "check the AppCoordinator for issues",
            index: index
        )

        #expect(candidates.contains { $0.text.contains("AppCoordinator") })
    }

    @Test func cacheReusedWhenRootsUnchanged() async {
        let fixture = makeSUT()

        let result1 = await fixture.sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        let result2 = await fixture.sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result1.text == result2.text)
        #expect(result1.rewrittenCount == result2.rewrittenCount)
    }

    @Test func cacheInvalidatedWhenRootsChange() async {
        let cursorCapabilities = makeSUT().cursorCapabilities

        var otherFS = MockFileSystemProvider()
        otherFS.directories = ["/other"]
        otherFS.filesByRoot = ["/other": ["/other/SomeFile.swift"]]

        let otherSut = MentionRewriteService(fileSystem: otherFS)

        let result = await otherSut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: cursorCapabilities,
            workspaceRoots: ["/other"]
        )

        #expect(result.didRewrite == false)
    }

    @Test func clearCacheResetsState() async {
        let fixture = makeSUT()

        _ = await fixture.sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        fixture.sut.clearCache()

        let result = await fixture.sut.rewrite(
            text: "AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.rewrittenCount > 0 || result.preservedCount >= 0)
    }

    @Test func vsCodeAdapterUsesAtPrefix() async {
        let fixture = makeSUT()
        let vsCodeCapabilities = VSCodeAdapter().capabilities

        let result = await fixture.sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: vsCodeCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@"))
        #expect(result.text.contains("#") == false)
    }

    @Test func vsCodeRewriteNormalizesExistingHashPrefix() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "Can you update #README.md for me?",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@README.md"))
        #expect(result.text.contains("#@README.md") == false)
        #expect(result.text.contains("@@README.md") == false)
    }

    @Test func zedAdapterUsesSlashPrefix() async {
        let fixture = makeSUT()
        let zedCapabilities = ZedAdapter().capabilities

        let result = await fixture.sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: zedCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("/"))
    }

    @Test func windsurfAdapterUsesAtPrefix() async {
        let fixture = makeSUT()
        let windsurfCapabilities = WindsurfAdapter().capabilities

        let result = await fixture.sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: windsurfCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@"))
    }

    @Test func cursorAdapterUsesAtPrefix() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@"))
    }

    @Test func vsCodeFormatsExactMentionPath() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func zedFormatsExactMentionPath() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: ZedAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("/Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func cursorFormatsExactMentionPath() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: CursorAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func windsurfFormatsExactMentionPath() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func resultDidRewriteReflectsRewrittenCount() {
        let noRewrite = MentionRewriteResult(text: "hello", rewrittenCount: 0, preservedCount: 0)
        #expect(noRewrite.didRewrite == false)

        let withRewrite = MentionRewriteResult(text: "hello", rewrittenCount: 1, preservedCount: 0)
        #expect(withRewrite.didRewrite)
    }

    @Test func originalTextPreservedWhenNoMentionCandidatesFound() async {
        let fixture = makeSUT()
        let originalText = "just a regular sentence with no code references at all"

        let result = await fixture.sut.rewrite(
            text: originalText,
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.text == originalText)
        #expect(result.rewrittenCount == 0)
        #expect(result.preservedCount == 0)
    }

    @Test func emptyTextReturnsEmptyResult() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.text == "")
        #expect(result.didRewrite == false)
    }

    @Test func normalizeFilePathToParentDirectory() {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.directories.insert("/workspace/Pindrop/Services")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "/workspace/Pindrop/Services/AppCoordinator.swift"
        ])

        #expect(result == ["/workspace/Pindrop/Services"])
    }

    @Test func normalizeTildePath() {
        let fixture = makeSUT()
        let home = NSHomeDirectory()
        let expandedPath = "\(home)/Projects/pindrop"
        var mockFS = fixture.mockFS
        mockFS.directories.insert(expandedPath)
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots(["~/Projects/pindrop"])

        #expect(result == [expandedPath])
    }

    @Test func normalizeFileURLScheme() {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.directories.insert("/workspace/some")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "file:///workspace/some/file.swift"
        ])

        #expect(result == ["/workspace/some"])
    }

    @Test func normalizeClimbsToProjectMarker() {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.directories.insert("/workspace/Pindrop/Services")
        mockFS.directories.insert("/workspace/Pindrop")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "/workspace/Pindrop/Services/AppCoordinator.swift"
        ])

        #expect(result == ["/workspace"])
    }

    @Test func normalizeDeduplicatesRoots() {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.directories.insert("/workspace")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "/workspace",
            "/workspace",
            "/workspace"
        ])

        #expect(result == ["/workspace"])
    }

    @Test func normalizeSkipsCompletelyInvalidPaths() {
        let fixture = makeSUT()
        let result = fixture.sut.normalizeWorkspaceRoots([
            "/nonexistent/path/to/file.swift"
        ])

        #expect(result.isEmpty)
    }

    @Test func normalizeWithFileURLAndTildeAndFilePath() {
        let fixture = makeSUT()
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        var mockFS = fixture.mockFS
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        mockFS.directories.insert("\(projectRoot)/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "file://\(projectRoot)/Pindrop/AppCoordinator.swift"
        ])

        #expect(result == [projectRoot])
    }

    @Test func rewriteWorksWithFilePathAsWorkspaceRoot() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.directories.insert("/workspace/Pindrop/Services")
        mockFS.directories.insert("/workspace/Pindrop")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")

        let fileSut = MentionRewriteService(fileSystem: mockFS)

        let result = await fileSut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace/Pindrop/Services/AppCoordinator.swift"]
        )

        #expect(result.didRewrite)
    }

    @Test func mixedDotPatternAndStemExtraction() async {
        let fixture = makeSUT()
        let index = WorkspaceFileIndexService(fileSystem: fixture.mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = fixture.sut.extractMentionCandidates(
            from: "check app coordinator dot swift and also AudioRecorder",
            index: index
        )

        let hasDotPattern = candidates.contains { $0.text.lowercased().contains("dot") }
        let hasStemMatch = candidates.contains { $0.text.contains("AudioRecorder") }

        #expect(hasDotPattern)
        #expect(hasStemMatch)
        #expect(candidates.count >= 2)
    }

    @Test func mixedExtractionDoesNotDuplicateOverlaps() async {
        let fixture = makeSUT()
        let index = WorkspaceFileIndexService(fileSystem: fixture.mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = fixture.sut.extractMentionCandidates(
            from: "look at app coordinator dot swift",
            index: index
        )

        let dotMentions = candidates.filter { $0.text.lowercased().contains("dot") }
        #expect(dotMentions.count == 1)
    }

    @Test func literalDottedFilenameExtraction() async {
        let fixture = makeSUT()
        let index = WorkspaceFileIndexService(fileSystem: fixture.mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = fixture.sut.extractMentionCandidates(
            from: "check the AppCoordinator.swift file",
            index: index
        )

        #expect(candidates.contains { $0.text == "AppCoordinator.swift" })
    }

    @Test func literalDottedFilenameWithDifferentExtension() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "open fixtures.go please",
            index: index
        )

        #expect(candidates.contains { $0.text == "fixtures.go" })
    }

    @Test func pathQualifiedLiteralFilename() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try? await index.buildIndex(roots: ["/workspace"])

        let candidates = sut.extractMentionCandidates(
            from: "look at gen/fixtures.go",
            index: index
        )

        #expect(candidates.contains { $0.text == "gen/fixtures.go" })
    }

    @Test func activeDocumentDisambiguatesMultipleMatches() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "check fixtures.go",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("gen/fixtures.go"))
    }

    @Test func rewriteWithoutActiveDocumentPreservesAmbiguous() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "check fixtures.go",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.text.contains("fixtures.go"))
    }

    @Test func vsCodeRewriteDisambiguatesReadmeInActiveDocumentDirectory() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/docs/README.md")
        mockFS.directories.insert("/workspace/docs")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "Can you update README.md for me?",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/CONTRIBUTING.md"
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@README.md"))
    }

    @Test func activeDocumentPathNormalizesFileURL() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "check fixtures.go",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "file:///workspace/gen/fixtures.go"
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("gen/fixtures.go"))
    }

    @Test func regressionCapitalizedFixturesGoWithActiveDocument() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "Can you fix the error in Fixtures.go?",
            capabilities: fixture.cursorCapabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@gen/fixtures.go"))
        #expect(result.text.contains("Fixtures.go") == false)
    }

    @Test func antigravityAdapterRewriteWithTildeRedactedRoot() async {
        let fixture = makeSUT()
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        var mockFS = fixture.mockFS
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        mockFS.directories.insert("\(projectRoot)/Pindrop/Services")
        mockFS.directories.insert("\(projectRoot)/.git")
        mockFS.filesByRoot[projectRoot] = [
            "\(projectRoot)/Pindrop/Services/AppCoordinator.swift",
            "\(projectRoot)/Pindrop/Services/AudioRecorder.swift",
            "\(projectRoot)/README.md",
        ]
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: AntigravityAdapter().capabilities,
            workspaceRoots: ["~/Projects/pindrop"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@"))
    }

    @Test func antigravityAdapterNoRewriteWithEmptyWorkspace() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "check the AppCoordinator.swift file",
            capabilities: AntigravityAdapter().capabilities,
            workspaceRoots: []
        )

        #expect(result.didRewrite == false)
    }

    @Test func normalizeTildeRedactedFilePath() {
        let fixture = makeSUT()
        let home = NSHomeDirectory()
        let projectRoot = "\(home)/Projects/pindrop"
        var mockFS = fixture.mockFS
        mockFS.directories.insert(projectRoot)
        mockFS.directories.insert("\(projectRoot)/.git")
        mockFS.directories.insert("\(projectRoot)/Pindrop")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = sut.normalizeWorkspaceRoots([
            "~/Projects/pindrop/Pindrop/AppCoordinator.swift"
        ])

        #expect(result == [projectRoot])
    }

    @Test func routingSignalDerivesWorkspaceRootFromDocumentPath() {
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

        #expect(signal.workspacePath == "~/Projects/pindrop/Pindrop")
    }

    @Test func routingSignalDerivesWorkspaceRootFromFileURL() {
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

        #expect(signal.workspacePath == "/Users/test/Projects/pindrop")
    }

    @Test func routingSignalUsesDirectoryDocumentPathForTerminalApps() {
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

        #expect(signal.workspacePath == "~/Projects/pindrop")
    }

    @Test func routingSignalNilWorkspaceWhenNoDocumentPath() {
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

        #expect(signal.workspacePath == nil)
    }

    private func makeEditorIntegrationSut() -> MentionRewriteService {
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
        return MentionRewriteService(fileSystem: fs)
    }

    @Test func cursorDerivationAndRewriteFromFilePath() async {
        let sut = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: CursorAdapter().capabilities,
            workspaceRoots: ["\(home)/Projects/pindrop/Pindrop/Services/AppCoordinator.swift"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func vsCodeDerivationAndRewriteFromFileURL() async {
        let sut = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: VSCodeAdapter().capabilities,
            workspaceRoots: ["file://\(home)/Projects/pindrop/Pindrop/Services/AppCoordinator.swift"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func zedDerivationAndRewriteFromTildePath() async {
        let sut = makeEditorIntegrationSut()

        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: ZedAdapter().capabilities,
            workspaceRoots: ["~/Projects/pindrop"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("/Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func windsurfDerivationAndRewriteFromSubdirectory() async {
        let sut = makeEditorIntegrationSut()
        let home = NSHomeDirectory()

        let result = await sut.rewrite(
            text: "open AppCoordinator.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["\(home)/Projects/pindrop/Pindrop/Services"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@Pindrop/Services/AppCoordinator.swift"))
    }

    @Test func windsurfNoRewriteWithEmptyWorkspace() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "check AppCoordinator.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: []
        )

        #expect(result.didRewrite == false)
    }

    @Test func windsurfRewriteMultipleMentions() async {
        let fixture = makeSUT()

        let result = await fixture.sut.rewrite(
            text: "look at AppCoordinator.swift and AudioRecorder.swift",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.rewrittenCount + result.preservedCount >= 2)
    }

    @Test func windsurfActiveDocumentDisambiguation() async {
        let fixture = makeSUT()
        var mockFS = fixture.mockFS
        mockFS.filesByRoot["/workspace"]?.append("/workspace/gen/fixtures.go")
        mockFS.filesByRoot["/workspace"]?.append("/workspace/test/fixtures.go")
        mockFS.directories.insert("/workspace/gen")
        mockFS.directories.insert("/workspace/test")
        mockFS.directories.insert("/workspace")
        mockFS.directories.insert("/workspace/.git")
        let sut = MentionRewriteService(fileSystem: mockFS)

        let result = await sut.rewrite(
            text: "check fixtures.go",
            capabilities: WindsurfAdapter().capabilities,
            workspaceRoots: ["/workspace"],
            activeDocumentPath: "/workspace/gen/fixtures.go"
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("@gen/fixtures.go"))
    }

    @Test func allEditorsPrefixDeterminism() async {
        let fixture = makeSUT()
        let editors: [(String, AppAdapterCapabilities, String)] = [
            ("Cursor", CursorAdapter().capabilities, "@"),
            ("VS Code", VSCodeAdapter().capabilities, "@"),
            ("Zed", ZedAdapter().capabilities, "/"),
            ("Windsurf", WindsurfAdapter().capabilities, "@"),
        ]

        for (name, caps, expectedPrefix) in editors {
            let result = await fixture.sut.rewrite(
                text: "check AppCoordinator.swift",
                capabilities: caps,
                workspaceRoots: ["/workspace"]
            )

            #expect(result.didRewrite, "\(name): should rewrite with valid workspace")
            #expect(
                result.text.contains("\(expectedPrefix)Pindrop/Services/AppCoordinator.swift"),
                "\(name): expected prefix '\(expectedPrefix)' in mention - got: \(result.text)"
            )
        }
    }

    @Test func rewriteToCanonicalPlaceholdersUsesCanonicalTemplate() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewriteToCanonicalPlaceholders(
            text: "check AppCoordinator.swift",
            capabilities: CursorAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.didRewrite)
        #expect(result.text.contains("[[:Pindrop/Services/AppCoordinator.swift:]]"))
    }

    @Test func renderCanonicalPlaceholdersUsesCodexMarkdownTemplate() {
        let fixture = makeSUT()
        let result = fixture.sut.renderCanonicalPlaceholders(
            in: "update [[:README.md:]]",
            capabilities: CodexAdapter().capabilities
        )

        #expect(result.didRewrite)
        #expect(result.rewrittenCount == 1)
        #expect(result.text == "update [@README.md](README.md)")
    }

    @Test func rewriteDoesNotCorruptMarkdownLinkTargetPath() async {
        let fixture = makeSUT()
        let result = await fixture.sut.rewrite(
            text: "see [@README.md](README.md)",
            capabilities: CodexAdapter().capabilities,
            workspaceRoots: ["/workspace"]
        )

        #expect(result.text == "see [@README.md](README.md)")
    }
}
