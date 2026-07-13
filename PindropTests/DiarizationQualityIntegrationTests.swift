import AVFoundation
import Foundation
import Testing
@testable import Pindrop

private let diarizationIntegrationPrerequisitesAvailable: Bool = {
    guard ProcessInfo.processInfo.environment["PINDROP_RUN_INTEGRATION_TESTS"] == "1" else { return false }
    let configuredRoot = ProcessInfo.processInfo.environment["PINDROP_DIARIZATION_FIXTURE_ROOT"]
    let root = configuredRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: "PindropTests/Fixtures/Diarization/Generated", isDirectory: true)
    return FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path)
}()

@MainActor
@Suite(.serialized, .enabled(if: diarizationIntegrationPrerequisitesAvailable, "Diarization fixtures/models are unavailable"))
struct DiarizationQualityIntegrationTests {
    static var prerequisitesAvailable: Bool {
        guard ProcessInfo.processInfo.environment["PINDROP_RUN_INTEGRATION_TESTS"] == "1" else { return false }
        let root = fixtureRoot
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path)
    }

    private static var fixtureRoot: URL {
        if let configured = ProcessInfo.processInfo.environment["PINDROP_DIARIZATION_FIXTURE_ROOT"] {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return URL(fileURLWithPath: "PindropTests/Fixtures/Diarization/Generated", isDirectory: true)
    }

    private struct Fixture: Decodable {
        let id: String
        let audio: String
        let expectedSpeakerCount: Int
    }

    private func fixtures() throws -> [Fixture] {
        let data = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode([Fixture].self, from: data)
    }

    @Test func publicFixturesProduceExpectedSpeakerCounts() async throws {
        for fixture in try fixtures() {
            let url = Self.fixtureRoot.appendingPathComponent(fixture.audio)
            let samples = try Self.readMono16kWAV(url)
            let diarizer = FluidSpeakerDiarizer()
            let result = try await diarizer.diarize(samples: samples, sampleRate: 16_000, options: .init())
            #expect(result.speakerCount == fixture.expectedSpeakerCount, "fixture=\(fixture.id)")
        }
    }

    @Test func exactSpeakerCountProducesRequestedCountForFixture() async throws {
        guard let fixture = try fixtures().first else { return }
        let samples = try Self.readMono16kWAV(Self.fixtureRoot.appendingPathComponent(fixture.audio))
        let diarizer = FluidSpeakerDiarizer()
        let result = try await diarizer.diarize(
            samples: samples,
            sampleRate: 16_000,
            options: DiarizationOptions(expectedSpeakerCount: fixture.expectedSpeakerCount)
        )
        #expect(result.speakerCount == fixture.expectedSpeakerCount)
    }

    private static func readMono16kWAV(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

struct DiarizationFrameErrorRates: Equatable {
    let missedSpeech: Double
    let falseAlarm: Double
    let speakerConfusion: Double

    var diarizationErrorRate: Double {
        missedSpeech + falseAlarm + speakerConfusion
    }

    static func score(reference: [String?], predicted: [String?]) -> DiarizationFrameErrorRates {
        guard reference.count == predicted.count, !reference.isEmpty else {
            return DiarizationFrameErrorRates(missedSpeech: 0, falseAlarm: 0, speakerConfusion: 0)
        }
        let speech = reference.filter { $0 != nil }.count
        let referenceSpeech = max(speech, 1)
        let mapping = optimalLabelMapping(reference: reference, predicted: predicted)
        let missed = zip(reference, predicted).filter { $0.0 != nil && $0.1 == nil }.count
        let falseAlarm = zip(reference, predicted).filter { $0.0 == nil && $0.1 != nil }.count
        let confusion = zip(reference, predicted).filter {
            guard let referenceLabel = $0.0, let predictedLabel = $0.1 else { return false }
            return mapping[predictedLabel] != referenceLabel
        }.count
        return DiarizationFrameErrorRates(
            missedSpeech: Double(missed) / Double(referenceSpeech),
            falseAlarm: Double(falseAlarm) / Double(referenceSpeech),
            speakerConfusion: Double(confusion) / Double(referenceSpeech)
        )
    }

    private static func optimalLabelMapping(
        reference: [String?],
        predicted: [String?]
    ) -> [String: String] {
        let referenceLabels = Array(Set(reference.compactMap { $0 })).sorted()
        let predictedLabels = Array(Set(predicted.compactMap { $0 })).sorted()
        guard !referenceLabels.isEmpty, !predictedLabels.isEmpty else { return [:] }

        var bestMapping: [String: String] = [:]
        var bestMatches = -1

        func visit(_ index: Int, _ mapping: [String: String], _ used: Set<String>) {
            if index == predictedLabels.count {
                let matches = zip(reference, predicted).reduce(into: 0) { count, pair in
                    guard let referenceLabel = pair.0,
                          let predictedLabel = pair.1,
                          mapping[predictedLabel] == referenceLabel else { return }
                    count += 1
                }
                if matches > bestMatches {
                    bestMatches = matches
                    bestMapping = mapping
                }
                return
            }
            let predictedLabel = predictedLabels[index]
            for referenceLabel in referenceLabels where !used.contains(referenceLabel) {
                var nextMapping = mapping
                nextMapping[predictedLabel] = referenceLabel
                visit(index + 1, nextMapping, used.union([referenceLabel]))
            }
            visit(index + 1, mapping, used)
        }

        visit(0, [:], [])
        return bestMapping
    }
}
@Suite
struct DiarizationFrameErrorRateTests {
    @Test func scoreIsInvariantToClusterLabelPermutation() {
        let score = DiarizationFrameErrorRates.score(
            reference: ["A", "A", "B", "B", nil],
            predicted: ["cluster-2", "cluster-2", "cluster-1", "cluster-1", nil]
        )
        #expect(score.diarizationErrorRate == 0)
    }

    @Test func scoreSeparatesMissedFalseAlarmAndConfusion() {
        let score = DiarizationFrameErrorRates.score(
            reference: ["A", "A", nil, "B"],
            predicted: ["A", nil, "B", "A"]
        )
        #expect(score.missedSpeech == 1.0 / 3.0)
        #expect(score.falseAlarm == 1.0 / 3.0)
        #expect(score.speakerConfusion == 1.0 / 3.0)
    }
}
