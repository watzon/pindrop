//
//  MentionFormatter.swift
//  Pindrop
//
//  Created on 2026-02-09.
//

import Foundation
import os.log

// MARK: - Mention Formatter Configuration

/// Configuration for mention formatting behavior.
struct MentionFormatterConfig: Sendable, Equatable {
    /// Minimum resolution confidence score to allow rewrite.
    /// Mentions resolved below this threshold are preserved as-is.
    let confidenceThreshold: Double

    /// When true, ambiguous resolutions are never rewritten.
    /// When false, the top candidate from ambiguous results is used
    /// (only if it meets the confidence threshold).
    let strictMode: Bool

    static let `default` = MentionFormatterConfig(
        confidenceThreshold: 0.5,
        strictMode: true
    )

    /// Permissive config for testing or known-good workspaces.
    static let permissive = MentionFormatterConfig(
        confidenceThreshold: 0.3,
        strictMode: false
    )
}

// MARK: - Formatted Mention Result

/// The result of formatting a single mention.
enum FormattedMentionResult: Equatable, Sendable {
    /// Mention was successfully rewritten to app-specific syntax.
    case formatted(text: String, relativePath: String, confidence: Double)

    /// Mention was preserved as-is (not rewritten).
    case preserved(originalText: String, reason: PreservationReason)

    var outputText: String {
        switch self {
        case .formatted(let text, _, _):
            return text
        case .preserved(let text, _):
            return text
        }
    }
}

/// Reason a mention was not rewritten.
enum PreservationReason: Equatable, Sendable {
    /// Resolution confidence was below the threshold.
    case lowConfidence(score: Double, threshold: Double)

    /// Resolution was ambiguous and strict mode is enabled.
    case ambiguousInStrictMode(candidateCount: Int)

    /// No candidates matched the mention.
    case unresolved

    /// The app adapter does not support file mentions.
    case unsupportedByAdapter(appName: String)

    /// The mention is already in app-specific formatted syntax.
    case alreadyFormatted
}

// MARK: - Batch Format Result

/// Result of formatting all mentions in a text string.
struct MentionFormatReport: Equatable, Sendable {
    /// The final output text with mentions formatted where possible.
    let formattedText: String

    /// Individual results for each mention processed.
    let mentionResults: [FormattedMentionResult]

    /// Mentions that were preserved (not rewritten) due to warnings.
    var preservedMentions: [FormattedMentionResult] {
        mentionResults.filter {
            if case .preserved = $0 { return true }
            return false
        }
    }

    /// Mentions that were successfully formatted.
    var formattedMentions: [FormattedMentionResult] {
        mentionResults.filter {
            if case .formatted = $0 { return true }
            return false
        }
    }

    /// Whether any mentions were skipped/preserved.
    var hasPreservedMentions: Bool {
        !preservedMentions.isEmpty
    }
}

// MARK: - Formatter Metrics

@MainActor
final class MentionFormatterMetrics {
    private(set) var totalMentions: Int = 0
    private(set) var formattedCount: Int = 0
    private(set) var preservedCount: Int = 0
    private(set) var lowConfidenceCount: Int = 0
    private(set) var ambiguousStrictCount: Int = 0
    private(set) var unresolvedCount: Int = 0
    private(set) var unsupportedCount: Int = 0
    private(set) var alreadyFormattedCount: Int = 0

    var preservedRate: Double {
        totalMentions > 0 ? Double(preservedCount) / Double(totalMentions) : 0
    }

    func record(_ result: FormattedMentionResult) {
        totalMentions += 1
        switch result {
        case .formatted:
            formattedCount += 1
        case .preserved(_, let reason):
            preservedCount += 1
            switch reason {
            case .lowConfidence:
                lowConfidenceCount += 1
            case .ambiguousInStrictMode:
                ambiguousStrictCount += 1
            case .unresolved:
                unresolvedCount += 1
            case .unsupportedByAdapter:
                unsupportedCount += 1
            case .alreadyFormatted:
                alreadyFormattedCount += 1
            }
        }
    }

    func reset() {
        totalMentions = 0
        formattedCount = 0
        preservedCount = 0
        lowConfidenceCount = 0
        ambiguousStrictCount = 0
        unresolvedCount = 0
        unsupportedCount = 0
        alreadyFormattedCount = 0
    }
}

// MARK: - Mention Formatter

/// Converts resolved path mentions to app-specific mention syntax.
///
/// The formatter is deterministic and idempotent:
/// - Already-formatted mentions are detected and preserved.
/// - Unresolved and low-confidence mentions are never rewritten.
/// - Strict mode prevents rewriting ambiguous resolutions.
///
/// ## Usage
/// ```swift
/// let formatter = MentionFormatter()
/// let result = formatter.formatMention(
///     originalText: "app coordinator",
///     resolution: .resolved(candidate),
///     capabilities: cursorAdapter.capabilities
/// )
/// ```
@MainActor
final class MentionFormatter {

    private let config: MentionFormatterConfig
    let metrics = MentionFormatterMetrics()

    init(config: MentionFormatterConfig = .default) {
        self.config = config
    }

    // MARK: - Single Mention Formatting

