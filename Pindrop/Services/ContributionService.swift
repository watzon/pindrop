//
//  ContributionService.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  Captures opt-in training-data contributions: before/after transcript text
//  pairs that could eventually train an on-device transcript-correction model
//  (docs/transcript-post-processing-model-research.md, Phase 5). Everything is
//  gated on `SettingsStore.trainingDataContributionEnabled` (off by default),
//  redacted at capture time, and stored only in the local SwiftData store. The
//  uploader seam is NoOp — nothing is ever transmitted.
//

import Foundation
import SwiftData

@MainActor
final class ContributionService {
    private let modelContext: ModelContext
    private let settingsStore: SettingsStore
    private let redactor: TrainingTextRedactor
    private let uploader: ContributionUploader

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore,
        redactor: TrainingTextRedactor = TrainingTextRedactor(),
        uploader: ContributionUploader? = nil
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.redactor = redactor
        self.uploader = uploader ?? NoOpContributionUploader()
    }

    // MARK: - Capture

    /// Records a raw-ASR → AI-enhanced pair. No-op unless the user opted in.
    func recordAIEnhancementPair(
        input: String,
        target: String,
        modelUsed: String?,
        enhancedWith: String?,
        sourceRecordID: UUID?
    ) {
        record(
            kind: .aiEnhancement,
            input: input,
            target: target,
            modelUsed: modelUsed,
            enhancedWith: enhancedWith,
            sourceRecordID: sourceRecordID
        )
    }

    /// Records a pre-edit → user-corrected pair. No-op unless the user opted in.
    func recordManualEdit(
        input: String,
        target: String,
        modelUsed: String?,
        sourceRecordID: UUID?
    ) {
        record(
            kind: .manualEdit,
            input: input,
            target: target,
            modelUsed: modelUsed,
            enhancedWith: nil,
            sourceRecordID: sourceRecordID
        )
    }

    private func record(
        kind: TrainingContributionKind,
        input: String,
        target: String,
        modelUsed: String?,
        enhancedWith: String?,
        sourceRecordID: UUID?
    ) {
        guard settingsStore.trainingDataContributionEnabled else { return }

        let redactedInput = redactor.redact(input)
        let redactedTarget = redactor.redact(target)

        // Identity pairs teach nothing the identity split can't; skip them.
        let trimmedInput = redactedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = redactedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !trimmedTarget.isEmpty, trimmedInput != trimmedTarget else {
            return
        }

        let contribution = TrainingContribution(
            kind: kind,
            inputText: redactedInput,
            targetText: redactedTarget,
            modelUsed: modelUsed,
            enhancedWith: enhancedWith,
            language: settingsStore.selectedAppLanguage.rawValue,
            locale: settingsStore.selectedAppLocale.locale.identifier,
            appVersion: Bundle.main.appShortVersionString,
            sourceRecordID: sourceRecordID,
            redactionVersion: TrainingTextRedactor.version
        )
        modelContext.insert(contribution)
        do {
            try modelContext.save()
        } catch {
            Log.telemetry.error("Failed to save training contribution: \(error.localizedDescription)")
            return
        }
        Log.telemetry.info("Stored training contribution kind=\(kind.rawValue)")
        uploader.enqueue(contribution)
    }

    // MARK: - Review / export / delete

    func count() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<TrainingContribution>())) ?? 0
    }

    func fetchAll() throws -> [TrainingContribution] {
        try modelContext.fetch(
            FetchDescriptor<TrainingContribution>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    func deleteAll() throws {
        try Self.deleteAll(in: modelContext)
    }

    /// Shared mutation used by both the service and the Privacy settings pane
    /// (which reaches the same store through its SwiftUI model context).
    static func deleteAll(in modelContext: ModelContext) throws {
        try modelContext.delete(model: TrainingContribution.self)
        try modelContext.save()
    }

    // MARK: - JSONL export

    /// One JSON object per line, keyed to align with the canonical example schema
    /// in docs/transcript-post-processing-model-research.md §7. `sourceRecordID`
    /// is intentionally not exported.
    static func jsonlData(from contributions: [TrainingContribution]) -> Data {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.reserveCapacity(contributions.count)

        for contribution in contributions {
            let transformationType: String
            switch contribution.kind {
            case .aiEnhancement: transformationType = "ai_enhancement"
            case .manualEdit: transformationType = "manual_edit"
            case nil: transformationType = contribution.kindRawValue
            }

            var object: [String: Any] = [
                "example_id": contribution.id.uuidString,
                "created_at": formatter.string(from: contribution.createdAt),
                "input_text": contribution.inputText,
                "target_text": contribution.targetText,
                "primary_transformation_type": transformationType,
                "synthetic_or_observed": "observed",
                "redaction_version": contribution.redactionVersion,
                "source": "pindrop-first-party"
            ]
            object["language"] = contribution.language
            object["locale"] = contribution.locale
            object["recognizer"] = contribution.modelUsed
            object["enhanced_with"] = contribution.enhancedWith
            object["app_version"] = contribution.appVersion

            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else {
                continue
            }
            lines.append(line)
        }

        return Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
    }
}
