//
//  DictationAudioRetentionServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite
struct DictationAudioRetentionServiceTests {
    private struct Fixture {
        let modelContainer: ModelContainer
        let modelContext: ModelContext
        let historyStore: HistoryStore
        let settingsStore: SettingsStore
        let directoryURL: URL
        var now: Date
        let sut: DictationAudioRetentionService
    }

    private func makeFixture(
        retention: DictationAudioRetention = .days7,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> Fixture {
        let modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let historyStore = HistoryStore(modelContext: modelContext)
        let settingsStore = SettingsStore()
        settingsStore.dictationAudioRetention = retention

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-dictation-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var clock = now
        let sut = DictationAudioRetentionService(
            historyStore: historyStore,
            settingsStore: settingsStore,
            directoryURL: directoryURL,
            now: { clock }
        )

        return Fixture(
            modelContainer: modelContainer,
            modelContext: modelContext,
            historyStore: historyStore,
            settingsStore: settingsStore,
            directoryURL: directoryURL,
            now: now,
            sut: sut
        )
    }

    private func cleanup(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directoryURL)
        fixture.settingsStore.resetAllSettings()
    }

    /// Mono float32 PCM at 16 kHz: short sine tone.
    private func makeSinePCM(seconds: Double = 0.25, frequency: Float = 440, sampleRate: Double = 16_000) -> Data {
        let frameCount = Int(seconds * sampleRate)
        var samples = [Float](repeating: 0, count: frameCount)
        let twoPi = Float(2 * Double.pi)
        for i in 0..<frameCount {
            samples[i] = sin(twoPi * frequency * Float(i) / Float(sampleRate)) * 0.5
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func writeFixtureAudio(
        for recordID: UUID,
        in directory: URL,
        pcm: Data? = nil
    ) throws -> URL {
        let audioData = pcm ?? makeSinePCM()
        return try DictationAudioRetentionService.encodeAndWritePeaks(
            pcmFloatData: audioData,
            recordID: recordID,
            directoryURL: directory
        )
    }

    // MARK: - Retention sweeper

    @Test func testSweepDeletesExpiredVoiceAudioKeepsTranscriptAndFresh() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = try makeFixture(retention: .days7, now: fixedNow)
        defer { cleanup(fixture) }

        let expiredID = UUID()
        let freshID = UUID()
        let mediaID = UUID()

        let expiredURL = try writeFixtureAudio(for: expiredID, in: fixture.directoryURL)
        let freshURL = try writeFixtureAudio(for: freshID, in: fixture.directoryURL)
        let mediaURL = fixture.directoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("media-\(mediaID.uuidString).mp4")
        try Data("not-dictation".utf8).write(to: mediaURL)
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        let expiredRecord = try fixture.historyStore.save(
            text: "expired transcript",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording,
            managedMediaPath: expiredURL.path
        )
        expiredRecord.timestamp = fixedNow.addingTimeInterval(-8 * 24 * 60 * 60)

        let freshRecord = try fixture.historyStore.save(
            text: "fresh transcript",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording,
            managedMediaPath: freshURL.path
        )
        freshRecord.timestamp = fixedNow.addingTimeInterval(-2 * 24 * 60 * 60)

        let mediaRecord = try fixture.historyStore.save(
            text: "imported media transcript",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            managedMediaPath: mediaURL.path
        )
        mediaRecord.timestamp = fixedNow.addingTimeInterval(-30 * 24 * 60 * 60)

        try fixture.historyStore.saveContext()

        let result = try fixture.sut.sweepExpired()

        #expect(result.deletedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
        #expect(!FileManager.default.fileExists(atPath: WaveformPeaks.sidecarURL(for: expiredURL).path))
        #expect(FileManager.default.fileExists(atPath: freshURL.path))
        #expect(FileManager.default.fileExists(atPath: mediaURL.path))

        let reloadedExpired = try #require(try fixture.historyStore.fetchRecord(with: expiredRecord.id))
        #expect(reloadedExpired.text == "expired transcript")
        #expect(reloadedExpired.managedMediaPath == nil)

        let reloadedFresh = try #require(try fixture.historyStore.fetchRecord(with: freshRecord.id))
        #expect(reloadedFresh.managedMediaPath == freshURL.path)

        let reloadedMedia = try #require(try fixture.historyStore.fetchRecord(with: mediaRecord.id))
        #expect(reloadedMedia.managedMediaPath == mediaURL.path)
        #expect(reloadedMedia.text == "imported media transcript")
    }

    @Test func testSweepWithForeverDeletesNothing() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = try makeFixture(retention: .forever, now: fixedNow)
        defer { cleanup(fixture) }

        let recordID = UUID()
        let mediaURL = try writeFixtureAudio(for: recordID, in: fixture.directoryURL)
        let record = try fixture.historyStore.save(
            text: "kept forever",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording,
            managedMediaPath: mediaURL.path
        )
        record.timestamp = fixedNow.addingTimeInterval(-365 * 24 * 60 * 60)
        try fixture.historyStore.saveContext()

        let result = try fixture.sut.sweepExpired()
        #expect(result.deletedCount == 0)
        #expect(FileManager.default.fileExists(atPath: mediaURL.path))
        #expect(try fixture.historyStore.fetchRecord(with: record.id)?.managedMediaPath == mediaURL.path)
    }

