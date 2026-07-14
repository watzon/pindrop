//
//  TelemetryServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-14.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class TelemetrySinkSpy: TelemetrySink {
    private(set) var initializedAppIDs: [String] = []
    private(set) var sentSignals: [(name: String, parameters: [String: String])] = []

    func initialize(appID: String) {
        initializedAppIDs.append(appID)
    }

    func send(_ signalName: String, parameters: [String: String]) {
        sentSignals.append((signalName, parameters))
    }
}

@MainActor
@Suite(.serialized)
struct TelemetryServiceTests {
    @Test func dropsSignalsWhenTelemetryDisabled() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink)

        #expect(settings.telemetryEnabled == false)
        sut.send(.appLaunched)

        #expect(sink.sentSignals.isEmpty)
        #expect(sink.initializedAppIDs.isEmpty)
    }

    @Test func sendsSignalsWhenTelemetryEnabled() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink)

        sut.send(.appLaunched, parameters: [TelemetryParameter.backend: "parakeet"])

        #expect(sink.initializedAppIDs == ["TEST-APP-ID"])
        #expect(sink.sentSignals.count == 1)
        #expect(sink.sentSignals.first?.name == "app.launched")
        #expect(sink.sentSignals.first?.parameters[TelemetryParameter.backend] == "parakeet")
    }

    @Test func initializesSinkOnlyOnce() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink)

        sut.send(.appLaunched)
        sut.send(.transcriptionSucceeded)

        #expect(sink.initializedAppIDs == ["TEST-APP-ID"])
        #expect(sink.sentSignals.count == 2)
    }

    @Test func dropsSignalsWhenSuppressed() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink, isSuppressed: { true })

        sut.send(.appLaunched)

        #expect(sink.sentSignals.isEmpty)
    }

    @Test func dropsSignalsWhenAppIDUnconfigured() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink, appID: "")

        sut.send(.appLaunched)

        #expect(sink.sentSignals.isEmpty)
        #expect(sut.isConfigured == false)
    }

    @Test func samplingDropsSignalsAboveRate() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink, randomUnit: { 0.9 })

        sut.send(.transcriptionSucceeded, sampleRate: 0.5)

        #expect(sink.sentSignals.isEmpty)
    }

    @Test func samplingKeepsSignalsBelowRate() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink, randomUnit: { 0.1 })

        sut.send(.transcriptionSucceeded, sampleRate: 0.5)

        #expect(sink.sentSignals.count == 1)
    }

    @Test func fullRateNeverConsultsRandomness() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true
        let sink = TelemetrySinkSpy()
        let sut = makeService(settings: settings, sink: sink, randomUnit: {
            Issue.record("randomUnit must not be consulted at sampleRate 1.0")
            return 0.0
        })

        sut.send(.transcriptionFailed)

        #expect(sink.sentSignals.count == 1)
    }

    // MARK: - Sanitizers

    @Test func errorCaseNameStripsAssociatedValues() {
        let error = TranscriptionService.TranscriptionError.transcriptionFailed("/Users/someone/secret/path.wav")
        let name = TelemetryService.errorCaseName(error)

        #expect(name == "TranscriptionError.transcriptionFailed")
        #expect(!name.contains("secret"))
    }

    @Test func errorCaseNameHandlesBareEnumCases() {
        let error = TranscriptionService.TranscriptionError.modelNotLoaded
        #expect(TelemetryService.errorCaseName(error) == "TranscriptionError.modelNotLoaded")
    }

    @Test func errorCaseNameReducesNonEnumErrorsToTypeName() {
        struct SampleFailure: Error {
            let message = "user content"
        }
        let name = TelemetryService.errorCaseName(SampleFailure())

        #expect(name == "SampleFailure")
        #expect(!name.contains("user content"))
    }

    @Test func durationBuckets() {
        #expect(TelemetryService.durationBucket(2) == "<5s")
        #expect(TelemetryService.durationBucket(10) == "5-15s")
        #expect(TelemetryService.durationBucket(30) == "15-60s")
        #expect(TelemetryService.durationBucket(120) == "1-5m")
        #expect(TelemetryService.durationBucket(900) == ">5m")
    }

    @Test func wordCountBuckets() {
        #expect(TelemetryService.wordCountBucket(0) == "0")
        #expect(TelemetryService.wordCountBucket(5) == "1-10")
        #expect(TelemetryService.wordCountBucket(30) == "11-50")
        #expect(TelemetryService.wordCountBucket(100) == "51-200")
        #expect(TelemetryService.wordCountBucket(500) == ">200")
    }

    // MARK: - Helpers

    private func makeService(
        settings: SettingsStore,
        sink: TelemetrySinkSpy,
        appID: String = "TEST-APP-ID",
        isSuppressed: @escaping () -> Bool = { false },
        randomUnit: @escaping () -> Double = { 0.0 }
    ) -> TelemetryService {
        TelemetryService(
            settingsStore: settings,
            sink: sink,
            appID: appID,
            isSuppressed: isSuppressed,
            randomUnit: randomUnit
        )
    }

    private func makeSettingsStore() -> SettingsStore {
        let settings = SettingsStore()
        cleanup(settings)
        return settings
    }

    private func cleanup(_ settings: SettingsStore) {
        settings.resetAllSettings()
        try? settings.deleteAPIEndpoint()
        try? settings.deleteAPIKey()
    }
}
