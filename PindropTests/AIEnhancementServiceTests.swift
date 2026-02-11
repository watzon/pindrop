//
//  AIEnhancementServiceTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

// XCTest may not be available to the language server in this editor environment.
#if canImport(XCTest)
import XCTest
#endif
@testable import Pindrop

@MainActor
final class AIEnhancementServiceTests: XCTestCase {
    
    var service: AIEnhancementService!
    var mockSession: MockURLSession!
    
    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockURLSession()
        service = AIEnhancementService(session: mockSession)
    }
    
    override func tearDown() async throws {
        service = nil
        mockSession = nil
        try await super.tearDown()
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
            
            // Current service default model is gpt-4o-mini; validate against that
            XCTAssertEqual(bodyJSON["model"] as? String, "gpt-4o-mini")
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
            hasClipboardImage: true
        )
        XCTAssertEqual(clipboardOnly.imageDescription, "clipboard image")

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
            clipboardText: "README section",
            hasClipboardImage: false,
            appContext: nil
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        XCTAssertTrue(result.contains("<supplementary_context>"))
        XCTAssertTrue(result.contains("<available>true</available>"))
        XCTAssertTrue(result.contains("<type>clipboard_text</type>"))
        XCTAssertTrue(result.contains("<clipboard_text>"))
        XCTAssertTrue(result.contains("README section"))
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

    func testBuildContextAwareSystemPromptWithClipboardImage() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: true
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        XCTAssertTrue(result.contains("<supplementary_context>"))
        XCTAssertTrue(result.contains("<type>clipboard_image</type>"))
        XCTAssertTrue(result.contains(basePrompt))
    }

    func testBuildMessagesWithContext() {
        let systemPrompt = "You are helpful"
        let userContent = "Hello"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            clipboardText: "clipboard snippet",
            hasClipboardImage: false,
            appContext: nil
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
        XCTAssertTrue(systemContent!.contains("<clipboard_text>"))
        XCTAssertTrue(systemContent!.contains("clipboard snippet"))
        XCTAssertTrue(systemContent!.contains(systemPrompt))

        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, userContent)
    }

    func testBuildMessagesContextLivesInSystemPromptUserHasOnlyTranscription() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowTitle: "Editor.swift",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "let value = 42",
            documentPath: "~/Projects/pindrop/Pindrop/Editor.swift",
            browserURL: nil
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            clipboardText: "public struct Editor {}",
            hasClipboardImage: false,
            appContext: appContext,
            adapterCapabilities: CursorAdapter().capabilities,
            routingSignal: PromptRoutingSignal(
                appBundleIdentifier: "com.todesktop.230313mzl4w4u92",
                appName: "cursor",
                windowTitle: "Editor.swift",
                workspacePath: "~/Projects/pindrop",
                browserDomain: nil,
                isCodeEditorContext: true
            ),
            workspaceFileTree: "total_files: 2\n---\nPindrop/AppCoordinator.swift\nPindrop/Services/AIEnhancementService.swift"
        )

        let messages = AIEnhancementService.buildMessages(
            systemPrompt: "Improve formatting only",
            text: "this is the spoken message",
            imageBase64: nil,
            context: context
        )

        let systemContent = messages[0]["content"] as? String
        XCTAssertNotNil(systemContent)
        XCTAssertTrue(systemContent!.contains("<context_payload>"))
        XCTAssertTrue(systemContent!.contains("<clipboard_text>"))
        XCTAssertTrue(systemContent!.contains("public struct Editor {}"))
        XCTAssertTrue(systemContent!.contains("<app_context>"))
        XCTAssertTrue(systemContent!.contains("<app_adapter>"))
        XCTAssertTrue(systemContent!.contains("<routing_signal>"))
        XCTAssertTrue(systemContent!.contains("<workspace_file_tree>"))

        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "this is the spoken message")
    }

    func testRedactedPayloadLogLinesRedactsImageAndChunks() {
        // Given
        let longBase64 = String(repeating: "A", count: 3000)
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "system prompt"],
                ["role": "user", "content": [
                    ["type": "text", "text": "hello world"],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(longBase64)"]]
                ]]
            ]
        ]

        // When
        let lines = AIEnhancementService.redactedPayloadLogLines(for: payload, redactImageBase64: true)

        // Then
        XCTAssertGreaterThan(lines.count, 1, "Expected payload to be chunked into multiple log lines")
        let combined = lines.joined()
        XCTAssertTrue(combined.contains("REDACTED_BASE64"), "Expected base64 to be redacted")
        // Expect size marker to equal length of original base64
        if let range = combined.range(of: "size=") {
            let after = combined[range.upperBound...]
            // read digits
            let digits = after.prefix { $0.isNumber }
            XCTAssertEqual(String(digits), "\(longBase64.count)")
        } else {
            XCTFail("Size marker not found")
        }
    }

    func testBuildTranscriptionEnhancementInputIncludesXMLBlocks() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: true
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
        XCTAssertTrue(payload.contains("clipboard image"))
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

    // MARK: - Test UI Context Sources

    func testContextMetadataUISourceFlags() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Apple",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "selected stuff",
            documentPath: nil,
            browserURL: "https://apple.com"
        )
        let meta = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        XCTAssertTrue(meta.hasAppMetadata)
        XCTAssertTrue(meta.hasWindowTitle)
        XCTAssertTrue(meta.hasSelectedText)
        XCTAssertFalse(meta.hasDocumentPath)
        XCTAssertTrue(meta.hasBrowserURL)
        XCTAssertTrue(meta.hasAnyContext)
    }

    func testContextMetadataUISourceFlagsNilAppContext() {
        let meta = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil
        )

        XCTAssertFalse(meta.hasAppMetadata)
        XCTAssertFalse(meta.hasWindowTitle)
        XCTAssertFalse(meta.hasSelectedText)
        XCTAssertFalse(meta.hasDocumentPath)
        XCTAssertFalse(meta.hasBrowserURL)
    }

    func testContextMetadataBackwardCompatInitHasNilAppContext() {
        let meta = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: false
        )

        XCTAssertTrue(meta.hasClipboardText)
        XCTAssertFalse(meta.hasAppMetadata)
    }

    func testBuildContextAwareSystemPromptWithUIContextSources() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Apple - Search",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "some text",
            documentPath: nil,
            browserURL: "https://apple.com"
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        XCTAssertTrue(result.contains("<available>true</available>"))
        XCTAssertTrue(result.contains("<type>app_metadata</type>"))
        XCTAssertTrue(result.contains("<type>window_title</type>"))
        XCTAssertTrue(result.contains("<type>selected_text</type>"))
        XCTAssertTrue(result.contains("<type>browser_url</type>"))
        XCTAssertFalse(result.contains("<type>document_path</type>"))
        XCTAssertTrue(result.contains("app_metadata,window_title,selected_text,document_path,browser_url"))
    }

    func testBuildContextAwareSystemPromptWithAdapterAndRoutingSources() {
        let capabilities = CursorAdapter().capabilities
        let routingSignal = PromptRoutingSignal(
            appBundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appName: "cursor",
            windowTitle: nil,
            workspacePath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
            browserDomain: nil,
            isCodeEditorContext: true
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: capabilities,
            routingSignal: routingSignal
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        XCTAssertTrue(result.contains("<type>app_adapter</type>"))
        XCTAssertTrue(result.contains("<type>routing_signal</type>"))
        XCTAssertTrue(result.contains("app_adapter,routing_signal"))
    }

    func testBuildTranscriptionEnhancementInputWithAppContext() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode",
            windowTitle: "My<Project>.swift",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "let x = 1 & 2",
            documentPath: "/Users/dev/My<Project>.swift",
            browserURL: nil
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<app_context>"))
        XCTAssertTrue(payload.contains("<app_name>Xcode</app_name>"))
        XCTAssertTrue(payload.contains("<bundle_id>com.apple.dt.Xcode</bundle_id>"))
        XCTAssertTrue(payload.contains("<window_title>My&lt;Project&gt;.swift</window_title>"))
        XCTAssertTrue(payload.contains("<selected_text>let x = 1 &amp; 2</selected_text>"))
        XCTAssertTrue(payload.contains("<document_path>/Users/dev/My&lt;Project&gt;.swift</document_path>"))
        XCTAssertFalse(payload.contains("<browser_url>"))
    }

    func testBuildTranscriptionEnhancementInputNoAppContext() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: nil,
            context: .none
        )

        XCTAssertFalse(payload.contains("<app_context>"))
    }

    func testBuildTranscriptionEnhancementInputWithAdapterAndRoutingMetadata() {
        let capabilities = VSCodeAdapter().capabilities
        let routingSignal = PromptRoutingSignal(
            appBundleIdentifier: "com.microsoft.vscode",
            appName: "visual studio code",
            windowTitle: nil,
            workspacePath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
            browserDomain: nil,
            isCodeEditorContext: true
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: capabilities,
            routingSignal: routingSignal
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<app_adapter>"))
        XCTAssertTrue(payload.contains("<display_name>Visual Studio Code</display_name>"))
        XCTAssertTrue(payload.contains("<mention_prefix>#</mention_prefix>"))
        XCTAssertTrue(payload.contains("<supports_file_mentions>true</supports_file_mentions>"))
        XCTAssertTrue(payload.contains("<routing_signal>"))
        XCTAssertTrue(payload.contains("<is_code_editor_context>true</is_code_editor_context>"))
    }

    // MARK: - Test Empty Value Sanitization

    func testEmptyWindowTitleNotEmitted() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.example.app",
            appName: "TestApp",
            windowTitle: "",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: nil,
            documentPath: nil,
            browserURL: nil
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<app_name>TestApp</app_name>"))
        XCTAssertFalse(payload.contains("<window_title>"))
        XCTAssertFalse(context.hasWindowTitle)
    }

    func testWhitespaceOnlyFieldsNotEmitted() {
        let appContext = AppContextInfo(
            bundleIdentifier: "  ",
            appName: "TestApp",
            windowTitle: " \t\n ",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "",
            documentPath: "   ",
            browserURL: "\n"
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<app_name>TestApp</app_name>"))
        XCTAssertFalse(payload.contains("<bundle_id>"))
        XCTAssertFalse(payload.contains("<window_title>"))
        XCTAssertFalse(payload.contains("<selected_text>"))
        XCTAssertFalse(payload.contains("<document_path>"))
        XCTAssertFalse(payload.contains("<browser_url>"))
        XCTAssertFalse(context.hasWindowTitle)
        XCTAssertFalse(context.hasDocumentPath)
        XCTAssertFalse(context.hasBrowserURL)
        XCTAssertFalse(context.hasSelectedText)
    }

    func testRoutingSignalEmptyFieldsNotEmitted() {
        let routingSignal = PromptRoutingSignal(
            appBundleIdentifier: "",
            appName: "  ",
            windowTitle: nil,
            workspacePath: "",
            browserDomain: nil,
            isCodeEditorContext: false
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: routingSignal
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<routing_signal>"))
        XCTAssertFalse(payload.contains("<app_bundle_identifier>"))
        XCTAssertFalse(payload.contains("<app_name>"))
        XCTAssertFalse(payload.contains("<workspace_path>"))
        XCTAssertFalse(payload.contains("<browser_domain>"))
        XCTAssertTrue(payload.contains("<is_code_editor_context>false</is_code_editor_context>"))
    }

    func testContextAwareSystemPromptOmitsEmptyFieldSources() {
        let appContext = AppContextInfo(
            bundleIdentifier: nil,
            appName: "TestApp",
            windowTitle: "",
            focusedElementRole: nil,
            focusedElementValue: nil,
            selectedText: "",
            documentPath: nil,
            browserURL: "  "
        )
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: appContext
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        XCTAssertTrue(result.contains("<type>app_metadata</type>"))
        XCTAssertFalse(result.contains("<type>window_title</type>"))
        XCTAssertFalse(result.contains("<type>selected_text</type>"))
        XCTAssertFalse(result.contains("<type>document_path</type>"))
        XCTAssertFalse(result.contains("<type>browser_url</type>"))
    }

    func testEmptyClipboardTextNotEmittedInEnhancementInput() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: "   ",
            context: .none
        )

        XCTAssertFalse(payload.contains("<clipboard_text>"))
        XCTAssertTrue(payload.contains("<transcription>"))
    }

    // MARK: - Test Workspace File Tree Context

    func testHasWorkspaceFileTreeNil() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil
        )
        XCTAssertFalse(context.hasWorkspaceFileTree)
    }

    func testHasWorkspaceFileTreeEmpty() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: ""
        )
        XCTAssertFalse(context.hasWorkspaceFileTree)
    }

    func testHasWorkspaceFileTreeWhitespaceOnly() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "  \n\t  "
        )
        XCTAssertFalse(context.hasWorkspaceFileTree)
    }

    func testHasWorkspaceFileTreeValid() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "total_files: 5\n---\nsrc/main.swift"
        )
        XCTAssertTrue(context.hasWorkspaceFileTree)
        XCTAssertTrue(context.hasAnyContext)
    }

    func testBuildContextAwareSystemPromptIncludesWorkspaceFileTreeSource() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "total_files: 3\n---\nfoo.swift\nbar.swift\nbaz.swift"
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        XCTAssertTrue(result.contains("<available>true</available>"))
        XCTAssertTrue(result.contains("<type>workspace_file_tree</type>"))
        XCTAssertTrue(result.contains("<usage>reference_only</usage>"))
    }

    func testBuildContextAwareSystemPromptOmitsWorkspaceFileTreeSourceWhenNil() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        XCTAssertFalse(result.contains("<type>workspace_file_tree</type>"))
    }

    func testBuildTranscriptionEnhancementInputIncludesWorkspaceFileTreeBlock() {
        let treeSummary = "total_files: 2\n---\nsrc/App.swift\nsrc/Service.swift"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: treeSummary
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: context
        )

        XCTAssertTrue(payload.contains("<workspace_file_tree>"))
        XCTAssertTrue(payload.contains("total_files: 2"))
        XCTAssertTrue(payload.contains("src/App.swift"))
    }

    func testBuildTranscriptionEnhancementInputOmitsWorkspaceFileTreeBlockWhenNil() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: .none
        )

        XCTAssertFalse(payload.contains("<workspace_file_tree>"))
    }

    func testBuildTranscriptionEnhancementInputOmitsWorkspaceFileTreeBlockWhenEmpty() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "   "
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: context
        )

        XCTAssertFalse(payload.contains("<workspace_file_tree>"))
    }

    // MARK: - Test Double-Wrap Prevention

    func testBuildMessagesDoesNotDoubleWrapEnhancementRequest() {
        let basePrompt = "You are a text enhancement assistant."
        let messages = AIEnhancementService.buildMessages(
            systemPrompt: basePrompt,
            text: "hello world",
            imageBase64: nil,
            context: .none
        )

        let systemContent = messages[0]["content"] as! String

        let openCount = systemContent.components(separatedBy: "<enhancement_request>").count - 1
        let closeCount = systemContent.components(separatedBy: "</enhancement_request>").count - 1

        XCTAssertEqual(openCount, 1, "Expected exactly one <enhancement_request> open tag, got \(openCount)")
        XCTAssertEqual(closeCount, 1, "Expected exactly one </enhancement_request> close tag, got \(closeCount)")
    }

    func testBuildMessagesWithAlreadyWrappedPromptStillSingleWraps() {
        // Inner XML tags get escaped by buildContextAwareSystemPrompt, so only one raw wrapper should exist
        let alreadyWrapped = "<enhancement_request><instructions>Do stuff</instructions></enhancement_request>"
        let messages = AIEnhancementService.buildMessages(
            systemPrompt: alreadyWrapped,
            text: "hello",
            imageBase64: nil,
            context: .none
        )

        let systemContent = messages[0]["content"] as! String

        let rawOpenCount = systemContent.components(separatedBy: "<enhancement_request>").count - 1
        XCTAssertEqual(rawOpenCount, 1, "Inner <enhancement_request> should be escaped, only one raw open tag expected")
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
