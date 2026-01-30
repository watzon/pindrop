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
        guard let data = key.data(using: .utf8) else {
            throw EnhancementError.keychainError("Failed to encode API key")
        }

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
    // MARK: - Note Enhancement
    
    struct EnhancedNote {
        let content: String
        let title: String
        let tags: [String]
    }
    
    func enhanceNote(
        content: String,
        apiEndpoint: String,
        apiKey: String,
        model: String = "gpt-4o-mini",
        contentPrompt: String,
        generateMetadata: Bool = true,
        existingTags: [String] = []
    ) async throws -> EnhancedNote {
        guard !content.isEmpty else {
            return EnhancedNote(content: content, title: "Untitled Note", tags: [])
        }
        
        let enhancedContent = try await enhance(
            text: content,
            apiEndpoint: apiEndpoint,
            apiKey: apiKey,
            model: model,
            customPrompt: contentPrompt
        )
        
        var title = generateFallbackTitle(from: enhancedContent)
        var tags: [String] = []
        
        if generateMetadata {
            do {
                let metadata = try await generateNoteMetadata(
                    content: enhancedContent,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: model,
                    existingTags: existingTags
                )
                title = metadata.title
                tags = metadata.tags
            } catch {
                Log.aiEnhancement.warning("Metadata generation failed, using fallback: \(error.localizedDescription)")
            }
        }
        
        return EnhancedNote(content: enhancedContent, title: title, tags: tags)
    }
    
    func generateFallbackTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Note" }
        
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        
        if words.count <= 50 {
            return words.isEmpty ? "Untitled Note" : words
        } else {
            let index = words.index(words.startIndex, offsetBy: 47)
            return String(words[..<index]) + "..."
        }
    }
    
    // MARK: - Note Metadata Generation
    
    static func metadataGenerationPrompt(existingTags: [String] = []) -> String {
        var prompt = """
        You are a note organization assistant. Given a note's content, generate:
        1. A concise title (5-10 words) that summarizes the content
        2. 3-5 relevant tags/keywords that categorize the content
        
        Return ONLY a JSON object in this exact format:
        {"title": "Generated Title Here", "tags": ["tag1", "tag2", "tag3"]}
        
        Rules:
        - Title should be descriptive but concise (5-10 words)
        - Tags should be lowercase, single words or short phrases (1-2 words max)
        - Tags should be relevant keywords for categorization
        - Do not include any markdown, explanations, or additional text
        - Return valid JSON only
        """
        
        if !existingTags.isEmpty {
            let tagList = existingTags.prefix(30).joined(separator: ", ")
            prompt += """
            
            
            IMPORTANT: Prefer using these existing tags when they are relevant to maintain consistency: [\(tagList)]
            Only create new tags if none of the existing tags appropriately describe the content.
            """
        }
        
        return prompt
    }
    
    struct NoteMetadata: Codable {
        let title: String
        let tags: [String]
    }
    
    func generateNoteMetadata(
        content: String,
        apiEndpoint: String,
        apiKey: String,
        model: String = "gpt-4o-mini",
        existingTags: [String] = []
    ) async throws -> (title: String, tags: [String]) {
        guard !content.isEmpty else {
            return ("Untitled Note", [])
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
                        "content": AIEnhancementService.metadataGenerationPrompt(existingTags: existingTags)
                    ],
                    [
                        "role": "user",
                        "content": content
                    ]
                ],
                "temperature": 0.3,
                "max_tokens": 256
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
            
            // Parse the JSON response from the AI
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = cleanedContent.data(using: .utf8) else {
                throw EnhancementError.invalidResponse
            }
            
            let metadata = try JSONDecoder().decode(NoteMetadata.self, from: jsonData)
            
            // Validate and clean the results
            let cleanTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTags = metadata.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            
            return (cleanTitle.isEmpty ? "Untitled Note" : cleanTitle, cleanTags)
            
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.apiError(error.localizedDescription)
        }
    }
}
