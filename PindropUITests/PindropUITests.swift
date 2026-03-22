//
//  PindropUITests.swift
//  PindropUITests
//
//  Created on 2026-03-21.
//

import AppKit
import XCTest

final class PindropUITests: XCTestCase {
    private let targetBundleIdentifier = "tech.watzon.pindrop"
    private let testModeKey = "PINDROP_TEST_MODE"
    private let uiTestModeKey = "PINDROP_UI_TEST_MODE"
    private let uiTestSurfaceKey = "PINDROP_UI_TEST_SURFACE"
    private let settingsTabKey = "PINDROP_UI_TEST_SETTINGS_TAB"
    private let settingsSearchTextKey = "PINDROP_UI_TEST_SETTINGS_SEARCH_TEXT"
    private let defaultsSuiteKey = "PINDROP_TEST_USER_DEFAULTS_SUITE"
    private var launchedApplication: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let launchedApplication, launchedApplication.state != .notRunning {
            launchedApplication.terminate()
        }
        launchedApplication = nil
    }

    @MainActor
    func testSettingsFixtureLaunches() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication()
        launchedApplication = app
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Search settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["General"].exists)
    }

    @MainActor
    func testSettingsSearchShowsEmptyStateForUnknownQuery() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication(searchText: "no-match-query")
        launchedApplication = app
        app.launch()

        XCTAssertTrue(app.staticTexts["No settings found"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testThemeTabFixtureLaunches() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication(settingsTab: "Theme")
        launchedApplication = app
        app.launch()

        XCTAssertTrue(app.staticTexts["Theme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Light Theme"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Dark Theme"].waitForExistence(timeout: 2))
    }

    private func configuredApplication(
        surface: String = "settings",
        settingsTab: String = "General",
        searchText: String? = nil,
        defaultsSuite: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[testModeKey] = "1"
        app.launchEnvironment[uiTestModeKey] = "1"
        app.launchEnvironment[uiTestSurfaceKey] = surface
        app.launchEnvironment[settingsTabKey] = settingsTab
        if let searchText {
            app.launchEnvironment[settingsSearchTextKey] = searchText
        }
        if let defaultsSuite {
            app.launchEnvironment[defaultsSuiteKey] = defaultsSuite
        }
        return app
    }

    private func skipIfTargetAppIsAlreadyRunning() throws {
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier)
        if !runningApplications.isEmpty {
            throw XCTSkip("Quit Pindrop before running UI tests so XCTest does not force-terminate your active app session.")
        }
    }

}
