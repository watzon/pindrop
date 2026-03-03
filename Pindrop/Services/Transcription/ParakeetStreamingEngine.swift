//
//  ParakeetStreamingEngine.swift
//  Pindrop
//
//  Created on 2026-03-03.
//

import AVFoundation
import FluidAudio
import Foundation

@MainActor
public final class ParakeetStreamingEngine: StreamingTranscriptionEngine {

    public enum EngineError: Error, LocalizedError {
        case modelNotFound(String)
        case modelNotLoaded
        case invalidState(String)
        case processingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Streaming model not found at path: \(path)"
            case .modelNotLoaded:
                return "Streaming model is not loaded"
            case .invalidState(let message):
                return message
            case .processingFailed(let message):
                return "Streaming transcription failed: \(message)"
            }
        }
    }

    public private(set) var state: StreamingTranscriptionState = .unloaded

    private var manager: StreamingEouAsrManager?
    private var transcriptionCallback: StreamingTranscriptionCallback?
    private var endOfUtteranceCallback: EndOfUtteranceCallback?

    public init() {}

    public func loadModel(name: String) async throws {
        guard state != .loading else { return }

        state = .loading

        do {
            let modelDirectory = resolveModelDirectory(for: name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw EngineError.modelNotFound(modelDirectory.path)
            }

            let streamingManager = StreamingEouAsrManager(chunkSize: .ms160)
            await streamingManager.setPartialCallback { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = StreamingTranscriptionResult(
                        text: text,
                        isFinal: false,
                        timestamp: Date().timeIntervalSince1970
                    )
                    self.transcriptionCallback?(result)
                }
            }
            await streamingManager.setEouCallback { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let result = StreamingTranscriptionResult(
                        text: text,
                        isFinal: true,
                        timestamp: Date().timeIntervalSince1970
                    )
                    self.transcriptionCallback?(result)
                    self.endOfUtteranceCallback?(text)
                }
            }

            try await streamingManager.loadModels(modelDir: modelDirectory)

            manager = streamingManager
            state = .ready
        } catch {
            state = .error
            if let engineError = error as? EngineError {
                throw engineError
            }
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        if let manager {
            await manager.reset()
        }
        manager = nil
        state = .unloaded
    }

    public func startStreaming() async throws {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        switch state {
        case .ready, .paused:
            await manager.reset()
            state = .streaming
        case .streaming:
            return
        case .loading, .unloaded, .error:
            throw EngineError.invalidState("Cannot start streaming while in state: \(state)")
        }
    }

    public func stopStreaming() async throws -> String {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        guard state == .streaming || state == .paused else {
            throw EngineError.invalidState("Cannot stop streaming while in state: \(state)")
        }

        do {
            let finalText = try await manager.finish()
            state = .ready
            return finalText
        } catch {
            state = .ready
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func pauseStreaming() async {
        guard state == .streaming else { return }
        state = .paused
    }

    public func resumeStreaming() async throws {
        guard state == .paused else {
            throw EngineError.invalidState("Cannot resume streaming while in state: \(state)")
        }
        state = .streaming
    }

    public func processAudioChunk(_ samples: [Float]) async throws {
        let buffer = try makePCMBuffer(from: samples)
        try await processAudioBuffer(buffer)
    }

    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        guard state == .streaming else {
            throw EngineError.invalidState("Cannot process audio while in state: \(state)")
        }

        do {
            _ = try await manager.process(audioBuffer: buffer)
        } catch {
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
        transcriptionCallback = callback
    }

    public func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        endOfUtteranceCallback = callback
    }

    public func reset() async {
        if let manager {
            await manager.reset()
            state = .ready
        } else {
            state = .unloaded
        }
    }

    private func resolveModelDirectory(for name: String) -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }

        let relativePath = trimmed.isEmpty ? FeatureModelType.streaming.repoFolderName : trimmed
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
    }

    private func makePCMBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            throw EngineError.processingFailed("Failed to create PCM buffer")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        channelData.update(from: samples, count: samples.count)
        return buffer
    }
}
