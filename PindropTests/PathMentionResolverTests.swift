//
//  PathMentionResolverTests.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import Testing

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

@MainActor
@Suite
struct PathMentionResolverTests {
    private func makeSUT() async throws -> (
        sut: PathMentionResolver,
        index: WorkspaceFileIndexService,
        mockFS: MockFileSystemProvider
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

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        try await index.buildIndex(roots: ["/workspace"])

        return (PathMentionResolver(), index, mockFS)
    }

    @Test func resolvesNestedMentionsToCanonicalRelativePath() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "AppCoordinator.swift", in: fixture.index)

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.relativePath == "Pindrop/Services/AppCoordinator.swift")
            #expect(candidate.file.filename == "AppCoordinator.swift")
            #expect(candidate.score >= PathScoringWeights.exactFilenameMatch)
        default:
            Issue.record("Expected .resolved, got \(result)")
        }
    }

    @Test func ambiguousMentionsReturnCandidatesNotFabricatedPath() async throws {
        let fixture = try await makeSUT()
        let sut = fixture.sut
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

        switch result {
        case .ambiguous(let candidates):
            #expect(candidates.count >= 2)

            for candidate in candidates {
                #expect(candidate.file.absolutePath.hasSuffix("Button.swift"))
            }

            let paths = candidates.map { $0.file.relativePath }
            #expect(paths.contains("Button.swift") == false)
        default:
            Issue.record("Expected .ambiguous, got \(result)")
        }
    }

    @Test func activeDocumentDirectoryDisambiguatesSingleTopTierCandidate() async throws {
        let fixture = try await makeSUT()
        let sut = fixture.sut
        var ambiguousFS = MockFileSystemProvider()
        ambiguousFS.directories = ["/workspace"]
        ambiguousFS.filesByRoot = [
            "/workspace": [
                "/workspace/README.md",
                "/workspace/docs/README.md",
                "/workspace/src/main.swift",
                "/workspace/CONTRIBUTING.md",
            ]
        ]

        let ambiguousIndex = WorkspaceFileIndexService(fileSystem: ambiguousFS)
        try await ambiguousIndex.buildIndex(roots: ["/workspace"])

        let result = sut.resolve(
            mention: "README.md",
            in: ambiguousIndex,
            activeDocumentPath: "/workspace/CONTRIBUTING.md"
        )

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.relativePath == "README.md")
        default:
            Issue.record("Expected .resolved, got \(result)")
        }
    }

    @Test func activeDocumentDirectoryDoesNotDisambiguateWithoutSameDirectoryCandidate() async throws {
        let fixture = try await makeSUT()
        let sut = fixture.sut
        var ambiguousFS = MockFileSystemProvider()
        ambiguousFS.directories = ["/workspace"]
        ambiguousFS.filesByRoot = [
            "/workspace": [
                "/workspace/docs/README.md",
                "/workspace/samples/README.md",
                "/workspace/src/main.swift",
            ]
        ]

        let ambiguousIndex = WorkspaceFileIndexService(fileSystem: ambiguousFS)
        try await ambiguousIndex.buildIndex(roots: ["/workspace"])

        let result = sut.resolve(
            mention: "README.md",
            in: ambiguousIndex,
            activeDocumentPath: "/workspace/src/main.swift"
        )

        switch result {
        case .ambiguous(let candidates):
            #expect(candidates.count == 2)
        default:
            Issue.record("Expected .ambiguous, got \(result)")
        }
    }

    @Test func exactStemMatchWithoutExtension() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "AppCoordinator", in: fixture.index)

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.filename == "AppCoordinator.swift")
            #expect(candidate.score >= PathScoringWeights.exactStemMatch)
        default:
            Issue.record("Expected .resolved, got \(result)")
        }
    }

    @Test func spokenDotNormalization() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "app coordinator dot swift", in: fixture.index)

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.stem == "AppCoordinator")
        default:
            Issue.record("Expected .resolved, got \(result)")
        }
    }

    @Test func tokenizedSegmentMatchByCamelCase() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "audio recorder", in: fixture.index)

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.stem.lowercased().contains("audiorecorder"))
        case .ambiguous(let candidates):
            #expect(candidates.contains { $0.file.stem == "AudioRecorder" })
        case .unresolved:
            Issue.record("Should resolve via tokenized segment match, got .unresolved")
        }
    }

    @Test func unresolvedForNonsenseMention() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "xyzzy_nonexistent_file", in: fixture.index)

        switch result {
        case .unresolved(let query):
            #expect(query == "xyzzy_nonexistent_file")
        default:
            Issue.record("Expected .unresolved, got \(result)")
        }
    }

    @Test func emptyMentionReturnsUnresolved() async throws {
        let fixture = try await makeSUT()
        let result = fixture.sut.resolve(mention: "   ", in: fixture.index)

        if case .unresolved = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .unresolved for empty mention, got \(result)")
        }
    }

    @Test func deterministicOrderingIsStable() async throws {
        let fixture = try await makeSUT()
        let sut = fixture.sut
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

        #expect(result1 == result2)
    }

    @Test func recencyBoostInfluencesResolution() async throws {
        let fixture = try await makeSUT()
        let sut = fixture.sut
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

        let newFile = try #require(twoFileIndex.allFiles.first { $0.absolutePath.contains("new/") })
        sut.recordAccess(for: newFile, at: Date())

        let result = sut.resolve(mention: "Helper.swift", in: twoFileIndex)

        switch result {
        case .resolved(let candidate):
            #expect(candidate.file.absolutePath.contains("new/"))
        case .ambiguous(let candidates):
            #expect(candidates[0].file.absolutePath.contains("new/"))
        case .unresolved:
            Issue.record("Should not be unresolved")
        }
    }

    @Test func indexBuildCountsFiles() async throws {
        let fixture = try await makeSUT()
        let count = try await fixture.index.buildIndex(roots: ["/workspace"])
        #expect(count == 9)
    }

    @Test func indexBuildWithInvalidRootThrows() async {
        var emptyFS = MockFileSystemProvider()
        emptyFS.directories = []
        let emptyIndex = WorkspaceFileIndexService(fileSystem: emptyFS)

        do {
            try await emptyIndex.buildIndex(roots: ["/nonexistent"])
            Issue.record("Expected error for invalid root")
        } catch is WorkspaceFileIndexError {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func normalizeMentionHandlesSpokenDot() async throws {
        let fixture = try await makeSUT()
        #expect(fixture.sut.normalizeMention("app dot swift") == "app.swift")
    }

    @Test func normalizeMentionHandlesSpokenSlash() async throws {
        let fixture = try await makeSUT()
        #expect(fixture.sut.normalizeMention("services slash app") == "services/app")
    }

    @Test func normalizeMentionLowercases() async throws {
        let fixture = try await makeSUT()
        #expect(fixture.sut.normalizeMention("AppCoordinator") == "appcoordinator")
    }
}

@MainActor
@Suite
struct WorkspaceFileIndexRealFileSystemTests {
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git"), "git executable is unavailable"))
    func buildIndexExcludesGitIgnoredFiles() async throws {

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-workspace-index-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot.path)

        let sourcesDirectory = tempRoot.appendingPathComponent("Sources", isDirectory: true)
        let ignoredBuildDirectory = tempRoot.appendingPathComponent("build", isDirectory: true)

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredBuildDirectory, withIntermediateDirectories: true)

        try createFile(
            at: tempRoot.appendingPathComponent(".gitignore"),
            contents: "*.log\nbuild/\n"
        )
        try createFile(
            at: sourcesDirectory.appendingPathComponent("App.swift"),
            contents: "struct App {}\n"
        )
        try createFile(
            at: tempRoot.appendingPathComponent("debug.log"),
            contents: "ignore me\n"
        )
        try createFile(
            at: ignoredBuildDirectory.appendingPathComponent("generated.swift"),
            contents: "ignore me\n"
        )

        let index = WorkspaceFileIndexService(fileSystem: RealFileSystemProvider())
        _ = try await index.buildIndex(roots: [tempRoot.path])

        let relativePaths = Set(index.allFiles.map(\.relativePath))
        #expect(relativePaths.contains("Sources/App.swift"))
        #expect(relativePaths.contains("debug.log") == false)
        #expect(relativePaths.contains("build/generated.swift") == false)
    }

    private func createFile(at url: URL, contents: String) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorText = String(data: stderrData, encoding: .utf8)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let message = errorText?.isEmpty == false
                ? (errorText ?? "git command failed with status \(process.terminationStatus)")
                : "git command failed with status \(process.terminationStatus)"
            throw NSError(domain: "WorkspaceFileIndexRealFileSystemTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }
}
