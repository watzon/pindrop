//
//  MediaTranscriptionTypes.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import Foundation
import Observation

#if canImport(PindropSharedTranscription)
import PindropSharedTranscription
#endif

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
        applySharedSnapshot(
            KMPMediaTranscriptionBridge.beginJob(
                snapshot: sharedSnapshot(),
                job: job
            )
        )
    }

    func updateJob(
        stage: MediaTranscriptionStage,
        progress: Double? = nil,
        detail: String? = nil,
        errorMessage: String? = nil
    ) {
        applySharedSnapshot(
            KMPMediaTranscriptionBridge.updateJob(
                snapshot: sharedSnapshot(),
                stage: stage,
                progress: progress,
                detail: detail,
                errorMessage: errorMessage
            )
        )
    }

    func exitProcessingView() {
        showLibrary()
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
        if case .detail(let detailID) = route, detailID == id {
            route = .library
        }
        if selectedRecordID == id {
            selectedRecordID = nil
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
        applySharedSnapshot(
            KMPMediaTranscriptionBridge.completeCurrentJob(
                snapshot: sharedSnapshot(),
                recordID: recordID,
                shouldNavigateToDetail: shouldNavigateToDetail
            )
        )
    }

    func failCurrentJob(_ message: String, returnToLibrary: Bool) {
        applySharedSnapshot(
            KMPMediaTranscriptionBridge.failCurrentJob(
                snapshot: sharedSnapshot(),
                message: message,
                returnToLibrary: returnToLibrary
            )
        )
    }

    func clearCurrentJob() {
        currentJob = nil
    }

    func setSetupIssue(_ message: String) {
        setupIssue = message
        route = .library
    }

    func clearSetupIssue() {
        setupIssue = nil
    }

    func setLibraryMessage(_ message: String?) {
        libraryMessage = message
    }

    func updateDraftLinkFromClipboard(_ candidate: String) {
        guard !hasUserEditedDraftLink else { return }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, draftLink != trimmed else { return }
        draftLink = trimmed
    }

    private func sharedSnapshot() -> SharedMediaTranscriptionFeatureSnapshot {
        SharedMediaTranscriptionFeatureSnapshot(
            route: route,
            selectedRecordID: selectedRecordID,
            selectedFolderID: selectedFolderID,
            currentJob: currentJob,
            setupIssue: setupIssue,
            libraryMessage: libraryMessage
        )
    }

    private func applySharedSnapshot(_ snapshot: SharedMediaTranscriptionFeatureSnapshot) {
        route = snapshot.route
        selectedRecordID = snapshot.selectedRecordID
        selectedFolderID = snapshot.selectedFolderID
        currentJob = snapshot.currentJob
        setupIssue = snapshot.setupIssue
        libraryMessage = snapshot.libraryMessage
    }
}

struct SharedMediaTranscriptionFeatureSnapshot: Equatable, Sendable {
    let route: MediaTranscriptionRoute
    let selectedRecordID: UUID?
    let selectedFolderID: UUID?
    let currentJob: MediaTranscriptionJobState?
    let setupIssue: String?
    let libraryMessage: String?
}

enum KMPMediaTranscriptionBridge {
    static func beginJob(
        snapshot: SharedMediaTranscriptionFeatureSnapshot,
        job: MediaTranscriptionJobState
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        #if canImport(PindropSharedTranscription)
        let machine = MediaTranscriptionJobStateMachine.shared
        let transformed = machine.beginJob(
            snapshot: coreSnapshot(from: snapshot),
            job: coreJob(from: job)
        )
        return makeSharedSnapshot(from: transformed, currentJob: job)
        #else
        SharedMediaTranscriptionFeatureSnapshot(
            route: .processing(job.id),
            selectedRecordID: snapshot.selectedRecordID,
            selectedFolderID: snapshot.selectedFolderID,
            currentJob: job,
            setupIssue: nil,
            libraryMessage: nil
        )
        #endif
    }

