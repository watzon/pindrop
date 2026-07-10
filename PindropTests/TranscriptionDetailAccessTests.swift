//
//  TranscriptionDetailAccessTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized, .enabled(if: sqlite3_libversion_number() > 0, "SQLite is unavailable in this environment"))
struct TranscriptionDetailAccessTests {
    private func makeRecord(
        text: String = "Hello",
        sourceKind: MediaSourceKind = .voiceRecording,
        managedMediaPath: String? = nil
    ) throws -> TranscriptionRecord {
        let container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let record = TranscriptionRecord(
            text: text,
            duration: 1,
            modelUsed: "tiny",
            sourceKind: sourceKind,
            managedMediaPath: managedMediaPath
        )
        context.insert(record)
        try context.save()
        return record
    }

    @Test func canOpenDetailForVoiceWithoutMedia() throws {
        let record = try makeRecord(sourceKind: .voiceRecording, managedMediaPath: nil)
        #expect(TranscriptionDetailAccess.canOpenDetail(for: record))
        #expect(!TranscriptionDetailAccess.shouldShowPlayback(for: record))
    }

    @Test func canOpenDetailForVoiceWithManagedAudio() throws {
        let record = try makeRecord(
            sourceKind: .voiceRecording,
            managedMediaPath: "/tmp/dictation.m4a"
        )
        #expect(TranscriptionDetailAccess.canOpenDetail(for: record))
        #expect(TranscriptionDetailAccess.shouldShowPlayback(for: record))
    }

    @Test func canOpenDetailForMediaKinds() throws {
        let imported = try makeRecord(
            sourceKind: .importedFile,
            managedMediaPath: "/tmp/file.mp3"
        )
        let meeting = try makeRecord(sourceKind: .manualCapture, managedMediaPath: nil)
        #expect(TranscriptionDetailAccess.canOpenDetail(for: imported))
        #expect(TranscriptionDetailAccess.canOpenDetail(for: meeting))
        #expect(TranscriptionDetailAccess.shouldShowPlayback(for: imported))
        #expect(!TranscriptionDetailAccess.shouldShowPlayback(for: meeting))
    }
}
