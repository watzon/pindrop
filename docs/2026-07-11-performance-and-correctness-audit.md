# Performance and Correctness Audit

**Date:** 2026-07-11  
**Scope:** Static, evidence-driven review of the app lifecycle, services, SwiftUI surfaces, audio/transcription paths, and persistence.  
**Method:** Source inspection, focused subagent review, `just build`, and `just test`. No application code was changed.

## Validation Baseline

- `just build` passed.
- `just test` passed: 1,003 tests in 71 suites. One opt-in integration test was skipped as expected because `PINDROP_RUN_INTEGRATION_TESTS` was not enabled.
- The worktree was clean before the audit. This document is the only resulting repository change.
- The audit is static and test-backed, not profile-backed. The attempted Axiom `xcprof doctor --human` invocation failed internally with `undefined is not an object (evaluating 'session.data.location')`, so it did not produce a usable runtime trace.

## Findings

### 1. High: Direct media downloads can wait forever after an early completion

**References:** `Pindrop/Services/MediaIngestionService.swift:449-489`, `Pindrop/Services/MediaIngestionService.swift:657-674`

`downloadDirectMedia` resumes its `URLSessionDownloadTask` before calling `waitForCompletion`, which installs the delegate's checked continuation. An immediate failure, cancellation, or fast completion can reach `didCompleteWithError` or `didFinishDownloadingTo` while `continuation` is `nil`. The delegate drops the result and the subsequent waiter suspends indefinitely. The continuation is also read and written from URLSession delegate callbacks without synchronization.

**Impact:** A direct media URL can leave its transcription job permanently in the download stage.

**Recommended direction:** Register the waiter before starting the task, or encapsulate completion state in an actor or lock-protected state machine that retains either an already-arrived result or the waiting continuation. Resolve exactly once and invalidate the session on every exit path.

### 2. High: Media preparation does synchronous decode and conversion on the main actor

**References:** `Pindrop/Services/MediaPreparationService.swift:40`, `Pindrop/Services/MediaPreparationService.swift:109-238`, `Pindrop/AppCoordinator.swift:4506-4509`

`MediaPreparationService` is `@MainActor`. Its async entry point opens `AVAudioFile`, loops over synchronous reads and converter calls, and appends all samples to a `Data` value. `await` does not move this synchronous loop off the main actor. The media-transcription task calls it from the main actor.

**Impact:** Importing a large media file can block menus, windows, progress updates, and cancellation handling until conversion completes.

**Recommended direction:** Move file reads, conversion, and data accumulation to a non-main-isolated worker using sendable inputs and results. Check for cancellation between chunks and return to the main actor only for state updates.

### 3. High: Recording memory is unbounded and stop/finalization multiplies copies

**References:** `Pindrop/Services/AudioRecorder.swift:241-293`, `Pindrop/Services/AudioRecorder.swift:940-981`, `Pindrop/Services/AudioRecorder.swift:1960-1989`, `Pindrop/Services/StreamingSessionController.swift:437-450`

Every converted ASR buffer is retained in `AudioBufferStorage` for the whole recording. Native-audio retention can retain a second, higher-rate stream. Streaming audio also enters an `AsyncStream` configured with `.unbounded`, so processing that falls behind capture can add a third growing queue.

At stop, `combineBuffersToData` first creates a complete `[Float]` from all buffers and then copies that array into `Data`. At 16 kHz mono Float32, the ASR stream alone is approximately 230 MB per hour. A retained 48 kHz mono Float32 stream adds approximately 691 MB per hour, before object overhead, inference input, queue backlog, and stop-time copies.

**Impact:** Long dictations and meeting recordings can cause severe memory pressure, substantial stop-time stalls, or process termination.

**Recommended direction:** Use a bounded, chunked or file-backed accumulator rather than retaining all `AVAudioPCMBuffer` instances. Eliminate the intermediate `[Float]` when creating `Data`. Give streaming a bounded buffering policy with an explicit backpressure or overflow policy. If full in-memory inference remains necessary, define and surface a safe recording limit.

