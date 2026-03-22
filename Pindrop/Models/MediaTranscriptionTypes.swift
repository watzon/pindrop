//
//  MediaTranscriptionTypes.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import Foundation
import Observation

enum MediaLibrarySortMode: String, CaseIterable, Equatable, Sendable {
    case newest
    case oldest
    case nameAscending
    case nameDescending

    var title: String {
        switch self {
        case .newest:
            return "Newest"
        case .oldest:
            return "Oldest"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        }
    }

    func title(locale: Locale) -> String {
        localized(title, locale: locale)
    }
}

enum MediaTranscriptionStage: String, CaseIterable, Equatable, Sendable {
    case preflight
    case importing
    case downloading
    case preparingAudio
    case transcribing
    case saving
    case completed
    case failed

    var title: String {
        switch self {
        case .preflight:
            return "Checking setup"
        case .importing:
            return "Importing media"
        case .downloading:
            return "Downloading media"
        case .preparingAudio:
            return "Preparing audio"
        case .transcribing:
            return "Transcribing"
        case .saving:
            return "Saving"
        case .completed:
            return "Finished"
        case .failed:
            return "Failed"
        }
    }

    func title(locale: Locale) -> String {
        localized(title, locale: locale)
    }
}

enum MediaTranscriptionRoute: Equatable, Sendable {
    case library
    case processing(UUID)
    case detail(UUID)
}

enum MediaTranscriptionRequest: Sendable, Equatable {
    case file(URL)
    case link(String)

    var sourceKind: MediaSourceKind {
        switch self {
        case .file:
            return .importedFile
        case .link:
            return .webLink
        }
    }

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .link(let string):
            return string
        }
    }
}

struct MediaTranscriptionJobState: Identifiable, Equatable, Sendable {
    let id: UUID
    var request: MediaTranscriptionRequest
    var destinationFolderID: UUID?
    var stage: MediaTranscriptionStage
    var progress: Double?
    var detail: String
    var errorMessage: String?
    var startedAt: Date

    init(
        id: UUID = UUID(),
        request: MediaTranscriptionRequest,
        destinationFolderID: UUID? = nil,
        stage: MediaTranscriptionStage = .preflight,
        progress: Double? = nil,
        detail: String = "",
        errorMessage: String? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.destinationFolderID = destinationFolderID
        self.stage = stage
        self.progress = progress
        self.detail = detail
        self.errorMessage = errorMessage
        self.startedAt = startedAt
    }
}

@MainActor
@Observable
final class MediaTranscriptionFeatureState {
    var route: MediaTranscriptionRoute = .library
    var selectedRecordID: UUID?
    var selectedFolderID: UUID?
    var currentJob: MediaTranscriptionJobState?
    var draftLink: String = ""
    var hasUserEditedDraftLink = false
    var librarySearchText: String = ""
    var librarySortMode: MediaLibrarySortMode = .newest
    var setupIssue: String?
    var libraryMessage: String?

    func beginJob(_ job: MediaTranscriptionJobState) {
        currentJob = job
        setupIssue = nil
        libraryMessage = nil
        route = .processing(job.id)
    }

    func updateJob(
        stage: MediaTranscriptionStage,
        progress: Double? = nil,
        detail: String? = nil,
        errorMessage: String? = nil
    ) {
        guard var job = currentJob else { return }
        job.stage = stage
        job.progress = progress
        if let detail {
            job.detail = detail
        }
        job.errorMessage = errorMessage
        currentJob = job
    }

    func exitProcessingView() {
        route = .library
    }

    func selectRecord(_ id: UUID) {
        selectedRecordID = id
        route = .detail(id)
        libraryMessage = nil
    }

    func showLibrary() {
        route = .library
    }

    func selectFolder(_ id: UUID) {
        selectedFolderID = id
        libraryMessage = nil
    }

    func clearSelectedFolder() {
        selectedFolderID = nil
    }

    func handleDeletedRecord(_ id: UUID, message: String = "Transcription deleted.") {
        if selectedRecordID == id {
            selectedRecordID = nil
        }

        if case .detail(let recordID) = route, recordID == id {
            route = .library
        }

        libraryMessage = message
    }

    func handleDeletedFolder(_ id: UUID, message: String = "Folder deleted.") {
        if selectedFolderID == id {
            selectedFolderID = nil
        }
        libraryMessage = message
    }

    func completeCurrentJob(with recordID: UUID, shouldNavigateToDetail: Bool) {
        updateJob(stage: .completed, progress: 1.0, detail: "Saved transcription")
        selectedRecordID = recordID
        if shouldNavigateToDetail {
            route = .detail(recordID)
        } else {
            route = .library
            libraryMessage = "Transcription finished."
        }
    }

    func failCurrentJob(_ message: String, returnToLibrary: Bool) {
        updateJob(stage: .failed, progress: nil, errorMessage: message)
        if returnToLibrary {
            route = .library
            libraryMessage = message
        }
    }

    func clearCurrentJob() {
        currentJob = nil
    }

    func setSetupIssue(_ message: String) {
        setupIssue = message
        route = .library
    }

    func updateDraftLinkFromClipboard(_ candidate: String) {
        guard !hasUserEditedDraftLink else { return }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, draftLink != trimmed else { return }
        draftLink = trimmed
    }
}
