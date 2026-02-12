//
//  MentionRewriteService.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import os.log

// MARK: - Mention Rewrite Errors

enum MentionRewriteError: Error, LocalizedError {
    case indexBuildFailed(String)
    case noWorkspaceRoots
    case rewriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .indexBuildFailed(let reason):
            return "Failed to build workspace file index: \(reason)"
        case .noWorkspaceRoots:
            return "No workspace roots available for mention resolution"
        case .rewriteFailed(let reason):
            return "Mention rewrite failed: \(reason)"
        }
    }
}

// MARK: - Mention Rewrite Result

/// Result of a mention rewrite pass over transcribed text.
struct MentionRewriteResult: Sendable, Equatable {
    /// The text after mention rewriting (may be unchanged).
    let text: String

    /// Number of mentions that were successfully rewritten.
    let rewrittenCount: Int

    /// Number of candidate mentions found but not rewritten.
    let preservedCount: Int

    /// Whether any rewriting actually occurred.
    var didRewrite: Bool { rewrittenCount > 0 }
}

struct WorkspaceContextInsights: Sendable, Equatable {
    let normalizedWorkspaceRoots: [String]
    let workspaceConfidence: Double
    let activeDocumentRelativePath: String?
    let activeDocumentConfidence: Double
    let fileTagCandidates: [String]

    static let none = WorkspaceContextInsights(
        normalizedWorkspaceRoots: [],
        workspaceConfidence: 0,
        activeDocumentRelativePath: nil,
        activeDocumentConfidence: 0,
        fileTagCandidates: []
    )
}


// MARK: - Mention Extraction

/// A candidate mention extracted from transcribed text.
struct ExtractedMention: Equatable {
    /// The range in the original text where this mention was found.
    let range: Range<String.Index>

    /// The raw mention text (e.g. "app coordinator dot swift").
    let text: String
}

// MARK: - Mention Rewrite Service

/// Orchestrates the end-to-end mention rewrite pipeline:
/// 1. Extracts candidate file mentions from transcribed text
/// 2. Resolves each mention against the workspace file index
/// 3. Formats resolved mentions using app-specific syntax
/// 4. Returns rewritten text with mentions replaced
///
/// This service is non-blocking and failure-safe: any error in the pipeline
/// returns the original text unchanged. It is designed to sit between
/// dictionary replacements and AI enhancement in the transcription flow.
@MainActor
final class MentionRewriteService {

    // MARK: - Dependencies

    private let resolver: PathMentionResolver
    private let formatter: MentionFormatter
    private let fileSystem: FileSystemProvider

    // MARK: - State

    /// Lazily built workspace index. Cleared when workspace roots change.
    private var cachedIndex: WorkspaceFileIndexService?
    private var cachedRoots: [String] = []

    // MARK: - Init

    init(
        resolver: PathMentionResolver? = nil,
        formatter: MentionFormatter? = nil,
        fileSystem: FileSystemProvider = RealFileSystemProvider()
    ) {
        self.resolver = resolver ?? PathMentionResolver()
        self.formatter = formatter ?? MentionFormatter()
        self.fileSystem = fileSystem
    }

    // MARK: - Public API

    /// Rewrite file mentions in transcribed text using app-specific mention syntax.
    ///
    /// - Parameters:
    ///   - text: The transcribed text (after dictionary replacements).
    ///   - capabilities: The active app's adapter capabilities.
    ///   - workspaceRoots: Workspace root paths to index for file resolution.
    ///   - activeDocumentPath: Optional path of the currently open document, used to
    ///     disambiguate when multiple files share the same filename.
    /// - Returns: A `MentionRewriteResult` with the (possibly rewritten) text.
    ///
    /// This method never throws. On any internal error, it returns the original
    /// text with `rewrittenCount = 0`.
    func rewrite(
        text: String,
        capabilities: AppAdapterCapabilities,
        workspaceRoots: [String],
        activeDocumentPath: String? = nil
    ) async -> MentionRewriteResult {
        await rewrite(
            text: text,
            capabilities: capabilities,
            workspaceRoots: workspaceRoots,
            activeDocumentPath: activeDocumentPath,
            mentionTemplateOverride: nil
        )
    }