    static func updateJob(
        snapshot: SharedMediaTranscriptionFeatureSnapshot,
        stage: MediaTranscriptionStage,
        progress: Double?,
        detail: String?,
        errorMessage: String?
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        #if canImport(PindropSharedTranscription)
        apply(snapshot) { machine, coreSnapshot in
            machine.updateJob(
                snapshot: coreSnapshot,
                update: JobProgressUpdate(
                    stage: coreStage(from: stage),
                    progress: progress.map(KotlinDouble.init(value:)),
                    detail: detail,
                    errorMessage: errorMessage
                )
            )
        }
        #else
        guard var job = snapshot.currentJob else { return snapshot }
        job.stage = stage
        job.progress = progress
        if let detail {
            job.detail = detail
        }
        job.errorMessage = errorMessage
        return SharedMediaTranscriptionFeatureSnapshot(
            route: snapshot.route,
            selectedRecordID: snapshot.selectedRecordID,
            selectedFolderID: snapshot.selectedFolderID,
            currentJob: job,
            setupIssue: snapshot.setupIssue,
            libraryMessage: snapshot.libraryMessage
        )
        #endif
    }

    static func completeCurrentJob(
        snapshot: SharedMediaTranscriptionFeatureSnapshot,
        recordID: UUID,
        shouldNavigateToDetail: Bool
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        #if canImport(PindropSharedTranscription)
        apply(snapshot) { machine, coreSnapshot in
            machine.completeCurrentJob(
                snapshot: coreSnapshot,
                recordId: recordID.uuidString,
                shouldNavigateToDetail: shouldNavigateToDetail
            )
        }
        #else
        let updated = updateJob(
            snapshot: snapshot,
            stage: .completed,
            progress: 1.0,
            detail: "Saved transcription",
            errorMessage: nil
        )
        return SharedMediaTranscriptionFeatureSnapshot(
            route: shouldNavigateToDetail ? .detail(recordID) : .library,
            selectedRecordID: recordID,
            selectedFolderID: updated.selectedFolderID,
            currentJob: updated.currentJob,
            setupIssue: updated.setupIssue,
            libraryMessage: shouldNavigateToDetail ? nil : "Transcription finished."
        )
        #endif
    }

    static func failCurrentJob(
        snapshot: SharedMediaTranscriptionFeatureSnapshot,
        message: String,
        returnToLibrary: Bool
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        #if canImport(PindropSharedTranscription)
        apply(snapshot) { machine, coreSnapshot in
            machine.failCurrentJob(
                snapshot: coreSnapshot,
                message: message,
                returnToLibrary: returnToLibrary
            )
        }
        #else
        let updated = updateJob(
            snapshot: snapshot,
            stage: .failed,
            progress: nil,
            detail: nil,
            errorMessage: message
        )
        guard returnToLibrary else { return updated }
        return SharedMediaTranscriptionFeatureSnapshot(
            route: .library,
            selectedRecordID: updated.selectedRecordID,
            selectedFolderID: updated.selectedFolderID,
            currentJob: updated.currentJob,
            setupIssue: updated.setupIssue,
            libraryMessage: message
        )
        #endif
    }

}

#if canImport(PindropSharedTranscription)
private extension KMPMediaTranscriptionBridge {
    static func apply(
        _ state: SharedMediaTranscriptionFeatureSnapshot,
        transform: (MediaTranscriptionJobStateMachine, MediaTranscriptionFeatureSnapshot) -> MediaTranscriptionFeatureSnapshot
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        let machine = MediaTranscriptionJobStateMachine.shared
        let transformed = transform(machine, coreSnapshot(from: state))
        return makeSharedSnapshot(
            from: transformed,
            currentJob: state.currentJob
        )
    }

    static func coreSnapshot(
        from snapshot: SharedMediaTranscriptionFeatureSnapshot
    ) -> MediaTranscriptionFeatureSnapshot {
        MediaTranscriptionFeatureSnapshot(
            route: coreRoute(from: snapshot.route),
            selectedRecordId: snapshot.selectedRecordID?.uuidString,
            selectedFolderId: snapshot.selectedFolderID?.uuidString,
            currentJob: snapshot.currentJob.map(coreJob(from:)),
            setupIssue: snapshot.setupIssue,
            libraryMessage: snapshot.libraryMessage
        )
    }

