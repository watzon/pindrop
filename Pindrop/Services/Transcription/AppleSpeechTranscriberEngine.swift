//
//  AppleSpeechTranscriberEngine.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  macOS 26+ streaming backend built on Speech.SpeechAnalyzer + SpeechTranscriber.
//  Emits a Parakeet-compatible `StreamingTranscriptionResult` stream so the
//  `StreamingRefinementCoordinator` can drive it without knowing which backend produced
//  the text.
//
//  Apple's native volatile/finalized result contract maps cleanly to our
//  committed/tentative split: volatile results flow through as partials (cumulative
//  text), finalized results extend the running finalized-text buffer and are forwarded
//  as an EOU so the coordinator commits the chunk.
//

import AVFoundation
import Foundation
import Speech

@available(macOS 26, *)
@MainActor
public final class AppleSpeechTranscriberEngine: StreamingTranscriptionEngine {

   public enum EngineError: Error, LocalizedError {
      case notSupportedOnThisPlatform
      case localeNotSupported(String)
      case notInstalled(String)
      case modelNotLoaded
      case invalidState(String)
      case processingFailed(String)

      public var errorDescription: String? {
         switch self {
         case .notSupportedOnThisPlatform:
            return "Apple SpeechTranscriber is not available on this system."
         case .localeNotSupported(let id):
            return "Apple SpeechTranscriber does not support locale \(id)."
         case .notInstalled(let id):
            return "Apple SpeechTranscriber assets for locale \(id) are not installed."
         case .modelNotLoaded:
            return "Apple SpeechTranscriber model is not loaded."
         case .invalidState(let message):
            return message
         case .processingFailed(let message):
            return "Apple SpeechTranscriber processing failed: \(message)"
         }
      }
   }

   public private(set) var state: StreamingTranscriptionState = .unloaded

   private let locale: Locale

   private var transcriber: SpeechTranscriber?
   private var analyzer: SpeechAnalyzer?
   private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
   private var consumptionTask: Task<Void, Never>?

   private var transcriptionCallback: StreamingTranscriptionCallback?
   private var endOfUtteranceCallback: EndOfUtteranceCallback?

   // Running aggregation. `finalizedText` grows monotonically as the transcriber emits
   // `isFinal == true` results; `currentVolatileText` holds the latest volatile snippet.
   // Our callbacks see `finalizedText + currentVolatileText` so the coordinator observes
   // cumulative text like it does with Parakeet.
   private var finalizedText = ""
   private var currentVolatileText = ""

   public init(locale: Locale = Locale(identifier: "en-US")) {
      self.locale = locale
   }

   public func loadModel(name: String) async throws {
      guard state == .unloaded || state == .error else { return }
      state = .loading

      guard SpeechTranscriber.isAvailable else {
         state = .error
         throw EngineError.notSupportedOnThisPlatform
      }

      guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
      else {
         state = .error
         throw EngineError.localeNotSupported(locale.identifier)
      }

      let newTranscriber = SpeechTranscriber(
         locale: resolvedLocale,
         preset: .progressiveTranscription
      )

      let installed = await SpeechTranscriber.installedLocales
      let alreadyInstalled = installed.contains {
         $0.identifier == resolvedLocale.identifier
      }
      if !alreadyInstalled {
         do {
            if let request = try await AssetInventory.assetInstallationRequest(
               supporting: [newTranscriber])
            {
               try await request.downloadAndInstall()
            } else {
               state = .error
               throw EngineError.notInstalled(resolvedLocale.identifier)
            }
         } catch let error as EngineError {
            throw error
         } catch {
            state = .error
            throw EngineError.processingFailed(error.localizedDescription)
         }
      }

      transcriber = newTranscriber
      state = .ready
   }

   public func unloadModel() async {
      await teardownAnalyzer()
      transcriber = nil
      state = .unloaded
   }

