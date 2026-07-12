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

/// Slows enumeration so concurrent identical builds can share one in-flight task,
/// and counts how many times the filesystem is walked.
final class DelayedCountingFileSystemProvider: FileSystemProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _enumerateCount = 0

    var directories: Set<String>
    var filesByRoot: [String: [String]]
    var delayNanoseconds: UInt64

    var enumerateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _enumerateCount
    }

    init(
        directories: Set<String>,
        filesByRoot: [String: [String]],
        delayNanoseconds: UInt64
    ) {
        self.directories = directories
        self.filesByRoot = filesByRoot
        self.delayNanoseconds = delayNanoseconds
    }

    func enumerateFiles(under root: String) throws -> [String] {
        lock.lock()
        _enumerateCount += 1
        lock.unlock()

        // Cooperative delay: keep checking cancellation so cancelled builds abort.
        let steps = max(1, Int(delayNanoseconds / 5_000_000))
        for _ in 0..<steps {
            try Task.checkCancellation()
            Thread.sleep(forTimeInterval: 0.005)
        }
        try Task.checkCancellation()
        return filesByRoot[root] ?? []
    }

    func directoryExists(at path: String) -> Bool {
        directories.contains(path)
    }
}

/// Blocks enumeration until `releaseEnumeration` for a root is called, enabling
/// deterministic slower-old / faster-new build ordering without real timing races.
final class GatedFileSystemProvider: FileSystemProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [String: DispatchSemaphore] = [:]
    private var enteredRoots: Set<String> = []
    private var _enumerateCount = 0

    var directories: Set<String>
    var filesByRoot: [String: [String]]

    var enumerateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _enumerateCount
    }

    init(
        directories: Set<String>,
        filesByRoot: [String: [String]]
    ) {
        self.directories = directories
        self.filesByRoot = filesByRoot
    }

    /// Hold the next enumeration of `root` until `releaseEnumeration` is called.
    func holdEnumeration(for root: String) {
        lock.lock()
        gates[root] = DispatchSemaphore(value: 0)
        enteredRoots.remove(root)
        lock.unlock()
    }

    /// Async-friendly wait until enumeration for `root` has entered its hold gate.
    /// Polls so `@MainActor` tests do not deadlock waiting for a detached enumerator.
    func waitUntilEnumerationStarted(for root: String, timeoutSeconds: TimeInterval = 2) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(Int64(timeoutSeconds))
        while ContinuousClock.now < deadline {
            lock.lock()
            let entered = enteredRoots.contains(root)
            lock.unlock()
            if entered { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    func releaseEnumeration(for root: String) {
        lock.lock()
        let gate = gates.removeValue(forKey: root)
        lock.unlock()
        gate?.signal()
    }

    func enumerateFiles(under root: String) throws -> [String] {
        lock.lock()
        _enumerateCount += 1
        let gate = gates[root]
        enteredRoots.insert(root)
        lock.unlock()

        if let gate {
            gate.wait()
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        return filesByRoot[root] ?? []
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

    // MARK: - Compact index lookup + build coalescing

    @Test func compactIndexLookupMatchesAllFilesScan() async throws {
        var mockFS = MockFileSystemProvider()
        mockFS.directories = ["/workspace"]
        mockFS.filesByRoot = [
            "/workspace": [
                "/workspace/src/components/Button.swift",
                "/workspace/src/views/Button.swift",
                "/workspace/lib/Helper.swift",
                "/workspace/docs/README.md",
            ]
        ]

        let index = WorkspaceFileIndexService(fileSystem: mockFS)
        let count = try await index.buildIndex(roots: ["/workspace"])
        #expect(count == 4)

        let byFilename = index.filesMatching(filename: "Button.swift")
        let expectedFilename = index.allFiles.filter { $0.lowercasedFilename == "button.swift" }
        #expect(Set(byFilename.map(\.absolutePath)) == Set(expectedFilename.map(\.absolutePath)))
        #expect(byFilename.count == 2)

        let byStem = index.filesMatching(stem: "Helper")
        let expectedStem = index.allFiles.filter { $0.lowercasedStem == "helper" }
        #expect(Set(byStem.map(\.absolutePath)) == Set(expectedStem.map(\.absolutePath)))
        #expect(byStem.count == 1)
        #expect(byStem.first?.relativePath == "lib/Helper.swift")

        // Compatibility projection stays aligned with compact lookup maps.
        #expect(index.filesByName["button.swift"]?.count == 2)
        #expect(index.filesByStem["helper"]?.count == 1)
        #expect(index.filesMatching(filename: "missing.swift").isEmpty)
    }

    @Test func identicalConcurrentBuildsCoalesceEnumeration() async throws {
        let mockFS = DelayedCountingFileSystemProvider(
            directories: ["/workspace"],
            filesByRoot: [
                "/workspace": [
                    "/workspace/A.swift",
                    "/workspace/B.swift",
                    "/workspace/nested/C.swift",
                ]
            ],
            delayNanoseconds: 80_000_000
        )
        let index = WorkspaceFileIndexService(fileSystem: mockFS, buildTimeout: .seconds(5))

        async let first = index.buildIndex(roots: ["/workspace"])
        async let second = index.buildIndex(roots: ["/workspace"])
        let counts = try await [first, second]

        #expect(counts == [3, 3])
        #expect(mockFS.enumerateCount == 1)
        #expect(index.fileCount == 3)
        #expect(index.filesMatching(filename: "C.swift").count == 1)
    }

    @Test func cancelledBuildDoesNotPoisonLaterRebuild() async throws {
        let mockFS = DelayedCountingFileSystemProvider(
            directories: ["/workspace"],
            filesByRoot: [
                "/workspace": [
                    "/workspace/Keep.swift",
                    "/workspace/Other.swift",
                ]
            ],
            delayNanoseconds: 120_000_000
        )
        let index = WorkspaceFileIndexService(fileSystem: mockFS, buildTimeout: .seconds(5))

        let cancelled = Task { @MainActor in
            try await index.buildIndex(roots: ["/workspace"])
        }
        // Let the delayed enumeration start, then cancel the caller task.
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            // Completing before cancellation is observed is acceptable; the rebuild
            // below still has to produce a coherent index.
        } catch is CancellationError {
            // Expected when cancellation wins the race.
        } catch {
            Issue.record("Unexpected error from cancelled build: \(error)")
        }

        let count = try await index.buildIndex(roots: ["/workspace"])
        #expect(count == 2)
        #expect(index.filesMatching(filename: "Keep.swift").map(\.relativePath) == ["Keep.swift"])
        #expect(index.filesMatching(stem: "Other").count == 1)
        #expect(mockFS.enumerateCount >= 1)
    }

    @Test func slowerOldBuildCannotOverwriteFasterNewBuild() async throws {
        let mockFS = GatedFileSystemProvider(
            directories: ["/workspace-old", "/workspace-new"],
            filesByRoot: [
                "/workspace-old": [
                    "/workspace-old/OldOnly.swift",
                    "/workspace-old/Shared.swift",
                ],
                "/workspace-new": [
                    "/workspace-new/NewOnly.swift",
                    "/workspace-new/Shared.swift",
                ],
            ]
        )
        // Hold the older root so the newer root can finish first.
        mockFS.holdEnumeration(for: "/workspace-old")
        defer { mockFS.releaseEnumeration(for: "/workspace-old") }

        let index = WorkspaceFileIndexService(fileSystem: mockFS, buildTimeout: .seconds(5))

        let oldBuild = Task { @MainActor in
            try await index.buildIndex(roots: ["/workspace-old"])
        }

        #expect(await mockFS.waitUntilEnumerationStarted(for: "/workspace-old"))

        let newCount = try await index.buildIndex(roots: ["/workspace-new"])
        #expect(newCount == 2)
        #expect(index.filesMatching(filename: "NewOnly.swift").count == 1)
        #expect(index.filesMatching(filename: "OldOnly.swift").isEmpty)
        #expect(Set(index.workspaceRoots) == ["/workspace-new"])

        // Completing the slower old build must not clobber the newer published state.
        mockFS.releaseEnumeration(for: "/workspace-old")
        do {
            _ = try await oldBuild.value
            Issue.record("Superseded older build should not publish successfully")
        } catch is CancellationError {
            // Expected: generation ownership rejected the stale output.
        } catch {
            Issue.record("Unexpected error from superseded build: \(error)")
        }

        #expect(index.fileCount == 2)
        #expect(index.filesMatching(filename: "NewOnly.swift").map(\.relativePath) == ["NewOnly.swift"])
        #expect(index.filesMatching(filename: "OldOnly.swift").isEmpty)
        #expect(Set(index.workspaceRoots) == ["/workspace-new"])
    }

    @Test func identicalRootsStillCoalesceWhileDifferentRootsSupersede() async throws {
        let mockFS = GatedFileSystemProvider(
            directories: ["/workspace", "/other"],
            filesByRoot: [
                "/workspace": [
                    "/workspace/A.swift",
                    "/workspace/B.swift",
                ],
                "/other": [
                    "/other/Other.swift",
                ],
            ]
        )
        mockFS.holdEnumeration(for: "/workspace")
        defer { mockFS.releaseEnumeration(for: "/workspace") }

        let index = WorkspaceFileIndexService(fileSystem: mockFS, buildTimeout: .seconds(5))

        async let first = index.buildIndex(roots: ["/workspace"])
        #expect(await mockFS.waitUntilEnumerationStarted(for: "/workspace"))

        // Identical roots share the in-flight build (still gated).
        async let second = index.buildIndex(roots: ["/workspace"])

        // Different roots supersede the older in-flight work.
        let otherCount = try await index.buildIndex(roots: ["/other"])
        #expect(otherCount == 1)
        #expect(index.filesMatching(filename: "Other.swift").count == 1)

        mockFS.releaseEnumeration(for: "/workspace")

        do {
            _ = try await first
            Issue.record("Superseded coalesced build should not publish")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error from superseded first build: \(error)")
        }

        do {
            _ = try await second
            Issue.record("Superseded coalesced build should not publish")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error from superseded second build: \(error)")
        }

        #expect(index.fileCount == 1)
        #expect(index.filesMatching(filename: "Other.swift").map(\.relativePath) == ["Other.swift"])
        #expect(index.filesMatching(filename: "A.swift").isEmpty)
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

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git"), "git executable is unavailable"))
    func processCancelledBetweenLaunchAndRegistrationDoesNotEscape() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-workspace-launch-race-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot.path)
        try createFile(
            at: tempRoot.appendingPathComponent("Tracked.swift"),
            contents: "struct Tracked {}\n"
        )

        let provider = RealFileSystemProvider()
        let generation = provider.beginGeneration()

        // Deterministic seam: cancel the generation after process.run and before register.
        provider.processLaunchHandler = { launchedGeneration in
            #expect(launchedGeneration == generation)
            provider.cancelGeneration(launchedGeneration)
        }

        do {
            _ = try RealFileSystemProvider.$activeGeneration.withValue(generation) {
                try provider.enumerateFiles(under: tempRoot.path)
            }
            Issue.record("Expected cancellation when generation ends between launch and registration")
        } catch is CancellationError {
            // Expected: registration rejects the ended generation and terminates the process.
        } catch {
            Issue.record("Unexpected error from cancelled launch/registration race: \(error)")
        }

        #expect(provider.registeredProcessCount == 0)

        // Ending an already-cancelled generation must remain idempotent and leave no stragglers.
        provider.endGeneration(generation)
        #expect(provider.registeredProcessCount == 0)
    }
}
