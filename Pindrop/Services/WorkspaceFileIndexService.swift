//
//  WorkspaceFileIndexService.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import os.log

// MARK: - File System Provider Protocol

/// Abstraction over the file system for testability.
/// Production code uses `RealFileSystemProvider`; tests inject a mock.
protocol FileSystemProvider: Sendable {
    /// Returns all file paths under `root`, recursively.
    /// Paths are absolute.
    func enumerateFiles(under root: String) throws -> [String]

    /// Whether a directory exists at the given path.
    func directoryExists(at path: String) -> Bool

    /// Cancels any subprocess-backed enumeration currently in progress. Providers
    /// without subprocesses can use the default no-op implementation.
    func cancelEnumeration()
}

extension FileSystemProvider {
    func cancelEnumeration() {}
}

/// Production implementation using `FileManager`.
final class RealFileSystemProvider: FileSystemProvider, @unchecked Sendable {
    private static let maxFilesPerRoot = 12000
    private static let gitExecutablePath = "/usr/bin/git"
    /// Owning build generation for the current enumeration task. Set by the
    /// timeout wrapper so git process registration cannot slip onto a newer
    /// build's generation while an older build is still scanning.
    @TaskLocal static var activeGeneration: UInt64?

    private let processLock = NSLock()
    /// Live generations only. Presence of a key means that generation may own
    /// git processes; cancel/end remove the key so late registration is rejected.
    private var activeGitProcessesByGeneration: [UInt64: [ObjectIdentifier: Process]] = [:]
    private var currentGeneration: UInt64 = 0

    /// Test seam: invoked after `process.run()` and before generation-scoped
    /// registration. Used to deterministically cancel in the launch/register window.
    var processLaunchHandler: (@Sendable (UInt64) -> Void)?

    func beginGeneration() -> UInt64 {
        processLock.lock()
        defer { processLock.unlock() }
        currentGeneration &+= 1
        let generation = currentGeneration
        activeGitProcessesByGeneration[generation] = [:]
        return generation
    }

    func endGeneration(_ generation: UInt64) {
        let processes = takeProcesses(for: generation)
        terminateAndWait(processes)
    }

    func cancelGeneration(_ generation: UInt64) {
        let processes = takeProcesses(for: generation)
        terminateAndWait(processes)
    }

    /// Ensures there is a live generation bucket for direct/non-build callers.
    /// Never resurrects a cancelled generation: if the current one is gone, open a new one.
    private func ensureLiveGeneration() -> UInt64 {
        processLock.lock()
        defer { processLock.unlock() }
        if activeGitProcessesByGeneration[currentGeneration] == nil {
            currentGeneration &+= 1
            activeGitProcessesByGeneration[currentGeneration] = [:]
        }
        return currentGeneration
    }

    /// Number of git processes currently registered across all live generations.
    /// Exposed for deterministic cancellation tests.
    var registeredProcessCount: Int {
        processLock.lock()
        defer { processLock.unlock() }
        return activeGitProcessesByGeneration.values.reduce(0) { $0 + $1.count }
    }

    func enumerateFiles(under root: String) throws -> [String] {
        // Prefer the generation bound to this build task. Falling back creates or
        // reuses a live ad-hoc generation so direct callers still register processes.
        let generation = Self.activeGeneration ?? ensureLiveGeneration()

        do {
            if let gitFilteredPaths = try enumerateFilesUsingGit(under: root, generation: generation) {
                return gitFilteredPaths
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.context.warning("Git-aware workspace indexing failed for root \(root), falling back to filesystem scan: \(error.localizedDescription)")
        }

        return try enumerateFilesUsingFileManager(under: root)
    }

    private func enumerateFilesUsingFileManager(under root: String) throws -> [String] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [String] = []
        results.reserveCapacity(min(Self.maxFilesPerRoot, 1024))
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            results.append(url.path)

            if results.count >= Self.maxFilesPerRoot {
                Log.context.warning("Workspace indexing truncated at \(Self.maxFilesPerRoot) files for root: \(root)")
                break
            }
        }

