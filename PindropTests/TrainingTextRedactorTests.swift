//
//  TrainingTextRedactorTests.swift
//  PindropTests
//
//  Created on 2026-07-14.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct TrainingTextRedactorTests {
    private let sut = TrainingTextRedactor()

    @Test func redactsEmailAddresses() {
        let result = sut.redact("send it to jane.doe@example.com please")
        #expect(result == "send it to <email> please")
    }

    @Test func redactsURLs() {
        let result = sut.redact("check https://example.com/private/doc for details")
        #expect(result == "check <url> for details")
    }

    @Test func redactsFilePaths() {
        let result = sut.redact("open /Users/someone/Documents/secret.txt now")
        #expect(!result.contains("someone"))
        #expect(result.contains("<path>"))
    }

    @Test func redactsBearerTokens() {
        let result = sut.redact("use Bearer abc123def456ghi789 for auth")
        #expect(!result.contains("abc123def456ghi789"))
    }

    @Test func redactsSecretAssignments() {
        let result = sut.redact("set api_key = sk-supersecretvalue")
        #expect(!result.contains("sk-supersecretvalue"))
    }

    @Test func redactsUUIDs() {
        let result = sut.redact("record 123E4567-E89B-12D3-A456-426614174000 failed")
        #expect(result == "record <uuid> failed")
    }

    @Test func redactsLongDigitRuns() {
        #expect(sut.redact("call me at 5550123456") == "call me at <number>")
        #expect(sut.redact("call me at 555 0123 4567") == "call me at <number>")
        #expect(sut.redact("card 4111-1111-1111-1111 expired") == "card <number> expired")
    }

    @Test func keepsShortNumbersIntact() {
        #expect(sut.redact("meet me at 3 pm on the 21st") == "meet me at 3 pm on the 21st")
        #expect(sut.redact("in 2026 we shipped 45 features") == "in 2026 we shipped 45 features")
    }

    @Test func redactsSocialHandles() {
        let result = sut.redact("ping @some_user about this")
        #expect(result == "ping <handle> about this")
    }

    @Test func leavesOrdinaryDictationUntouched() {
        let text = "Hello world, this is an ordinary sentence with punctuation."
        #expect(sut.redact(text) == text)
    }
}
