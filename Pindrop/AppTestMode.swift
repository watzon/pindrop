//
//  AppTestMode.swift
//  Pindrop
//
//  Created on 2026-03-21.
//

import AppKit
import SwiftData
import SwiftUI

enum AppTestMode {
    static let unitTestModeKey = "PINDROP_TEST_MODE"
    static let uiTestModeKey = "PINDROP_UI_TEST_MODE"
    static let uiTestSurfaceKey = "PINDROP_UI_TEST_SURFACE"
    static let uiTestSettingsTabKey = "PINDROP_UI_TEST_SETTINGS_TAB"
    static let testUserDefaultsSuiteKey = "PINDROP_TEST_USER_DEFAULTS_SUITE"

    static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static var isRunningUITests: Bool {
        environment[uiTestModeKey] == "1"
    }

    static var isRunningUnitTests: Bool {
        !isRunningUITests && (
            environment[unitTestModeKey] == "1"
                || environment["XCTestConfigurationFilePath"] != nil
        )
    }

    static var isRunningAnyTests: Bool {
        isRunningUITests || isRunningUnitTests
    }
}

enum AppUITestSurface: String {
    case settings
}

enum AppUITestFixture {
    static var isEnabled: Bool {
        surface != nil
    }

    static var surface: AppUITestSurface? {
        guard AppTestMode.isRunningUITests else { return nil }
        let rawValue = AppTestMode.environment[AppTestMode.uiTestSurfaceKey] ?? AppUITestSurface.settings.rawValue
        return AppUITestSurface(rawValue: rawValue)
    }

    static var settingsInitialTab: SettingsTab {
        let rawValue = AppTestMode.environment[AppTestMode.uiTestSettingsTabKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return SettingsTab(rawValue: rawValue ?? "") ?? .general
    }

    @ViewBuilder
    static func rootView() -> some View {
        switch surface {
        case .settings:
            SettingsFixtureRootView(initialTab: settingsInitialTab)
        case nil:
            EmptyView()
        }
    }

    @MainActor
    static func configureApplication() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct SettingsFixtureRootView: View {
    @StateObject private var settings = SettingsStore()

    let initialTab: SettingsTab

    /// Deterministic in-memory store so panes using @Query (e.g. Privacy) render
    /// in the fixture without touching the real persistent store.
    private static let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: TranscriptionRecordSchemaV11.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create UI-test fixture model container: \(error)")
        }
    }()

    var body: some View {
        SettingsPaneContent(settings: settings, tab: initialTab)
            .frame(minWidth: 620, minHeight: 420)
            .environment(\.locale, settings.selectedAppLocale.locale)
            .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
            .modelContainer(Self.modelContainer)
    }
}
