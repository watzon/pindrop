//
//  OrukeetTests.swift
//  PindropSpeech
//
//  Created on 2026-09-17.
//

#if os(macOS)
import Foundation
import AVFoundation
import Testing
import PindropCore
@testable import PindropSpeech

@MainActor
@Suite
struct OrukeetTests {
    @Test func catalogKeepsRecommendationsAndSeparateInjectedStorage() throws {
        let (locations, root) = try SpeechTestSupport.makeStorageLocations(label: "orukeet-catalog")
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = ModelManager(storageLocations: locations)
        let model = try #require(sut.availableModels.first { $0.name == ParakeetEngine.orukeetModelName })
        #expect(model.provider == .parakeet)
        #expect(model.speedRating == nil)
        #expect(model.accuracyRating == nil)
        #expect(!sut.recommendedModels.contains(model))
        let directory = ParakeetEngine.modelDirectory(forName: model.name, fluidAudioModelsRoot: locations.fluidAudioModelsRoot)
        #expect(directory.deletingLastPathComponent() == locations.fluidAudioModelsRoot)
        #expect(directory != ParakeetEngine.modelDirectory(for: .v3, fluidAudioModelsRoot: locations.fluidAudioModelsRoot))
    }

    @Test func installationRequiresStampAndEveryCompiledComponent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try OrukeetModelStore.revision.write(to: root.appendingPathComponent(".revision"), atomically: true, encoding: .utf8)
        #expect(!OrukeetModelStore.installed(at: root))
        for name in OrukeetModelStore.components {
            let model = root.appendingPathComponent("\(name).mlmodelc")
            try FileManager.default.createDirectory(at: model.appendingPathComponent("weights"), withIntermediateDirectories: true)
            try Data([1]).write(to: model.appendingPathComponent("coremldata.bin"))
            try Data([1]).write(to: model.appendingPathComponent("weights/weight.bin"))
        }
        try Data([1]).write(to: root.appendingPathComponent("parakeet_vocab.json"))
        #expect(OrukeetModelStore.installed(at: root))
        try Data().write(to: root.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin"))
        #expect(!OrukeetModelStore.installed(at: root))
    }