    static func makeSharedSnapshot(
        from coreSnapshot: MediaTranscriptionFeatureSnapshot,
        currentJob existingJob: MediaTranscriptionJobState?
    ) -> SharedMediaTranscriptionFeatureSnapshot {
        SharedMediaTranscriptionFeatureSnapshot(
            route: route(from: coreSnapshot.route, existingJob: existingJob),
            selectedRecordID: coreSnapshot.selectedRecordId.flatMap(UUID.init(uuidString:)),
            selectedFolderID: coreSnapshot.selectedFolderId.flatMap(UUID.init(uuidString:)),
            currentJob: jobState(from: coreSnapshot.currentJob, existingJob: existingJob),
            setupIssue: coreSnapshot.setupIssue,
            libraryMessage: coreSnapshot.libraryMessage
        )
    }

    static func coreRoute(from route: MediaTranscriptionRoute) -> PindropSharedTranscription.MediaTranscriptionRoute {
        switch route {
        case .library:
            return PindropSharedTranscription.MediaTranscriptionRoute.Library()
        case .processing(let jobID):
            return PindropSharedTranscription.MediaTranscriptionRoute.Processing(jobId: jobID.uuidString)
        case .detail(let recordID):
            return PindropSharedTranscription.MediaTranscriptionRoute.Detail(recordId: recordID.uuidString)
        }
    }

    static func route(
        from coreRoute: PindropSharedTranscription.MediaTranscriptionRoute,
        existingJob: MediaTranscriptionJobState?
    ) -> MediaTranscriptionRoute {
        if coreRoute is PindropSharedTranscription.MediaTranscriptionRoute.Library {
            return .library
        }
        if let processing = coreRoute as? PindropSharedTranscription.MediaTranscriptionRoute.Processing,
           let id = UUID(uuidString: processing.jobId) {
            return .processing(id)
        }
        if let detail = coreRoute as? PindropSharedTranscription.MediaTranscriptionRoute.Detail,
           let id = UUID(uuidString: detail.recordId) {
            return .detail(id)
        }
        if let existingJob {
            return .processing(existingJob.id)
        }
        return .library
    }

    static func coreJob(from job: MediaTranscriptionJobState) -> PindropSharedTranscription.MediaTranscriptionJob {
        PindropSharedTranscription.MediaTranscriptionJob(
            id: job.id.uuidString,
            requestDisplayName: job.request.displayName,
            stage: coreStage(from: job.stage),
            progress: job.progress.map(KotlinDouble.init(value:)),
            detail: job.detail,
            errorMessage: job.errorMessage
        )
    }

    static func jobState(
        from coreJob: PindropSharedTranscription.MediaTranscriptionJob?,
        existingJob: MediaTranscriptionJobState?
    ) -> MediaTranscriptionJobState? {
        guard let coreJob else { return nil }
        guard var existingJob else {
            return nil
        }

        existingJob.stage = stage(from: coreJob.stage)
        existingJob.progress = coreJob.progress?.doubleValue
        existingJob.detail = coreJob.detail
        existingJob.errorMessage = coreJob.errorMessage
        return existingJob
    }

    static func coreStage(from stage: MediaTranscriptionStage) -> PindropSharedTranscription.MediaTranscriptionStage {
        switch stage {
        case .preflight:
            .preflight
        case .importing:
            .importing
        case .downloading:
            .downloading
        case .preparingAudio:
            .preparingAudio
        case .transcribing:
            .transcribing
        case .saving:
            .saving
        case .completed:
            .completed
        case .failed:
            .failed
        }
    }

    static func stage(from stage: PindropSharedTranscription.MediaTranscriptionStage) -> MediaTranscriptionStage {
        switch stage {
        case .preflight:
            .preflight
        case .importing:
            .importing
        case .downloading:
            .downloading
        case .preparingAudio:
            .preparingAudio
        case .transcribing:
            .transcribing
        case .saving:
            .saving
        case .completed:
            .completed
        case .failed:
            .failed
        default:
            .preflight
        }
    }
}
#endif
