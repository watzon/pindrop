//
//  AIEnhancementServiceTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct AIEnhancementServiceTests {
    private func makeSUT() -> (service: AIEnhancementService, mockSession: MockURLSession) {
        let mockSession = MockURLSession()
        let service = AIEnhancementService(session: mockSession)
        return (service, mockSession)
    }
    
    // MARK: - Test Enhancement with Mock API
    @Test func testEnhanceTextWithMockAPI() async throws {
        let (service, mockSession) = makeSUT()

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
        #expect(result == expectedEnhancedText)
        #expect(mockSession.lastRequest != nil)
        #expect(mockSession.lastRequest?.httpMethod == "POST")
        #expect(mockSession.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(mockSession.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
    @Test func testEnhanceWithoutAPIKeyOmitsAuthorizationHeader() async throws {
        let (service, mockSession) = makeSUT()

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
            url: URL(string: "http://localhost:11434/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        _ = try await service.enhance(
            text: "test",
            apiEndpoint: "http://localhost:11434/v1/chat/completions",
            apiKey: nil
        )

        #expect(mockSession.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }
    
    // MARK: - Test Fallback on API Error
    @Test func testThrowsOnAPIError() async throws {
        let (service, mockSession) = makeSUT()

        mockSession.mockError = URLError(.notConnectedToInternet)
        
        do {
            _ = try await service.enhance(
                text: "original text",
                apiEndpoint: "https://api.openai.com/v1/chat/completions",
                apiKey: "test-api-key"
            )
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is AIEnhancementService.EnhancementError)
        }
    }
    @Test func testThrowsOnHTTPError() async throws {
        let (service, mockSession) = makeSUT()

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
            Issue.record("Expected error to be thrown")
        } catch let error as AIEnhancementService.EnhancementError {
            if case .apiError(let message) = error {
                #expect(message == "HTTP 500")
            } else {
                Issue.record("Wrong error type")
            }
        }
    }
    @Test func testThrowsOnInvalidJSON() async throws {
        let (service, mockSession) = makeSUT()

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
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is AIEnhancementService.EnhancementError)
        }
    }
    
    // MARK: - Test Request Body
    @Test func testRequestBodyFormat() async throws {
        let (service, mockSession) = makeSUT()

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
        #expect(mockSession.lastRequest?.httpBody != nil)
        
        if let bodyData = mockSession.lastRequest?.httpBody,
           let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            
            // Current service default model is gpt-4o-mini; validate against that
            #expect(bodyJSON["model"] as? String == "gpt-4o-mini")
            #expect(bodyJSON["messages"] as? [[String: Any]] != nil)
            
            if let messages = bodyJSON["messages"] as? [[String: Any]] {
                #expect(messages.count == 2)
                
                // System message
                #expect(messages[0]["role"] as? String == "system")
                #expect((messages[0]["content"] as? String)?.contains("grammar") ?? false)
                
                // User message
                #expect(messages[1]["role"] as? String == "user")
                #expect(messages[1]["content"] as? String == inputText)
            }
        } else {
            Issue.record("Failed to parse request body")
        }
    }
    
