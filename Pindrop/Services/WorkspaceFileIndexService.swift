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
}

/// Production implementation using `FileManager`.
struct RealFileSystemProvider: FileSystemProvider {
    private static let maxFilesPerRoot = 12000
    private static let gitExecutablePath = "/usr/bin/git"

    func enumerateFiles(under root: String) throws -> [String] {
        do {
            if let gitFilteredPaths = try enumerateFilesUsingGit(under: root) {
                return gitFilteredPaths
            }
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
        for case let url as URL in enumerator {
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

    private func enumerateFilesUsingGit(under root: String) throws -> [String]? {
        guard FileManager.default.isExecutableFile(atPath: Self.gitExecutablePath) else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let revParse = try runGit(arguments: ["-C", root, "rev-parse", "--is-inside-work-tree"])

        guard revParse.status == 0,
              let revParseText = String(data: revParse.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              revParseText == "true" else {
            return nil
        }

        let listResult = try runGit(arguments: [
            "-C", root,
            "ls-files", "-z",
            "--cached", "--others", "--exclude-standard",
        ])

        guard listResult.status == 0 else {
            let message = String(data: listResult.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkspaceFileIndexError.enumerationFailed(
                message?.isEmpty == false
                    ? message ?? "git ls-files exited with status \(listResult.status)"
                    : "git ls-files exited with status \(listResult.status)"
            )
        }

        let rawPaths = listResult.stdout.split(separator: 0, omittingEmptySubsequences: true)
        var results: [String] = []

        for rawPath in rawPaths {
            guard let relativePath = String(data: Data(rawPath), encoding: .utf8),
                  !shouldSkipRelativePath(relativePath) else {
                continue
            }

            let absolutePath = URL(fileURLWithPath: relativePath, relativeTo: rootURL)
                .standardizedFileURL
                .path

            results.append(absolutePath)

            if results.count >= Self.maxFilesPerRoot {
                Log.context.warning("Workspace indexing truncated at \(Self.maxFilesPerRoot) files for root: \(root)")
                break
            }
        }

        return results
    }

    private func runGit(arguments: [String]) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitExecutablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw WorkspaceFileIndexError.enumerationFailed("Unable to launch git: \(error.localizedDescription)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }

    private func shouldSkipRelativePath(_ relativePath: String) -> Bool {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let components = trimmed.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
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
        let workspaceRoots: [String]
        let allFiles: [IndexedFile]
        let filesByName: [String: [IndexedFile]]
        let filesByStem: [String: [IndexedFile]]
    }

    // MARK: - State

    /// All indexed files, keyed by lowercased filename for O(1) lookup.
    private(set) var filesByName: [String: [IndexedFile]] = [:]

    private(set) var filesByStem: [String: [IndexedFile]] = [:]

    private(set) var allFiles: [IndexedFile] = []

    private(set) var workspaceRoots: [String] = []

    var fileCount: Int { allFiles.count }

    // MARK: - Dependencies

    private let fileSystem: FileSystemProvider

    private static let buildTimeout: Duration = .seconds(2)

    // MARK: - Init

    init(fileSystem: FileSystemProvider = RealFileSystemProvider()) {
        self.fileSystem = fileSystem
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

        self.workspaceRoots = output.workspaceRoots
        self.allFiles = output.allFiles
        self.filesByName = output.filesByName
        self.filesByStem = output.filesByStem

        Log.context.info("Workspace index built: \(output.allFiles.count) files across \(output.workspaceRoots.count) roots")
        return output.allFiles.count
    }

    private func buildIndexData(roots: [String]) async throws -> BuildOutput {
        let fileSystem = self.fileSystem

        return try await withThrowingTaskGroup(of: BuildOutput.self) { group in
            group.addTask(priority: .utility) {
                let validRoots = roots.filter { root in
                    let exists = fileSystem.directoryExists(at: root)
                    if !exists {
                        Log.context.warning("Workspace root not found, skipping: \(root)")
                    }
                    return exists
                }

                guard !validRoots.isEmpty else {
                    throw WorkspaceFileIndexError.rootNotFound(roots.joined(separator: ", "))
                }

                var indexed: [IndexedFile] = []

                for root in validRoots {
                    do {
                        let paths = try fileSystem.enumerateFiles(under: root)

                        for absolutePath in paths {
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
                    } catch {
                        Log.context.error("Failed to enumerate files under \(root): \(error.localizedDescription)")
                    }
                }

                var byName: [String: [IndexedFile]] = [:]
                var byStem: [String: [IndexedFile]] = [:]
                for file in indexed {
                    byName[file.lowercasedFilename, default: []].append(file)
                    byStem[file.lowercasedStem, default: []].append(file)
                }

                return BuildOutput(
                    workspaceRoots: validRoots,
                    allFiles: indexed,
                    filesByName: byName,
                    filesByStem: byStem
                )
            }

            group.addTask {
                try await Task.sleep(for: Self.buildTimeout)
                throw WorkspaceFileIndexError.enumerationFailed(
                    "Indexing exceeded \(Int(Self.buildTimeout.components.seconds)) seconds"
                )
            }

            guard let firstResult = try await group.next() else {
                throw WorkspaceFileIndexError.enumerationFailed("Indexing returned no result")
            }

            group.cancelAll()
            return firstResult
        }
    }

    func clearIndex() {
        allFiles = []
        filesByName = [:]
        filesByStem = [:]
        workspaceRoots = []
    }

    // MARK: - Lookup

    /// Find files matching an exact filename (case-insensitive).
    func filesMatching(filename: String) -> [IndexedFile] {
        filesByName[filename.lowercased()] ?? []
    }

    /// Find files matching a stem (filename without extension, case-insensitive).
    func filesMatching(stem: String) -> [IndexedFile] {
        filesByStem[stem.lowercased()] ?? []
    }

    /// Find files where any path segment contains the query (case-insensitive).
    func filesContaining(segment: String) -> [IndexedFile] {
        let query = segment.lowercased()
        return allFiles.filter { file in
            file.pathSegments.contains { $0.lowercased().contains(query) }
        }
    }
}