    func rewriteToCanonicalPlaceholders(
        text: String,
        capabilities: AppAdapterCapabilities,
        workspaceRoots: [String],
        activeDocumentPath: String? = nil
    ) async -> MentionRewriteResult {
        await rewrite(
            text: text,
            capabilities: capabilities,
            workspaceRoots: workspaceRoots,
            activeDocumentPath: activeDocumentPath,
            mentionTemplateOverride: MentionTemplateCatalog.canonicalPlaceholderTemplate
        )
    }

    func renderCanonicalPlaceholders(
        in text: String,
        capabilities: AppAdapterCapabilities
    ) -> MentionRewriteResult {
        guard capabilities.supportsFileMentions else {
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }

        guard let regex = try? NSRegularExpression(pattern: #"\[\[:(.+?):\]\]"#) else {
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else {
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }

        var renderedText = text
        var rewrittenCount = 0
        var preservedCount = 0

        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range, in: renderedText),
                  let pathRange = Range(match.range(at: 1), in: renderedText) else {
                preservedCount += 1
                continue
            }

            let relativePath = renderedText[pathRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relativePath.isEmpty else {
                preservedCount += 1
                continue
            }

            renderedText.replaceSubrange(matchRange, with: capabilities.renderMention(path: relativePath))
            rewrittenCount += 1
        }

        return MentionRewriteResult(text: renderedText, rewrittenCount: rewrittenCount, preservedCount: preservedCount)
    }

    private func rewrite(
        text: String,
        capabilities: AppAdapterCapabilities,
        workspaceRoots: [String],
        activeDocumentPath: String? = nil,
        mentionTemplateOverride: String?
    ) async -> MentionRewriteResult {
        guard !text.isEmpty else {
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }
        // Guard: adapter must support file mentions
        guard capabilities.supportsFileMentions else {
            Log.context.debug("Mention rewrite skipped: adapter '\(capabilities.displayName)' does not support file mentions")
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }

        let effectiveCapabilities: AppAdapterCapabilities
        if let mentionTemplateOverride,
           mentionTemplateOverride.contains(MentionTemplateCatalog.pathToken) {
            effectiveCapabilities = capabilities.withMentionFormatting(
                prefix: capabilities.mentionPrefix,
                template: mentionTemplateOverride
            )
        } else {
            effectiveCapabilities = capabilities
        }
        // Normalize raw workspace roots (expand ~, strip file://, convert file→dir, climb to project root)
        let normalizedRoots = normalizeWorkspaceRoots(workspaceRoots)
        guard !normalizedRoots.isEmpty else {
            Log.context.debug("Mention rewrite skipped: no valid workspace roots after normalization")
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }
        // Build or reuse file index
        let index: WorkspaceFileIndexService
        do {
            index = try await getOrBuildIndex(roots: normalizedRoots)
        } catch {
            Log.context.error("Mention rewrite aborted: index build failed: \(error.localizedDescription)")
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }
        guard index.fileCount > 0 else {
            Log.context.debug("Mention rewrite skipped: workspace index is empty")
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }
        // Extract candidate mentions from the text
        let candidates = extractMentionCandidates(from: text, index: index)
        guard !candidates.isEmpty else {
            Log.context.debug("Mention rewrite: no candidate mentions found in text")
            return MentionRewriteResult(text: text, rewrittenCount: 0, preservedCount: 0)
        }

        Log.context.info("Mention rewrite: found \(candidates.count) candidate mention(s)")

        let normalizedActiveDoc = normalizeActiveDocumentPath(activeDocumentPath)
        // Resolve and format each candidate, building the rewritten text
        var rewrittenText = text
        var rewrittenCount = 0
        var preservedCount = 0
        // Process candidates in reverse order so range offsets remain valid
        for candidate in candidates.reversed() {
            if isLikelyMarkdownLinkTarget(candidate.range, in: text) {
                preservedCount += 1
                continue
            }
            let (replacementRange, originalCandidateText) = replacementRangeAndOriginalText(
                for: candidate,
                in: text
            )
            let resolution = resolver.resolve(mention: candidate.text, in: index, activeDocumentPath: normalizedActiveDoc)
            let formatted = formatter.formatMention(
                originalText: originalCandidateText,
                resolution: resolution,
                capabilities: effectiveCapabilities
            )
            switch formatted {
            case .formatted(let formattedText, let relativePath, let confidence):
                Log.context.info("Mention rewritten: '\(originalCandidateText)' → '\(formattedText)' (path: \(relativePath), confidence: \(String(format: "%.2f", confidence)))")
                rewrittenText.replaceSubrange(replacementRange, with: formattedText)
                rewrittenCount += 1
            case .preserved(_, let reason):
                Log.context.debug("Mention preserved: '\(originalCandidateText)' reason=\(String(describing: reason))")
                preservedCount += 1
            }
        }
        Log.context.info("Mention rewrite complete: \(rewrittenCount) rewritten, \(preservedCount) preserved")
        return MentionRewriteResult(
            text: rewrittenText,
            rewrittenCount: rewrittenCount,
            preservedCount: preservedCount
        )
    }

