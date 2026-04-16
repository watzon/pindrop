//
//  AppleSpeechEngine.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation
import Speech
import AVFoundation

@MainActor
public final class AppleSpeechEngine: TranscriptionEngine, CapabilityReporting {

    public static var capabilities: AudioEngineCapabilities {
        [.transcription, .languageDetection]
    }

    public enum EngineError: Error, LocalizedError {
        case authorizationDenied
        case recognizerUnavailable(Locale)
        case invalidAudioData
        case recognitionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                return "Speech recognition permission was denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
            case .recognizerUnavailable(let locale):
                return "Apple Speech recognition is not available for '\(locale.identifier)' on this device."
            case .invalidAudioData:
                return "The audio data is empty or invalid."
            case .recognitionFailed(let message):
                return "Speech recognition failed: \(message)"
            }
        }
    }

    public private(set) var state: TranscriptionEngineState = .unloaded
    public private(set) var error: Error?

    public init() {}

    // `name` is the model name ("apple_speech_on_device"), not a language.
    // Authorization is the only thing to check at load time; the recognizer
    // is created per-transcription using the language from TranscriptionOptions.
    public func loadModel(path: String) async throws {
        throw EngineError.recognitionFailed(
            "Apple Speech does not use local model files. Use loadModel(name:downloadBase:) instead."
        )
    }

    public func loadModel(name: String, downloadBase: URL? = nil) async throws {
        guard state != .loading else { return }
        state = .loading
        error = nil

        do {
            try await requestAuthorization()
            state = .ready
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }

    public func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        guard state == .ready else {
            throw EngineError.recognitionFailed("Model not loaded. Call loadModel first.")
        }
        guard !audioData.isEmpty else {
            throw EngineError.invalidAudioData
        }

        // Resolve the locale now that we know the actual language being transcribed.
        // Automatic → device's current locale (best match for system speech models).
        let locale = resolvedLocale(for: options.language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw EngineError.recognizerUnavailable(locale)
        }
        recognizer.defaultTaskHint = .dictation

        state = .transcribing

        do {
            let buffer = try makePCMBuffer(from: audioData)
            let result = try await performRecognition(using: recognizer, buffer: buffer)
            state = .ready
            return result
        } catch {
            state = .ready
            self.error = error
            throw error
        }
    }

    public func unloadModel() async {
        error = nil
        state = .unloaded
    }

    // MARK: - Private helpers

    private func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw EngineError.authorizationDenied
        case .notDetermined:
            throw EngineError.recognitionFailed("Speech recognition authorization was not determined.")
        @unknown default:
            throw EngineError.recognitionFailed("Unknown speech recognition authorization status.")
        }
    }

    /// Maps AppLanguage to a Locale suitable for SFSpeechRecognizer.
    /// `.automatic` resolves to the device's current locale so the system
    /// speech model matches the user's actual language.
    private func resolvedLocale(for language: AppLanguage) -> Locale {
        switch language {
        case .automatic:
            // Use the full device locale (e.g. "en-US", "fr-FR") so SFSpeechRecognizer
            // picks the best available on-device model.
            return Locale.current
        default:
            // AppLanguage rawValues are BCP-47 codes ("en", "es", "ja", etc.).
            // Prefer the full device locale when the language codes match, so we
            // get the regional variant the device already has a model for.
            let tag = language.rawValue
            if Locale.current.language.languageCode?.identifier == tag {
                return Locale.current
            }
            return Locale(identifier: tag)
        }
    }

    private func makePCMBuffer(from data: Data) throws -> AVAudioPCMBuffer {
        let sampleCount = data.count / MemoryLayout<Float>.size
        guard sampleCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))
        else {
            throw EngineError.invalidAudioData
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { rawBytes in
            guard let src = rawBytes.baseAddress?.assumingMemoryBound(to: Float.self),
                  let dst = buffer.floatChannelData?[0] else { return }
            dst.update(from: src, count: sampleCount)
        }
        return buffer
    }

    private func performRecognition(
        using recognizer: SFSpeechRecognizer,
        buffer: AVAudioPCMBuffer
    ) async throws -> String {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let error {
                    didResume = true
                    continuation.resume(throwing: EngineError.recognitionFailed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
            request.append(buffer)
            request.endAudio()
        }
    }
}