// MARK: - Test Empty Text
    @Test func testEnhanceEmptyText() async throws {
        let (service, mockSession) = makeSUT()

        // Given
        let inputText = ""

        // When
        let result = try await service.enhance(
            text: inputText,
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key"
        )

        // Then - should return empty text without making API call
        #expect(result == "")
        #expect(mockSession.lastRequest == nil)
    }

    // MARK: - Test Message Building
    @Test func testBuildMessagesTextOnly() {
        // Given
        let systemPrompt = "You are helpful"
        let userContent = "Hello"
        let expectedUserPayload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: userContent,
            clipboardText: nil,
            context: .none
        )

        // When
        let messages = AIEnhancementService.buildMessages(
            systemPrompt: systemPrompt,
            text: userContent,
            imageBase64: nil
        )

        // Then
        #expect(messages.count == 2)

        // System message
        #expect(messages[0]["role"] as? String == "system")
        let systemContent = messages[0]["content"] as? String
        #expect(systemContent != nil)
        #expect(systemContent!.contains("<enhancement_request>"))
        #expect(systemContent!.contains("<instructions>"))
        #expect(systemContent!.contains(systemPrompt))
        #expect(systemContent!.contains("<behavior_rule>"))

        // User message - structured enhancement payload (not raw transcript only)
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == expectedUserPayload)
    }
    @Test func testBuildMessagesWithImage() {
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
        #expect(messages.count == 2)

        // System message
        #expect(messages[0]["role"] as? String == "system")
        let systemContent = messages[0]["content"] as? String
        #expect(systemContent != nil)
        #expect(systemContent!.contains("<enhancement_request>"))
        #expect(systemContent!.contains(systemPrompt))

        // User message - vision format with content array
        #expect(messages[1]["role"] as? String == "user")

        let content = messages[1]["content"] as? [[String: Any]]
        #expect(content != nil)
        #expect(content?.count == 2)

        // Text part
        let expectedUserPayload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: userContent,
            clipboardText: nil,
            context: .none
        )
        #expect(content?[0]["type"] as? String == "text")
        #expect(content?[0]["text"] as? String == expectedUserPayload)

        // Image part
        #expect(content?[1]["type"] as? String == "image_url")

        let imageUrl = content?[1]["image_url"] as? [String: String]
        #expect(imageUrl != nil)
        #expect(imageUrl?["url"] == "data:image/png;base64,\(imageBase64)")
    }

    // MARK: - Test Context Metadata
    @Test func testContextMetadataImageDescription() {
        let clipboardOnly = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: true
        )
        #expect(clipboardOnly.imageDescription == "clipboard image")

        let none = AIEnhancementService.ContextMetadata.none
        #expect(none.imageDescription == nil)
    }
    @Test func testBuildContextAwareSystemPromptNoContext() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata.none

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        #expect(result.contains("<enhancement_request>"))
        #expect(result.contains("<instructions>"))
        #expect(result.contains(basePrompt))
        #expect(result.contains("<supplementary_context>"))
        #expect(result.contains("<available>false</available>"))
        #expect(result.contains("<behavior_rule>"))
        #expect(result.contains("Do not answer questions"))
    }
    @Test func testBuildContextAwareSystemPromptWithClipboardText() {
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

        #expect(result.contains("<supplementary_context>"))
        #expect(result.contains("<available>true</available>"))
        #expect(result.contains("<type>clipboard_text</type>"))
        #expect(result.contains("<clipboard_text>"))
        #expect(result.contains("README section"))
        #expect(result.contains(basePrompt))
    }
    @Test func testBuildContextAwareSystemPromptRemovesTranscriptionPlaceholder() {
        let basePrompt = "Clean this text: ${transcription}"

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: .none
        )

        #expect(result.contains("Clean this text:"))
        #expect(!(result.contains("${transcription}")))
        #expect(!(result.contains("&lt;transcription/&gt;")))
    }
    @Test func testBuildContextAwareSystemPromptIncludesAssistantModeGuardrails() {
        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Clean this text",
            context: .none
        )

        #expect(result.contains("<interpretation_rule>"))
        #expect(result.contains("Never ask the user for additional text or clarification"))
    }
    @Test func testBuildContextAwareSystemPromptWithClipboardImage() {
        let basePrompt = "Enhance this text"
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: true
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: basePrompt,
            context: context
        )

        #expect(result.contains("<supplementary_context>"))
        #expect(result.contains("<type>clipboard_image</type>"))
        #expect(result.contains("clipboard_text,clipboard_image"))
        #expect(result.contains(basePrompt))
    }
    @Test func testBuildMessagesWithContext() {
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

        #expect(messages.count == 2)

        let systemContent = messages[0]["content"] as? String
        #expect(systemContent != nil)
        #expect(systemContent!.contains("<supplementary_context>"))
        #expect(systemContent!.contains("<type>clipboard_text</type>"))
        #expect(systemContent!.contains("<clipboard_text>"))
        #expect(systemContent!.contains("clipboard snippet"))
        #expect(systemContent!.contains(systemPrompt))

        let expectedUserPayload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: userContent,
            clipboardText: "clipboard snippet",
            context: context
        )
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == expectedUserPayload)
    }
    @Test func testBuildMessagesUserPayloadIncludesTranscriptionAndContextBlocks() {
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
        #expect(systemContent != nil)
        #expect(systemContent!.contains("<context_payload>"))
        #expect(systemContent!.contains("<clipboard_text>"))
        #expect(systemContent!.contains("public struct Editor {}"))
        #expect(systemContent!.contains("<app_context>"))
        #expect(systemContent!.contains("<app_adapter>"))
        #expect(systemContent!.contains("<routing_signal>"))
        #expect(systemContent!.contains("<workspace_file_tree>"))

        let expectedUserPayload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "this is the spoken message",
            clipboardText: context.clipboardText,
            context: context
        )
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == expectedUserPayload)
    }
    @Test func testRedactedPayloadLogLinesRedactsImageAndChunks() {
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
        #expect(lines.count > 1, "Expected payload to be chunked into multiple log lines")
        let combined = lines.joined()
        #expect(combined.contains("REDACTED_BASE64"), "Expected base64 to be redacted")
        // Expect size marker to equal length of original base64
        if let range = combined.range(of: "size=") {
            let after = combined[range.upperBound...]
            // read digits
            let digits = after.prefix { $0.isNumber }
            #expect(String(digits) == "\(longBase64.count)")
        } else {
            Issue.record("Size marker not found")
        }
    }
    @Test func testBuildTranscriptionEnhancementInputIncludesXMLBlocks() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: true
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: "clipboard reference",
            context: context
        )

        #expect(payload.contains("<enhancement_input>"))
        #expect(payload.contains("<transcription>"))
        #expect(payload.contains("hello world"))
        #expect(payload.contains("<clipboard_text>"))
        #expect(payload.contains("clipboard reference"))
        #expect(payload.contains("<image_context>"))
        #expect(payload.contains("clipboard image"))
    }
    @Test func testBuildTranscriptionEnhancementInputEscapesXML() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "Use <tag> & symbols \"now\"",
            clipboardText: "value with 'quotes'",
            context: .none
        )

        #expect(payload.contains("Use &lt;tag&gt; &amp; symbols &quot;now&quot;"))
        #expect(payload.contains("value with &apos;quotes&apos;"))
    }

    // MARK: - Test UI Context Sources
    @Test func testContextMetadataUISourceFlags() {
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

        #expect(meta.hasAppMetadata)
        #expect(meta.hasWindowTitle)
        #expect(meta.hasSelectedText)
        #expect(!(meta.hasDocumentPath))
        #expect(meta.hasBrowserURL)
        #expect(meta.hasAnyContext)
    }
    @Test func testContextMetadataUISourceFlagsNilAppContext() {
        let meta = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil
        )

        #expect(!(meta.hasAppMetadata))
        #expect(!(meta.hasWindowTitle))
        #expect(!(meta.hasSelectedText))
        #expect(!(meta.hasDocumentPath))
        #expect(!(meta.hasBrowserURL))
    }
    @Test func testContextMetadataBackwardCompatInitHasNilAppContext() {
        let meta = AIEnhancementService.ContextMetadata(
            hasClipboardText: true,
            hasClipboardImage: false
        )

        #expect(meta.hasClipboardText)
        #expect(!(meta.hasAppMetadata))
        #expect(!(meta.hasVocabularyWords))
        #expect(!(meta.hasReplacementCorrections))
    }
    @Test func testBuildContextAwareSystemPromptWithVocabularyContext() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            clipboardText: nil,
            hasClipboardImage: false,
            appContext: nil,
            vocabularyWords: ["Butterbase", "OpenCode", "OpenCode", ""]
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        #expect(result.contains("<type>custom_vocabulary</type>"))
        #expect(result.contains("<vocabulary_context>"))
        #expect(result.contains("<word>Butterbase</word>"))
        #expect(result.contains("<word>OpenCode</word>"))
        #expect(result.contains("Use only to improve spelling/casing"))
        #expect(result.contains("custom_vocabulary"))
    }
    @Test func testBuildContextAwareSystemPromptWithAppliedReplacementsContext() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            clipboardText: nil,
            hasClipboardImage: false,
            appContext: nil,
            replacementCorrections: [
                AIEnhancementService.ContextMetadata.ReplacementCorrection(original: "hashline", replacement: "hash line"),
                AIEnhancementService.ContextMetadata.ReplacementCorrection(original: "hashline", replacement: "hash line"),
                AIEnhancementService.ContextMetadata.ReplacementCorrection(original: "omipy", replacement: "Omipy")
            ]
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        #expect(result.contains("<type>applied_replacements</type>"))
        #expect(result.contains("<applied_replacements>"))
        #expect(result.contains("<from>hashline</from>"))
        #expect(result.contains("<to>hash line</to>"))
        #expect(result.contains("<from>omipy</from>"))
        #expect(result.contains("<to>Omipy</to>"))
        #expect(result.contains("custom_vocabulary,applied_replacements"))
    }
    @Test func testBuildContextAwareSystemPromptWithUIContextSources() {
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

        #expect(result.contains("<available>true</available>"))
        #expect(result.contains("<type>app_metadata</type>"))
        #expect(result.contains("<type>window_title</type>"))
        #expect(result.contains("<type>selected_text</type>"))
        #expect(result.contains("<type>browser_url</type>"))
        #expect(!(result.contains("<type>document_path</type>")))
        #expect(result.contains("app_metadata,window_title,selected_text,document_path,browser_url"))
    }
    @Test func testBuildContextAwareSystemPromptWithAdapterAndRoutingSources() {
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

        #expect(result.contains("<type>app_adapter</type>"))
        #expect(result.contains("<type>routing_signal</type>"))
        #expect(result.contains("app_adapter,routing_signal"))
    }
    @Test func testBuildTranscriptionEnhancementInputWithAppContext() {
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

        #expect(payload.contains("<app_context>"))
        #expect(payload.contains("<app_name>Xcode</app_name>"))
        #expect(payload.contains("<bundle_id>com.apple.dt.Xcode</bundle_id>"))
        #expect(payload.contains("<window_title>My&lt;Project&gt;.swift</window_title>"))
        #expect(payload.contains("<selected_text>let x = 1 &amp; 2</selected_text>"))
        #expect(payload.contains("<document_path>/Users/dev/My&lt;Project&gt;.swift</document_path>"))
        #expect(!(payload.contains("<browser_url>")))
    }
    @Test func testBuildTranscriptionEnhancementInputNoAppContext() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: nil,
            context: .none
        )

        #expect(!(payload.contains("<app_context>")))
    }
    @Test func testBuildTranscriptionEnhancementInputWithAdapterAndRoutingMetadata() {
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

        #expect(payload.contains("<app_adapter>"))
        #expect(payload.contains("<display_name>Visual Studio Code</display_name>"))
        #expect(payload.contains("<mention_prefix>@</mention_prefix>"))
        #expect(payload.contains("<mention_template>"))
        #expect(payload.contains("<supports_file_mentions>true</supports_file_mentions>"))
        #expect(payload.contains("<routing_signal>"))
        #expect(payload.contains("<is_code_editor_context>true</is_code_editor_context>"))
    }

    // MARK: - Test Empty Value Sanitization
    @Test func testEmptyWindowTitleNotEmitted() {
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

        #expect(payload.contains("<app_name>TestApp</app_name>"))
        #expect(!(payload.contains("<window_title>")))
        #expect(!(context.hasWindowTitle))
    }
    @Test func testWhitespaceOnlyFieldsNotEmitted() {
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

        #expect(payload.contains("<app_name>TestApp</app_name>"))
        #expect(!(payload.contains("<bundle_id>")))
        #expect(!(payload.contains("<window_title>")))
        #expect(!(payload.contains("<selected_text>")))
        #expect(!(payload.contains("<document_path>")))
        #expect(!(payload.contains("<browser_url>")))
        #expect(!(context.hasWindowTitle))
        #expect(!(context.hasDocumentPath))
        #expect(!(context.hasBrowserURL))
        #expect(!(context.hasSelectedText))
    }
    @Test func testRoutingSignalEmptyFieldsNotEmitted() {
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

        #expect(payload.contains("<routing_signal>"))
        #expect(!(payload.contains("<app_bundle_identifier>")))
        #expect(!(payload.contains("<app_name>")))
        #expect(!(payload.contains("<workspace_path>")))
        #expect(!(payload.contains("<browser_domain>")))
        #expect(!(payload.contains("<terminal_provider_identifier>")))
        #expect(payload.contains("<is_code_editor_context>false</is_code_editor_context>"))
    }
    @Test func testRoutingSignalIncludesTerminalProviderIdentifierWhenPresent() {
        let routingSignal = PromptRoutingSignal(
            appBundleIdentifier: "com.mitchellh.ghostty",
            appName: "ghostty",
            windowTitle: "codex",
            workspacePath: "~/Projects/pindrop",
            browserDomain: nil,
            isCodeEditorContext: false,
            terminalProviderIdentifier: "codex"
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

        #expect(payload.contains("<terminal_provider_identifier>codex</terminal_provider_identifier>"))
    }
    @Test func testContextAwareSystemPromptOmitsEmptyFieldSources() {
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

        #expect(result.contains("<type>app_metadata</type>"))
        #expect(!(result.contains("<type>window_title</type>")))
        #expect(!(result.contains("<type>selected_text</type>")))
        #expect(!(result.contains("<type>document_path</type>")))
        #expect(!(result.contains("<type>browser_url</type>")))
    }
    @Test func testEmptyClipboardTextNotEmittedInEnhancementInput() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello",
            clipboardText: "   ",
            context: .none
        )

        #expect(!(payload.contains("<clipboard_text>")))
        #expect(payload.contains("<transcription>"))
    }

    // MARK: - Test Workspace File Tree Context
    @Test func testHasWorkspaceFileTreeNil() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil
        )
        #expect(!(context.hasWorkspaceFileTree))
    }
    @Test func testHasWorkspaceFileTreeEmpty() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: ""
        )
        #expect(!(context.hasWorkspaceFileTree))
    }
    @Test func testHasWorkspaceFileTreeWhitespaceOnly() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "  \n\t  "
        )
        #expect(!(context.hasWorkspaceFileTree))
    }
    @Test func testHasWorkspaceFileTreeValid() {
        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: "total_files: 5\n---\nsrc/main.swift"
        )
        #expect(context.hasWorkspaceFileTree)
        #expect(context.hasAnyContext)
    }
    @Test func testBuildContextAwareSystemPromptIncludesWorkspaceFileTreeSource() {
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

        #expect(result.contains("<available>true</available>"))
        #expect(result.contains("<type>workspace_file_tree</type>"))
        #expect(result.contains("<usage>reference_only</usage>"))
    }
    @Test func testBuildContextAwareSystemPromptOmitsWorkspaceFileTreeSourceWhenNil() {
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

        #expect(!(result.contains("<type>workspace_file_tree</type>")))
    }
    @Test func testBuildTranscriptionEnhancementInputIncludesWorkspaceFileTreeBlock() {
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

        #expect(payload.contains("<workspace_file_tree>"))
        #expect(payload.contains("total_files: 2"))
        #expect(payload.contains("src/App.swift"))
    }
    @Test func testBuildTranscriptionEnhancementInputOmitsWorkspaceFileTreeBlockWhenNil() {
        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: .none
        )

        #expect(!(payload.contains("<workspace_file_tree>")))
    }
    @Test func testBuildTranscriptionEnhancementInputOmitsWorkspaceFileTreeBlockWhenEmpty() {
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

        #expect(!(payload.contains("<workspace_file_tree>")))
    }
    @Test func testContextMetadataLiveSessionFlags() {
        let appContext = AppContextInfo(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appName: "Cursor",
            windowTitle: "AppCoordinator.swift",
            focusedElementRole: "AXTextArea",
            focusedElementValue: nil,
            selectedText: "handleToggleRecording",
            documentPath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
            browserURL: nil
        )

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: appContext,
            clipboardText: nil,
            warnings: []
        )

        let transition = ContextSessionTransition(
            trigger: .recordingStart,
            snapshot: snapshot,
            activeFilePath: "Pindrop/AppCoordinator.swift",
            activeFileConfidence: 1.0,
            workspacePath: "~/Projects/pindrop",
            workspaceConfidence: 0.9,
            outputMode: "clipboard",
            contextTags: ["AppCoordinator.swift", "style:swift"],
            transitionSignature: "sig-1"
        )

        let liveContext = AIEnhancementService.LiveSessionContext(
            runtimeState: .ready,
            latestAppName: "Cursor",
            latestWindowTitle: "AppCoordinator.swift",
            activeFilePath: "Pindrop/AppCoordinator.swift",
            activeFileConfidence: 1.0,
            workspacePath: "~/Projects/pindrop",
            workspaceConfidence: 0.9,
            fileTagCandidates: ["AppCoordinator.swift"],
            styleSignals: ["style:swift"],
            codingSignals: ["code_editor_context"],
            transitions: [transition]
        )

        let metadata = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil,
            liveSessionContext: liveContext
        )

        #expect(metadata.hasLiveSessionContext)
        #expect(metadata.hasAnyContext)
    }
    @Test func testBuildContextAwareSystemPromptIncludesLiveSessionContextSource() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                appName: "Cursor",
                windowTitle: "AppCoordinator.swift",
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let liveContext = AIEnhancementService.LiveSessionContext(
            runtimeState: .ready,
            latestAppName: "Cursor",
            latestWindowTitle: "AppCoordinator.swift",
            activeFilePath: "Pindrop/AppCoordinator.swift",
            activeFileConfidence: 1.0,
            workspacePath: "~/Projects/pindrop",
            workspaceConfidence: 0.9,
            fileTagCandidates: ["AppCoordinator.swift"],
            styleSignals: ["style:swift"],
            codingSignals: ["code_editor_context"],
            transitions: [
                ContextSessionTransition(
                    trigger: .recordingStart,
                    snapshot: snapshot,
                    activeFilePath: "Pindrop/AppCoordinator.swift",
                    activeFileConfidence: 1.0,
                    workspacePath: "~/Projects/pindrop",
                    workspaceConfidence: 0.9,
                    outputMode: "clipboard",
                    contextTags: ["AppCoordinator.swift"],
                    transitionSignature: "sig-1"
                )
            ]
        )

        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil,
            liveSessionContext: liveContext
        )

        let result = AIEnhancementService.buildContextAwareSystemPrompt(
            basePrompt: "Enhance text",
            context: context
        )

        #expect(result.contains("<type>live_session_context</type>"))
        #expect(result.contains("<live_session_context>"))
        #expect(result.contains("<runtime_state>ready</runtime_state>"))
    }
    @Test func testBuildTranscriptionEnhancementInputIncludesLiveSessionContextBlock() {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                appName: "Cursor",
                windowTitle: "AppCoordinator.swift",
                focusedElementRole: nil,
                focusedElementValue: nil,
                selectedText: nil,
                documentPath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let context = AIEnhancementService.ContextMetadata(
            hasClipboardText: false,
            hasClipboardImage: false,
            appContext: nil,
            adapterCapabilities: nil,
            routingSignal: nil,
            workspaceFileTree: nil,
            liveSessionContext: AIEnhancementService.LiveSessionContext(
                runtimeState: .limited,
                latestAppName: "Cursor",
                latestWindowTitle: "AppCoordinator.swift",
                activeFilePath: "Pindrop/AppCoordinator.swift",
                activeFileConfidence: 0.75,
                workspacePath: "~/Projects/pindrop",
                workspaceConfidence: 0.7,
                fileTagCandidates: ["AppCoordinator.swift"],
                styleSignals: ["style:swift"],
                codingSignals: ["code_editor_context"],
                transitions: [
                    ContextSessionTransition(
                        trigger: .poll,
                        snapshot: snapshot,
                        activeFilePath: "Pindrop/AppCoordinator.swift",
                        activeFileConfidence: 0.75,
                        workspacePath: "~/Projects/pindrop",
                        workspaceConfidence: 0.7,
                        outputMode: "clipboard",
                        contextTags: ["AppCoordinator.swift"],
                        transitionSignature: "sig-1"
                    )
                ]
            )
        )

        let payload = AIEnhancementService.buildTranscriptionEnhancementInput(
            transcription: "hello world",
            clipboardText: nil,
            context: context
        )

        #expect(payload.contains("<live_session_context>"))
        #expect(payload.contains("<runtime_state>limited</runtime_state>"))
        #expect(payload.contains("<recent_transitions>"))
    }


    // MARK: - Test Double-Wrap Prevention
    @Test func testBuildMessagesDoesNotDoubleWrapEnhancementRequest() {
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

        #expect(openCount == 1, "Expected exactly one <enhancement_request> open tag, got \(openCount)")
        #expect(closeCount == 1, "Expected exactly one </enhancement_request> close tag, got \(closeCount)")
    }
    @Test func testBuildMessagesWithAlreadyWrappedPromptStillSingleWraps() {
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
        #expect(rawOpenCount == 1, "Inner <enhancement_request> should be escaped, only one raw open tag expected")
    }

    // MARK: - Test Transcription Metadata
    @Test func testGenerateTranscriptionMetadataParsesTitleAndSummary() async throws {
        let (service, mockSession) = makeSUT()

        mockSession.mockData = #"""
        {
            "choices": [{
                "message": {
                    "content": "```json\n{\"title\":\"Q1 Planning Review\",\"summary\":\"The team reviewed first quarter priorities and aligned on launch timing. They called out staffing risk and agreed to follow up on hiring needs.\"}\n```"
                }
            }]
        }
        """#.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let result = try await service.generateTranscriptionMetadata(
            transcription: "We reviewed first quarter priorities and launch timing.",
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key",
            model: "gpt-4o-mini",
            includeTitle: true
        )

        #expect(result.title == "Q1 Planning Review")
        #expect(result.summary == "The team reviewed first quarter priorities and aligned on launch timing. They called out staffing risk and agreed to follow up on hiring needs.")

        if let bodyData = mockSession.lastRequest?.httpBody,
           let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let messages = bodyJSON["messages"] as? [[String: Any]],
           let systemPrompt = messages.first?["content"] as? String {
            #expect(systemPrompt.contains("4-8 words"))
            #expect(systemPrompt.contains("2-4 sentences"))
        } else {
            Issue.record("Failed to inspect transcription metadata request body")
        }
    }

    @Test func testGenerateTranscriptionMetadataAllowsSummaryOnlyResponses() async throws {
        let (service, mockSession) = makeSUT()

        mockSession.mockData = #"""
        {
            "choices": [{
                "message": {
                    "content": "{\"title\":\"\",\"summary\":\"The meeting focused on release blockers and next steps.\"}"
                }
            }]
        }
        """#.data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let result = try await service.generateTranscriptionMetadata(
            transcription: "We focused on release blockers and next steps.",
            apiEndpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "test-api-key",
            model: "gpt-4o-mini",
            includeTitle: false
        )

        #expect(result.title == nil)
        #expect(result.summary == "The meeting focused on release blockers and next steps.")

        if let bodyData = mockSession.lastRequest?.httpBody,
           let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let messages = bodyJSON["messages"] as? [[String: Any]],
           let systemPrompt = messages.first?["content"] as? String {
            #expect(systemPrompt.contains("return an empty string"))
        } else {
            Issue.record("Failed to inspect transcription metadata summary-only request body")
        }
    }

    // MARK: - Test Model Capabilities
    @Test func testKnownVisionModels() {
        // OpenAI vision models
        #expect(ModelCapabilities.supportsVision(modelId: "gpt-4o"))
        #expect(ModelCapabilities.supportsVision(modelId: "gpt-4o-mini"))
        #expect(ModelCapabilities.supportsVision(modelId: "gpt-4-vision-preview"))
        #expect(ModelCapabilities.supportsVision(modelId: "gpt-4-turbo"))

        // Anthropic Claude 3 vision models
        #expect(ModelCapabilities.supportsVision(modelId: "claude-3-opus"))
        #expect(ModelCapabilities.supportsVision(modelId: "claude-3-sonnet"))
        #expect(ModelCapabilities.supportsVision(modelId: "claude-3-haiku"))
        #expect(ModelCapabilities.supportsVision(modelId: "claude-3.5-sonnet"))

        // Google Gemini vision models
        #expect(ModelCapabilities.supportsVision(modelId: "gemini-pro-vision"))
        #expect(ModelCapabilities.supportsVision(modelId: "gemini-1.5-pro"))
        #expect(ModelCapabilities.supportsVision(modelId: "gemini-1.5-flash"))
        #expect(ModelCapabilities.supportsVision(modelId: "gemini-2.0-flash"))
    }
    @Test func testNonVisionModels() {
        // OpenAI non-vision models
        #expect(!(ModelCapabilities.supportsVision(modelId: "gpt-3.5-turbo")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "gpt-4")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "gpt-4-0613")))

        // Anthropic non-vision models
        #expect(!(ModelCapabilities.supportsVision(modelId: "claude-2")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "claude-2.1")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "claude-instant")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "claude-instant-1.2")))

        // Unknown models
        #expect(!(ModelCapabilities.supportsVision(modelId: "unknown-model")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "some-random-model")))
    }
    @Test func testOpenRouterPrefixedModels() {
        // OpenRouter vision models
        #expect(ModelCapabilities.supportsVision(modelId: "openai/gpt-4o"))
        #expect(ModelCapabilities.supportsVision(modelId: "openai/gpt-4o-mini"))
        #expect(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3-opus"))
        #expect(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3-sonnet"))
        #expect(ModelCapabilities.supportsVision(modelId: "anthropic/claude-3.5-sonnet"))
        #expect(ModelCapabilities.supportsVision(modelId: "google/gemini-1.5-pro"))

        // OpenRouter non-vision models
        #expect(!(ModelCapabilities.supportsVision(modelId: "openai/gpt-3.5-turbo")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "openai/gpt-4")))
        #expect(!(ModelCapabilities.supportsVision(modelId: "anthropic/claude-2")))
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
