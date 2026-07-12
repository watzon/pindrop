//
//  NoteAppendTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@Suite("NoteContentAppend")
struct NoteContentAppendTests {
    @Test func appendsToEmptyContent() {
        #expect(NoteContentAppend.append(transcript: "hello", to: "") == "hello")
        #expect(NoteContentAppend.append(transcript: "  hello  ", to: "") == "hello")
    }

    @Test func appendsWithSpaceWhenNeeded() {
        #expect(NoteContentAppend.append(transcript: "world", to: "hello") == "hello world")
    }

    @Test func appendsDirectlyAfterWhitespace() {
        #expect(NoteContentAppend.append(transcript: "world", to: "hello ") == "hello world")
        #expect(NoteContentAppend.append(transcript: "world", to: "hello\n") == "hello\nworld")
    }

    @Test func ignoresEmptyTranscript() {
        #expect(NoteContentAppend.append(transcript: "   ", to: "keep") == "keep")
        #expect(NoteContentAppend.append(transcript: "", to: "keep") == "keep")
    }
}

@Suite("NoteAppendGate")
struct NoteAppendGateTests {
    @Test func refusesNoteAppendWhenGlobalDictationActive() {
        #expect(NoteAppendGate.canStartNoteAppend(isRecording: true, isProcessing: false) == false)
        #expect(NoteAppendGate.canStartNoteAppend(isRecording: false, isProcessing: true) == false)
        #expect(NoteAppendGate.canStartNoteAppend(isRecording: false, isProcessing: false) == true)
    }

    @Test func refusesGlobalDictationWhenNoteAppendActive() {
        #expect(NoteAppendGate.canStartGlobalDictation(isNoteAppendListening: true) == false)
        #expect(NoteAppendGate.canStartGlobalDictation(isNoteAppendListening: false) == true)
    }
}

