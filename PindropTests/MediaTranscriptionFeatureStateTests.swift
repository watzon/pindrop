//
//  MediaTranscriptionFeatureStateTests.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct MediaTranscriptionFeatureStateTests {
    @Test func clipboardPrefillDoesNotOverwriteUserEditedDraft() {
        let sut = MediaTranscriptionFeatureState()
        sut.draftLink = "https://user-entered.example"
        sut.hasUserEditedDraftLink = true

        sut.updateDraftLinkFromClipboard("https://clipboard.example")

        #expect(sut.draftLink == "https://user-entered.example")
    }

    @Test func completeCurrentJobNavigatesToDetailWhenRequested() {
        let sut = MediaTranscriptionFeatureState()
        let recordID = UUID()
        let job = MediaTranscriptionJobState(
            id: UUID(),
            request: .link("https://example.com/video"),
            stage: .transcribing,
            progress: 0.8,
            detail: "Transcribing"
        )

        sut.beginJob(job)
        sut.completeCurrentJob(with: recordID, shouldNavigateToDetail: true)

        #expect(sut.route == .detail(recordID))
        #expect(sut.selectedRecordID == recordID)
        #expect(sut.currentJob?.stage == .completed)
        #expect(sut.currentJob?.progress == 1.0)
        #expect(sut.currentJob?.detail == "Saved transcription")
    }

    @Test func completeCurrentJobReturnsToLibraryWhenProcessingViewExited() {
        let sut = MediaTranscriptionFeatureState()
        let recordID = UUID()
        let job = MediaTranscriptionJobState(
            id: UUID(),
            request: .file(URL(fileURLWithPath: "/tmp/example.mov")),
            stage: .preparingAudio,
            detail: "Preparing audio"
        )

        sut.beginJob(job)
        sut.exitProcessingView()
        sut.completeCurrentJob(with: recordID, shouldNavigateToDetail: false)

        #expect(sut.route == .library)
        #expect(sut.selectedRecordID == recordID)
        #expect(sut.libraryMessage == "Transcription finished.")
    }

    @Test func selectedFolderPersistsAcrossRouteChanges() {
        let sut = MediaTranscriptionFeatureState()
        let folderID = UUID()
        let recordID = UUID()

        sut.selectFolder(folderID)
        sut.selectRecord(recordID)
        sut.showLibrary()

        #expect(sut.selectedFolderID == folderID)
        #expect(sut.route == .library)
    }

    @Test func deletingSelectedFolderClearsFolderSelection() {
        let sut = MediaTranscriptionFeatureState()
        let folderID = UUID()

        sut.selectFolder(folderID)
        sut.handleDeletedFolder(folderID)

        #expect(sut.selectedFolderID == nil)
    }

    @Test func setupIssueAndLibraryMessageFollowSharedStateMachine() {
        let sut = MediaTranscriptionFeatureState()

        sut.setSetupIssue("ffmpeg missing")
        #expect(sut.route == .library)
        #expect(sut.setupIssue == "ffmpeg missing")

        sut.clearSetupIssue()
        #expect(sut.setupIssue == nil)

        sut.setLibraryMessage("Ready")
        #expect(sut.libraryMessage == "Ready")

        sut.setLibraryMessage(nil)
        #expect(sut.libraryMessage == nil)
    }

    @Test func clearCurrentJobUsesSharedStateMachine() {
        let sut = MediaTranscriptionFeatureState()
        let job = MediaTranscriptionJobState(request: .link("https://example.com"))
        sut.beginJob(job)

        sut.clearCurrentJob()

        #expect(sut.currentJob == nil)
        #expect(sut.route == .processing(job.id))
    }

    @Test func librarySearchAndSortStateRemainMutableDuringJobLifecycle() {
        let sut = MediaTranscriptionFeatureState()
        let folderID = UUID()

        sut.librarySearchText = "roadmap"
        sut.librarySortMode = .nameAscending
        sut.selectFolder(folderID)
        sut.beginJob(MediaTranscriptionJobState(request: .link("https://example.com"), destinationFolderID: folderID))
        sut.completeCurrentJob(with: UUID(), shouldNavigateToDetail: false)

        #expect(sut.librarySearchText == "roadmap")
        #expect(sut.librarySortMode == .nameAscending)
        #expect(sut.selectedFolderID == folderID)
    }
}
