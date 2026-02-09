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
    func enumerateFiles(under root: String) throws -> [String] {
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
        }
        return results
    }

    func directoryExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
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

    // MARK: - State

    /// All indexed files, keyed by lowercased filename for O(1) lookup.
    private(set) var filesByName: [String: [IndexedFile]] = [:]

    private(set) var filesByStem: [String: [IndexedFile]] = [:]

    private(set) var allFiles: [IndexedFile] = []

    private(set) var workspaceRoots: [String] = []

    var fileCount: Int { allFiles.count }

    // MARK: - Dependencies

    private let fileSystem: FileSystemProvider

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
        let validRoots = roots.filter { root in
            let exists = fileSystem.directoryExists(at: root)
            if !exists {
                Log.context.warning("Workspace root not found, skipping: \(root)")
            }
            return exists
        }

        guard !validRoots.isEmpty else {
            clearIndex()
            throw WorkspaceFileIndexError.rootNotFound(
                roots.joined(separator: ", ")
            )
        }

        var indexed: [IndexedFile] = []

        for root in validRoots {
            do {
                let paths = try fileSystem.enumerateFiles(under: root)
                let rootURL = URL(fileURLWithPath: root, isDirectory: true)

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

                    let entry = IndexedFile(
                        absolutePath: absolutePath,
                        relativePath: relativePath,
                        workspaceRoot: root,
                        stem: stem,
                        filename: filename,
                        fileExtension: ext,
                        pathSegments: segments,
                        lowercasedFilename: filename.lowercased(),
                        lowercasedStem: stem.lowercased()
                    )
                    indexed.append(entry)
                }
            } catch {
                Log.context.error("Failed to enumerate files under \(root): \(error.localizedDescription)")
            }
        }

        // Rebuild lookup tables
        self.workspaceRoots = validRoots
        self.allFiles = indexed

        var byName: [String: [IndexedFile]] = [:]
        var byStem: [String: [IndexedFile]] = [:]
        for file in indexed {
            byName[file.lowercasedFilename, default: []].append(file)
            byStem[file.lowercasedStem, default: []].append(file)
        }
        self.filesByName = byName
        self.filesByStem = byStem

        Log.context.info("Workspace index built: \(indexed.count) files across \(validRoots.count) roots")
        return indexed.count
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