    /// Clear the cached workspace index.
    func clearCache() {
        cachedIndex = nil
        cachedRoots = []
    }

    private static let knownMentionPrefixCharacters: Set<Character> = ["@", "#", "/"]

    private func replacementRangeAndOriginalText(
        for candidate: ExtractedMention,
        in sourceText: String
    ) -> (Range<String.Index>, String) {
        var replacementStart = candidate.range.lowerBound

        while replacementStart > sourceText.startIndex {
            let previousIndex = sourceText.index(before: replacementStart)
            let previousCharacter = sourceText[previousIndex]
            guard Self.knownMentionPrefixCharacters.contains(previousCharacter) else { break }
            replacementStart = previousIndex
        }

        let replacementRange = replacementStart..<candidate.range.upperBound
        return (replacementRange, String(sourceText[replacementRange]))
    }

    private func isLikelyMarkdownLinkTarget(
        _ range: Range<String.Index>,
        in sourceText: String
    ) -> Bool {
        guard range.lowerBound > sourceText.startIndex else { return false }

        let openParenIndex = sourceText.index(before: range.lowerBound)
        guard sourceText[openParenIndex] == "(" else { return false }
        guard openParenIndex > sourceText.startIndex else { return false }

        let possibleBracketIndex = sourceText.index(before: openParenIndex)
        return sourceText[possibleBracketIndex] == "]"
    }


    // MARK: - Workspace Root Normalization

