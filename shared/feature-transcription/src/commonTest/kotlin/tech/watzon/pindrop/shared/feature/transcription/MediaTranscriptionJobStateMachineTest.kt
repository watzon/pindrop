package tech.watzon.pindrop.shared.feature.transcription

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class MediaTranscriptionJobStateMachineTest {
    @Test
    fun beginJobMovesFeatureToProcessingRoute() {
        val job = MediaTranscriptionJob(id = "job-1", requestDisplayName = "demo.mp3")
        val snapshot = MediaTranscriptionJobStateMachine.beginJob(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            job = job,
        )

        assertEquals(job, snapshot.currentJob)
        assertIs<MediaTranscriptionRoute.Processing>(snapshot.route)
    }

    @Test
    fun updateJobMutatesStageAndProgress() {
        val initial = MediaTranscriptionJobStateMachine.beginJob(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            job = MediaTranscriptionJob(id = "job-1", requestDisplayName = "demo.mp3"),
        )

        val updated = MediaTranscriptionJobStateMachine.updateJob(
            snapshot = initial,
            update = JobProgressUpdate(
                stage = MediaTranscriptionStage.TRANSCRIBING,
                progress = 0.5,
                detail = "Halfway there",
            ),
        )

        assertEquals(MediaTranscriptionStage.TRANSCRIBING, updated.currentJob?.stage)
        assertEquals(0.5, updated.currentJob?.progress)
        assertEquals("Halfway there", updated.currentJob?.detail)
    }

    @Test
    fun completeCurrentJobHandlesDetailAndLibraryRoutes() {
        val initial = MediaTranscriptionJobStateMachine.beginJob(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            job = MediaTranscriptionJob(id = "job-1", requestDisplayName = "demo.mp3"),
        )

        val detailSnapshot = MediaTranscriptionJobStateMachine.completeCurrentJob(
            snapshot = initial,
            recordId = "record-1",
            shouldNavigateToDetail = true,
        )
        assertIs<MediaTranscriptionRoute.Detail>(detailSnapshot.route)

        val librarySnapshot = MediaTranscriptionJobStateMachine.completeCurrentJob(
            snapshot = initial,
            recordId = "record-1",
            shouldNavigateToDetail = false,
        )
        assertIs<MediaTranscriptionRoute.Library>(librarySnapshot.route)
        assertEquals("Transcription finished.", librarySnapshot.libraryMessage)
    }

    @Test
    fun failCurrentJobCanReturnToLibrary() {
        val initial = MediaTranscriptionJobStateMachine.beginJob(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            job = MediaTranscriptionJob(id = "job-1", requestDisplayName = "demo.mp3"),
        )

        val failed = MediaTranscriptionJobStateMachine.failCurrentJob(
            snapshot = initial,
            message = "No audio stream",
            returnToLibrary = true,
        )

        assertIs<MediaTranscriptionRoute.Library>(failed.route)
        assertEquals("No audio stream", failed.libraryMessage)
        assertEquals(MediaTranscriptionStage.FAILED, failed.currentJob?.stage)
    }

    @Test
    fun selectionAndDeletionStateIsManagedBySharedSnapshot() {
        val folderSnapshot = MediaTranscriptionJobStateMachine.selectFolder(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            folderId = "folder-1",
        )
        assertEquals("folder-1", folderSnapshot.selectedFolderId)

        val recordSnapshot = MediaTranscriptionJobStateMachine.selectRecord(
            snapshot = folderSnapshot,
            recordId = "record-1",
        )
        assertIs<MediaTranscriptionRoute.Detail>(recordSnapshot.route)
        assertEquals("record-1", recordSnapshot.selectedRecordId)

        val afterRecordDelete = MediaTranscriptionJobStateMachine.handleDeletedRecord(
            snapshot = recordSnapshot,
            recordId = "record-1",
            message = "Deleted",
        )
        assertIs<MediaTranscriptionRoute.Library>(afterRecordDelete.route)
        assertNull(afterRecordDelete.selectedRecordId)

        val afterFolderDelete = MediaTranscriptionJobStateMachine.handleDeletedFolder(
            snapshot = afterRecordDelete,
            folderId = "folder-1",
            message = "Folder deleted",
        )
        assertNull(afterFolderDelete.selectedFolderId)
    }

    @Test
    fun setupIssueAndLibraryMessagesCanBeMutatedWithoutSwiftFallbacks() {
        val initial = MediaTranscriptionJobStateMachine.setSetupIssue(
            snapshot = MediaTranscriptionFeatureSnapshot(),
            message = "ffmpeg missing",
        )

        assertEquals("ffmpeg missing", initial.setupIssue)
        assertIs<MediaTranscriptionRoute.Library>(initial.route)

        val messaged = MediaTranscriptionJobStateMachine.setLibraryMessage(
            snapshot = initial,
            message = "Ready",
        )
        assertEquals("Ready", messaged.libraryMessage)
    }
}