    // MARK: - Retention off means no persistence

    @Test func testRetentionOffDoesNotPersist() async throws {
        let fixture = try makeFixture(retention: .off)
        defer { cleanup(fixture) }

        let record = try fixture.historyStore.save(
            text: "no audio",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording
        )

        fixture.sut.schedulePersist(pcmFloatData: makeSinePCM(), recordID: record.id)

        // Allow any accidental async work to settle.
        try await Task.sleep(nanoseconds: 200_000_000)

        let reloaded = try #require(try fixture.historyStore.fetchRecord(with: record.id))
        #expect(reloaded.managedMediaPath == nil)

        let usage = try fixture.sut.diskUsage()
        #expect(usage.snippetCount == 0)
        #expect(usage.totalBytes == 0)
    }

    @Test func testSchedulePersistAttachesPathWhenRetentionEnabled() async throws {
        let fixture = try makeFixture(retention: .days7)
        defer { cleanup(fixture) }

        let record = try fixture.historyStore.save(
            text: "with audio",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording
        )

        fixture.sut.schedulePersist(pcmFloatData: makeSinePCM(), recordID: record.id)

        // Wait for detached encode + main-actor path attach.
        var attachedPath: String?
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let path = try fixture.historyStore.fetchRecord(with: record.id)?.managedMediaPath {
                attachedPath = path
                break
            }
        }

        let path = try #require(attachedPath)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(path.hasSuffix(".m4a"))
        #expect(FileManager.default.fileExists(atPath: WaveformPeaks.sidecarURL(for: URL(fileURLWithPath: path)).path))
    }

    // MARK: - Disk usage

    @Test func testDiskUsageAggregation() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }

        let url1 = try writeFixtureAudio(for: UUID(), in: fixture.directoryURL)
        let url2 = try writeFixtureAudio(for: UUID(), in: fixture.directoryURL)
        _ = url1
        _ = url2

        let usage = try fixture.sut.diskUsage()
        #expect(usage.snippetCount == 2)
        #expect(usage.totalBytes > 0)
    }

    // MARK: - deleteAll

    @Test func testDeleteAllClearsAudioKeepsTranscripts() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }

        let voiceURL = try writeFixtureAudio(for: UUID(), in: fixture.directoryURL)
        let mediaURL = fixture.directoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("imported-\(UUID().uuidString).mp4")
        try Data("imported".utf8).write(to: mediaURL)
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        let voice = try fixture.historyStore.save(
            text: "voice kept",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .voiceRecording,
            managedMediaPath: voiceURL.path
        )
        let imported = try fixture.historyStore.save(
            text: "import kept",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            managedMediaPath: mediaURL.path
        )

        try fixture.sut.deleteAllDictationAudio()

        #expect(!FileManager.default.fileExists(atPath: voiceURL.path))
        #expect(!FileManager.default.fileExists(atPath: WaveformPeaks.sidecarURL(for: voiceURL).path))
        #expect(FileManager.default.fileExists(atPath: mediaURL.path))

        let reloadedVoice = try #require(try fixture.historyStore.fetchRecord(with: voice.id))
        #expect(reloadedVoice.text == "voice kept")
        #expect(reloadedVoice.managedMediaPath == nil)

        let reloadedImported = try #require(try fixture.historyStore.fetchRecord(with: imported.id))
        #expect(reloadedImported.managedMediaPath == mediaURL.path)
        #expect(reloadedImported.text == "import kept")

        let usage = try fixture.sut.diskUsage()
        #expect(usage.snippetCount == 0)
    }
}

