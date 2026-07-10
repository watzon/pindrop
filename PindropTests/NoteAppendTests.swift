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
}