    @Test func manifestMustDescribePinnedArchive() throws {
        let valid = Data("""
        {"archives":{"baseline":{"filename":"orukeet-r3-coreml-baseline.zip","bytes":466579851,"sha256":"b2a6efc4ed3280c860f29b3e2e2ea242ade14c6482c94f1c8d3e8551d5edb626"}}}
        """.utf8)
        #expect(try OrukeetModelStore.validateManifest(valid).bytes == OrukeetModelStore.archiveBytes)
        let wrong = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "466579851", with: "1").utf8)
        #expect(throws: (any Error).self) { try OrukeetModelStore.validateManifest(wrong) }
    }

    @Test func interruptedDownloadUsesInjectedDirectoryAndClearsState() async throws {
        let (locations, root) = try SpeechTestSupport.makeStorageLocations(label: "orukeet-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = ParakeetEngine.modelDirectory(forName: ParakeetEngine.orukeetModelName, fluidAudioModelsRoot: locations.fluidAudioModelsRoot)
        var operations = ModelManager.DownloadOperations.production()
        operations.prepareOrukeet = { directory, _ in
            #expect(directory == expected)
            throw URLError(.networkConnectionLost)
        }
        let sut = ModelManager(storageLocations: locations, downloadOperations: operations)
        await #expect(throws: (any Error).self) { try await sut.downloadModel(named: ParakeetEngine.orukeetModelName) }
        #expect(!sut.isDownloading)
        #expect(sut.currentDownloadModel == nil)
        #expect(sut.downloadSnapshot == nil)
        #expect(!sut.downloadedModelNames.contains(ParakeetEngine.orukeetModelName))
    }

    @Test func replacingInstallationIsAtomicAndFailureKeepsOldContents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("installed")
        let replacement = root.appendingPathComponent("replacement")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: destination.appendingPathComponent("model"))
        try Data("new".utf8).write(to: replacement.appendingPathComponent("model"))
        try OrukeetModelStore.commitInstallation(from: replacement, to: destination)
        #expect(try Data(contentsOf: destination.appendingPathComponent("model")) == Data("new".utf8))
        #expect(throws: (any Error).self) {
            try OrukeetModelStore.commitInstallation(from: root.appendingPathComponent("missing"), to: destination)
        }
        #expect(try Data(contentsOf: destination.appendingPathComponent("model")) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["installed"])
    }

    @Test func cancelledOwnerDoesNotCancelIndependentInstallationWaiter() async throws {
        let gate = OrukeetInstallationGate()
        let sut = OrukeetInstallation { _, progress in try await gate.run(progress: progress) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ownerProgress = OrukeetProgressRecorder()
        let independentProgress = OrukeetProgressRecorder()
        let owner = Task { try await sut.install(at: directory, progress: { ownerProgress.record($0) }) }
        try await gate.waitForStarts(1)
        await gate.emitProgress(0.25)
        try await waitForProgress(0.25, in: ownerProgress)
        let independent = Task { try await sut.install(at: directory, progress: { independentProgress.record($0) }) }
        try await waitForWaiters(2, in: sut, directory: directory)
        #expect(independentProgress.values.contains(0.25))
        owner.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        let cancelledProgress = ownerProgress.values
        await gate.emitProgress(0.75)
        try await waitForProgress(0.75, in: independentProgress)
        #expect(ownerProgress.values == cancelledProgress)
        #expect(!independent.isCancelled)
        await gate.release()
        try await independent.value
        #expect(await gate.starts == 1)
        #expect(await gate.cancelled == 0)
    }

    @Test func cancelledJoiningWaiterDetachesItsProgressOnly() async throws {
        let gate = OrukeetInstallationGate()
        let sut = OrukeetInstallation { _, progress in try await gate.run(progress: progress) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ownerProgress = OrukeetProgressRecorder()
        let joiningProgress = OrukeetProgressRecorder()
        let owner = Task { try await sut.install(at: directory, progress: { ownerProgress.record($0) }) }
        try await gate.waitForStarts(1)
        let joining = Task { try await sut.install(at: directory, progress: { joiningProgress.record($0) }) }
        try await waitForWaiters(2, in: sut, directory: directory)
        joining.cancel()
        await #expect(throws: CancellationError.self) { try await joining.value }
        let cancelledProgress = joiningProgress.values
        await gate.emitProgress(0.75)
        try await waitForProgress(0.75, in: ownerProgress)
        #expect(joiningProgress.values == cancelledProgress)
        await gate.release()
        try await owner.value
        #expect(await gate.starts == 1)
        #expect(await gate.cancelled == 0)
    }

    @Test func cancelledOnlyWaiterStopsWorkAndRetryWaitsForCleanup() async throws {
        let gate = OrukeetInstallationGate()
        let sut = OrukeetInstallation { _, _ in try await gate.run() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let owner = Task { try await sut.install(at: directory, progress: { _ in }) }
        try await gate.waitForStarts(1)
        owner.cancel()
        await #expect(throws: CancellationError.self) { try await owner.value }
        let retry = Task { try await sut.install(at: directory, progress: { _ in }) }
        #expect(await gate.starts == 1)
        await gate.release()
        try await gate.waitForStarts(2)
        #expect(await gate.cancelled == 1)
        await gate.release()
        try await retry.value
    }

    @Test func alreadyCancelledCallerDoesNotStartInstallation() async throws {
        let gate = OrukeetInstallationGate()
        let sut = OrukeetInstallation { _, _ in try await gate.run() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await sut.install(at: directory, progress: { _ in })
        }
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await gate.starts == 0)
    }

    private func waitForProgress(_ value: Double, in recorder: OrukeetProgressRecorder) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if recorder.values.contains(value) { return }
            await Task.yield()
        }
        Issue.record("Installation progress did not reach the active caller")
        throw URLError(.timedOut)
    }

    private func waitForWaiters(_ count: Int, in installation: OrukeetInstallation, directory: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await installation.waiterCount(at: directory) == count { return }
            await Task.yield()
        }
        Issue.record("Installation callers did not register")
        throw URLError(.timedOut)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORUKEET_AUDIO_DIR"] != nil))
    func actualEngineSpeechSilenceAndCachedReload() async throws {
        let audioPath = try #require(ProcessInfo.processInfo.environment["ORUKEET_AUDIO_DIR"])
        let (locations, root) = try SpeechTestSupport.makeStorageLocations(label: "orukeet-runtime")
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = ModelManager(storageLocations: locations)
        try await sut.downloadModel(named: ParakeetEngine.orukeetModelName)
        #expect(sut.downloadedModelNames.contains(ParakeetEngine.orukeetModelName))
        let directory = try #require(sut.existingLocalModelPath(for: ParakeetEngine.orukeetModelName))
        let engine = ParakeetEngine()
        try await engine.loadModel(name: ParakeetEngine.orukeetModelName, downloadBase: directory)
        var expected: [String: String] = [:]
        for name in ["en", "de", "fr", "silence"] {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath).appendingPathComponent("\(name).wav"))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channel = try #require(buffer.floatChannelData?.pointee)
            #expect(buffer.format.sampleRate == 16000)
            #expect(buffer.format.channelCount == 1)
            let data = Data(bytes: channel, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
            let text = try await engine.transcribe(audioData: data, options: .init())
            let repeated = try await engine.transcribe(audioData: data, options: .init())
            #expect(text == repeated)
            #expect(name == "silence" ? text.isEmpty : !text.isEmpty)
            expected[name] = text
            print("ORUKEET_REAL \(name): \(text)")
        }
        await engine.unloadModel()
        try await engine.loadModel(name: ParakeetEngine.orukeetModelName, downloadBase: directory)
        #expect(engine.state == .ready)
        #expect(expected.count == 4)
        await engine.unloadModel()
    }
}
private actor OrukeetInstallationGate {
    private(set) var starts = 0
    private(set) var cancelled = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var progress: (@Sendable (Double) -> Void)?

    func run(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        self.progress = progress
        starts += 1
        await withCheckedContinuation { continuation = $0 }
        do { try Task.checkCancellation() }
        catch { cancelled += 1; throw error }
    }

    func waitForStarts(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if starts >= count { return }
            await Task.yield()
        }
        Issue.record("Installation operation did not start")
        throw URLError(.timedOut)
    }

    func emitProgress(_ value: Double) { progress?(value) }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
private final class OrukeetProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(value)
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
#endif
