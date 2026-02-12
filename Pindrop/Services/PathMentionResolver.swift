//
//  PathMentionResolver.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import os.log

// MARK: - Resolution Result Types

/// A scored candidate file from the resolution pipeline.
struct PathCandidate: Sendable, Equatable {
    let file: IndexedFile
    let score: Double

    /// Deterministic ordering: score descending, then relative path ascending.
    static func deterministicOrder(_ a: PathCandidate, _ b: PathCandidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.file.relativePath < b.file.relativePath
    }
}

/// Result of resolving a spoken path mention against the workspace index.
enum PathResolutionResult: Sendable, Equatable {
    /// Single unambiguous match above threshold.
    case resolved(PathCandidate)

    /// Multiple candidates too close in score to pick one.
    /// Sorted by `PathCandidate.deterministicOrder`.
    case ambiguous([PathCandidate])

    /// No candidates matched above the minimum threshold.
    case unresolved(query: String)
}

// MARK: - Resolver Configuration

struct PathResolverConfig: Sendable {
    /// Minimum score a candidate must reach to be considered at all.
    let minimumThreshold: Double

    /// Maximum score difference between top candidate and runner-up
    /// for the result to be considered unambiguous.
    let ambiguityMargin: Double

    static let `default` = PathResolverConfig(
        minimumThreshold: 0.3,
        ambiguityMargin: 0.15
    )
}

// MARK: - Scoring Constants

/// Deterministic, tunable weights for each scoring stage.
/// All scores are normalized to [0, 1] before combining.
enum PathScoringWeights {
    static let exactFilenameMatch: Double = 1.0
    static let exactStemMatch: Double = 0.9
    static let tokenizedSegmentMatch: Double = 0.7
    static let fuzzyMatch: Double = 0.5
    static let recencyBoostMax: Double = 0.1
}

// MARK: - Resolver Metrics

@MainActor
final class PathResolverMetrics {
    private(set) var resolveCount: Int = 0
    private(set) var resolvedCount: Int = 0
    private(set) var ambiguousCount: Int = 0
    private(set) var unresolvedCount: Int = 0

    var ambiguityRate: Double {
        resolveCount > 0 ? Double(ambiguousCount) / Double(resolveCount) : 0
    }

    var unresolvedRate: Double {
        resolveCount > 0 ? Double(unresolvedCount) / Double(resolveCount) : 0
    }

    func record(_ result: PathResolutionResult) {
        resolveCount += 1
        switch result {
        case .resolved:
            resolvedCount += 1
        case .ambiguous:
            ambiguousCount += 1
        case .unresolved:
            unresolvedCount += 1
        }
    }

    func reset() {
        resolveCount = 0
        resolvedCount = 0
        ambiguousCount = 0
        unresolvedCount = 0
    }
}

// MARK: - Path Mention Resolver

/// Resolves spoken/transcribed path mentions to actual workspace files
/// using a deterministic scoring pipeline.
///
/// Pipeline stages (in priority order):
/// 1. Exact filename match (e.g. "AppCoordinator.swift")
/// 2. Exact stem match (e.g. "AppCoordinator" → AppCoordinator.swift)
/// 3. Tokenized segment match (e.g. "app coordinator" → AppCoordinator)
/// 4. Fuzzy substring match
/// 5. Recency boost (optional, based on access timestamps)
///
/// Ambiguity: When the top two candidates are within `ambiguityMargin`,
/// returns `.ambiguous` with all qualifying candidates instead of guessing.
@MainActor
final class PathMentionResolver {

    private let config: PathResolverConfig
    private var recentAccessTimes: [String: Date] = [:]
    let metrics = PathResolverMetrics()