   public func startStreaming() async throws {
      guard let transcriber else {
         throw EngineError.modelNotLoaded
      }
      switch state {
      case .ready, .paused:
         break
      case .streaming:
         return
      default:
         throw EngineError.invalidState("Cannot start streaming in state \(state)")
      }

      finalizedText = ""
      currentVolatileText = ""

      let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      inputContinuation = continuation

      let newAnalyzer = SpeechAnalyzer(
         modules: [transcriber],
         options: SpeechAnalyzer.Options(
            priority: .userInitiated, modelRetention: .whileInUse
         )
      )
      analyzer = newAnalyzer

      // Consume results on a detached task. The results stream itself is Sendable, so we
      // hold it across the actor hop.
      let resultsStream = transcriber.results
      consumptionTask = Task { [weak self] in
         do {
            for try await result in resultsStream {
               if Task.isCancelled { break }
               await self?.handleResult(result)
            }
         } catch {
            await self?.handleConsumptionError(error)
         }
      }

      do {
         try await newAnalyzer.start(inputSequence: stream)
      } catch {
         state = .error
         throw EngineError.processingFailed(error.localizedDescription)
      }
      state = .streaming
   }

   public func stopStreaming() async throws -> String {
      guard state == .streaming || state == .paused else {
         throw EngineError.invalidState("Cannot stop streaming in state \(state)")
      }
      inputContinuation?.finish()
      inputContinuation = nil
      if let analyzer {
         do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
         } catch {
            // Best-effort finalize — drop the error but log so we don't mask issues.
            Log.transcription.warning(
               "AppleSpeechTranscriberEngine: finalize failed: \(error.localizedDescription)"
            )
         }
      }
      consumptionTask?.cancel()
      consumptionTask = nil
      analyzer = nil
      let finalText = finalizedText + currentVolatileText
      state = .ready
      return finalText
   }

   public func pauseStreaming() async {
      guard state == .streaming else { return }
      state = .paused
   }

   public func resumeStreaming() async throws {
      guard state == .paused else {
         throw EngineError.invalidState("Cannot resume streaming in state \(state)")
      }
      state = .streaming
   }

   public func processAudioChunk(_ samples: [Float]) async throws {
      guard
         let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
         let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
         let channelData = buffer.floatChannelData?[0]
      else {
         throw EngineError.processingFailed("Failed to construct PCM buffer")
      }
      buffer.frameLength = AVAudioFrameCount(samples.count)
      channelData.update(from: samples, count: samples.count)
      try await processAudioBuffer(buffer)
   }

   public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
      guard state == .streaming, let inputContinuation else {
         throw EngineError.invalidState("Cannot process audio while not streaming")
      }
      inputContinuation.yield(AnalyzerInput(buffer: buffer))
   }

   public func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
      transcriptionCallback = callback
   }

   public func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
      endOfUtteranceCallback = callback
   }

   public func reset() async {
      await teardownAnalyzer()
      finalizedText = ""
      currentVolatileText = ""
      state = transcriber != nil ? .ready : .unloaded
   }

   // MARK: - Private

   private func teardownAnalyzer() async {
      inputContinuation?.finish()
      inputContinuation = nil
      consumptionTask?.cancel()
      consumptionTask = nil
      if let analyzer {
         await analyzer.cancelAndFinishNow()
      }
      analyzer = nil
   }

   private func handleResult(_ result: SpeechTranscriber.Result) async {
      let chunk = String(result.text.characters)
      if result.isFinal {
         finalizedText += chunk
         currentVolatileText = ""
         let cumulative = finalizedText
         transcriptionCallback?(
            StreamingTranscriptionResult(
               text: cumulative, isFinal: true,
               timestamp: Date().timeIntervalSince1970
            ))
         endOfUtteranceCallback?(cumulative)
      } else {
         currentVolatileText = chunk
         let cumulative = finalizedText + currentVolatileText
         transcriptionCallback?(
            StreamingTranscriptionResult(
               text: cumulative, isFinal: false,
               timestamp: Date().timeIntervalSince1970
            ))
      }
   }

   private func handleConsumptionError(_ error: Error) async {
      Log.transcription.error(
         "AppleSpeechTranscriberEngine: result stream error: \(error.localizedDescription)"
      )
      state = .error
   }
}
