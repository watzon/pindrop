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
    
    func testFallbackOnAPIError() async throws {
        // Given
        let inputText = "original text"
        
        // Mock error response
        mockSession.mockError = URLError(.notConnectedToInternet)
        
        // When
        let result = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )
        
        // Then - should return original text on error
        XCTAssertEqual(result, inputText)
    }
    
    func testFallbackOnHTTPError() async throws {
        // Given
        let inputText = "original text"
        
        // Mock HTTP error response
        mockSession.mockData = "Error".data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )
        
        // Then - should return original text on HTTP error
        XCTAssertEqual(result, inputText)
    }
    
    func testFallbackOnInvalidJSON() async throws {
        // Given
        let inputText = "original text"
        
        // Mock invalid JSON response
        mockSession.mockData = "Invalid JSON".data(using: .utf8)
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
        
        // Then - should return original text on JSON parsing error
        XCTAssertEqual(result, inputText)
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