### 4. High: Task-group timeouts do not enforce a hard deadline for noncooperative work

**References:** `Pindrop/Services/StreamingSessionController.swift:511-526`, `Pindrop/Services/TranscriptionService.swift:179-194`, `Pindrop/Services/TranscriptionService.swift:237-251`, `Pindrop/Services/WorkspaceFileIndexService.swift:273-352`

The timeout helpers race an operation against `Task.sleep` in a structured task group, then call `cancelAll()`. Structured task-group scope cannot return until all children have stopped. Consequently, cancellation only works when the timed-out operation cooperatively exits. Synchronous file enumeration, process work, and cancellation-insensitive model/inference work can continue past the documented deadline.

**Impact:** Workspace indexing, model loading, and streaming finalization can exceed their supposed timeout and keep the UI in a loading or processing state longer than intended.

**Recommended direction:** Add cooperative cancellation checks to loops and explicitly terminate subprocesses. Where the caller must return at the deadline despite uncooperative work, use independently owned tasks with safe cleanup and late-result suppression instead of relying on structured task-group cancellation alone.

### 5. Medium: `HistoryStore.save` can report failure after the record is committed

**References:** `Pindrop/Services/HistoryStore.swift:672-691`

`HistoryStore.save` saves the new `TranscriptionRecord`, then runs potentially throwing speaker-training work in the same `do` block. If `learnFromDictation` fails, the catch reports `HistoryStoreError.saveFailed`, even though the record is durable. The history-change notification is also skipped.

**Impact:** The caller can present a failed-save message even though the record exists. UI refresh may be delayed, and retry behavior can create duplicate records.

**Recommended direction:** Make record persistence and speaker training an explicit transaction boundary. Either perform both atomically before the save, or treat speaker learning as separately reported best-effort work after a successful record save. Post the history-change notification after the record save succeeds.

### 6. Medium: Note editing saves SwiftData on every keystroke

**References:** `Pindrop/UI/NoteEditor/NoteEditorWindow.swift:228-241`, `Pindrop/UI/NoteEditor/NoteEditorWindow.swift:471-500`

Changes to title and content immediately call `saveNote()`. That updates `updatedAt`, saves the model context, and invokes the save callback for every typed character.

**Impact:** Typing in larger notes can cause frequent main-context writes and unnecessary UI work. The updated timestamp can continually reorder note lists while the user is editing.

**Recommended direction:** Debounce autosave, save only if persisted values differ, and retain an explicit immediate-save action for the existing keyboard shortcut.

### 7. Medium: History search repeatedly loads the full matching store

**References:** `Pindrop/Services/HistoryStore.swift:781-827`, `Pindrop/UI/Main/HistoryView.swift:877-998`

For a nonempty search, `countTranscriptions`, `totalSpokenDuration`, and the paginated fetch each materialize all matching records through `fetchAllTranscriptions`, then filter and slice in memory. Even with an empty query, computing total spoken duration fetches every matching record. These methods are invoked during reload and refresh paths on main-actor-owned state.

**Impact:** Search and history refresh scale poorly as the library grows, producing repeated O(N) model materialization and allocation churn. Pagination does not bound work for searched results.

**Recommended direction:** Add store-level aggregate APIs for count and duration. Where optional-field searching prevents a direct SwiftData predicate, create a searchable representation that can be queried at the store layer or produce one reusable background snapshot rather than fetching the same full set three times.

### 8. Medium: Core Audio property reads use an unsafe `CFString` output representation

**References:** `Pindrop/Services/AudioRecorder.swift:1508-1513`, `Pindrop/Services/AudioRecorder.swift:1542-1547`

The build reports that the code forms an `UnsafeMutableRawPointer` to a `CFString` variable when calling `AudioObjectGetPropertyData`. The API's returned object pointer should be represented as an optional `CFString?`, matching the buffer size already computed with `MemoryLayout<CFString?>`.

**Impact:** This is a memory-safety/API-bridging warning. It may behave correctly today, but the current representation is not safe according to the Swift compiler.

