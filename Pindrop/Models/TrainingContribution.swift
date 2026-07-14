//
//  TrainingContribution.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  One locally stored before/after text pair for the opt-in training-data
//  contribution program (Settings → Privacy). Rows exist only when the user has
//  enabled contribution; both texts are redacted at capture time and never leave
//  this Mac — `uploadStateRawValue` stays `pending` until a future release ships
//  a real uploader (see ContributionUploader).
//

import Foundation
import SwiftData

enum TrainingContributionKind: String {
    /// Raw ASR output → AI-enhanced text, captured when a dictation is saved.
    case aiEnhancement
    /// Pre-edit transcript → user-corrected text, captured on a library edit.
    case manualEdit
}

enum TrainingContributionUploadState: String {
    case pending
    case uploaded
    case skipped
}

@Model
final class TrainingContribution {

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var kindRawValue: String
    /// Redacted input text (the "before" side of the pair).
    var inputText: String
    /// Redacted target text (the "after" side of the pair).
    var targetText: String
    /// Recognizer model that produced the input (e.g. "parakeet-tdt-0.6b-v3").
    var modelUsed: String?
    /// AI model that produced the target for aiEnhancement pairs.
    var enhancedWith: String?
    /// Dictation language setting at capture time (AppLanguage raw value).
    var language: String?
    /// Interface locale identifier at capture time.
    var locale: String?
    var appVersion: String?
    /// Source TranscriptionRecord for dedup/delete bookkeeping. Never exported.
    var sourceRecordID: UUID?
    /// Version of TrainingTextRedactor that produced the stored texts.
    var redactionVersion: Int
    var uploadStateRawValue: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: TrainingContributionKind,
        inputText: String,
        targetText: String,
        modelUsed: String? = nil,
        enhancedWith: String? = nil,
        language: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        sourceRecordID: UUID? = nil,
        redactionVersion: Int,
        uploadState: TrainingContributionUploadState = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRawValue = kind.rawValue
        self.inputText = inputText
        self.targetText = targetText
        self.modelUsed = modelUsed
        self.enhancedWith = enhancedWith
        self.language = language
        self.locale = locale
        self.appVersion = appVersion
        self.sourceRecordID = sourceRecordID
        self.redactionVersion = redactionVersion
        self.uploadStateRawValue = uploadState.rawValue
    }

    var kind: TrainingContributionKind? {
        TrainingContributionKind(rawValue: kindRawValue)
    }

    var uploadState: TrainingContributionUploadState {
        TrainingContributionUploadState(rawValue: uploadStateRawValue) ?? .pending
    }
}