        return results
    }

    func directoryExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func cancelEnumeration() {
        let generation: UInt64
        processLock.lock()
        generation = currentGeneration
        processLock.unlock()
        cancelGeneration(generation)
    }

    private func enumerateFilesUsingGit(under root: String, generation: UInt64) throws -> [String]? {
        guard FileManager.default.isExecutableFile(atPath: Self.gitExecutablePath) else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let revParse = try runGit(
            arguments: ["-C", root, "rev-parse", "--is-inside-work-tree"],
            generation: generation
        )

        guard revParse.status == 0,
              let revParseText = String(data: revParse.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              revParseText == "true" else {
            return nil
        }

        // Stream NUL-delimited output and enforce the accepted-file cap while reading
        // so memory stays bounded and the process is terminated at cap/cancellation.
        return try streamGitLSFiles(root: root, rootURL: rootURL, generation: generation)
    }

    private func streamGitLSFiles(
        root: String,
        rootURL: URL,
        generation: UInt64
    ) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitExecutablePath)
        process.arguments = [
            "-C", root,
            "ls-files", "-z",
            "--cached", "--others", "--exclude-standard",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try launchAndRegister(process, generation: generation)
        defer { finishProcess(process, generation: generation) }

        var results: [String] = []
        results.reserveCapacity(min(Self.maxFilesPerRoot, 1024))
        var pending = Data()
        pending.reserveCapacity(4096)
        let readHandle = stdoutPipe.fileHandleForReading
        var reachedCap = false

        while true {
            try Task.checkCancellation()
            if reachedCap { break }

            let chunk = readHandle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }

            pending.append(chunk)

            var consumeStart = pending.startIndex
            while let nulIndex = pending[consumeStart...].firstIndex(of: 0) {
                let pathBytes = pending[consumeStart..<nulIndex]
                consumeStart = pending.index(after: nulIndex)

                guard !pathBytes.isEmpty else { continue }
                // Decode path bytes in place — avoid allocating a per-path Data copy.
                let relativePath = decodeUTF8(pathBytes)
                guard let relativePath,
                      !shouldSkipRelativePath(relativePath) else {
                    continue
                }

                let absolutePath = URL(fileURLWithPath: relativePath, relativeTo: rootURL)
                    .standardizedFileURL
                    .path
                results.append(absolutePath)

                if results.count >= Self.maxFilesPerRoot {
                    Log.context.warning("Workspace indexing truncated at \(Self.maxFilesPerRoot) files for root: \(root)")
                    reachedCap = true
                    break
                }
            }

            if consumeStart > pending.startIndex {
                pending.removeSubrange(pending.startIndex..<consumeStart)
            }
        }

        if reachedCap || Task.isCancelled {
            if process.isRunning {
                process.terminate()
            }
        }

        // Drain stderr without retaining a huge buffer when we already have paths.
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if process.isRunning {
            process.waitUntilExit()
        } else {
            // Already exited (or terminated by us); wait is still safe/idempotent enough.
            process.waitUntilExit()
        }

        try Task.checkCancellation()

        // If we terminated early due to the accepted-file cap, treat as success.
        if reachedCap {
            return results
        }

        guard process.terminationStatus == 0 else {
            if Task.isCancelled {
                throw CancellationError()
            }
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkspaceFileIndexError.enumerationFailed(
                message?.isEmpty == false
                    ? message ?? "git ls-files exited with status \(process.terminationStatus)"
                    : "git ls-files exited with status \(process.terminationStatus)"
            )
        }

        // Flush any trailing path without a final NUL (unusual for -z, but cheap).
        if !pending.isEmpty, results.count < Self.maxFilesPerRoot {
            if let relativePath = decodeUTF8(pending[pending.startIndex..<pending.endIndex]),
               !shouldSkipRelativePath(relativePath) {
                let absolutePath = URL(fileURLWithPath: relativePath, relativeTo: rootURL)
                    .standardizedFileURL
                    .path
                results.append(absolutePath)
            }
        }

        return results
    }

    private func runGit(
        arguments: [String],
        generation: UInt64
    ) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitExecutablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try launchAndRegister(process, generation: generation)
        defer { finishProcess(process, generation: generation) }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()

        return (status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }

    /// Launch a process and register it under `generation` only if that generation
    /// is still live. A cancelled/ended generation rejects registration and
    /// immediately terminates + waits for the already-started process.
    private func launchAndRegister(_ process: Process, generation: UInt64) throws {
        processLock.lock()
        let canLaunch = activeGitProcessesByGeneration[generation] != nil
        processLock.unlock()
        guard canLaunch else {
            throw CancellationError()
        }

        do {
            try process.run()
        } catch {
            throw WorkspaceFileIndexError.enumerationFailed(
                "Unable to launch git: \(error.localizedDescription)"
            )
        }

        // Deterministic test seam for the run→register window.
        processLaunchHandler?(generation)

        processLock.lock()
        let stillLive = activeGitProcessesByGeneration[generation] != nil
        if stillLive {
            activeGitProcessesByGeneration[generation]![ObjectIdentifier(process)] = process
        }
        processLock.unlock()

        guard stillLive else {
            // Generation ended/cancelled between launch and registration.
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            throw CancellationError()
        }
    }

    /// Cancellation/error unwind: if this call still owns the process, terminate
    /// (when needed), wait, then unregister. If cancel/end already took ownership,
    /// skip waiting to avoid concurrent `waitUntilExit` on the same `Process`.
    private func finishProcess(_ process: Process, generation: UInt64) {
        processLock.lock()
        let wasRegistered = activeGitProcessesByGeneration[generation]?[ObjectIdentifier(process)] != nil
        activeGitProcessesByGeneration[generation]?[ObjectIdentifier(process)] = nil
        processLock.unlock()

        guard wasRegistered else { return }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
    }

    private func takeProcesses(for generation: UInt64) -> [Process] {
        processLock.lock()
        let processes = activeGitProcessesByGeneration.removeValue(forKey: generation)?.values.map { $0 } ?? []
        // Terminate under the lock so concurrent launchAndRegister cannot observe a
        // live generation while processes are still being signalled.
        for process in processes where process.isRunning {
            process.terminate()
        }
        processLock.unlock()
        return processes
    }

    private func terminateAndWait(_ processes: [Process]) {
        for process in processes {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }
    }

    private func shouldSkipRelativePath(_ relativePath: String) -> Bool {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let components = trimmed.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }

    private func decodeUTF8(_ bytes: Data.SubSequence) -> String? {
        bytes.withUnsafeBytes { raw -> String? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return String(
                decoding: UnsafeBufferPointer(start: base, count: bytes.count),
                as: UTF8.self
            )
        }
    }
}