    init(config: PathResolverConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    func resolve(
        mention: String,
        in index: WorkspaceFileIndexService,
        activeDocumentPath: String? = nil
    ) -> PathResolutionResult {
        let normalizedMention = normalizeMention(mention)

        guard !normalizedMention.isEmpty else {
            let result = PathResolutionResult.unresolved(query: mention)
            recordAndLogResult(result)
            return result
        }

        var candidates: [PathCandidate] = []

        // Stage 1: Exact filename match
        let exactFilenameMatches = index.filesMatching(filename: normalizedMention)
        for file in exactFilenameMatches {
            candidates.append(PathCandidate(
                file: file,
                score: PathScoringWeights.exactFilenameMatch + recencyBoost(for: file)
            ))
        }

        // Stage 2: Exact stem match (only if no exact filename match)
        if candidates.isEmpty {
            let stemQuery = normalizedMention.contains(".")
                ? URL(fileURLWithPath: normalizedMention).deletingPathExtension().lastPathComponent
                : normalizedMention
            let stemMatches = index.filesMatching(stem: stemQuery)
            for file in stemMatches {
                candidates.append(PathCandidate(
                    file: file,
                    score: PathScoringWeights.exactStemMatch + recencyBoost(for: file)
                ))
            }
        }

        // Stage 3: Tokenized segment match
        if candidates.isEmpty {
            let tokens = tokenize(normalizedMention)
            if !tokens.isEmpty {
                for file in index.allFiles {
                    let segmentScore = tokenizedSegmentScore(tokens: tokens, file: file)
                    if segmentScore > 0 {
                        let score = PathScoringWeights.tokenizedSegmentMatch * segmentScore
                            + recencyBoost(for: file)
                        candidates.append(PathCandidate(file: file, score: score))
                    }
                }
            }
        }

        // Stage 4: Fuzzy substring match
        if candidates.isEmpty {
            let compactQuery = normalizedMention
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            for file in index.allFiles {
                let fuzzyScore = fuzzyMatchScore(query: compactQuery, target: file.lowercasedFilename)
                if fuzzyScore > 0 {
                    let score = PathScoringWeights.fuzzyMatch * fuzzyScore
                        + recencyBoost(for: file)
                    candidates.append(PathCandidate(file: file, score: score))
                }
            }
        }

        candidates = candidates.filter { $0.score >= config.minimumThreshold }

        guard !candidates.isEmpty else {
            let result = PathResolutionResult.unresolved(query: mention)
            recordAndLogResult(result)
            return result
        }

        candidates.sort(by: PathCandidate.deterministicOrder)

        if candidates.count == 1 {
            let result = PathResolutionResult.resolved(candidates[0])
            recordAndLogResult(result)
            return result
        }

        let topScore = candidates[0].score
        let runnerUpScore = candidates[1].score
        let margin = topScore - runnerUpScore

        if margin >= config.ambiguityMargin {
            let result = PathResolutionResult.resolved(candidates[0])
            recordAndLogResult(result)
            return result
        }

        // Active document disambiguation: when ambiguous, prefer the candidate
        // matching the currently open file (if provided).
        if let activeDoc = activeDocumentPath {
            let normalizedActiveDoc = (activeDoc as NSString).standardizingPath
            if let activeCandidate = candidates.first(where: { $0.file.absolutePath == normalizedActiveDoc }) {
                Log.context.info("Path resolve: disambiguated via active document → \(activeCandidate.file.relativePath)")
                let result = PathResolutionResult.resolved(activeCandidate)
                recordAndLogResult(result)
                return result
            }

            // Directory-level disambiguation: if exactly one top-tier candidate is in
            // the same directory as the active document, prefer it deterministically.
            let activeDirectory = (normalizedActiveDoc as NSString).deletingLastPathComponent
            if !activeDirectory.isEmpty {
                let sameDirectoryCandidates = candidates.filter { candidate in
                    topScore - candidate.score < config.ambiguityMargin
                        && ((candidate.file.absolutePath as NSString).deletingLastPathComponent == activeDirectory)
                }

                if sameDirectoryCandidates.count == 1, let directoryCandidate = sameDirectoryCandidates.first {
                    Log.context.info("Path resolve: disambiguated via active document directory → \(directoryCandidate.file.relativePath)")
                    let result = PathResolutionResult.resolved(directoryCandidate)
                    recordAndLogResult(result)
                    return result
                }
            }
        }
        let ambiguousCandidates = candidates.filter {
            topScore - $0.score < config.ambiguityMargin
        }
        let result = PathResolutionResult.ambiguous(ambiguousCandidates)
        recordAndLogResult(result)
        return result
    }

    private func recordAndLogResult(_ result: PathResolutionResult) {
        metrics.record(result)
        switch result {
        case .resolved(let candidate):
            Log.context.info("Path resolve: outcome=resolved score=\(String(format: "%.2f", candidate.score)) total=\(self.metrics.resolveCount) ambiguityRate=\(String(format: "%.2f", self.metrics.ambiguityRate)) unresolvedRate=\(String(format: "%.2f", self.metrics.unresolvedRate))")
        case .ambiguous(let candidates):
            Log.context.info("Path resolve: outcome=ambiguous candidateCount=\(candidates.count) total=\(self.metrics.resolveCount) ambiguityRate=\(String(format: "%.2f", self.metrics.ambiguityRate))")
        case .unresolved:
            Log.context.info("Path resolve: outcome=unresolved total=\(self.metrics.resolveCount) unresolvedRate=\(String(format: "%.2f", self.metrics.unresolvedRate))")
        }
    }

    // MARK: - Recency Tracking

    func recordAccess(for file: IndexedFile, at date: Date = Date()) {
        recentAccessTimes[file.absolutePath] = date
    }

    func clearRecencyData() {
        recentAccessTimes.removeAll()
    }

    // MARK: - Mention Normalization

    /// Converts spoken mention forms to filesystem-friendly queries.
    /// "app coordinator dot swift" → "appcoordinator.swift"
    /// "App Coordinator" → "appcoordinator"
    func normalizeMention(_ mention: String) -> String {
        var result = mention
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        result = result.replacingOccurrences(of: " dot ", with: ".")
        result = result.replacingOccurrences(
            of: #"dot\s+(\w+)$"#,
            with: ".$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: " slash ", with: "/")

        return result
    }

    // MARK: - Tokenization

    /// Splits a mention into searchable tokens.
    /// "services app coordinator" → ["services", "app", "coordinator"]
    private func tokenize(_ mention: String) -> [String] {
        mention
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Scoring Functions

    /// Score how well tokens match a file's path segments and filename.
    /// Returns 0..1 normalized score.
    private func tokenizedSegmentScore(tokens: [String], file: IndexedFile) -> Double {
        guard !tokens.isEmpty else { return 0 }

        var matchedTokens = 0
        let lowercasedSegments = file.pathSegments.map { $0.lowercased() }
        let stemLower = file.lowercasedStem

        for token in tokens {
            let segmentMatch = lowercasedSegments.contains { segment in
                segment.contains(token)
            }
            let camelTokens = camelCaseSplit(stemLower)
            let stemMatch = camelTokens.contains { $0.hasPrefix(token) || $0 == token }

            if segmentMatch || stemMatch {
                matchedTokens += 1
            }
        }

        return Double(matchedTokens) / Double(tokens.count)
    }

    /// Simple fuzzy match: checks if all characters of query appear
    /// in order within target. Returns 0..1 based on coverage.
    private func fuzzyMatchScore(query: String, target: String) -> Double {
        guard !query.isEmpty, !target.isEmpty else { return 0 }

        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var matchCount = 0

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                matchCount += 1
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        guard queryIndex == query.endIndex else { return 0 }

        return Double(matchCount) / Double(target.count)
    }

    private func recencyBoost(for file: IndexedFile) -> Double {
        guard let accessTime = recentAccessTimes[file.absolutePath] else { return 0 }
        let age = Date().timeIntervalSince(accessTime)
        let decayOverOneHour = max(0, 1.0 - (age / 3600.0))
        return PathScoringWeights.recencyBoostMax * decayOverOneHour
    }

    // MARK: - Helpers

    /// Split camelCase/PascalCase into lowercase tokens.
    /// "AppCoordinator" → ["app", "coordinator"]
    private func camelCaseSplit(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in input {
            if char.isUppercase && !current.isEmpty {
                tokens.append(current.lowercased())
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }
}
