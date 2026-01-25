//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import WhisperKit

@MainActor
@Observable
final class TranscriptionService {
    
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
        
        do {
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .none
            )
            
            whisperKit = try await WhisperKit(config)
            state = .ready
        } catch {
            self.error = TranscriptionError.modelLoadFailed(error.localizedDescription)
            state = .error
            throw self.error!
        }
    }
    
    func loadModel(modelPath: String) async throws {
        state = .loading
        error = nil
        
        do {
            let config = WhisperKitConfig(
                modelFolder: modelPath,
                verbose: false,
                logLevel: .none
            )
            
            whisperKit = try await WhisperKit(config)
            state = .ready
        } catch {
            self.error = TranscriptionError.modelLoadFailed(error.localizedDescription)
            state = .error
            throw self.error!
        }
    }
    
    func transcribe(audioData: Data) async throws -> String {
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
            let floatArray = convertPCMDataToFloatArray(audioData)
            
            guard !floatArray.isEmpty else {
                state = .ready
                throw TranscriptionError.invalidAudioData
            }
            
            let options = DecodingOptions(
                task: .transcribe,
                language: "en",
                withoutTimestamps: true
            )
            
            let results = try await whisperKit!.transcribe(
                audioArray: floatArray,
                decodeOptions: options
            )
            
            state = .ready
            
            guard let firstResult = results.first else {
                throw TranscriptionError.transcriptionFailed("No transcription results returned")
            }
            
            return firstResult.text
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    func convertPCMDataToFloatArray(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var floatArray: [Float] = []
        floatArray.reserveCapacity(sampleCount)
        
        data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            let bufferPointer = rawBufferPointer.bindMemory(to: Int16.self)
            
            for sample in bufferPointer {
                let normalizedSample = Float(sample) / Float(Int16.max)
                floatArray.append(normalizedSample)
            }
        }
        
        return floatArray
    }
}