// MARK: - Indexed File Entry

/// A single file in the workspace index.
struct IndexedFile: Sendable, Equatable {
    /// Absolute path on disk
    let absolutePath: String

    /// Path relative to the workspace root that contains it
    let relativePath: String

    /// The workspace root this file belongs to
    let workspaceRoot: String

    /// Filename without extension (e.g. "AppCoordinator")
    let stem: String

    /// Full filename including extension (e.g. "AppCoordinator.swift")
    let filename: String

    /// File extension without dot (e.g. "swift")
    let fileExtension: String

    /// Path segments for tokenized matching (e.g. ["Pindrop", "Services", "AppCoordinator.swift"])
    let pathSegments: [String]

    /// Lowercased filename for case-insensitive matching
    let lowercasedFilename: String

    /// Lowercased stem for case-insensitive matching
    let lowercasedStem: String
}

// MARK: - Workspace File Index Errors

enum WorkspaceFileIndexError: Error, LocalizedError {
    case rootNotFound(String)
    case enumerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootNotFound(let path):
            return "Workspace root directory not found: \(path)"
        case .enumerationFailed(let reason):
            return "Failed to enumerate workspace files: \(reason)"
        }
    }
}

// MARK: - Workspace File Index Service

/// Scans configured workspace root directories and builds an in-memory file index.
///
/// The index supports lookup by filename, stem, and path segments for the
/// `PathMentionResolver` scoring pipeline. The service does NOT watch for
/// file system changes — callers must explicitly call `rebuildIndex()` when
/// the workspace may have changed.
@MainActor
final class WorkspaceFileIndexService {

