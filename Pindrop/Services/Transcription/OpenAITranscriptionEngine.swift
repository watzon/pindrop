//
//  OpenAITranscriptionEngine.swift
//  Pindrop
//
//  Created on 2026-07-21.
//

import Foundation

@MainActor
public final class OpenAITranscriptionEngine: TranscriptionEngine {
    enum EngineError: Error, LocalizedError {
        case modelNotLoaded
        case unsupportedModel(String)
        case apiKeyMissing
        case invalidAudioData
        case audioEncodingFailed(String)
        case uploadTooLarge
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "OpenAI transcription model is not loaded."
            case .unsupportedModel(let model):
                return "Unsupported OpenAI transcription model: \(model)"
            case .apiKeyMissing:
                return "Enter an OpenAI API key in Settings → Models before using cloud transcription."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16 kHz mono Float32 PCM."
            case .audioEncodingFailed(let message):
                return "Unable to prepare audio for OpenAI: \(message)"
            case .uploadTooLarge:
                return "An encoded audio chunk exceeded OpenAI's 25 MB upload limit."
            case .invalidResponse:
                return "OpenAI returned an invalid transcription response."
            case .apiError(let statusCode, let message):
                return "OpenAI transcription failed (HTTP \(statusCode)): \(message)"
            }
        }
    }

    public private(set) var state: TranscriptionEngineState = .unloaded
    private(set) var error: Error?

    nonisolated private static let defaultEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    nonisolated private static let sampleRate = 16_000
    private static let bytesPerSample = MemoryLayout<Float>.size
    private static let maximumChunkDurationSeconds = 30 * 60
    private static let maximumUploadBytes = 25 * 1_024 * 1_024
    private static let modelIDs: [String: String] = [
        "openai_gpt-4o-transcribe": "gpt-4o-transcribe",
        "openai_gpt-4o-mini-transcribe": "gpt-4o-mini-transcribe"
    ]

    private let apiKeyProvider: @MainActor () throws -> String
    private let session: URLSessionProtocol
    private let endpoint: URL
    private var modelID: String?

    init(
        apiKeyProvider: @escaping @MainActor () throws -> String,
        session: URLSessionProtocol = URLSession.shared,
        endpoint: URL = OpenAITranscriptionEngine.defaultEndpoint
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.endpoint = endpoint
    }

    public func loadModel(path: String) async throws {
        throw EngineError.unsupportedModel(path)
    }

    public func loadModel(name: String, downloadBase: URL? = nil) async throws {
        state = .loading
        error = nil

        do {
            guard let resolvedModelID = Self.modelIDs[name] else {
                throw EngineError.unsupportedModel(name)
            }
            _ = try resolvedAPIKey()
            modelID = resolvedModelID
            state = .ready
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }

    public func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        guard state == .ready, let modelID else {
            throw EngineError.modelNotLoaded
        }
        guard !audioData.isEmpty,
              audioData.count.isMultiple(of: Self.bytesPerSample) else {
            throw EngineError.invalidAudioData
        }

        state = .transcribing
        error = nil

        do {
            let apiKey = try resolvedAPIKey()
            let maximumChunkBytes = Self.maximumChunkDurationSeconds
                * Self.sampleRate
                * Self.bytesPerSample
            let prompt = VocabularyBiasPrompt.assemblePrompt(words: options.vocabularyBiasWords)
            var transcripts: [String] = []
            transcripts.reserveCapacity((audioData.count + maximumChunkBytes - 1) / maximumChunkBytes)

            var offset = 0
            while offset < audioData.count {
                try Task.checkCancellation()
                let end = min(offset + maximumChunkBytes, audioData.count)
                let chunk = audioData.subdata(in: offset..<end)
                let encodedAudio = try await Self.encodeM4A(chunk)
                guard encodedAudio.count < Self.maximumUploadBytes else {
                    throw EngineError.uploadTooLarge
                }

                let transcript = try await transcribeChunk(
                    encodedAudio,
                    modelID: modelID,
                    apiKey: apiKey,
                    languageCode: options.language.whisperLanguageCode,
                    prompt: prompt
                )
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    transcripts.append(trimmed)
                }
                offset = end
            }

            state = .ready
            return transcripts.joined(separator: " ")
        } catch {
            state = .ready
            self.error = error
            throw error
        }
    }

    public func unloadModel() async {
        modelID = nil
        error = nil
        state = .unloaded
    }

    private func resolvedAPIKey() throws -> String {
        let key = try apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw EngineError.apiKeyMissing
        }
        return key
    }

    private func transcribeChunk(
        _ audio: Data,
        modelID: String,
        apiKey: String,
        languageCode: String?,
        prompt: String?
    ) async throws -> String {
        let boundary = "Pindrop-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            modelID: modelID,
            languageCode: languageCode,
            prompt: prompt,
            audio: audio
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            let requestID = httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "unavailable"
            Log.transcription.error(
                "OpenAI transcription request failed status=\(httpResponse.statusCode) requestID=\(requestID)"
            )
            throw EngineError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let response = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw EngineError.invalidResponse
        }
        return response.text
    }

    nonisolated private static func encodeM4A(_ audioData: Data) async throws -> Data {
        do {
            return try await Task.detached(priority: .userInitiated) {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pindrop-openai-\(UUID().uuidString)")
                    .appendingPathExtension("m4a")
                defer { try? FileManager.default.removeItem(at: destination) }

                try DictationAudioEncoder.encodePCMFloatData(audioData, to: destination)
                return try Data(contentsOf: destination)
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EngineError.audioEncodingFailed(error.localizedDescription)
        }
    }

    nonisolated private static func multipartBody(
        boundary: String,
        modelID: String,
        languageCode: String?,
        prompt: String?,
        audio: Data
    ) -> Data {
        var body = Data()
        appendField(name: "model", value: modelID, boundary: boundary, to: &body)
        if let languageCode {
            appendField(name: "language", value: languageCode, boundary: boundary, to: &body)
        }
        if let prompt {
            appendField(name: "prompt", value: prompt, boundary: boundary, to: &body)
        }

        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n", to: &body)
        append("Content-Type: audio/mp4\r\n\r\n", to: &body)
        body.append(audio)
        append("\r\n--\(boundary)--\r\n", to: &body)
        return body
    }

    nonisolated private static func appendField(
        name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        append("\(value)\r\n", to: &body)
    }

    nonisolated private static func append(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
