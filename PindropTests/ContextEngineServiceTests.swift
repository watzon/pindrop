//
//  ContextEngineServiceTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import ApplicationServices
import Foundation
import Testing

@testable import Pindrop

// MARK: - Mock AX Provider

final class MockAXProvider: AXProviderProtocol, @unchecked Sendable {
    var isTrusted: Bool = true
    var frontmostAppElement: AXUIElement?
    var frontmostPID: pid_t?

    private var stringAttributes: [String: String] = [:]
    private var elementAttributes: [String: AXUIElement] = [:]
    private var pointAttributes: [String: CGPoint] = [:]
    private var sizeAttributes: [String: CGSize] = [:]
    private var rangeAttributes: [String: CFRange] = [:]
    private var rectForRangeAttributes: [String: CGRect] = [:]

    func isProcessTrusted() -> Bool {
        isTrusted
    }

    func copyFrontmostApplication() -> AXUIElement? {
        frontmostAppElement
    }

    func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        stringAttributes["\(attribute):\(CFHash(element))"]
    }

    func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        elementAttributes["\(attribute):\(CFHash(element))"]
    }

    func pointAttribute(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        pointAttributes["\(attribute):\(CFHash(element))"]
    }

    func sizeAttribute(_ attribute: String, of element: AXUIElement) -> CGSize? {
        sizeAttributes["\(attribute):\(CFHash(element))"]
    }

    func rangeAttribute(_ attribute: String, of element: AXUIElement) -> CFRange? {
        rangeAttributes["\(attribute):\(CFHash(element))"]
    }

    func rectForRangeAttribute(_ attribute: String, range: CFRange, of element: AXUIElement) -> CGRect? {
        rectForRangeAttributes["\(attribute):\(range.location):\(range.length):\(CFHash(element))"]
    }

    func frontmostAppPID() -> pid_t? {
        frontmostPID
    }

    func setStringAttribute(_ attribute: String, of element: AXUIElement, value: String) {
        stringAttributes["\(attribute):\(CFHash(element))"] = value
    }

    func setElementAttribute(_ attribute: String, of element: AXUIElement, value: AXUIElement) {
        elementAttributes["\(attribute):\(CFHash(element))"] = value
    }

    func setPointAttribute(_ attribute: String, of element: AXUIElement, value: CGPoint) {
        pointAttributes["\(attribute):\(CFHash(element))"] = value
    }

    func setSizeAttribute(_ attribute: String, of element: AXUIElement, value: CGSize) {
        sizeAttributes["\(attribute):\(CFHash(element))"] = value
    }

    func setRangeAttribute(_ attribute: String, of element: AXUIElement, value: CFRange) {
        rangeAttributes["\(attribute):\(CFHash(element))"] = value
    }

    func setRectForRangeAttribute(_ attribute: String, range: CFRange, of element: AXUIElement, value: CGRect) {
        rectForRangeAttributes["\(attribute):\(range.location):\(range.length):\(CFHash(element))"] = value
    }
}

@MainActor
@Suite
struct ContextEngineServiceTests {
    private func makeSUT() -> (
        sut: ContextEngineService,
        mockAXProvider: MockAXProvider,
        fakeAppElement: AXUIElement,
        fakeFocusedWindow: AXUIElement,
        fakeFocusedElement: AXUIElement
    ) {
        let mockAXProvider = MockAXProvider()
        let fakeAppElement = AXUIElementCreateApplication(99990)
        let fakeFocusedWindow = AXUIElementCreateApplication(99991)
        let fakeFocusedElement = AXUIElementCreateApplication(99992)

        mockAXProvider.frontmostAppElement = fakeAppElement
        mockAXProvider.frontmostPID = 99990

        return (
            ContextEngineService(axProvider: mockAXProvider),
            mockAXProvider,
            fakeAppElement,
            fakeFocusedWindow,
            fakeFocusedElement
        )
    }

