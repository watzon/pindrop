//
//  AIEnhancementServiceTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
@testable import Pindrop

final class AIEnhancementServiceTests: XCTestCase {
    
    var service: AIEnhancementService!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        service = AIEnhancementService(session: mockSession)
    }
    
    override func tearDown() {
        service = nil
        mockSession = nil
        super.tearDown()
    }
    
    // MARK: - Test Enhancement with Mock API
    
    func testEnhanceTextWithMockAPI() async throws {
        // Given
        let inputText = "this is test text with bad grammar and no punctuation"
        let expectedEnhancedText = "This is test text with bad grammar and no punctuation."
        
        // Mock successful API response
        let mockResponse = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4",
            "choices": [{
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": "\(expectedEnhancedText)"
                },
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 20,
                "total_tokens": 30
            }
        }
        """
        
        mockSession.mockData = mockResponse.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )
        
        // Then
        XCTAssertEqual(result, expectedEnhancedText)
        XCTAssertNotNil(mockSession.lastRequest)
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(
            mockSession.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-api-key"
        )
        XCTAssertEqual(
            mockSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }
    
    // MARK: - Test Fallback on API Error
    
    func testThrowsOnAPIError() async throws {
        mockSession.mockError = URLError(.notConnectedToInternet)
        
        do {
            _ = try await service.enhance(
                text: "original text",
                apiEndpoint: "https://api.openai.com/v1/chat/completions",
                apiKey: "test-api-key"
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is AIEnhancementService.EnhancementError)
        }
    }
    
    func testThrowsOnHTTPError() async throws {
        mockSession.mockData = "Error".data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        
        do {
            _ = try await service.enhance(
                text: "original text",
                apiEndpoint: "https://api.openai.com/v1/chat/completions",
                apiKey: "test-api-key"
            )
            XCTFail("Expected error to be thrown")
        } catch let error as AIEnhancementService.EnhancementError {
            if case .apiError(let message) = error {
                XCTAssertEqual(message, "HTTP 500")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testThrowsOnInvalidJSON() async throws {
        mockSession.mockData = "Invalid JSON".data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        do {
            _ = try await service.enhance(
                text: "original text",
                apiEndpoint: "https://api.openai.com/v1/chat/completions",
                apiKey: "test-api-key"
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is AIEnhancementService.EnhancementError)
        }
    }
    
    // MARK: - Test Request Body
    
    func testRequestBodyFormat() async throws {
        // Given
        let inputText = "test text"
        
        mockSession.mockData = """
        {
            "choices": [{
                "message": {
                    "content": "Enhanced text"
                }
            }]
        }
        """.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        _ = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )
        
        // Then - verify request body structure
        XCTAssertNotNil(mockSession.lastRequest?.httpBody)
        
        if let bodyData = mockSession.lastRequest?.httpBody,
           let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            
            XCTAssertEqual(bodyJSON["model"] as? String, "gpt-4")
            XCTAssertNotNil(bodyJSON["messages"] as? [[String: Any]])
            
            if let messages = bodyJSON["messages"] as? [[String: Any]] {
                XCTAssertEqual(messages.count, 2)
                
                // System message
                XCTAssertEqual(messages[0]["role"] as? String, "system")
                XCTAssertTrue((messages[0]["content"] as? String)?.contains("grammar") ?? false)
                
                // User message
                XCTAssertEqual(messages[1]["role"] as? String, "user")
                XCTAssertEqual(messages[1]["content"] as? String, inputText)
            }
        } else {
            XCTFail("Failed to parse request body")
        }
    }
    
// MARK: - Test Empty Text

    func testEnhanceEmptyText() async throws {
        // Given
        let inputText = ""

        // When
        let result = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )

        // Then - should return empty text without making API call
        XCTAssertEqual(result, "")
        XCTAssertNil(mockSession.lastRequest)
    }

    // MARK: - Test Message Building

    func testBuildMessagesTextOnly() {
        // Given
        let systemPrompt = "You are helpful"
        let userContent = "Hello"

        // When
        let messages = AIEnhancementService.buildMessages(
            systemPrompt: systemPrompt,
            text: userContent,
            imageBase64: nil
        )

        // Then
        XCTAssertEqual(messages.count, 2)

        // System message
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        let systemContent = messages[0]["content"] as? String
        XCTAssertNotNil(systemContent)
        XCTAssertTrue(systemContent!.contains("<enhancement_request>"))
        XCTAssertTrue(systemContent!.contains("<instructions>"))
        XCTAssertTrue(systemContent!.contains(systemPrompt))

        // User message - text only format
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, userContent)
    }

    func testBuildMessagesWithImage() {
        // Given
        let systemPrompt = "You are helpful"
        let userContent = "Describe this"
        let imageBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

        // When
        let messages = AIEnhancementService.buildMessages(
            systemPrompt: systemPrompt,
            text: userContent,
            imageBase64: imageBase64
        )

        // Then
        XCTAssertEqual(messages.count, 2)

        // System message
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        let systemContent = messages[0]["content"] as? String
        XCTAssertNotNil(systemContent)
        XCTAssertTrue(systemContent!.contains("<enhancement_request>"))
        XCTAssertTrue(systemContent!.contains(systemPrompt))

        // User message - vision format with content array
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let content = messages[1]["content"] as? [[String: Any]]
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.count, 2)

        // Text part
        XCTAssertEqual(content?[0]["type"] as? String, "text")
        XCTAssertEqual(content?[0]["text"] as? String, userContent)

        // Image part
        XCTAssertEqual(content?[1]["type"] as? String, "image_url")

        let imageUrl = content?[1]["image_url"] as? [String: String]
        XCTAssertNotNil(imageUrl)
        XCTAssertEqual(imageUrl?["url"], "data:image/png;base64,\(imageBase64)")
    }

    // MARK: - Test Context Metadata

    func testContextMetadataImageDescription() {
        let clipboardOnly = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: true,
            hasScreenshot: false
        )
        XCTAssertEqual(clipboardOnly.imageDescription, "clipboard image")

        let screenshotOnly = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            hasScreenshot: true
        )
        XCTAssertEqual(screenshotOnly.imageDescription, "screenshot")

        let both = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: true,
            hasScreenshot: true
        )
        XCTAssertEqual(both.imageDescription, "clipboard image and screenshot")

        let none = AIEnhancementService.ContextMetadata.none
        XCTAssertNil(none.imageDescription)
    }

    func testBuildContextAwareSystemPromptNoContext() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata.none

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        XCTAssertTrue(result.contains("<enhancement_request>"))
        XCTAssertTrue(result.contains("<instructions>"))
        XCTAssertTrue(result.contains(basePrompt))
        XCTAssertTrue(result.contains("<supplementary_context>"))
        XCTAssertTrue(result.contains("<available>false</available>"))
    }

    func testBuildContextAwareSystemPromptWithClipboardText() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: false,
            hasScreenshot: false
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        XCTAssertTrue(result.contains("<supplementary_context>"))
        XCTAssertTrue(result.contains("<available>true</available>"))
        XCTAssertTrue(result.contains("<type>clipboard_text</type>"))
        XCTAssertTrue(result.contains(basePrompt))
    }

    func testBuildContextAwareSystemPromptNormalizesTranscriptionPlaceholder() {
        let basePrompt = "Clean this text: ${transcription}"

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: .none
        )

        XCTAssertTrue(result.contains("Clean this text: &lt;transcription/&gt;"))
        XCTAssertFalse(result.contains("${transcription}"))
    }

    func testBuildContextAwareSystemPromptWithImage() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            hasScreenshot: true
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        XCTAssertTrue(result.contains("<supplementary_context>"))
        XCTAssertTrue(result.contains("<type>screenshot</type>"))
        XCTAssertTrue(result.contains(basePrompt))
    }

    func testBuildMessagesWithContext() {
        let systemPrompt = "You are helpful"
        let userContent = "Hello"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: false,
            hasScreenshot: false
        )

        let messages = AIEnhancementService.buildMessages(
            systemPrompt: systemPrompt,
            text: userContent,
            imageBase64: nil,
            context: context
        )

        XCTAssertEqual(messages.count, 2)

        let systemContent = messages[0]["content"] as? String
        XCTAssertNotNil(systemContent)
        XCTAssertTrue(systemContent!.contains("<supplementary_context>"))
        XCTAssertTrue(systemContent!.contains("<type>clipboard_text</type>"))
        XCTAssertTrue(systemContent!.contains(systemPrompt))
    }

    func testBuildTranscriptionEnhancementInputIncludesXMLBlocks() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: false,
            hasScreenshot: true
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: "clipboard reference",
            context: context
        )

        XCTAssertTrue(payload.contains("<enhancement_input>"))
        XCTAssertTrue(payload.contains("<transcription>"))
        XCTAssertTrue(payload.contains("hello world"))
        XCTAssertTrue(payload.contains("<clipboard_text>"))
        XCTAssertTrue(payload.contains("clipboard reference"))
        XCTAssertTrue(payload.contains("<image_context>"))
        XCTAssertTrue(payload.contains("screenshot"))
    }

    func testBuildTranscriptionEnhancementInputEscapesXML() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "Use <tag> & symbols \"now\"",
            clipboardText: "value with 'quotes'",
            context: .none
        )

        XCTAssertTrue(payload.contains("Use &lt;tag&gt; &amp; symbols &quot;now&quot;"))
        XCTAssertTrue(payload.contains("value with &apos;quotes&apos;"))
    }

    // MARK: - Test Model Capabilities

    func testKnownVisionModels() {
        // OpenAI vision models
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gpt-4o"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gpt-4o-mini"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gpt-4-vision-preview"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gpt-4-turbo"))

        // Anthropic Claude 3 vision models
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "claude-3-opus"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "claude-3-sonnet"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "claude-3-haiku"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "claude-3.5-sonnet"))

        // Google Gemini vision models
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gemini-pro-vision"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gemini-1.5-pro"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gemini-1.5-flash"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "gemini-2.0-flash"))
    }

    func testNonVisionModels() {
        // OpenAI non-vision models
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "gpt-3.5-turbo"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "gpt-4"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "gpt-4-0613"))

        // Anthropic non-vision models
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "claude-2"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "claude-2.1"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "claude-instant"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "claude-instant-1.2"))

        // Unknown models
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "unknown-model"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "some-random-model"))
    }

    func testOpenRouterPrefixedModels() {
        // OpenRouter vision models
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "openai/gpt-4o"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "openai/gpt-4o-mini"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3-opus"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3-sonnet"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3.5-sonnet"))
        XCTAssertTrue(ModelCapabilities.supportsVision(modelId: "google/gemini-1.5-pro"))

        // OpenRouter non-vision models
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "openai/gpt-3.5-turbo"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "openai/gpt-4"))
        XCTAssertFalse(ModelCapabilities.supportsVision(modelId: "anthropic/claude-2"))
    }
}

// MARK: - Mock URLSession

class MockURLSession: URLSessionProtocol {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var lastRequest: URLRequest?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        
        if let error = mockError {
            throw error
        }
        
        guard let data = mockData, let response = mockResponse else {
            throw URLError(.unknown)
        }
        
        return (data, response)
    }
}