    /// Format a single mention based on its resolution result and the target app's capabilities.
    ///
    /// - Parameters:
    ///   - originalText: The raw transcribed mention text.
    ///   - resolution: The path resolution result from `PathMentionResolver`.
    ///   - capabilities: The target app's declared capabilities.
    /// - Returns: A `FormattedMentionResult` describing what happened.
    func formatMention(
        originalText: String,
        resolution: PathResolutionResult,
        capabilities: AppAdapterCapabilities
    ) -> FormattedMentionResult {

        // Check if already formatted (idempotency guard)
        if isAlreadyFormatted(originalText, prefix: capabilities.mentionPrefix) {
            Log.context.debug("Mention already formatted, preserving: \(originalText)")
            let result = FormattedMentionResult.preserved(originalText: originalText, reason: .alreadyFormatted)
            metrics.record(result)
            return result
        }

        // Check adapter support
        guard capabilities.supportsFileMentions else {
            Log.context.info("App '\(capabilities.displayName)' does not support file mentions, preserving: \(originalText)")
            let result = FormattedMentionResult.preserved(
                originalText: originalText,
                reason: .unsupportedByAdapter(appName: capabilities.displayName)
            )
            metrics.record(result)
            return result
        }

        let result: FormattedMentionResult
        switch resolution {
        case .resolved(let candidate):
            result = formatResolved(
                originalText: originalText,
                candidate: candidate,
                capabilities: capabilities
            )

        case .ambiguous(let candidates):
            result = formatAmbiguous(
                originalText: originalText,
                candidates: candidates,
                capabilities: capabilities
            )

        case .unresolved:
            Log.context.debug("Mention unresolved, preserving: \(originalText)")
            result = .preserved(originalText: originalText, reason: .unresolved)
        }

        metrics.record(result)
        return result
    }

    // MARK: - Batch Formatting

    /// Format multiple mentions in sequence, producing a report.
    ///
    /// - Parameters:
    ///   - mentions: Array of (originalText, resolution) pairs.
    ///   - capabilities: The target app's declared capabilities.
    /// - Returns: A `MentionFormatReport` with all results.
    func formatMentions(
        _ mentions: [(originalText: String, resolution: PathResolutionResult)],
        capabilities: AppAdapterCapabilities
    ) -> MentionFormatReport {
        var results: [FormattedMentionResult] = []
        var outputParts: [String] = []

        for mention in mentions {
            let result = formatMention(
                originalText: mention.originalText,
                resolution: mention.resolution,
                capabilities: capabilities
            )
            results.append(result)
            outputParts.append(result.outputText)
        }

        let formattedText = outputParts.joined(separator: " ")

        let batchPreserved = results.filter { if case .preserved = $0 { return true }; return false }.count
        let batchFormatted = results.count - batchPreserved
        Log.context.info("Mention format batch: total=\(results.count) formatted=\(batchFormatted) preserved=\(batchPreserved) cumulativeTotal=\(self.metrics.totalMentions) preservedRate=\(String(format: "%.2f", self.metrics.preservedRate))")

        return MentionFormatReport(
            formattedText: formattedText,
            mentionResults: results
        )
    }

    // MARK: - Private Helpers

    private func formatResolved(
        originalText: String,
        candidate: PathCandidate,
        capabilities: AppAdapterCapabilities
    ) -> FormattedMentionResult {
        // Confidence gating
        guard candidate.score >= config.confidenceThreshold else {
            Log.context.info(
                "Mention confidence \(candidate.score) below threshold \(self.config.confidenceThreshold), preserving: \(originalText)"
            )
            return .preserved(
                originalText: originalText,
                reason: .lowConfidence(
                    score: candidate.score,
                    threshold: config.confidenceThreshold
                )
            )
        }

        let formatted = buildFormattedMention(
            relativePath: candidate.file.relativePath,
            prefix: capabilities.mentionPrefix
        )

        Log.context.debug(
            "Formatted mention '\(originalText)' → '\(formatted)' (confidence: \(candidate.score))"
        )

        return .formatted(
            text: formatted,
            relativePath: candidate.file.relativePath,
            confidence: candidate.score
        )
    }

    private func formatAmbiguous(
        originalText: String,
        candidates: [PathCandidate],
        capabilities: AppAdapterCapabilities
    ) -> FormattedMentionResult {
        if config.strictMode {
            Log.context.info(
                "Ambiguous mention with \(candidates.count) candidates in strict mode, preserving: \(originalText)"
            )
            return .preserved(
                originalText: originalText,
                reason: .ambiguousInStrictMode(candidateCount: candidates.count)
            )
        }

        // Non-strict: use top candidate if it meets threshold
        guard let topCandidate = candidates.first else {
            return .preserved(originalText: originalText, reason: .unresolved)
        }

        return formatResolved(
            originalText: originalText,
            candidate: topCandidate,
            capabilities: capabilities
        )
    }

    /// Build the app-specific mention string.
    /// Example: prefix="@", path="Pindrop/Services/AppCoordinator.swift"
    /// → "@Pindrop/Services/AppCoordinator.swift"
    private func buildFormattedMention(relativePath: String, prefix: String) -> String {
        "\(prefix)\(relativePath)"
    }

    /// Detect if a mention is already in formatted syntax.
    /// A mention is considered already formatted if it starts with the app's
    /// mention prefix followed by a path-like string (containing "/" or ".").
    func isAlreadyFormatted(_ text: String, prefix: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix(prefix) else { return false }

        let afterPrefix = String(trimmed.dropFirst(prefix.count))
        guard !afterPrefix.isEmpty else { return false }

        // Check for path-like content after prefix:
        // Must contain "/" or "." to distinguish from regular words starting with the prefix
        let hasPathSeparator = afterPrefix.contains("/")
        let hasExtension = afterPrefix.contains(".")

        return hasPathSeparator || hasExtension
    }
}
