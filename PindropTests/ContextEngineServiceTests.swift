//
//  ContextEngineServiceTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import ApplicationServices
import XCTest

@testable import Pindrop

// MARK: - Mock AX Provider

/// Mock implementation of AXProviderProtocol for testing.
/// All behavior is configurable — no real AX calls are made.
final class MockAXProvider: AXProviderProtocol, @unchecked Sendable {

    // MARK: - Configurable State

    var isTrusted: Bool = true
    var frontmostAppElement: AXUIElement?
    var frontmostPID: pid_t?

    /// Map of (attribute, element-hash) → String value.
    /// Uses the element's CFHash as the key component.
    private var stringAttributes: [String: String] = [:]

    /// Map of (attribute, element-hash) → AXUIElement value.
    private var elementAttributes: [String: AXUIElement] = [:]

    // MARK: - Protocol Implementation

    func isProcessTrusted() -> Bool {
        isTrusted
    }

    func copyFrontmostApplication() -> AXUIElement? {
        frontmostAppElement
    }

    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        let key = "\(attribute):\(CFHash(element))"
        return stringAttributes[key]
    }

    func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        let key = "\(attribute):\(CFHash(element))"
        return elementAttributes[key]
    }

    func frontmostAppPID() -> pid_t? {
        frontmostPID
    }

    // MARK: - Test Helpers

    /// Register a string attribute return value for a specific element.
    func setStringAttribute(_ attribute: String, of element: AXUIElement, value: String) {
        let key = "\(attribute):\(CFHash(element))"
        stringAttributes[key] = value
    }

    /// Register an element attribute return value for a specific element.
    func setElementAttribute(_ attribute: String, of element: AXUIElement, value: AXUIElement) {
        let key = "\(attribute):\(CFHash(element))"
        elementAttributes[key] = value
    }
}

// MARK: - Tests

@MainActor
final class ContextEngineServiceTests: XCTestCase {

    var sut: ContextEngineService!
    var mockAXProvider: MockAXProvider!

    // Synthetic AXUIElements for testing (created via AXUIElementCreateApplication with fake PIDs)
    var fakeAppElement: AXUIElement!
    var fakeFocusedWindow: AXUIElement!
    var fakeFocusedElement: AXUIElement!

    override func setUp() async throws {
        mockAXProvider = MockAXProvider()

        // Create synthetic AXUIElements using different fake PIDs
        fakeAppElement = AXUIElementCreateApplication(99990)
        fakeFocusedWindow = AXUIElementCreateApplication(99991)
        fakeFocusedElement = AXUIElementCreateApplication(99992)

        mockAXProvider.frontmostAppElement = fakeAppElement
        mockAXProvider.frontmostPID = 99990

        sut = ContextEngineService(axProvider: mockAXProvider)
    }

    override func tearDown() async throws {
        sut = nil
        mockAXProvider = nil
        fakeAppElement = nil
        fakeFocusedWindow = nil
        fakeFocusedElement = nil
    }

    // MARK: - Required Verification Tests

    /// Verifies that when AX is trusted and data is available, the service returns
    /// a populated AppContextInfo with focused element metadata and no warnings.
    func testCaptureWithTrustedAXReturnsFocusedMetadata() {
        // Configure: AX trusted, app element returns window, window has title,
        // focused element has role + value + selected text
        mockAXProvider.isTrusted = true

        // App title
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "TestApp")

