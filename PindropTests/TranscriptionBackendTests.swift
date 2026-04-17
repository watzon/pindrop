//
//  TranscriptionBackendTests.swift
//  PindropTests
//
//  Created on 2026-04-17.
//
//  Verifies the Phase 3 backend resolution: the user's selection in SettingsStore is
//  honored unless Apple's SpeechTranscriber isn't available on the host, in which case
//  Parakeet is substituted.
//

import AVFoundation
import Foundation
import Speech
import Testing
@testable import Pindrop

@MainActor
@Suite
struct TranscriptionBackendTests {

   /// Minimal stub for StreamingTranscriptionEngine, scoped to this suite so we aren't
   /// coupled to TranscriptionServiceTests' private mock.
   @MainActor
   final class StubStreamingEngine: StreamingTranscriptionEngine {
      var state: StreamingTranscriptionState = .unloaded
      private(set) var loadCount = 0
      private(set) var unloadCount = 0

      func loadModel(name: String) async throws {
         loadCount += 1
         state = .ready
      }
      func unloadModel() async {
         unloadCount += 1
         state = .unloaded
      }
      func startStreaming() async throws { state = .streaming }
      func stopStreaming() async throws -> String {
         state = .ready
         return ""
      }
      func pauseStreaming() async { state = .paused }
      func resumeStreaming() async throws { state = .streaming }
      func processAudioChunk(_ samples: [Float]) async throws {}
      func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {}
      func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {}
      func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {}
      func reset() async { state = .ready }
   }

   private func makeCleanStore() -> SettingsStore {
      let store = SettingsStore()
      store.resetAllSettings()
      return store
   }

   @Test func defaultBackendIsParakeet() {
      let store = makeCleanStore()
      #expect(store.selectedTranscriptionBackend == .parakeet)
      #expect(store.resolvedTranscriptionBackend == .parakeet)
   }

   @Test func selectionRoundTripsThroughRawStorage() {
      let store = makeCleanStore()
      store.selectedTranscriptionBackend = .appleSpeechTranscriber
      #expect(store.transcriptionBackend == "apple")
      #expect(store.selectedTranscriptionBackend == .appleSpeechTranscriber)
   }

   @Test func applePreferenceResolvesToAppleOnlyWhenAvailable() {
      let store = makeCleanStore()
      store.selectedTranscriptionBackend = .appleSpeechTranscriber

      // `resolvedTranscriptionBackend` answers .apple only on hosts that expose
      // SpeechTranscriber. Mirror the same check we perform at the call site.
      let expected: TranscriptionBackend = SettingsStore.appleSpeechTranscriberAvailable
         ? .appleSpeechTranscriber
         : .parakeet
      #expect(store.resolvedTranscriptionBackend == expected)
   }

   @Test func availabilityMatchesSpeechTranscriberIsAvailable() {
      let expected: Bool
      if #available(macOS 26, *) {
         expected = SpeechTranscriber.isAvailable
      } else {
         expected = false
      }
      #expect(SettingsStore.appleSpeechTranscriberAvailable == expected)
   }

   // MARK: - TranscriptionService integration

   @Test func prepareStreamingEngineSwitchesEngineOnBackendChange() async throws {
      // Two-stage test: first a Parakeet backend → ParakeetStreamingEngine; then an
      // Apple preference → Apple engine (on macOS 26+) or fallback with the flag set.
      let parakeetEngine = StubStreamingEngine()
      let appleEngine = StubStreamingEngine()
      var backend: TranscriptionBackend = .parakeet
      let service = TranscriptionService(
         streamingEngineFactory: { _ in parakeetEngine },
         appleSpeechEngineFactory: { appleEngine },
         streamingBackendProvider: { backend }
      )

      try await service.prepareStreamingEngine()
      #expect(parakeetEngine.state == .ready)

      backend = .appleSpeechTranscriber
      try await service.prepareStreamingEngine()
      #expect(appleEngine.state == .ready)
      // Parakeet should have been torn down on backend swap.
      #expect(parakeetEngine.unloadCount >= 1)
   }

   @Test func appleUnavailabilityFallsBackToParakeetAndSetsFlag() async throws {
      let parakeetEngine = StubStreamingEngine()
      // Simulate macOS < 26 by returning nil from the Apple factory.
      let service = TranscriptionService(
         streamingEngineFactory: { _ in parakeetEngine },
         appleSpeechEngineFactory: { nil },
         streamingBackendProvider: { .appleSpeechTranscriber }
      )

      try await service.prepareStreamingEngine()
      #expect(parakeetEngine.state == .ready)
      #expect(service.consumeAppleBackendFallbackFlag() == true)
      // Second read — the flag is one-shot.
      #expect(service.consumeAppleBackendFallbackFlag() == false)
   }
}
