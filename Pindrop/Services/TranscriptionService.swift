//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit
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
            }
        }
    }
    
    private(set) var state: State = .unloaded
    private(set) var error: Error?
    private var whisperKit: WhisperKit?
    
    func loadModel(modelName: String = "tiny") async throws {
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model: \(modelName) with prewarm enabled...")
        
        do {
            // Create URL for download base to log the full path
            let fileManager = FileManager.default
            let downloadBaseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Pindrop", isDirectory: true)
            let expectedModelPath = downloadBaseURL
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(modelName, isDirectory: true)
            
            Log.transcription.info("Expected model path: \(expectedModelPath.path)")
            Log.transcription.info("Model folder exists: \(fileManager.fileExists(atPath: expectedModelPath.path))")
            
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: downloadBaseURL,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true
            )
            
            Log.transcription.info("WhisperKitConfig created - model: \(modelName), downloadBase: \(downloadBaseURL.path), verbose: false, logLevel: .error, prewarm: true, load: true")
            
            // Race the load against a 60-second timeout
            let whisperKitResult: WhisperKit = try await withThrowingTaskGroup(of: WhisperKit.self) { group in
                // Load task
                group.addTask {
                    try await WhisperKit(config)
                }
                
                // Timeout task - throws if load takes longer than 60s
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 60s. The model files may be corrupted. Try deleting and re-downloading the model from Settings.")
                }
                
                // Return whichever completes first
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            whisperKit = whisperKitResult
            Log.transcription.info("Model loaded and prewarmed successfully")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            self.error = TranscriptionError.modelLoadFailed(error.localizedDescription)
            state = .error
            throw self.error!
        }
    }
    
    func loadModel(modelPath: String) async throws {
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model from path: \(modelPath) with prewarm enabled...")
        
        let config = WhisperKitConfig(
            modelFolder: modelPath,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true
        )
        
        Log.transcription.info("WhisperKitConfig created - modelFolder: \(modelPath), verbose: false, logLevel: .error, prewarm: true, load: true")
        
        do {
            // Race the load against a 60-second timeout
            whisperKit = try await withThrowingTaskGroup(of: WhisperKit.self) { group in
                // Load task
                group.addTask {
                    try await WhisperKit(config)
                }
                
                // Timeout task - throws if load takes longer than 60s
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 60s. The model files may be corrupted. Try deleting and re-downloading the model from Settings.")
                }
                
                // Return whichever completes first
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            Log.transcription.info("Model loaded and prewarmed successfully")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            self.error = TranscriptionError.modelLoadFailed(error.localizedDescription)
            state = .error
            throw self.error!
        }
    }
    
    func transcribe(audioData: Data) async throws -> String {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")
        
        guard whisperKit != nil else {
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
            let floatArray = dataToFloatArray(audioData)
            let duration = Double(floatArray.count) / 16000.0
            Log.transcription.info("Transcribing \(floatArray.count) samples (\(duration, format: .fixed(precision: 2))s)")
            
            guard !floatArray.isEmpty else {
                state = .ready
                throw TranscriptionError.invalidAudioData
            }
            
            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                withoutTimestamps: true
            )
            
            let startTime = Date()
            let results = try await whisperKit!.transcribe(
                audioArray: floatArray,
                decodeOptions: options
            )
            
            let elapsed = Date().timeIntervalSince(startTime)
            Log.transcription.info("Transcription completed in \(elapsed, format: .fixed(precision: 2))s")
            
            state = .ready
            
            guard let firstResult = results.first else {
                throw TranscriptionError.transcriptionFailed("No transcription results returned")
            }
            
            Log.transcription.debug("Result: '\(firstResult.text)'")
            return firstResult.text
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
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