    private struct BuildOutput: Sendable {
        /// Build generation that produced this output. Published only when current.
        let generation: UInt64
        let workspaceRoots: [String]
        let allFiles: [IndexedFile]
        /// Integer indices into `allFiles` for compact storage.
        let nameIndex: [String: [Int]]
        let stemIndex: [String: [Int]]
    }

    private struct InFlightBuild {
        let generation: UInt64
        let providerGeneration: UInt64?
        let task: Task<BuildOutput, Error>
    }

    // MARK: - State

    /// Canonical ordered file list. Lookup maps store integer indices into this array.
    private(set) var allFiles: [IndexedFile] = []

    /// Lowercased filename → indices into `allFiles`.
    private var nameIndex: [String: [Int]] = [:]

    /// Lowercased stem → indices into `allFiles`.
    private var stemIndex: [String: [Int]] = [:]

    private(set) var workspaceRoots: [String] = []

    /// Compatibility projection used by older call sites/tests that still expect
    /// materialised `[IndexedFile]` buckets. Built lazily from the compact index.
    var filesByName: [String: [IndexedFile]] {
        materialize(index: nameIndex)
    }

    var filesByStem: [String: [IndexedFile]] {
        materialize(index: stemIndex)
    }

    var fileCount: Int { allFiles.count }

    // MARK: - Dependencies

    private let fileSystem: FileSystemProvider
    private let buildTimeout: Duration

    /// Coalesces identical in-flight builds for the same root set.
    private var inFlightBuilds: [[String]: InFlightBuild] = [:]
    private var buildGeneration: UInt64 = 0

    // MARK: - Init

    init(
        fileSystem: FileSystemProvider = RealFileSystemProvider(),
        buildTimeout: Duration = .seconds(2)
    ) {
        self.fileSystem = fileSystem
        self.buildTimeout = buildTimeout
    }

    // MARK: - Index Building

    /// Rebuild the file index for the given workspace roots.
    ///
    /// This replaces any previous index entirely. Invalid roots are logged
    /// as warnings but do not prevent indexing of valid roots.
    ///
    /// - Parameter roots: Absolute paths to workspace root directories.
    /// - Returns: Count of files indexed.
    @discardableResult
    func buildIndex(roots: [String]) async throws -> Int {
        let output = try await buildIndexData(roots: roots)

        // Stale completions must never clobber a newer published index.
        guard output.generation == buildGeneration else {
            throw CancellationError()
        }

        self.workspaceRoots = output.workspaceRoots
        self.allFiles = output.allFiles
        self.nameIndex = output.nameIndex
        self.stemIndex = output.stemIndex

        Log.context.info("Workspace index built: \(output.allFiles.count) files across \(output.workspaceRoots.count) roots")
        return output.allFiles.count
    }

