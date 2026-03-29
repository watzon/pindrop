//
//  LaunchAtLoginManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-29.
//

import ServiceManagement
import Testing
@testable import Pindrop

private enum MockLaunchAtLoginFailure: Error {
    case failed
}

final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var status: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

@MainActor
@Suite
struct LaunchAtLoginManagerTests {
    private func makeSUT() -> (sut: LaunchAtLoginManager, service: MockLaunchAtLoginService) {
        let service = MockLaunchAtLoginService()
        return (LaunchAtLoginManager(service: service), service)
    }

    @Test func initialization() {
        let sut = makeSUT().sut
        #expect(sut.isEnabled == false)
    }

    @Test func isEnabledReflectsServiceStatus() {
        let fixture = makeSUT()
        fixture.service.status = .enabled
        #expect(fixture.sut.isEnabled)

        fixture.service.status = .notRegistered
        #expect(fixture.sut.isEnabled == false)
    }

    @Test func setEnabledTrueRegistersService() throws {
        let fixture = makeSUT()
        try fixture.sut.setEnabled(true)

        #expect(fixture.service.registerCallCount == 1)
        #expect(fixture.service.unregisterCallCount == 0)
        #expect(fixture.sut.isEnabled)
    }

    @Test func setEnabledFalseUnregistersService() throws {
        let fixture = makeSUT()
        fixture.service.status = .enabled

        try fixture.sut.setEnabled(false)

        #expect(fixture.service.unregisterCallCount == 1)
        #expect(fixture.service.registerCallCount == 0)
        #expect(fixture.sut.isEnabled == false)
    }

    @Test func toggleState() throws {
        let fixture = makeSUT()
        #expect(fixture.sut.isEnabled == false)

        try fixture.sut.setEnabled(true)
        #expect(fixture.sut.isEnabled)

        try fixture.sut.setEnabled(false)
        #expect(fixture.sut.isEnabled == false)
    }

    @Test func setEnabledTrueWrapsRegistrationFailure() {
        let fixture = makeSUT()
        fixture.service.registerError = MockLaunchAtLoginFailure.failed

        do {
            try fixture.sut.setEnabled(true)
            Issue.record("Expected registrationFailed error")
        } catch let error as LaunchAtLoginManager.LaunchAtLoginError {
            guard case .registrationFailed = error else {
                Issue.record("Expected registrationFailed error")
                return
            }
        } catch {
            Issue.record("Expected LaunchAtLoginError, got \(error.localizedDescription)")
        }
    }

    @Test func setEnabledFalseWrapsUnregistrationFailure() {
        let fixture = makeSUT()
        fixture.service.status = .enabled
        fixture.service.unregisterError = MockLaunchAtLoginFailure.failed

        do {
            try fixture.sut.setEnabled(false)
            Issue.record("Expected unregistrationFailed error")
        } catch let error as LaunchAtLoginManager.LaunchAtLoginError {
            guard case .unregistrationFailed = error else {
                Issue.record("Expected unregistrationFailed error")
                return
            }
        } catch {
            Issue.record("Expected LaunchAtLoginError, got \(error.localizedDescription)")
        }
    }

    @Test func errorDescriptions() {
        let registrationError = LaunchAtLoginManager.LaunchAtLoginError.registrationFailed(NSError(domain: "test", code: 1))
        let unregistrationError = LaunchAtLoginManager.LaunchAtLoginError.unregistrationFailed(NSError(domain: "test", code: 2))

        #expect(registrationError.errorDescription != nil)
        #expect(unregistrationError.errorDescription != nil)
        #expect(registrationError.errorDescription?.contains("enable") == true)
        #expect(unregistrationError.errorDescription?.contains("disable") == true)
    }

    @Test func errorConformsToLocalizedError() {
        let error = LaunchAtLoginManager.LaunchAtLoginError.registrationFailed(NSError(domain: "test", code: 1))
        #expect((error as LocalizedError).errorDescription != nil)
    }

    @Test func stateConsistencyAfterMultipleToggles() throws {
        let fixture = makeSUT()

        for i in 0..<3 {
            try fixture.sut.setEnabled(i.isMultiple(of: 2))
        }

        #expect(fixture.sut.isEnabled)
        #expect(fixture.service.registerCallCount == 2)
        #expect(fixture.service.unregisterCallCount == 1)
    }
}