@MainActor
@Suite("NoteAppendPersistence", .serialized)
struct NoteAppendPersistenceTests {
    @Test func noteContentGrowsAfterAppendAndSave() async throws {
        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let store = NotesStore(modelContext: context)

        try await store.create(title: "Draft", content: "Existing body")
        let notes = try store.fetchAll()
        let note = try #require(notes.first)

        let updated = NoteContentAppend.append(transcript: "spoken words", to: note.content)
        note.content = updated
        note.updatedAt = Date()
        try context.save()

        let reloaded = try store.fetchAll()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.content == "Existing body spoken words")
    }

    @Test func sharedOwnerRejectsOlderGenerationAfterNewerSave() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "Race", content: "v0", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let olderEditedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newerEditedAt = Date(timeIntervalSince1970: 1_700_000_100)

        // Simulate a close draft racing a reopened edit: older generation first,
        // then a higher generation from the reopened editor.
        let olderTask = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(title: "Race", content: "close-draft", isPinned: false, tags: []),
            editedAt: olderEditedAt
        )
        let newerResult = await NoteEditorPersistenceController.shared.saveAndWait(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(title: "Race", content: "reopened-edit", isPinned: false, tags: []),
            editedAt: newerEditedAt
        )
        let olderResult = await olderTask.value

        #expect(newerResult?.applied == true)
        #expect(newerResult?.generation == 2)
        // Older close write must not win once a newer generation is scheduled.
        #expect(olderResult?.applied == false || olderResult?.generation == 1)

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll()
        let persisted = try #require(reloaded.first)
        #expect(persisted.content == "reopened-edit")
        #expect(NoteEditorPersistenceController.shared.currentGeneration(for: modelID) == 2)
    }

    @Test func closeFlushAwaitsNewestScheduledSnapshot() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "Flush", content: "initial", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let editedAt = Date(timeIntervalSince1970: 1_700_000_200)

        // Mirror onDisappear: enqueue without awaiting, then flush as windowWillClose does.
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(title: "Flush", content: "closed-body", isPinned: false, tags: ["done"]),
            editedAt: editedAt
        )
        await NoteEditorPersistenceController.shared.flush(modelID: modelID)

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll()
        let persisted = try #require(reloaded.first)
        #expect(persisted.content == "closed-body")
        #expect(persisted.tags == ["done"])
    }

    @Test func flushAllDrainsEveryPendingNoteSave() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let first = NoteSchema.Note(title: "A", content: "a0", tags: [], isPinned: false)
        let second = NoteSchema.Note(title: "B", content: "b0", tags: [], isPinned: false)
        context.insert(first)
        context.insert(second)
        try context.save()

        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: first.persistentModelID,
            snapshot: NoteSnapshot(title: "A", content: "a1", isPinned: false, tags: []),
            editedAt: Date(timeIntervalSince1970: 10)
        )
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: second.persistentModelID,
            snapshot: NoteSnapshot(title: "B", content: "b1", isPinned: false, tags: []),
            editedAt: Date(timeIntervalSince1970: 11)
        )

        await NoteEditorPersistenceController.shared.flushAll()

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll().sorted { $0.title < $1.title }
        #expect(reloaded.count == 2)
        #expect(reloaded[0].content == "a1")
        #expect(reloaded[1].content == "b1")
    }

    @Test func sharedOwnerRejectsOlderEditedAtDespiteLaterGeneration() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "EditTime", content: "v0", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let newerEditedAt = Date(timeIntervalSince1970: 1_700_000_300)
        let olderEditedAt = Date(timeIntervalSince1970: 1_700_000_200)

        // Apply a fresher edit first (generation 1).
        let newerResult = await NoteEditorPersistenceController.shared.saveAndWait(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(
                title: "EditTime",
                content: "newer-body",
                isPinned: false,
                tags: ["fresh"]
            ),
            editedAt: newerEditedAt
        )
        #expect(newerResult?.applied == true)
        #expect(newerResult?.generation == 1)

        // Later enqueue with an older editedAt must not override edit-time
        // ordering: schedule boundary rejects without bumping generation or
        // replacing the pending save for this note.
        let generationBeforeStale = NoteEditorPersistenceController.shared.currentGeneration(for: modelID)
        let olderTask = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(
                title: "EditTime",
                content: "stale-body",
                isPinned: false,
                tags: ["stale"]
            ),
            editedAt: olderEditedAt
        )
        await NoteEditorPersistenceController.shared.flush(modelID: modelID)
        let olderResult = await olderTask.value

        #expect(olderResult?.applied == false)
        #expect(olderResult?.generation == generationBeforeStale)
        #expect(
            NoteEditorPersistenceController.shared.currentGeneration(for: modelID)
                == generationBeforeStale
        )

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll()
        let persisted = try #require(reloaded.first)
        #expect(persisted.content == "newer-body")
        #expect(persisted.tags == ["fresh"])
        #expect(persisted.updatedAt == newerEditedAt)
    }

    @Test func flushAllKeepsLatestAcceptedEditForEachNote() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let first = NoteSchema.Note(title: "A", content: "a0", tags: [], isPinned: false)
        let second = NoteSchema.Note(title: "B", content: "b0", tags: [], isPinned: false)
        context.insert(first)
        context.insert(second)
        try context.save()

        let firstID = first.persistentModelID
        let secondID = second.persistentModelID

        // Prior accepted saves establish baseline edit-time and generation state.
        let firstPrior = await NoteEditorPersistenceController.shared.saveAndWait(
            container: container,
            modelID: firstID,
            snapshot: NoteSnapshot(title: "A", content: "a-prior", isPinned: false, tags: ["a"]),
            editedAt: Date(timeIntervalSince1970: 100)
        )
        let secondPrior = await NoteEditorPersistenceController.shared.saveAndWait(
            container: container,
            modelID: secondID,
            snapshot: NoteSnapshot(title: "B", content: "b-prior", isPinned: true, tags: ["b"]),
            editedAt: Date(timeIntervalSince1970: 101)
        )
        #expect(firstPrior?.applied == true)
        #expect(secondPrior?.applied == true)

        // Schedule later accepted drafts for both notes, then a stale older edit
        // for A. Edit-time ordering must keep the later accepted drafts; the
        // stale schedule must not replace pending work or win after flushAll.
        let firstGenerationBeforeLatest = NoteEditorPersistenceController.shared.currentGeneration(for: firstID)
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: firstID,
            snapshot: NoteSnapshot(title: "A", content: "a-latest", isPinned: false, tags: ["a", "latest"]),
            editedAt: Date(timeIntervalSince1970: 200)
        )
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: secondID,
            snapshot: NoteSnapshot(title: "B", content: "b-latest", isPinned: true, tags: ["b", "latest"]),
            editedAt: Date(timeIntervalSince1970: 201)
        )
        let firstGenerationAfterLatest = NoteEditorPersistenceController.shared.currentGeneration(for: firstID)
        #expect(firstGenerationAfterLatest == firstGenerationBeforeLatest + 1)

        let staleFirstTask = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: firstID,
            snapshot: NoteSnapshot(title: "A", content: "a-stale", isPinned: false, tags: ["stale"]),
            editedAt: Date(timeIntervalSince1970: 150)
        )

        await NoteEditorPersistenceController.shared.flushAll()
        let staleFirstResult = await staleFirstTask.value

        #expect(staleFirstResult?.applied == false)
        #expect(staleFirstResult?.generation == firstGenerationAfterLatest)
        #expect(
            NoteEditorPersistenceController.shared.currentGeneration(for: firstID)
                == firstGenerationAfterLatest
        )

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll().sorted { $0.title < $1.title }
        #expect(reloaded.count == 2)
        #expect(reloaded[0].content == "a-latest")
        #expect(reloaded[0].tags == ["a", "latest"])
        #expect(reloaded[0].updatedAt == Date(timeIntervalSince1970: 200))
        #expect(reloaded[1].content == "b-latest")
        #expect(reloaded[1].isPinned == true)
        #expect(reloaded[1].tags == ["b", "latest"])
        #expect(reloaded[1].updatedAt == Date(timeIntervalSince1970: 201))
    }

    @Test func prepareForTerminationPersistsUnscheduledTrackedDraft() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "Term", content: "seed", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let editedAt = Date(timeIntervalSince1970: 1_700_000_400)

        // Synchronous draft tracking only — no scheduleSave / onDisappear.
        // prepareForTermination must enqueue and await this tracked snapshot
        // even when no live windows exist to fire disappear handlers.
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(
                title: "Term",
                content: "quit-draft",
                isPinned: false,
                tags: ["term"]
            ),
            editedAt: editedAt
        )

        await NoteEditorPersistenceController.shared.prepareForTermination()

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll()
        let persisted = try #require(reloaded.first)
        #expect(persisted.content == "quit-draft")
        #expect(persisted.tags == ["term"])
        #expect(persisted.updatedAt == editedAt)
    }

    @Test func prepareForTerminationPrefersNewerTrackedDraftOverOlderPendingSave() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "RaceQuit", content: "v0", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let olderEditedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let newerEditedAt = Date(timeIntervalSince1970: 1_700_000_600)

        // Older in-flight save alone is not enough for quit durability of the
        // freshest keystrokes — those live only in the tracked draft.
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(
                title: "RaceQuit",
                content: "older-pending",
                isPinned: false,
                tags: ["old"]
            ),
            editedAt: olderEditedAt
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: modelID,
            snapshot: NoteSnapshot(
                title: "RaceQuit",
                content: "newer-tracked",
                isPinned: true,
                tags: ["new"]
            ),
            editedAt: newerEditedAt
        )

        await NoteEditorPersistenceController.shared.prepareForTermination()

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll()
        let persisted = try #require(reloaded.first)
        #expect(persisted.content == "newer-tracked")
        #expect(persisted.isPinned == true)
        #expect(persisted.tags == ["new"])
        #expect(persisted.updatedAt == newerEditedAt)
    }

    @Test func prepareForTerminationPersistsLatestTrackedDraftsForEveryNote() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let first = NoteSchema.Note(title: "A", content: "a0", tags: [], isPinned: false)
        let second = NoteSchema.Note(title: "B", content: "b0", tags: [], isPinned: false)
        let third = NoteSchema.Note(title: "C", content: "c0", tags: [], isPinned: false)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let firstID = first.persistentModelID
        let secondID = second.persistentModelID
        let thirdID = third.persistentModelID

        // Intermediate tracked values, then superseding latest drafts for each note.
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: firstID,
            snapshot: NoteSnapshot(title: "A", content: "a-mid", isPinned: false, tags: ["a"]),
            editedAt: Date(timeIntervalSince1970: 1_000)
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: secondID,
            snapshot: NoteSnapshot(title: "B", content: "b-mid", isPinned: false, tags: ["b"]),
            editedAt: Date(timeIntervalSince1970: 1_001)
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: firstID,
            snapshot: NoteSnapshot(title: "A", content: "a-latest", isPinned: true, tags: ["a", "final"]),
            editedAt: Date(timeIntervalSince1970: 2_000)
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: secondID,
            snapshot: NoteSnapshot(title: "B", content: "b-latest", isPinned: false, tags: ["b", "final"]),
            editedAt: Date(timeIntervalSince1970: 2_001)
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: thirdID,
            snapshot: NoteSnapshot(title: "C", content: "c-latest", isPinned: false, tags: ["c"]),
            editedAt: Date(timeIntervalSince1970: 2_002)
        )

        // No windows / no pendingSaves: termination must still materialize every
        // latest tracked draft before returning.
        await NoteEditorPersistenceController.shared.prepareForTermination()

        let store = NotesStore(modelContext: context)
        let reloaded = try store.fetchAll().sorted { $0.title < $1.title }
        #expect(reloaded.count == 3)
        #expect(reloaded[0].content == "a-latest")
        #expect(reloaded[0].isPinned == true)
        #expect(reloaded[0].tags == ["a", "final"])
        #expect(reloaded[0].updatedAt == Date(timeIntervalSince1970: 2_000))
        #expect(reloaded[1].content == "b-latest")
        #expect(reloaded[1].tags == ["b", "final"])
        #expect(reloaded[1].updatedAt == Date(timeIntervalSince1970: 2_001))
        #expect(reloaded[2].content == "c-latest")
        #expect(reloaded[2].tags == ["c"])
        #expect(reloaded[2].updatedAt == Date(timeIntervalSince1970: 2_002))
    }

    @Test func prepareForTerminationKeepsDifferentSnapshotAtSameEditedAt() async throws {
        NoteEditorPersistenceController.shared.resetForTesting()
        defer { NoteEditorPersistenceController.shared.resetForTesting() }

        let container = PreviewContainer.empty
        let context = ModelContext(container)
        let note = NoteSchema.Note(title: "Identity", content: "seed", tags: [], isPinned: false)
        context.insert(note)
        try context.save()

        let modelID = note.persistentModelID
        let sharedEditedAt = Date(timeIntervalSince1970: 1_700_000_700)
        let snapshotA = NoteSnapshot(
            title: "Identity",
            content: "snapshot-a",
            isPinned: false,
            tags: ["a"]
        )
        let snapshotB = NoteSnapshot(
            title: "Identity",
            content: "snapshot-b",
            isPinned: true,
            tags: ["b"]
        )

        // Track/schedule A, then replace tracking with a different B at the same
        // editedAt before A completes. Timestamp-only clear would drop B when A
        // applies; snapshot identity must keep B for termination durability.
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: modelID,
            snapshot: snapshotA,
            editedAt: sharedEditedAt
        )
        let taskA = NoteEditorPersistenceController.shared.scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: snapshotA,
            editedAt: sharedEditedAt
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: modelID,
            snapshot: snapshotB,
            editedAt: sharedEditedAt
        )

        let resultA = await taskA.value
        #expect(resultA?.applied == true)

        await NoteEditorPersistenceController.shared.prepareForTermination()

        let store = NotesStore(modelContext: context)
        var reloaded = try store.fetchAll()
        var persisted = try #require(reloaded.first)
        #expect(persisted.content == "snapshot-b")
        #expect(persisted.isPinned == true)
        #expect(persisted.tags == ["b"])
        #expect(persisted.updatedAt == sharedEditedAt)

        // Exact matching applied snapshot must clear tracking so a later
        // termination cannot re-enqueue and overwrite a newer direct store write.
        let exactEditedAt = Date(timeIntervalSince1970: 1_700_000_800)
        let exactSnapshot = NoteSnapshot(
            title: "Identity",
            content: "exact-match",
            isPinned: false,
            tags: ["exact"]
        )
        NoteEditorPersistenceController.shared.trackDraft(
            container: container,
            modelID: modelID,
            snapshot: exactSnapshot,
            editedAt: exactEditedAt
        )
        let exactResult = await NoteEditorPersistenceController.shared.saveAndWait(
            container: container,
            modelID: modelID,
            snapshot: exactSnapshot,
            editedAt: exactEditedAt
        )
        #expect(exactResult?.applied == true)

        let generationAfterExact = NoteEditorPersistenceController.shared.currentGeneration(for: modelID)

        reloaded = try store.fetchAll()
        persisted = try #require(reloaded.first)
        #expect(persisted.content == "exact-match")

        let directEditedAt = Date(timeIntervalSince1970: 1_700_000_900)
        persisted.content = "post-clear-direct"
        persisted.isPinned = true
        persisted.tags = ["direct"]
        persisted.updatedAt = directEditedAt
        try context.save()

        await NoteEditorPersistenceController.shared.prepareForTermination()

        #expect(NoteEditorPersistenceController.shared.currentGeneration(for: modelID) == generationAfterExact)

        reloaded = try store.fetchAll()
        persisted = try #require(reloaded.first)
        #expect(persisted.content == "post-clear-direct")
        #expect(persisted.isPinned == true)
        #expect(persisted.tags == ["direct"])
        #expect(persisted.updatedAt == directEditedAt)
    }
}