    private func buildIndexData(roots: [String]) async throws -> BuildOutput {
        let normalizedRoots = roots
        if let existing = inFlightBuilds[normalizedRoots] {
            return try await existing.task.value
        }

        // Non-identical root sets supersede any older in-flight builds.
        supersedeInFlightBuilds()

        buildGeneration &+= 1
        let generation = buildGeneration
        let fileSystem = self.fileSystem
        let realProvider = fileSystem as? RealFileSystemProvider
        let providerGeneration = realProvider?.beginGeneration()

        let task = Task { () -> BuildOutput in
            defer {
                if let realProvider, let providerGeneration {
                    realProvider.endGeneration(providerGeneration)
                }
            }

            return try await withWorkspaceTimeout(
                timeout: buildTimeout,
                fileSystem: fileSystem,
                generation: providerGeneration
            ) {
                var validRoots: [String] = []
                validRoots.reserveCapacity(normalizedRoots.count)
                for root in normalizedRoots {
                    try Task.checkCancellation()
                    if fileSystem.directoryExists(at: root) {
                        validRoots.append(root)
                    } else {
                        Log.context.warning("Workspace root not found, skipping: \(root)")
                    }
                }

                guard !validRoots.isEmpty else {
                    throw WorkspaceFileIndexError.rootNotFound(normalizedRoots.joined(separator: ", "))
                }

                var indexed: [IndexedFile] = []
                indexed.reserveCapacity(1024)

                for root in validRoots {
                    try Task.checkCancellation()
                    do {
                        let paths = try fileSystem.enumerateFiles(under: root)
                        if indexed.capacity < indexed.count + paths.count {
                            indexed.reserveCapacity(indexed.count + paths.count)
                        }

                        for absolutePath in paths {
                            try Task.checkCancellation()
                            let fileURL = URL(fileURLWithPath: absolutePath)
                            let relativePath = absolutePath.hasPrefix(root)
                                ? String(absolutePath.dropFirst(root.count))
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                : fileURL.lastPathComponent

                            let filename = fileURL.lastPathComponent
                            let stem = fileURL.deletingPathExtension().lastPathComponent
                            let ext = fileURL.pathExtension
                            let segments = relativePath.split(separator: "/").map(String.init)

                            indexed.append(IndexedFile(
                                absolutePath: absolutePath,
                                relativePath: relativePath,
                                workspaceRoot: root,
                                stem: stem,
                                filename: filename,
                                fileExtension: ext,
                                pathSegments: segments,
                                lowercasedFilename: filename.lowercased(),
                                lowercasedStem: stem.lowercased()
                            ))
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Log.context.error("Failed to enumerate files under \(root): \(error.localizedDescription)")
                    }
                }

                var byName: [String: [Int]] = [:]
                var byStem: [String: [Int]] = [:]
                byName.reserveCapacity(min(indexed.count, 1024))
                byStem.reserveCapacity(min(indexed.count, 1024))
                for (offset, file) in indexed.enumerated() {
                    try Task.checkCancellation()
                    byName[file.lowercasedFilename, default: []].append(offset)
                    byStem[file.lowercasedStem, default: []].append(offset)
                }

                return BuildOutput(
                    generation: generation,
                    workspaceRoots: validRoots,
                    allFiles: indexed,
                    nameIndex: byName,
                    stemIndex: byStem
                )
            }
        }

        inFlightBuilds[normalizedRoots] = InFlightBuild(
            generation: generation,
            providerGeneration: providerGeneration,
            task: task
        )
        do {
            let output = try await task.value
            // Drop the coalesced slot only if it still belongs to this generation.
            if inFlightBuilds[normalizedRoots]?.generation == generation {
                inFlightBuilds[normalizedRoots] = nil
            }
            return output
        } catch {
            if inFlightBuilds[normalizedRoots]?.generation == generation {
                inFlightBuilds[normalizedRoots] = nil
            }
            throw error
        }
    }

    /// Cancel every in-flight build. Called when a new non-identical root set starts
    /// so older work cannot publish over the newer generation.
    private func supersedeInFlightBuilds() {
        let pending = inFlightBuilds
        guard !pending.isEmpty else { return }
        inFlightBuilds.removeAll(keepingCapacity: true)

        let realProvider = fileSystem as? RealFileSystemProvider
        for build in pending.values {
            build.task.cancel()
            if let realProvider, let providerGeneration = build.providerGeneration {
                realProvider.cancelGeneration(providerGeneration)
            }
        }
    }

    func clearIndex() {
        allFiles = []
        nameIndex = [:]
        stemIndex = [:]
        workspaceRoots = []
    }

    // MARK: - Lookup

    /// Find files matching an exact filename (case-insensitive).
    func filesMatching(filename: String) -> [IndexedFile] {
        resolve(indices: nameIndex[filename.lowercased()] ?? [])
    }

    /// Find files matching a stem (filename without extension, case-insensitive).
    func filesMatching(stem: String) -> [IndexedFile] {
        resolve(indices: stemIndex[stem.lowercased()] ?? [])
    }

    /// Find files where any path segment contains the query (case-insensitive).
    func filesContaining(segment: String) -> [IndexedFile] {
        let query = segment.lowercased()
        return allFiles.filter { file in
            file.pathSegments.contains { $0.lowercased().contains(query) }
        }
    }

    private func resolve(indices: [Int]) -> [IndexedFile] {
        indices.compactMap { index in
            guard allFiles.indices.contains(index) else { return nil }
            return allFiles[index]
        }
    }

    private func materialize(index: [String: [Int]]) -> [String: [IndexedFile]] {
        var result: [String: [IndexedFile]] = [:]
        result.reserveCapacity(index.count)
        for (key, indices) in index {
            result[key] = resolve(indices: indices)
        }
        return result
    }
}

/// A detached watchdog is deliberate: a synchronous file-system provider can
/// ignore cancellation, but callers must regain the main actor at the deadline.
/// Its late result is discarded, and cancellation terminates registered git jobs.
private func withWorkspaceTimeout<Output: Sendable>(
    timeout: Duration,
    fileSystem: FileSystemProvider,
    generation: UInt64? = nil,
    operation: @escaping @Sendable () throws -> Output
) async throws -> Output {
    let state = WorkspaceTimeoutState<Output>()
    let realProvider = fileSystem as? RealFileSystemProvider
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard state.activate(continuation) else { return }

            let operationTask = Task.detached(priority: .utility) {
                do {
                    let output = try await withTaskCancellationHandler {
                        if let realProvider, let generation {
                            try RealFileSystemProvider.$activeGeneration.withValue(generation) {
                                try operation()
                            }
                        } else {
                            try operation()
                        }
                    } onCancel: {
                        if let realProvider, let generation {
                            realProvider.cancelGeneration(generation)
                        } else {
                            fileSystem.cancelEnumeration()
                        }
                    }
                    state.resolve(.success(output))
                } catch {
                    state.resolve(.failure(error))
                }
            }
            state.setOperationTask(operationTask)

            let timeoutTask = Task.detached {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                state.resolve(.failure(
                    WorkspaceFileIndexError.enumerationFailed(
                        "Indexing exceeded \(Int(timeout.components.seconds)) seconds"
                    )
                ))
            }
            state.setTimeoutTask(timeoutTask)
        }
    } onCancel: {
        if let realProvider, let generation {
            realProvider.cancelGeneration(generation)
        } else {
            fileSystem.cancelEnumeration()
        }
        state.resolve(.failure(CancellationError()))
    }
}

private final class WorkspaceTimeoutState<Output>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingResult: Result<Output, Error>?
    private var isResolved = false

    func activate(_ continuation: CheckedContinuation<Output, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let pendingResult {
            self.pendingResult = nil
            continuation.resume(with: pendingResult)
            return false
        }
        guard !isResolved else {
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        return true
    }

    func setOperationTask(_ task: Task<Void, Never>) { set(task, asOperation: true) }
    func setTimeoutTask(_ task: Task<Void, Never>) { set(task, asOperation: false) }

    private func set(_ task: Task<Void, Never>, asOperation: Bool) {
        lock.lock()
        let shouldCancel = isResolved
        if !shouldCancel {
            if asOperation { operationTask = task } else { timeoutTask = task }
        }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func resolve(_ result: Result<Output, Error>) {
        lock.lock()
        guard !isResolved else { lock.unlock(); return }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        let operationTask = self.operationTask
        self.operationTask = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        if continuation == nil { pendingResult = result }
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}