        // Focused window
        mockAXProvider.setElementAttribute(
            kAXFocusedWindowAttribute, of: fakeAppElement, value: fakeFocusedWindow)
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeFocusedWindow, value: "Untitled Document")

        // Focused UI element
        mockAXProvider.setElementAttribute(
            kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fakeFocusedElement, value: "AXTextArea")
        mockAXProvider.setStringAttribute(
            kAXValueAttribute, of: fakeFocusedElement, value: "Hello World")
        mockAXProvider.setStringAttribute(
            kAXSelectedTextAttribute, of: fakeFocusedElement, value: "World")

        // Act
        let result = sut.captureAppContext()

        // Assert: we get back an AppContextInfo with our data
        XCTAssertNotNil(result.appContext, "AppContext should not be nil when AX is trusted")
        XCTAssertTrue(result.warnings.isEmpty, "No warnings expected for fully trusted capture")

        let ctx = result.appContext!
        XCTAssertEqual(ctx.windowTitle, "Untitled Document")
        XCTAssertEqual(ctx.focusedElementRole, "AXTextArea")
        XCTAssertEqual(ctx.focusedElementValue, "Hello World")
        XCTAssertEqual(ctx.selectedText, "World")
    }

    /// Verifies that when AX permission is denied, the service returns a partial
    /// snapshot with appropriate warnings instead of blocking or throwing.
    func testCaptureWhenAXDeniedReturnsNonBlockingPartialSnapshot() {
        // Configure: AX NOT trusted
        mockAXProvider.isTrusted = false

        // Act
        let result = sut.captureAppContext()

        // Assert: warnings include permission denied + partial capture
        XCTAssertTrue(
            result.warnings.contains(.accessibilityPermissionDenied),
            "Should include accessibilityPermissionDenied warning"
        )

        // The method should NOT throw or block
        // App context may be nil (no NSWorkspace.frontmostApplication in test) or partial
        // Either way, we should not crash and should have warnings
        XCTAssertFalse(result.warnings.isEmpty, "Should have at least one warning")
    }

    // MARK: - Secure Field Tests

    /// Verifies that secure text fields (AXSecureTextField role) have their values skipped.
    func testSecureFieldRoleSkipsValueCapture() {
        mockAXProvider.isTrusted = true

        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Login")
        mockAXProvider.setElementAttribute(
            kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(
            kAXRoleAttribute, of: fakeFocusedElement, value: "AXSecureTextField")
        mockAXProvider.setStringAttribute(
            kAXValueAttribute, of: fakeFocusedElement, value: "SuperSecret123")
        mockAXProvider.setStringAttribute(
            kAXSelectedTextAttribute, of: fakeFocusedElement, value: "Secret")

        let result = sut.captureAppContext()

        XCTAssertNotNil(result.appContext)
        XCTAssertEqual(result.appContext?.focusedElementRole, "AXSecureTextField")
        XCTAssertNil(
            result.appContext?.focusedElementValue,
            "Secure field value must NOT be captured")
        XCTAssertNil(
            result.appContext?.selectedText,
            "Selected text in secure field must NOT be captured")
    }

    /// Verifies that secure text fields identified by subrole also have values skipped.
    func testSecureFieldSubroleSkipsValueCapture() {
        mockAXProvider.isTrusted = true

        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Login")
        mockAXProvider.setElementAttribute(
            kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(
            kAXRoleAttribute, of: fakeFocusedElement, value: "AXTextField")
        mockAXProvider.setStringAttribute(
            kAXSubroleAttribute, of: fakeFocusedElement, value: "AXSecureTextField")
        mockAXProvider.setStringAttribute(
            kAXValueAttribute, of: fakeFocusedElement, value: "password123")

        let result = sut.captureAppContext()

        XCTAssertNil(
            result.appContext?.focusedElementValue,
            "Secure subrole field value must NOT be captured")
    }

    // MARK: - Sanitization Tests

    /// Verifies that text values are truncated when they exceed max length.
    func testSanitizeAndTruncateLongText() {
        let longText = String(repeating: "a", count: 3000)
        let result = ContextEngineService.sanitizeAndTruncate(
            longText,
            maxLength: ContextEngineService.maxAXFieldLength,
            fieldName: "test"
        )

        XCTAssertNotNil(result)
        // maxAXFieldLength (2048) + "…[truncated]" (12 chars)
        XCTAssertEqual(result!.count, ContextEngineService.maxAXFieldLength + "…[truncated]".count)
        XCTAssertTrue(result!.hasSuffix("…[truncated]"))
    }

    /// Verifies that whitespace-only strings become nil.
    func testSanitizeAndTruncateWhitespaceReturnsNil() {
        let result = ContextEngineService.sanitizeAndTruncate(
            "   \n\t  ",
            maxLength: 100,
            fieldName: "test"
        )
        XCTAssertNil(result, "Whitespace-only strings should return nil")
    }

    /// Verifies that nil input returns nil.
    func testSanitizeAndTruncateNilReturnsNil() {
        let result = ContextEngineService.sanitizeAndTruncate(nil, maxLength: 100, fieldName: "test")
        XCTAssertNil(result)
    }

    /// Verifies that short text passes through with trimming only.
    func testSanitizeAndTruncateShortTextPassesThrough() {
        let result = ContextEngineService.sanitizeAndTruncate(
            "  hello  ", maxLength: 100, fieldName: "test")
        XCTAssertEqual(result, "hello")
    }

    // MARK: - Home Path Redaction Tests

    func testRedactHomePath() {
        let home = NSHomeDirectory()
        let path = "\(home)/Projects/myfile.swift"
        let result = ContextEngineService.redactHomePath(path)
        XCTAssertEqual(result, "~/Projects/myfile.swift")
    }

    func testRedactHomePathPreservesNonHomePaths() {
        let result = ContextEngineService.redactHomePath("/usr/local/bin/tool")
        XCTAssertEqual(result, "/usr/local/bin/tool")
    }

    func testRedactHomePathHandlesNil() {
        let result = ContextEngineService.redactHomePath(nil)
        XCTAssertNil(result)
    }

    func testRedactHomePathHandlesFileURL() {
        let home = NSHomeDirectory()
        let fileURL = "file://\(home)/Documents/test.txt"
        let result = ContextEngineService.redactHomePath(fileURL)
        XCTAssertEqual(result, "~/Documents/test.txt")
    }

    // MARK: - URL Param Redaction Tests

    func testRedactSensitiveURLParams() {
        let url = "https://example.com/page?token=abc123&query=hello&api_key=secret"
        let result = ContextEngineService.redactSensitiveURLParams(url)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("token=REDACTED"))
        XCTAssertTrue(result!.contains("query=hello"))
        XCTAssertTrue(result!.contains("api_key=REDACTED"))
    }

    func testRedactSensitiveURLParamsPreservesCleanURLs() {
        let url = "https://example.com/page?search=swift&page=1"
        let result = ContextEngineService.redactSensitiveURLParams(url)
        XCTAssertEqual(result, url)
    }

    func testRedactSensitiveURLParamsHandlesNil() {
        let result = ContextEngineService.redactSensitiveURLParams(nil)
        XCTAssertNil(result)
    }

    // MARK: - AX Data Unavailable Test

    /// Verifies behavior when AX is trusted but no frontmost app element is available.
    func testCaptureWithTrustedButNoAppElement() {
        mockAXProvider.isTrusted = true
        mockAXProvider.frontmostAppElement = nil

        let result = sut.captureAppContext()

        XCTAssertTrue(
            result.warnings.contains(.accessibilityDataUnavailable),
            "Should warn when AX element is unavailable"
        )
    }

    // MARK: - No Focused Element Test

    /// Verifies that when there's no focused element, role/value/selectedText are nil.
    func testCaptureWithNoFocusedElement() {
        mockAXProvider.isTrusted = true
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Finder")
        // No focused element set

        let result = sut.captureAppContext()

        XCTAssertNotNil(result.appContext)
        XCTAssertNil(result.appContext?.focusedElementRole)
        XCTAssertNil(result.appContext?.focusedElementValue)
        XCTAssertNil(result.appContext?.selectedText)
    }

    // MARK: - Document Path Test

    func testCaptureDocumentPath() {
        mockAXProvider.isTrusted = true
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Xcode")

        // Set focused window with document attribute
        mockAXProvider.setElementAttribute(
            kAXFocusedWindowAttribute, of: fakeAppElement, value: fakeFocusedWindow)
        let home = NSHomeDirectory()
        mockAXProvider.setStringAttribute(
            kAXDocumentAttribute, of: fakeFocusedWindow, value: "\(home)/Projects/test.swift")

        let result = sut.captureAppContext()

        XCTAssertNotNil(result.appContext)
        XCTAssertEqual(
            result.appContext?.documentPath, "~/Projects/test.swift",
            "Document path should have home directory redacted"
        )
    }
}
