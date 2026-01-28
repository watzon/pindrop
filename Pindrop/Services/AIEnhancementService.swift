//
//  AIEnhancementService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import Security

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

@MainActor
@Observable
final class AIEnhancementService {

    static let defaultSystemPrompt = "You are a text enhancement assistant. Improve the grammar, punctuation, and formatting of the provided text while preserving its original meaning and tone. Return only the enhanced text without any additional commentary."

    enum EnhancementError: Error, LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case apiError(String)
        case keychainError(String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Invalid API endpoint URL"
            case .invalidResponse:
                return "Invalid response from API"
            case .apiError(let message):
                return "API error: \(message)"
            case .keychainError(let message):
                return "Keychain error: \(message)"
            }
        }
    }

    private let session: URLSessionProtocol
    private let keychainService = "com.pindrop.ai-enhancement"

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func enhance(
        text: String,
        apiEndpoint: String,
        apiKey: String,
        model: String = "gpt-4o-mini",
        customPrompt: String = AIEnhancementService.defaultSystemPrompt
    ) async throws -> String {
        guard !text.isEmpty else {
            return text
        }

        guard let url = URL(string: apiEndpoint) else {
            throw EnhancementError.invalidEndpoint
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Pindrop/1.0", forHTTPHeaderField: "X-Title")

            let requestBody: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": customPrompt
                    ],
                    [
                        "role": "user",
                        "content": text
                    ]
                ],
                "temperature": 0.3,
                "max_tokens": 2048
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EnhancementError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw EnhancementError.apiError(message)
                }
                throw EnhancementError.apiError("HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw EnhancementError.invalidResponse
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.apiError(error.localizedDescription)
        }
    }

    func saveAPIKey(_ key: String, for endpoint: String) throws {
        let data = key.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EnhancementError.keychainError("Failed to save API key: \(status)")
        }
    }

    func loadAPIKey(for endpoint: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw EnhancementError.keychainError("Failed to load API key: \(status)")
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw EnhancementError.keychainError("Failed to decode API key")
        }

        return key
    }

    func deleteAPIKey(for endpoint: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EnhancementError.keychainError("Failed to delete API key: \(status)")
        }
    }
}