    @Test func captureWithTrustedAXReturnsFocusedMetadata() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "TestApp")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeFocusedWindow, value: "Untitled Document")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fixture.fakeFocusedElement, value: "AXTextArea")
        fixture.mockAXProvider.setStringAttribute(kAXValueAttribute, of: fixture.fakeFocusedElement, value: "Hello World")
        fixture.mockAXProvider.setStringAttribute(kAXSelectedTextAttribute, of: fixture.fakeFocusedElement, value: "World")

        let result = fixture.sut.captureAppContext()
        let ctx = try #require(result.appContext)

        #expect(result.warnings.isEmpty)
        #expect(ctx.windowTitle == "Untitled Document")
        #expect(ctx.focusedElementRole == "AXTextArea")
        #expect(ctx.focusedElementValue == "Hello World")
        #expect(ctx.selectedText == "World")
    }

    @Test func captureWhenAXDeniedReturnsNonBlockingPartialSnapshot() {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = false

        let result = fixture.sut.captureAppContext()

        #expect(result.warnings.contains(.accessibilityPermissionDenied))
        #expect(result.warnings.isEmpty == false)
    }

    @Test func captureSnapshotIncludesClipboardText() {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = false

        let snapshot = fixture.sut.captureSnapshot(clipboardText: "clipboard context")

        #expect(snapshot.clipboardText == "clipboard context")
        #expect(snapshot.warnings.contains(.accessibilityPermissionDenied))
    }

    @Test func deriveRuntimeStateReadyForDetailedCodeContext() {
        let fixture = makeSUT()
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: AppContextInfo(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                appName: "Cursor",
                windowTitle: "AppCoordinator.swift",
                focusedElementRole: "AXTextArea",
                focusedElementValue: nil,
                selectedText: "func startRecording()",
                documentPath: "~/Projects/pindrop/Pindrop/AppCoordinator.swift",
                browserURL: nil
            ),
            clipboardText: nil,
            warnings: []
        )

        let runtimeState = fixture.sut.deriveRuntimeState(
            for: snapshot,
            adapterCapabilities: CursorAdapter().capabilities
        )

        #expect(runtimeState == .ready)
    }

    @Test func deriveRuntimeStateLimitedWhenPermissionDeniedButClipboardPresent() {
        let fixture = makeSUT()
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: nil,
            clipboardText: "clipboard context",
            warnings: [.accessibilityPermissionDenied]
        )

        let runtimeState = fixture.sut.deriveRuntimeState(for: snapshot, adapterCapabilities: nil)
        #expect(runtimeState == .limited)
    }

    @Test func captureFocusedTextSnapshotReturnsTextRangeAndAnchorRect() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fixture.fakeFocusedElement, value: "AXTextArea")
        fixture.mockAXProvider.setStringAttribute(kAXValueAttribute, of: fixture.fakeFocusedElement, value: "hello world")
        fixture.mockAXProvider.setRangeAttribute(kAXSelectedTextRangeAttribute, of: fixture.fakeFocusedElement, value: CFRange(location: 6, length: 5))
        fixture.mockAXProvider.setRectForRangeAttribute(
            kAXBoundsForRangeParameterizedAttribute,
            range: CFRange(location: 6, length: 5),
            of: fixture.fakeFocusedElement,
            value: CGRect(x: 100, y: 200, width: 50, height: 20)
        )

        let snapshot = try #require(fixture.sut.captureFocusedTextSnapshot())
        #expect(snapshot.text == "hello world")
        #expect(snapshot.selectedRange.location == 6)
        #expect(snapshot.selectedRange.length == 5)
        #expect(snapshot.anchorRect == CGRect(x: 100, y: 200, width: 50, height: 20))
    }

    @Test func captureFocusedElementAnchorRectPrefersSelectedRangeBounds() {
        let fixture = makeSUT()
        let range = CFRange(location: 12, length: 0)
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setRangeAttribute(kAXSelectedTextRangeAttribute, of: fixture.fakeFocusedElement, value: range)
        fixture.mockAXProvider.setRectForRangeAttribute(
            kAXBoundsForRangeParameterizedAttribute,
            range: range,
            of: fixture.fakeFocusedElement,
            value: CGRect(x: 320, y: 480, width: 2, height: 18)
        )

        let rect = fixture.sut.captureFocusedElementAnchorRect()
        #expect(rect == CGRect(x: 320, y: 480, width: 2, height: 18))
    }

    @Test func captureFocusedElementAnchorRectFallsBackToFocusedElementFrame() {
        let fixture = makeSUT()
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedElement, value: CGPoint(x: 200, y: 300))
        fixture.mockAXProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedElement, value: CGSize(width: 420, height: 36))

        let rect = fixture.sut.captureFocusedElementAnchorRect()
        #expect(rect == CGRect(x: 200, y: 300, width: 420, height: 36))
    }

    @Test func secureFieldRoleSkipsValueCapture() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Login")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fixture.fakeFocusedElement, value: "AXSecureTextField")
        fixture.mockAXProvider.setStringAttribute(kAXValueAttribute, of: fixture.fakeFocusedElement, value: "SuperSecret123")
        fixture.mockAXProvider.setStringAttribute(kAXSelectedTextAttribute, of: fixture.fakeFocusedElement, value: "Secret")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)

        #expect(appContext.focusedElementRole == "AXSecureTextField")
        #expect(appContext.focusedElementValue == nil)
        #expect(appContext.selectedText == nil)
    }

    @Test func secureFieldSubroleSkipsValueCapture() {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Login")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fixture.fakeFocusedElement, value: "AXTextField")
        fixture.mockAXProvider.setStringAttribute(kAXSubroleAttribute, of: fixture.fakeFocusedElement, value: "AXSecureTextField")
        fixture.mockAXProvider.setStringAttribute(kAXValueAttribute, of: fixture.fakeFocusedElement, value: "password123")

        let result = fixture.sut.captureAppContext()
        #expect(result.appContext?.focusedElementValue == nil)
    }

    @Test func sanitizeAndTruncateLongText() throws {
        let longText = String(repeating: "a", count: 3000)
        let result = ContextEngineService.sanitizeAndTruncate(
            longText,
            maxLength: ContextEngineService.maxAXFieldLength,
            fieldName: "test"
        )

        let truncated = try #require(result)
        #expect(truncated.count == ContextEngineService.maxAXFieldLength + "...[truncated]".count || truncated.count == ContextEngineService.maxAXFieldLength + "…[truncated]".count)
        #expect(truncated.hasSuffix("…[truncated]"))
    }

    @Test func sanitizeAndTruncateWhitespaceReturnsNil() {
        let result = ContextEngineService.sanitizeAndTruncate("   \n\t  ", maxLength: 100, fieldName: "test")
        #expect(result == nil)
    }

    @Test func sanitizeAndTruncateNilReturnsNil() {
        let result = ContextEngineService.sanitizeAndTruncate(nil, maxLength: 100, fieldName: "test")
        #expect(result == nil)
    }

    @Test func sanitizeAndTruncateShortTextPassesThrough() {
        let result = ContextEngineService.sanitizeAndTruncate("  hello  ", maxLength: 100, fieldName: "test")
        #expect(result == "hello")
    }

    @Test func redactHomePath() {
        let home = NSHomeDirectory()
        let path = "\(home)/Projects/myfile.swift"
        let result = ContextEngineService.redactHomePath(path)
        #expect(result == "~/Projects/myfile.swift")
    }

    @Test func redactHomePathPreservesNonHomePaths() {
        let result = ContextEngineService.redactHomePath("/usr/local/bin/tool")
        #expect(result == "/usr/local/bin/tool")
    }

    @Test func redactHomePathHandlesNil() {
        let result = ContextEngineService.redactHomePath(nil)
        #expect(result == nil)
    }

    @Test func redactHomePathHandlesFileURL() {
        let home = NSHomeDirectory()
        let fileURL = "file://\(home)/Documents/test.txt"
        let result = ContextEngineService.redactHomePath(fileURL)
        #expect(result == "~/Documents/test.txt")
    }

    @Test func redactSensitiveURLParams() throws {
        let url = "https://example.com/page?token=abc123&query=hello&api_key=secret"
        let result = try #require(ContextEngineService.redactSensitiveURLParams(url))

        #expect(result.contains("token=REDACTED"))
        #expect(result.contains("query=hello"))
        #expect(result.contains("api_key=REDACTED"))
    }

    @Test func redactSensitiveURLParamsPreservesCleanURLs() {
        let url = "https://example.com/page?search=swift&page=1"
        let result = ContextEngineService.redactSensitiveURLParams(url)
        #expect(result == url)
    }

    @Test func redactSensitiveURLParamsHandlesNil() {
        let result = ContextEngineService.redactSensitiveURLParams(nil)
        #expect(result == nil)
    }

    @Test func captureWithTrustedButNoAppElement() {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.frontmostAppElement = nil

        let result = fixture.sut.captureAppContext()
        #expect(result.warnings.contains(.accessibilityDataUnavailable))
    }

    @Test func captureWithNoFocusedElement() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Finder")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.focusedElementRole == nil)
        #expect(appContext.focusedElementValue == nil)
        #expect(appContext.selectedText == nil)
    }

    @Test func captureDocumentPath() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Xcode")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        let home = NSHomeDirectory()
        fixture.mockAXProvider.setStringAttribute(kAXDocumentAttribute, of: fixture.fakeFocusedWindow, value: "\(home)/Projects/test.swift")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Projects/test.swift")
    }

    @Test func captureDocumentPathFallsBackToFocusedElement() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Antigravity")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        let home = NSHomeDirectory()
        fixture.mockAXProvider.setStringAttribute(kAXDocumentAttribute, of: fixture.fakeFocusedElement, value: "\(home)/Documents/note.txt")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Documents/note.txt")
    }

    @Test func captureDocumentPathHandlesFileURL() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "VSCode")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        let home = NSHomeDirectory()
        fixture.mockAXProvider.setStringAttribute(kAXDocumentAttribute, of: fixture.fakeFocusedWindow, value: "file://\(home)/Code/main.swift")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Code/main.swift")
    }

    @Test func captureDocumentPathFallsBackToRepresentedFilenameAttribute() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "VSCode")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        let home = NSHomeDirectory()
        fixture.mockAXProvider.setStringAttribute("AXRepresentedFilename", of: fixture.fakeFocusedWindow, value: "\(home)/Code/README.md")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Code/README.md")
    }

    @Test func captureDocumentPathAcceptsFileURLFromAXURLAttribute() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "VSCode")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        let home = NSHomeDirectory()
        fixture.mockAXProvider.setStringAttribute(kAXURLAttribute, of: fixture.fakeFocusedWindow, value: "file://\(home)/Code/main.swift")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Code/main.swift")
    }

    @Test func captureDocumentPathRejectsNonFileURLs() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Browser")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.mockAXProvider.setStringAttribute(kAXDocumentAttribute, of: fixture.fakeFocusedWindow, value: "https://github.com/user/repo")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == nil)
    }

    @Test func captureDocumentPathAcceptsTildePath() throws {
        let fixture = makeSUT()
        fixture.mockAXProvider.isTrusted = true
        fixture.mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fixture.fakeAppElement, value: "Ghostty")
        fixture.mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.mockAXProvider.setStringAttribute(kAXDocumentAttribute, of: fixture.fakeFocusedWindow, value: "~/Projects/personal/pindrop/")

        let result = fixture.sut.captureAppContext()
        let appContext = try #require(result.appContext)
        #expect(appContext.documentPath == "~/Projects/personal/pindrop/")
    }
}
