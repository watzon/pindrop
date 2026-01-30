//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import os.log

@MainActor
@Observable
class TranscriptionService {
    
    enum State: Equatable {
        case unloaded
        case loading
        case ready
        case transcribing
        case error
    }
    
    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case modelLoadFailed(String)
        case engineSwitchDuringTranscription
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM format."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
            case .engineSwitchDuringTranscription:
                return "Cannot switch engines during active transcription"
            }
        }
    }
    
    private(set) var state: State = .unloaded
    private(set) var error: Error?
    private var engine: (any TranscriptionEngine)?
    private var currentProvider: ModelManager.ModelProvider?
    
    func loadModel(modelName: String = "tiny", provider: ModelManager.ModelProvider = .whisperKit) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }
        
        if currentProvider != nil && currentProvider != provider {
            await unloadModel()
        }
        
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model: \(modelName) with provider: \(provider.rawValue)...")
        
        do {
            let newEngine: any TranscriptionEngine
            switch provider {
            case .whisperKit:
                newEngine = WhisperKitEngine()
            case .parakeet:
                newEngine = ParakeetEngine()
            default:
                throw TranscriptionError.modelLoadFailed("Provider \(provider.rawValue) not supported locally")
            }
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(name: modelName, downloadBase: self.getDownloadBase())
                }
                
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }
                
                try await group.next()
                group.cancelAll()
            }
            
            engine = newEngine
            currentProvider = provider
            Log.transcription.info("Model loaded successfully with \(provider.rawValue) engine")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }
    
    func loadModel(modelPath: String) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }
        
        if currentProvider != nil {
            await unloadModel()
        }
        
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model from path: \(modelPath) with prewarm enabled...")
        
        do {
            let newEngine = WhisperKitEngine()
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(path: modelPath)
                }
                
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }
                
                try await group.next()
                group.cancelAll()
            }
            
            engine = newEngine
            currentProvider = .whisperKit
            Log.transcription.info("Model loaded and prewarmed successfully")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    func transcribe(audioData: Data) async throws -> String {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")
        
        guard let engine = engine else {
            throw TranscriptionError.modelNotLoaded
        }
        
        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }
        
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }
        
        state = .transcribing
        
        do {
            let floatCount = audioData.count / MemoryLayout<Float>.size
            let duration = Double(floatCount) / 16000.0
            Log.transcription.info("Transcribing \(floatCount) samples (\(duration, format: .fixed(precision: 2))s)")
            
            let startTime = Date()
            let result = try await engine.transcribe(audioData: audioData)
            
            let elapsed = Date().timeIntervalSince(startTime)
            Log.transcription.info("Transcription completed in \(elapsed, format: .fixed(precision: 2))s")
            
            state = .ready
            
            Log.transcription.debug("Result: '\(result)'")
            return result
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    func unloadModel() async {
        await engine?.unloadModel()
        engine = nil
        currentProvider = nil
        state = .unloaded
        error = nil
    }
    
    private func getDownloadBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }
    
    private func dataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)
        
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                floatArray[i] = floatBuffer[i]
            }
        }
        
        return floatArray
    }
}