// MARK: - Waveform peaks

@Suite
struct WaveformPeaksTests {
    /// Write a mono 16-bit PCM WAV sine wave for AVAudioFile-based extraction tests.
    private func writeSineWaveWAV(
        frequency: Double = 440,
        sampleRate: Double = 16_000,
        duration: Double = 0.5,
        amplitude: Float = 0.8
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)
        var samples = [Int16](repeating: 0, count: frameCount)
        let twoPi = 2.0 * Double.pi
        for i in 0..<frameCount {
            let value = sin(twoPi * frequency * Double(i) / sampleRate) * Double(amplitude)
            samples[i] = Int16(max(-1.0, min(1.0, value)) * Double(Int16.max))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-sine-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let dataSize = frameCount * MemoryLayout<Int16>.size
        var header = Data()
        func appendASCII(_ s: String) { header.append(contentsOf: s.utf8) }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 2))
        }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 4))
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16) // PCM chunk size
        appendUInt16(1) // PCM format
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate) * 2) // byte rate
        appendUInt16(2) // block align
        appendUInt16(16) // bits per sample
        appendASCII("data")
        appendUInt32(UInt32(dataSize))

        var fileData = header
        samples.withUnsafeBufferPointer { fileData.append(Data(buffer: $0)) }
        try fileData.write(to: url)
        return url
    }

    @Test func testExtractPeaksBucketCountAndNormalization() throws {
        let wavURL = try writeSineWaveWAV()
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let peaks = try WaveformPeaks.extract(from: wavURL, bucketCount: 200)
        #expect(peaks.count == 200)

        let maxPeak = peaks.max() ?? 0
        #expect(maxPeak > 0.5)
        #expect(maxPeak <= 1.0 + 0.001)
        #expect(peaks.allSatisfy { $0 >= 0 && $0 <= 1.0 + 0.001 })
    }

    @Test func testLoaderBackfillsAndCachesSidecar() throws {
        let wavURL = try writeSineWaveWAV()
        defer {
            try? FileManager.default.removeItem(at: wavURL)
            WaveformPeaks.removeSidecar(for: wavURL)
        }

        let sidecar = WaveformPeaks.sidecarURL(for: wavURL)
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))

        let peaks = try WaveformPeaksLoader.load(for: wavURL, bucketCount: 200)
        #expect(peaks.count == 200)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))

        let cached = try WaveformPeaksLoader.load(for: wavURL, bucketCount: 200)
        #expect(cached == peaks)
    }

    @Test func testExtractFromPCMFloatData() throws {
        let sampleRate = 16_000.0
        let frameCount = Int(0.25 * sampleRate)
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = sin(2 * Float.pi * 440 * Float(i) / Float(sampleRate)) * 0.6
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let peaks = try WaveformPeaks.extract(fromPCMFloatData: data, sampleRate: sampleRate, bucketCount: 200)
        #expect(peaks.count == 200)
        #expect((peaks.max() ?? 0) > 0.5)
        #expect(peaks.allSatisfy { $0 >= 0 && $0 <= 1.0 + 0.001 })
    }
}

// MARK: - Settings

@MainActor
@Suite
struct DictationAudioRetentionSettingsTests {
    @Test func testDefaultRetentionIsDays7() {
        let settings = SettingsStore()
        settings.resetAllSettings()
        defer { settings.resetAllSettings() }

        #expect(settings.dictationAudioRetention == .days7)

        settings.dictationAudioRetention = .off
        #expect(settings.dictationAudioRetention == .off)
        #expect(settings.dictationAudioRetentionRawValue == DictationAudioRetention.off.rawValue)

        settings.dictationAudioRetention = .days30
        #expect(settings.dictationAudioRetention == .days30)

        settings.resetAllSettings()
        #expect(settings.dictationAudioRetention == .days7)
    }
}