**Recommended direction:** Declare the output as `var value: CFString?`, pass its address, then safely unwrap before bridging to `String`.

### 9. Medium: Note editor controllers created by `NotesView` are not retained

**References:** `Pindrop/UI/Main/NotesView.swift:395-404`, `Pindrop/UI/NoteEditor/NoteEditorWindow.swift:14-119`, `Pindrop/AppCoordinator.swift:308`, `Pindrop/AppCoordinator.swift:497-498`

`NotesView` creates `NoteEditorWindowController` instances in local variables and does not retain them. The controller holds the window and is its delegate, while window callbacks capture the controller weakly. `AppCoordinator` already owns a retained note editor controller for its menu-driven path, but `NotesView` bypasses it.

**Impact:** After the local controller is released, window lifecycle callbacks, pin-level updates, theme observation, and save forwarding can stop working. The behavior diverges from the menu-driven note flow.

**Recommended direction:** Route note creation and opening through the retained coordinator controller, or retain controllers explicitly for each note window.

### 10. Low/Medium: Every `UserDefaults` change rebuilds the main menu and reapplies Dock policy

**References:** `Pindrop/PindropApp.swift:303-322`

The app observes the global `UserDefaults.didChangeNotification`. Every notification schedules `updateDockVisibility()` and a complete `setupMainMenu()` rebuild, regardless of whether `showInDock` or the interface locale actually changed. The notification can originate from framework defaults activity, not only user settings.

**Impact:** Unrelated defaults mutations can cause unnecessary main-actor menu reconstruction and activation-policy calls, with possible menu flicker or focus churn.

**Recommended direction:** Track the relevant values, skip no-op changes, and coalesce successive notifications. Prefer a settings-specific observation path where practical.

## Additional Observations

The following were not ranked as confirmed current runtime defects, but should be addressed as part of ongoing maintenance:

- The test build emits Swift 6 concurrency warnings in `TranscriptionService`, `StreamingRefinementCoordinator`, `WorkspaceFileIndexService`, `FloatingIndicatorShared`, `FloatingIndicatorFocusTracker`, and `MainWindow`. They will become migration blockers when Swift 6 language mode is enabled.
- `FloatingIndicatorState` uses `Timer.scheduledTimer` for its duration ticker at `Pindrop/UI/FloatingIndicatorShared.swift:623-625`; it runs in the default run-loop mode and can pause during menu tracking or other event tracking. The project already has a `.common`-mode timer helper.
- `HistoryView` constructs a new `HistoryStore` and `SpeakerIdentityService` through a computed property at `Pindrop/UI/Main/HistoryView.swift:63-67`. Caching that service would avoid repeated construction and avoid future loss of in-memory service state.
- `StatusBarController` creates a new `DateFormatter` for each recent-transcript entry at `Pindrop/UI/StatusBarController.swift:312-317`. A cached formatter would avoid repeated allocation during menu refreshes.

## Recommended Remediation Order

1. Fix the direct-download continuation race and add immediate completion/cancellation tests.
2. Move media preparation off the main actor and add responsiveness/cancellation coverage for large inputs.
3. Bound recording and streaming memory, then measure peak memory and stop latency with long captures.
4. Make timeout behavior explicit and test cancellation-insensitive operations.
5. Correct the save transaction semantics and add a test for speaker-training failure after record persistence.
6. Address history query materialization and note autosave after the higher-risk correctness and memory work.

## Suggested Test Gaps to Close

- Direct downloads that complete or fail before the waiting continuation is installed.
- Direct-download cancellation and URLSession invalidation on every error path.
- Media import cancellation while conversion is in progress, with a responsiveness assertion for main-actor work.
- Long-recording peak-memory and stop-time behavior, including streaming backpressure.
- Timeout elapsed-wall-clock behavior when the timed-out operation ignores cancellation.
- `HistoryStore.save` behavior when speaker learning fails after the record has been saved.
- Large-history search, pagination, and aggregate query performance.
