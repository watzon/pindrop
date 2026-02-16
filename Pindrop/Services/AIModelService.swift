//
//  AIModelService.swift
//  Pindrop
//
//  Created on 2026-02-14.
//

import Foundation
import os.log

@MainActor
final class AIModelService {
    struct AIModel: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let provider: AIProvider
        let description: String?
        let contextLength: Int?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case provider
            case description
            case contextLength
        }

        init(
            id: String,
            name: String,
            provider: AIProvider,
            description: String? = nil,
            contextLength: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.provider = provider
            self.description = description
            self.contextLength = contextLength
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            let providerRaw = try container.decode(String.self, forKey: .provider)
            guard let provider = AIProvider(rawValue: providerRaw) else {
                throw ModelError.invalidProvider(providerRaw)
            }
            self.provider = provider
            description = try container.decodeIfPresent(String.self, forKey: .description)
            contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(provider.rawValue, forKey: .provider)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(contextLength, forKey: .contextLength)
        }
    }

    struct AIModelCache: Codable {
        let models: [AIModel]
        let fetchedAt: Date
    }

    enum ModelError: Error, LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case apiError(String)
        case missingAPIKey
        case unsupportedProvider
        case cacheWriteFailed(String)
        case invalidProvider(String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Invalid API endpoint URL"
            case .invalidResponse:
                return "Invalid response from API"
            case .apiError(let message):
                return "API error: \(message)"
            case .missingAPIKey:
                return "Missing API key"
            case .unsupportedProvider:
                return "Unsupported AI provider"
            case .cacheWriteFailed(let message):
                return "Failed to write model cache: \(message)"
            case .invalidProvider(let provider):
                return "Invalid AI provider: \(provider)"
            }
        }
    }

    private static let cacheStaleInterval: TimeInterval = 60 * 60 * 24 * 7

    private let session: URLSessionProtocol
    private let fileManager = FileManager.default

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func fetchModels(for provider: AIProvider, apiKey: String?) async throws -> [AIModel] {
        do {
            switch provider {
            case .openrouter:
                return try await fetchOpenRouterModels()
            case .openai:
                return try await fetchOpenAIModels(apiKey: apiKey)
            default:
                throw ModelError.unsupportedProvider
            }
        } catch let error as ModelError {
            throw error
        } catch {
            throw ModelError.apiError(error.localizedDescription)
        }
    }

    func refreshModels(for provider: AIProvider, apiKey: String?) async throws -> [AIModel] {
        let models = try await fetchModels(for: provider, apiKey: apiKey)
        try saveCache(AIModelCache(models: models, fetchedAt: Date()), for: provider)
        return models
    }

    func getCachedModels(for provider: AIProvider) -> [AIModel]? {
        guard let cache = loadCache(for: provider) else {
            return nil
        }
        guard !isCacheStale(cache) else {
            return nil
        }
        return cache.models
    }

    func isCacheStale(for provider: AIProvider) -> Bool {
        guard let cache = loadCache(for: provider) else {
            return true
        }
        return isCacheStale(cache)
    }

    private func isCacheStale(_ cache: AIModelCache) -> Bool {
        Date().timeIntervalSince(cache.fetchedAt) > Self.cacheStaleInterval
    }

    private var cacheBaseURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
            .appendingPathComponent("AIModels", isDirectory: true)
    }

    private func cacheFileURL(for provider: AIProvider) -> URL {
        let slug = provider.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        return cacheBaseURL.appendingPathComponent("ai-model-cache-\(slug).json", isDirectory: false)
    }

    private func loadCache(for provider: AIProvider) -> AIModelCache? {
        let url = cacheFileURL(for: provider)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AIModelCache.self, from: data)
        } catch {
            Log.aiEnhancement.warning("Failed to read model cache for \(provider.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    private func saveCache(_ cache: AIModelCache, for provider: AIProvider) throws {
        let url = cacheFileURL(for: provider)
        do {
            try fileManager.createDirectory(at: cacheBaseURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: url, options: [.atomic])
            Log.aiEnhancement.info("Saved model cache for \(provider.rawValue) (\(cache.models.count) models)")
        } catch {
            Log.aiEnhancement.error("Failed to write model cache for \(provider.rawValue): \(error.localizedDescription)")
            throw ModelError.cacheWriteFailed(error.localizedDescription)
        }
    }

    private func fetchOpenRouterModels() async throws -> [AIModel] {
        Log.aiEnhancement.info("Fetching OpenRouter models")
        let request = try buildRequest(urlString: "https://openrouter.ai/api/v1/models", apiKey: nil)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw parseHTTPError(from: data, statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(OpenRouterResponse.self, from: data)
            let models = payload.data.map {
                AIModel(
                    id: $0.id,
                    name: $0.name ?? $0.id,
                    provider: .openrouter,
                    description: $0.description,
                    contextLength: $0.contextLength
                )
            }
            return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw ModelError.invalidResponse
        }
    }

    private func fetchOpenAIModels(apiKey: String?) async throws -> [AIModel] {
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ModelError.missingAPIKey
        }

        Log.aiEnhancement.info("Fetching OpenAI models")
        let request = try buildRequest(urlString: "https://api.openai.com/v1/models", apiKey: apiKey)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw parseHTTPError(from: data, statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(OpenAIResponse.self, from: data)
            let models = payload.data.map {
                AIModel(
                    id: $0.id,
                    name: $0.id,
                    provider: .openai,
                    description: nil,
                    contextLength: nil
                )
            }
            return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw ModelError.invalidResponse
        }
    }

    private func buildRequest(urlString: String, apiKey: String?) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw ModelError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pindrop/1.0", forHTTPHeaderField: "X-Title")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func parseHTTPError(from data: Data, statusCode: Int) -> ModelError {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return .apiError(message)
        }
        return .apiError("HTTP \(statusCode)")
    }
}

private struct OpenRouterResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let name: String?
        let description: String?
        let contextLength: Int?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case description
            case contextLength = "context_length"
        }
    }

    let data: [Model]
}

private struct OpenAIResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let object: String?
        let created: Int?
    }

    let data: [Model]
}
