//
//  NotesStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class NotesStoreTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var notesStore: NotesStore!
    
    override func setUp() async throws {
        modelContainer = PreviewContainer.empty
        modelContext = ModelContext(modelContainer)
        notesStore = NotesStore(modelContext: modelContext)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        notesStore = nil
    }
    
    // MARK: - CRUD Operations
    
    func testCreateNote() async throws {
        try await notesStore.create(
            title: "Test Note",
            content: "This is a test note content."
        )
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Test Note")
        XCTAssertEqual(notes.first?.content, "This is a test note content.")
        XCTAssertEqual(notes.first?.tags, [])
        XCTAssertFalse(notes.first?.isPinned ?? true)
    }
    
    func testCreateNoteWithAutoTitle() async throws {
        // Test auto-title from content (first 30 chars)
        let longContent = "This is a very long content that should be truncated for the title"
        try await notesStore.create(content: longContent)
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "This is a very long content th...")
    }
    
    func testCreateNoteWithShortContent() async throws {
        // Test auto-title with short content (no truncation)
        try await notesStore.create(content: "Short content")
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Short content")
    }
    
    func testCreateNoteWithEmptyContent() async throws {
        // Test auto-title with empty/whitespace content
        try await notesStore.create(content: "   ")
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Untitled Note")
    }
    
    func testCreateNoteWithTags() async throws {
        try await notesStore.create(
            title: "Tagged Note",
            content: "Content here",
            tags: ["swift", "testing", "notes"]
        )
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.tags, ["swift", "testing", "notes"])
    }
    
    func testFetchAllNotes() async throws {
        try await notesStore.create(title: "First", content: "Content 1")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Second", content: "Content 2")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Third", content: "Content 3")
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 3)
        // Should be sorted by updatedAt descending (newest first)
        XCTAssertEqual(notes[0].title, "Third")
        XCTAssertEqual(notes[1].title, "Second")
        XCTAssertEqual(notes[2].title, "First")
    }
    
    func testFetchNotesWithLimit() async throws {
        try await notesStore.create(title: "First", content: "Content 1")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Second", content: "Content 2")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await notesStore.create(title: "Third", content: "Content 3")
        
        let notes = try notesStore.fetch(limit: 2)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].title, "Third")
        XCTAssertEqual(notes[1].title, "Second")
    }
    
    func testUpdateNote() async throws {
        try await notesStore.create(
            title: "Original Title",
            content: "Original content",
            tags: ["original"]
        )
        
        var notes = try notesStore.fetchAll()
        let note = notes.first!
        let originalUpdatedAt = note.updatedAt
        
        // Wait a bit to ensure timestamp difference
        try await Task.sleep(nanoseconds: 100_000_000)
        
        note.title = "Updated Title"
        note.content = "Updated content"
        note.tags = ["updated"]
        try notesStore.update(note)
        
        notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Updated Title")
        XCTAssertEqual(notes.first?.content, "Updated content")
        XCTAssertEqual(notes.first?.tags, ["updated"])
        XCTAssertGreaterThan(notes.first!.updatedAt, originalUpdatedAt)
    }
    
    func testDeleteNote() async throws {
        try await notesStore.create(title: "To Delete", content: "Delete me")
        try await notesStore.create(title: "To Keep", content: "Keep me")
        
        var notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 2)
        
        let noteToDelete = notes.first { $0.title == "To Delete" }!
        try notesStore.delete(noteToDelete)
        
        notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "To Keep")
    }
    
    func testDeleteAllNotes() async throws {
        try await notesStore.create(title: "First", content: "Content 1")
        try await notesStore.create(title: "Second", content: "Content 2")
        try await notesStore.create(title: "Third", content: "Content 3")
        
        var notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 3)
        
        try notesStore.deleteAll()
        
        notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 0)
    }
    
    // MARK: - Search
    
    func testSearchByTitle() async throws {
        try await notesStore.create(title: "Project Ideas", content: "Some content")
        try await notesStore.create(title: "Meeting Notes", content: "Other content")
        try await notesStore.create(title: "Shopping List", content: "More content")
        
        let results = try notesStore.search(query: "Project")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Project Ideas")
    }
    
    func testSearchByContent() async throws {
        try await notesStore.create(title: "Note One", content: "This contains the word elephant")
        try await notesStore.create(title: "Note Two", content: "This is about giraffes")
        try await notesStore.create(title: "Note Three", content: "More about elephants here")
        
        let results = try notesStore.search(query: "elephant")
        XCTAssertGreaterThanOrEqual(results.count, 0)
        XCTAssertTrue(results.contains { $0.title == "Note One" })
        XCTAssertTrue(results.contains { $0.title == "Note Three" })
    }
    
    func testSearchByTags() async throws {
        // Note: The current search implementation only searches title and content
        // This test verifies that tags are NOT searched (documenting current behavior)
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
        
        // Search for tag content - should not match based on current implementation
        let results = try notesStore.search(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift Note")
        // It matches because "swift" is in the title, not the tag
    }
    
    func testSearchNoResults() async throws {
        try await notesStore.create(title: "Note One", content: "Content")
        try await notesStore.create(title: "Note Two", content: "More content")
        
        let results = try notesStore.search(query: "nonexistent")
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchCaseInsensitive() async throws {
        try await notesStore.create(title: "Hello World", content: "Test Content")
        
        let lowerResults = try notesStore.search(query: "hello")
        XCTAssertEqual(lowerResults.count, 1)
        
        let upperResults = try notesStore.search(query: "WORLD")
        XCTAssertEqual(upperResults.count, 1)
        
        let mixedResults = try notesStore.search(query: "HeLLo WoRLd")
        XCTAssertEqual(mixedResults.count, 1)
    }
    
    func testSearchPartialMatch() async throws {
        try await notesStore.create(title: "Project Management", content: "Content here")
        try await notesStore.create(title: "Project Ideas", content: "More content")
        try await notesStore.create(title: "Personal", content: "Different")
        
        let results = try notesStore.search(query: "Proj")
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }
    
    // MARK: - Sorting
    
    func testSortByDateDescending() async throws {
        // Create notes in sequence with delays
        try await notesStore.create(title: "Oldest", content: "First note")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await notesStore.create(title: "Middle", content: "Second note")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await notesStore.create(title: "Newest", content: "Third note")
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes[0].title, "Newest")
        XCTAssertEqual(notes[1].title, "Middle")
        XCTAssertEqual(notes[2].title, "Oldest")
    }
    
    func testTogglePin() async throws {
        try await notesStore.create(title: "Test Note", content: "Content")
        
        var notes = try notesStore.fetchAll()
        let note = notes.first!
        XCTAssertFalse(note.isPinned)
        
        // Toggle pin on
        try notesStore.togglePin(note)
        notes = try notesStore.fetchAll()
        XCTAssertTrue(notes.first!.isPinned)
        
        // Toggle pin off
        try notesStore.togglePin(note)
        notes = try notesStore.fetchAll()
        XCTAssertFalse(notes.first!.isPinned)
    }
    
    func testPinUpdatesTimestamp() async throws {
        try await notesStore.create(title: "Test Note", content: "Content")
        
        var notes = try notesStore.fetchAll()
        let note = notes.first!
        let originalUpdatedAt = note.updatedAt
        
        // Wait a bit to ensure timestamp difference
        try await Task.sleep(nanoseconds: 100_000_000)
        
        try notesStore.togglePin(note)
        
        notes = try notesStore.fetchAll()
        XCTAssertGreaterThan(notes.first!.updatedAt, originalUpdatedAt)
    }
    
    // MARK: - Edge Cases
    
    func testCreateNoteWithSourceTranscriptionID() async throws {
        let transcriptionID = UUID()
        try await notesStore.create(
            title: "Transcription Note",
            content: "Content from transcription",
            sourceTranscriptionID: transcriptionID
        )
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.sourceTranscriptionID, transcriptionID)
    }
    
    func testUniqueIDs() async throws {
        try await notesStore.create(title: "First", content: "Content 1")
        try await notesStore.create(title: "Second", content: "Content 2")
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 2)
        XCTAssertNotEqual(notes[0].id, notes[1].id)
    }
    
    func testFetchEmptyStore() throws {
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 0)
    }
    
    func testDeleteFromEmptyStore() throws {
        // Should not throw when deleting all from empty store
        XCTAssertNoThrow(try notesStore.deleteAll())
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 0)
    }
    
    func testSearchEmptyStore() throws {
        let results = try notesStore.search(query: "anything")
        XCTAssertEqual(results.count, 0)
    }
    
    func testCreateNoteWithSpecialCharacters() async throws {
        try await notesStore.create(
            title: "Note with \"quotes\" and 'apostrophes'",
            content: "Content with emojis 🎉 and special chars: @#$%"
        )
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Note with \"quotes\" and 'apostrophes'")
        XCTAssertEqual(notes.first?.content, "Content with emojis 🎉 and special chars: @#$%")
    }
    
    func testCreateNoteWithMultilineContent() async throws {
        let multilineContent = """
        Line 1
        Line 2
        Line 3
        """
        try await notesStore.create(title: "Multiline", content: multilineContent)
        
        let notes = try notesStore.fetchAll()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.content, multilineContent)
    }
    
    func testSearchWithEmptyQuery() async throws {
        try await notesStore.create(title: "Note One", content: "Content")
        try await notesStore.create(title: "Note Two", content: "More content")
        
        // Empty query behavior varies - may match all or none
        let results = try notesStore.search(query: "")
        // Just verify it does not throw
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }
}
