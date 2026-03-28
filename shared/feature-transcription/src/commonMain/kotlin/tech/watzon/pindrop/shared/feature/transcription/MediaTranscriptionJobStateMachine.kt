package tech.watzon.pindrop.shared.feature.transcription

enum class MediaTranscriptionStage {
    PREFLIGHT,
    IMPORTING,
    DOWNLOADING,
    PREPARING_AUDIO,
    TRANSCRIBING,
    SAVING,
    COMPLETED,
    FAILED,
}

sealed class MediaTranscriptionRoute {
    data object Library : MediaTranscriptionRoute()
    data class Processing(val jobId: String) : MediaTranscriptionRoute()
    data class Detail(val recordId: String) : MediaTranscriptionRoute()
}

data class MediaTranscriptionJob(
    val id: String,
    val requestDisplayName: String,
    val stage: MediaTranscriptionStage = MediaTranscriptionStage.PREFLIGHT,
    val progress: Double? = null,
    val detail: String = "",
    val errorMessage: String? = null,
)

data class JobProgressUpdate(
    val stage: MediaTranscriptionStage,
    val progress: Double? = null,
    val detail: String? = null,
    val errorMessage: String? = null,
)

data class MediaTranscriptionFeatureSnapshot(
    val route: MediaTranscriptionRoute = MediaTranscriptionRoute.Library,
    val selectedRecordId: String? = null,
    val selectedFolderId: String? = null,
    val currentJob: MediaTranscriptionJob? = null,
    val setupIssue: String? = null,
    val libraryMessage: String? = null,
)

object MediaTranscriptionJobStateMachine {
    fun showLibrary(
        snapshot: MediaTranscriptionFeatureSnapshot,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(route = MediaTranscriptionRoute.Library)
    }

    fun beginJob(
        snapshot: MediaTranscriptionFeatureSnapshot,
        job: MediaTranscriptionJob,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(
            route = MediaTranscriptionRoute.Processing(job.id),
            currentJob = job,
            setupIssue = null,
            libraryMessage = null,
        )
    }

    fun selectRecord(
        snapshot: MediaTranscriptionFeatureSnapshot,
        recordId: String,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(
            selectedRecordId = recordId,
            route = MediaTranscriptionRoute.Detail(recordId),
            libraryMessage = null,
        )
    }

    fun selectFolder(
        snapshot: MediaTranscriptionFeatureSnapshot,
        folderId: String,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(
            selectedFolderId = folderId,
            libraryMessage = null,
        )
    }

    fun clearSelectedFolder(
        snapshot: MediaTranscriptionFeatureSnapshot,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(selectedFolderId = null)
    }

    fun updateJob(
        snapshot: MediaTranscriptionFeatureSnapshot,
        update: JobProgressUpdate,
    ): MediaTranscriptionFeatureSnapshot {
        val currentJob = snapshot.currentJob ?: return snapshot
        return snapshot.copy(
            currentJob = currentJob.copy(
                stage = update.stage,
                progress = update.progress,
                detail = update.detail ?: currentJob.detail,
                errorMessage = update.errorMessage,
            ),
        )
    }

    fun clearCurrentJob(
        snapshot: MediaTranscriptionFeatureSnapshot,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(currentJob = null)
    }

    fun setSetupIssue(
        snapshot: MediaTranscriptionFeatureSnapshot,
        message: String,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(
            setupIssue = message,
            route = MediaTranscriptionRoute.Library,
        )
    }

    fun setLibraryMessage(
        snapshot: MediaTranscriptionFeatureSnapshot,
        message: String?,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(libraryMessage = message)
    }

    fun handleDeletedRecord(
        snapshot: MediaTranscriptionFeatureSnapshot,
        recordId: String,
        message: String,
    ): MediaTranscriptionFeatureSnapshot {
        val nextRoute = when (val route = snapshot.route) {
            is MediaTranscriptionRoute.Detail -> {
                if (route.recordId == recordId) MediaTranscriptionRoute.Library else route
            }
            else -> snapshot.route
        }

        return snapshot.copy(
            selectedRecordId = if (snapshot.selectedRecordId == recordId) null else snapshot.selectedRecordId,
            route = nextRoute,
            libraryMessage = message,
        )
    }

    fun handleDeletedFolder(
        snapshot: MediaTranscriptionFeatureSnapshot,
        folderId: String,
        message: String,
    ): MediaTranscriptionFeatureSnapshot {
        return snapshot.copy(
            selectedFolderId = if (snapshot.selectedFolderId == folderId) null else snapshot.selectedFolderId,
            libraryMessage = message,
        )
    }

    fun completeCurrentJob(
        snapshot: MediaTranscriptionFeatureSnapshot,
        recordId: String,
        shouldNavigateToDetail: Boolean,
    ): MediaTranscriptionFeatureSnapshot {
        val updated = updateJob(
            snapshot = snapshot,
            update = JobProgressUpdate(
                stage = MediaTranscriptionStage.COMPLETED,
                progress = 1.0,
                detail = "Saved transcription",
            ),
        )

        return updated.copy(
            selectedRecordId = recordId,
            route = if (shouldNavigateToDetail) {
                MediaTranscriptionRoute.Detail(recordId)
            } else {
                MediaTranscriptionRoute.Library
            },
            libraryMessage = if (shouldNavigateToDetail) null else "Transcription finished.",
        )
    }

    fun failCurrentJob(
        snapshot: MediaTranscriptionFeatureSnapshot,
        message: String,
        returnToLibrary: Boolean,
    ): MediaTranscriptionFeatureSnapshot {
        val updated = updateJob(
            snapshot = snapshot,
            update = JobProgressUpdate(
                stage = MediaTranscriptionStage.FAILED,
                errorMessage = message,
            ),
        )

        return if (returnToLibrary) {
            updated.copy(
                route = MediaTranscriptionRoute.Library,
                libraryMessage = message,
            )
        } else {
            updated
        }
    }
}