    /// Known project-root marker files/directories.
    private static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "package.json", ".xcodeproj",
        ".xcworkspace", "Cargo.toml", "go.mod", "pyproject.toml",
        "Makefile", ".project", "build.gradle", "pom.xml"
    ]

    /// Normalize raw workspace root paths into valid directory paths for indexing.
    /// Handles `file://` URLs, `~` expansion, file→directory conversion, and project marker climbing.
    func normalizeWorkspaceRoots(_ rawRoots: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in rawRoots {
            var path = raw

            // 1. Strip file:// URL scheme
            if path.hasPrefix("file://") {
                if let url = URL(string: path) {
                    path = url.path
                } else {
                    // Fallback: just strip the scheme manually
                    path = String(path.dropFirst("file://".count))
                }
            }

            // 2. Expand tilde
            path = (path as NSString).expandingTildeInPath

            // 3. Standardize path (resolve symlinks, double slashes, etc.)
            path = (path as NSString).standardizingPath

            // 4. If path points to a file (not directory), use its parent
            if !fileSystem.directoryExists(at: path) {
                let parent = (path as NSString).deletingLastPathComponent
                if fileSystem.directoryExists(at: parent) {
                    path = parent
                } else {
                    // Neither path nor parent is a valid directory — skip
                    Log.context.warning("Mention rewrite: skipping invalid root '\(raw)' (resolved to '\(path)', parent '\(parent)' also invalid)")
                    continue
                }
            }

            // 5. Climb up to find a project marker for better tree coverage
            path = climbToProjectRoot(from: path)

            // 6. Dedup
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(path)
        }

        if result.count != rawRoots.count {
            Log.context.debug("Mention rewrite: normalized \(rawRoots.count) raw root(s) → \(result.count) valid root(s)")
        }

        return result
    }

    /// Normalize an active document path: strip file://, expand ~, standardize.
    /// Returns nil if input is nil or empty after normalization.
    private func normalizeActiveDocumentPath(_ rawPath: String?) -> String? {
        guard var path = rawPath, !path.isEmpty else { return nil }

        if path.hasPrefix("file://") {
            if let url = URL(string: path) {
                path = url.path
            } else {
                path = String(path.dropFirst("file://".count))
            }
        }

        path = (path as NSString).expandingTildeInPath
        path = (path as NSString).standardizingPath

        return path.isEmpty ? nil : path
    }

    /// Walk up from `directory` looking for project marker directories (.git, .xcodeproj, etc.).
    /// Returns immediately on `.git` (strongest signal). Falls back to original directory.
    private func climbToProjectRoot(from directory: String) -> String {
        var current = directory
        let maxClimb = 8

        for _ in 0..<maxClimb {
            for marker in Self.projectMarkers {
                let markerPath = (current as NSString).appendingPathComponent(marker)
                if fileSystem.directoryExists(at: markerPath) {
                    if marker == ".git" { return current }
                    return current
                }
            }

            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }

        return directory
    }

    // MARK: - Index Management

    private func getOrBuildIndex(roots: [String]) async throws -> WorkspaceFileIndexService {
        // Reuse cached index if roots haven't changed
        if let cached = cachedIndex, cachedRoots == roots {
            return cached
        }

        let index = WorkspaceFileIndexService(fileSystem: fileSystem)
        let count = try await index.buildIndex(roots: roots)
        Log.context.info("Mention rewrite: built workspace index with \(count) files from \(roots.count) root(s)")

        cachedIndex = index
        cachedRoots = roots
        return index
    }

    // MARK: - Mention Extraction

    /// Extract candidate file mentions from transcribed text.
    ///
    /// Strategy: Look for words or word sequences that match known filenames
    /// or stems in the workspace index. This is a heuristic approach — we cast
    /// a wide net and let the resolver/formatter pipeline filter out false positives.
    ///
    /// Patterns detected:
    /// 0. Literal dotted filenames (e.g. "fixtures.go", "AppCoordinator.swift", "gen/fixtures.go")
    /// 1. Exact filenames spoken with "dot" (e.g. "app coordinator dot swift")
    /// 2. Known filename stems as standalone words (e.g. "AppCoordinator")
    /// 3. Multi-word sequences that normalize to known filenames
    func extractMentionCandidates(
        from text: String,
        index: WorkspaceFileIndexService
    ) -> [ExtractedMention] {
        var mentions: [ExtractedMention] = []

        // Pattern 0: Literal dotted filenames in text (e.g. "fixtures.go", "gen/fixtures.go")
        // The word tokenizer splits on "." so this pattern must run first to capture
        // filename.ext tokens as a single unit before they get broken apart.
        let literalFilePattern = #"(?<![/\w])(?:[a-zA-Z_]\w*(?:/[a-zA-Z_]\w*)*\.[a-zA-Z]\w*)(?![/\w])"#
        if let literalRegex = try? NSRegularExpression(pattern: literalFilePattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let literalMatches = literalRegex.matches(in: text, range: nsRange)
            for match in literalMatches {
                guard let range = Range(match.range, in: text) else { continue }
                let candidate = String(text[range])

                let filename = (candidate as NSString).lastPathComponent

                let hasFilenameMatch = !index.filesMatching(filename: filename).isEmpty
                let hasStemMatch = !index.filesMatching(stem: (filename as NSString).deletingPathExtension).isEmpty

                if hasFilenameMatch || hasStemMatch {
                    mentions.append(ExtractedMention(range: range, text: candidate))
                }
            }
        }

        // Pattern 1: Explicit "dot" patterns (e.g. "app coordinator dot swift")
        // Find each " dot " in the text, then try 1-3 word prefixes, preferring shortest match.
        let dotLocator = #"(?i)\s+dot\s+"#
        if let dotRegex = try? NSRegularExpression(pattern: dotLocator) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let dotMatches = dotRegex.matches(in: text, range: nsRange)
            for dotMatch in dotMatches {
                guard let dotRange = Range(dotMatch.range, in: text) else { continue }

                let afterDot = text[dotRange.upperBound...]
                let suffixPattern = #"^\w+"#
                guard let suffixRegex = try? NSRegularExpression(pattern: suffixPattern),
                      let suffixMatch = suffixRegex.firstMatch(in: String(afterDot), range: NSRange(afterDot.startIndex..., in: afterDot)),
                      let suffixRange = Range(suffixMatch.range, in: afterDot) else { continue }
                let suffix = String(afterDot[suffixRange])

                let beforeDot = text[text.startIndex..<dotRange.lowerBound]
                let prefixWords = beforeDot.split(separator: " ").map(String.init)
                guard !prefixWords.isEmpty else { continue }

                // Try prefix lengths 1-3 (shortest first) — prefer tighter matches
                for prefixLen in 1...min(3, prefixWords.count) {
                    let prefixSlice = prefixWords.suffix(prefixLen)
                    let candidate = prefixSlice.joined(separator: " ") + " dot " + suffix
                    let normalized = resolver.normalizeMention(candidate)
                    let compact = normalized.replacingOccurrences(of: " ", with: "")

                    if !index.filesMatching(filename: compact).isEmpty ||
                       !index.filesMatching(stem: compact).isEmpty {
                        // Calculate range: from start of first prefix word to end of suffix
                        let prefixStart = beforeDot.index(beforeDot.endIndex, offsetBy: -(prefixSlice.joined(separator: " ").count))
                        let candidateEnd = suffixRange.upperBound
                        let fullRange = prefixStart..<candidateEnd
                        mentions.append(ExtractedMention(range: fullRange, text: String(text[fullRange])))
                        break
                    }
                }
            }
        }

        // Pattern 2: Known filenames or stems as standalone words.
        // Always runs (even if Pattern 1 found matches) — overlap dedup prevents duplicates.
        let words = tokenizeForExtraction(text)
        if !words.isEmpty {
            for window in 1...min(3, words.count) {
                for startIdx in 0...(words.count - window) {
                    let slice = words[startIdx..<(startIdx + window)]
                    let candidateText = slice.map(\.text).joined(separator: " ")
                    let normalized = resolver.normalizeMention(candidateText)

                    // Check against index
                    let hasFilenameMatch = !index.filesMatching(filename: normalized).isEmpty
                    let hasStemMatch = !index.filesMatching(stem: normalized).isEmpty
                    let compactNormalized = normalized.replacingOccurrences(of: " ", with: "")
                    let hasCompactStemMatch = !index.filesMatching(stem: compactNormalized).isEmpty

                    if hasFilenameMatch || hasStemMatch || hasCompactStemMatch {
                        // Build the range from the first word's start to the last word's end
                        let rangeStart = slice.first!.range.lowerBound
                        let rangeEnd = slice.last!.range.upperBound
                        let fullRange = rangeStart..<rangeEnd

                        // Don't add overlapping mentions
                        let overlaps = mentions.contains { existing in
                            existing.range.overlaps(fullRange)
                        }
                        if !overlaps {
                            mentions.append(ExtractedMention(
                                range: fullRange,
                                text: String(text[fullRange])
                            ))
                        }
                    }
                }
            }
        }

        // Sort by position in text (ascending) for deterministic processing
        mentions.sort { $0.range.lowerBound < $1.range.lowerBound }

        return mentions
    }

    // MARK: - Text Tokenization for Extraction

    private struct WordToken {
        let text: String
        let range: Range<String.Index>
    }

    /// Tokenize text into word tokens with their positions.
    private func tokenizeForExtraction(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        let pattern = #"\b[\w]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return tokens
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        for match in matches {
            if let range = Range(match.range, in: text) {
                tokens.append(WordToken(text: String(text[range]), range: range))
            }
        }
        return tokens
    }

    // MARK: - Workspace Insights

    private static let maxFileTagCandidates = 8

    func deriveWorkspaceInsights(
        workspaceRoots: [String],
        activeDocumentPath: String? = nil,
        limit: Int = 8
    ) async -> WorkspaceContextInsights {
        let normalizedRoots = normalizeWorkspaceRoots(workspaceRoots)
        guard !normalizedRoots.isEmpty else { return .none }

        let index: WorkspaceFileIndexService
        do {
            index = try await getOrBuildIndex(roots: normalizedRoots)
        } catch {
            Log.context.warning("Workspace insights skipped: index build failed: \(error.localizedDescription)")
            return WorkspaceContextInsights(
                normalizedWorkspaceRoots: normalizedRoots,
                workspaceConfidence: 0.2,
                activeDocumentRelativePath: nil,
                activeDocumentConfidence: 0,
                fileTagCandidates: []
            )
        }

        guard index.fileCount > 0 else {
            return WorkspaceContextInsights(
                normalizedWorkspaceRoots: normalizedRoots,
                workspaceConfidence: 0.2,
                activeDocumentRelativePath: nil,
                activeDocumentConfidence: 0,
                fileTagCandidates: []
            )
        }

        let normalizedActiveDocument = normalizeActiveDocumentPath(activeDocumentPath)
        let activeDocumentRelativePath = normalizedActiveDocument.flatMap {
            resolveActiveDocumentRelativePath($0, roots: normalizedRoots)
        }

        let activeDocumentConfidence: Double
        if activeDocumentRelativePath != nil {
            activeDocumentConfidence = 1.0
        } else if normalizedActiveDocument != nil {
            activeDocumentConfidence = 0.45
        } else {
            activeDocumentConfidence = 0
        }

        let fileTagCandidates = buildFileTagCandidates(
            index: index,
            activeDocumentRelativePath: activeDocumentRelativePath,
            limit: max(1, limit)
        )

        return WorkspaceContextInsights(
            normalizedWorkspaceRoots: normalizedRoots,
            workspaceConfidence: 0.9,
            activeDocumentRelativePath: activeDocumentRelativePath,
            activeDocumentConfidence: activeDocumentConfidence,
            fileTagCandidates: fileTagCandidates
        )
    }

    private func buildFileTagCandidates(
        index: WorkspaceFileIndexService,
        activeDocumentRelativePath: String?,
        limit: Int
    ) -> [String] {
        let sortedPaths = index.allFiles.map(\.relativePath).sorted()
        var candidates: [String] = []

        if let activeDocumentRelativePath {
            candidates.append(activeDocumentRelativePath)

            let activeFilename = (activeDocumentRelativePath as NSString).lastPathComponent
            if !activeFilename.isEmpty {
                candidates.append(activeFilename)
            }

            let activeDirectory = (activeDocumentRelativePath as NSString).deletingLastPathComponent
            if !activeDirectory.isEmpty {
                for path in sortedPaths where path.hasPrefix(activeDirectory + "/") {
                    candidates.append(path)
                    if candidates.count >= limit * 2 {
                        break
                    }
                }
            }
        }

        candidates.append(contentsOf: sortedPaths)

        var deduped: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard !candidate.isEmpty else { continue }
            if seen.insert(candidate).inserted {
                deduped.append(candidate)
            }
            if deduped.count >= limit {
                break
            }
        }

        return deduped
    }


    // MARK: - Workspace Tree Summary

    private static let maxTreeEntries = 200

    func generateWorkspaceTreeSummary(
        workspaceRoots: [String],
        activeDocumentPath: String? = nil
    ) async -> String? {
        let normalizedRoots = normalizeWorkspaceRoots(workspaceRoots)
        guard !normalizedRoots.isEmpty else { return nil }

        let index: WorkspaceFileIndexService
        do {
            index = try await getOrBuildIndex(roots: normalizedRoots)
        } catch {
            Log.context.warning("Workspace tree summary skipped: index build failed: \(error.localizedDescription)")
            return nil
        }

        guard index.fileCount > 0 else { return nil }

        let sorted = index.allFiles.map(\.relativePath).sorted()
        let totalCount = sorted.count
        let sampled: [String]
        let isTruncated: Bool

        if totalCount <= Self.maxTreeEntries {
            sampled = sorted
            isTruncated = false
        } else {
            sampled = Array(sorted.prefix(Self.maxTreeEntries))
            isTruncated = true
        }

        var lines: [String] = []
        lines.append("total_files: \(totalCount)")

        if let activeDoc = activeDocumentPath {
            let resolved = resolveActiveDocumentRelativePath(activeDoc, roots: normalizedRoots)
            if let resolved {
                lines.append("active_document: \(resolved)")
            }
        }

        if isTruncated {
            lines.append("showing: \(sampled.count) of \(totalCount)")
        }

        lines.append("---")
        lines.append(contentsOf: sampled)

        return lines.joined(separator: "\n")
    }

    private func resolveActiveDocumentRelativePath(_ path: String, roots: [String]) -> String? {
        let expandedPath = (path as NSString).expandingTildeInPath
        for root in roots {
            if expandedPath.hasPrefix(root) {
                let relative = String(expandedPath.dropFirst(root.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relative.isEmpty { return relative }
            }
        }
        return nil
    }
}
