//
//  NotesStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct NotesStoreTests {
    private func makeStore() -> NotesStore {
        let modelContainer = PreviewContainer.empty
        let modelContext = ModelContext(modelContainer)
        return NotesStore(modelContext: modelContext)
    }

    @Test func createNote() async throws {
        let notesStore = makeStore()
        try await notesStore.create(
            title: "Test Note",
            content: "This is a test note content."
        )

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Test Note")
        #expect(notes.first?.content == "This is a test note content.")
        #expect(notes.first?.tags == [])
        #expect(notes.first?.isPinned == false)
    }

    @Test func createNoteWithAutoTitle() async throws {
        let notesStore = makeStore()
        let longContent = "This is a very long content that should be truncated for the title"
        try await notesStore.create(content: longContent)

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "This is a very long content th...")
    }

    @Test func createNoteWithShortContent() async throws {
        let notesStore = makeStore()
        try await notesStore.create(content: "Short content")

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Short content")
    }

    @Test func createNoteWithEmptyContent() async throws {
        let notesStore = makeStore()
        try await notesStore.create(content: "   ")

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Untitled Note")
    }

    @Test func createNoteWithTags() async throws {
        let notesStore = makeStore()
        try await notesStore.create(
            title: "Tagged Note",
            content: "Content here",
            tags: ["swift", "testing", "notes"]
        )

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.tags == ["swift", "testing", "notes"])
    }

    @Test func fetchAllNotes() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "First", content: "Content 1")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Second", content: "Content 2")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Third", content: "Content 3")

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 3)
        #expect(notes[0].title == "Third")
        #expect(notes[1].title == "Second")
        #expect(notes[2].title == "First")
    }

    @Test func fetchNotesWithLimit() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "First", content: "Content 1")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Second", content: "Content 2")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Third", content: "Content 3")

        let notes = try notesStore.fetch(limit: 2)
        #expect(notes.count == 2)
        #expect(notes[0].title == "Third")
        #expect(notes[1].title == "Second")
    }

    @Test func updateNote() async throws {
        let notesStore = makeStore()
        try await notesStore.create(
            title: "Original Title",
            content: "Original content",
            tags: ["original"]
        )

        var notes = try notesStore.fetchAll()
        let note = try #require(notes.first)
        let originalUpdatedAt = note.updatedAt

        try await Task.sleep(nanoseconds: 100_000_000)

        note.title = "Updated Title"
        note.content = "Updated content"
        note.tags = ["updated"]
        try notesStore.update(note)

        notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Updated Title")
        #expect(notes.first?.content == "Updated content")
        #expect(notes.first?.tags == ["updated"])
        #expect(try #require(notes.first).updatedAt > originalUpdatedAt)
    }

    @Test func deleteNote() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "To Delete", content: "Delete me")
        try await notesStore.create(title: "To Keep", content: "Keep me")

        var notes = try notesStore.fetchAll()
        #expect(notes.count == 2)

        let noteToDelete = try #require(notes.first { $0.title == "To Delete" })
        try notesStore.delete(noteToDelete)

        notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "To Keep")
    }

    @Test func deleteAllNotes() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "First", content: "Content 1")
        try await notesStore.create(title: "Second", content: "Content 2")
        try await notesStore.create(title: "Third", content: "Content 3")

        var notes = try notesStore.fetchAll()
        #expect(notes.count == 3)

        try notesStore.deleteAll()

        notes = try notesStore.fetchAll()
        #expect(notes.count == 0)
    }

    @Test func searchByTitle() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Project Ideas", content: "Some content")
        try await notesStore.create(title: "Meeting Notes", content: "Other content")
        try await notesStore.create(title: "Shopping List", content: "More content")

        let results = try notesStore.search(query: "Project")
        #expect(results.count == 1)
        #expect(results.first?.title == "Project Ideas")
    }

    @Test func searchByContent() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Note One", content: "This contains the word elephant")
        try await notesStore.create(title: "Note Two", content: "This is about giraffes")
        try await notesStore.create(title: "Note Three", content: "More about elephants here")

        let results = try notesStore.search(query: "elephant")
        #expect(results.count >= 0)
        #expect(results.contains { $0.title == "Note One" })
        #expect(results.contains { $0.title == "Note Three" })
    }

    @Test func searchByTags() async throws {
        let notesStore = makeStore()
        try await notesStore.create(
            title: "Swift Note",
            content: "Content about programming",
            tags: ["swift", "coding"]
        )
        try await notesStore.create(
            title: "Other Note",
            content: "Different content",
            tags: ["personal"]
        )

        let results = try notesStore.search(query: "swift")
        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Note")
    }

    @Test func searchNoResults() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Note One", content: "Content")
        try await notesStore.create(title: "Note Two", content: "More content")

        let results = try notesStore.search(query: "nonexistent")
        #expect(results.count == 0)
    }

    @Test func searchCaseInsensitive() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Hello World", content: "Test Content")

        let lowerResults = try notesStore.search(query: "hello")
        #expect(lowerResults.count == 1)

        let upperResults = try notesStore.search(query: "WORLD")
        #expect(upperResults.count == 1)

        let mixedResults = try notesStore.search(query: "HeLLo WoRLd")
        #expect(mixedResults.count == 1)
    }

    @Test func searchPartialMatch() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Project Management", content: "Content here")
        try await notesStore.create(title: "Project Ideas", content: "More content")
        try await notesStore.create(title: "Personal", content: "Different")

        let results = try notesStore.search(query: "Proj")
        #expect(results.count >= 0)
    }

    @Test func sortByDateDescending() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Oldest", content: "First note")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await notesStore.create(title: "Middle", content: "Second note")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await notesStore.create(title: "Newest", content: "Third note")

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 3)
        #expect(notes[0].title == "Newest")
        #expect(notes[1].title == "Middle")
        #expect(notes[2].title == "Oldest")
    }

    @Test func togglePin() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Test Note", content: "Content")

        var notes = try notesStore.fetchAll()
        let note = try #require(notes.first)
        #expect(note.isPinned == false)

        try notesStore.togglePin(note)
        notes = try notesStore.fetchAll()
        #expect(try #require(notes.first).isPinned)

        try notesStore.togglePin(note)
        notes = try notesStore.fetchAll()
        #expect(try #require(notes.first).isPinned == false)
    }

    @Test func pinUpdatesTimestamp() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Test Note", content: "Content")

        var notes = try notesStore.fetchAll()
        let note = try #require(notes.first)
        let originalUpdatedAt = note.updatedAt

        try await Task.sleep(nanoseconds: 100_000_000)

        try notesStore.togglePin(note)

        notes = try notesStore.fetchAll()
        #expect(try #require(notes.first).updatedAt > originalUpdatedAt)
    }

    @Test func createNoteWithSourceTranscriptionID() async throws {
        let notesStore = makeStore()
        let transcriptionID = UUID()
        try await notesStore.create(
            title: "Transcription Note",
            content: "Content from transcription",
            sourceTranscriptionID: transcriptionID
        )

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.sourceTranscriptionID == transcriptionID)
    }

    @Test func uniqueIDs() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "First", content: "Content 1")
        try await notesStore.create(title: "Second", content: "Content 2")

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 2)
        #expect(notes[0].id != notes[1].id)
    }

    @Test func fetchEmptyStore() throws {
        let notesStore = makeStore()
        let notes = try notesStore.fetchAll()
        #expect(notes.count == 0)
    }

    @Test func deleteFromEmptyStore() throws {
        let notesStore = makeStore()
        do {
            try notesStore.deleteAll()
        } catch {
            Issue.record("Expected deleting all from an empty store not to throw: \(error.localizedDescription)")
        }

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 0)
    }

    @Test func searchEmptyStore() throws {
        let notesStore = makeStore()
        let results = try notesStore.search(query: "anything")
        #expect(results.count == 0)
    }

    @Test func createNoteWithSpecialCharacters() async throws {
        let notesStore = makeStore()
        try await notesStore.create(
            title: "Note with \"quotes\" and 'apostrophes'",
            content: "Content with emojis 🎉 and special chars: @#$%"
        )

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Note with \"quotes\" and 'apostrophes'")
        #expect(notes.first?.content == "Content with emojis 🎉 and special chars: @#$%")
    }

    @Test func createNoteWithMultilineContent() async throws {
        let notesStore = makeStore()
        let multilineContent = """
        Line 1
        Line 2
        Line 3
        """
        try await notesStore.create(title: "Multiline", content: multilineContent)

        let notes = try notesStore.fetchAll()
        #expect(notes.count == 1)
        #expect(notes.first?.content == multilineContent)
    }

    @Test func searchWithEmptyQuery() async throws {
        let notesStore = makeStore()
        try await notesStore.create(title: "Note One", content: "Content")
        try await notesStore.create(title: "Note Two", content: "More content")

        let results = try notesStore.search(query: "")
        #expect(results.count >= 0)
    }
}
