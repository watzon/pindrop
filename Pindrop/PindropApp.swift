//
//  PindropApp.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import SwiftData
import AppKit
import SQLite3

@main
struct PindropApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    var body: some Scene {
        WindowGroup(id: "placeholder") {
            if AppUITestFixture.isEnabled {
                AppUITestFixture.rootView()
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: AppUITestFixture.isEnabled ? 1240 : 0, height: AppUITestFixture.isEnabled ? 920 : 0)
        .windowResizability(.contentSize)
    }
}

extension AppDelegate {
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static var isRunningTests: Bool {
        AppTestMode.isRunningUnitTests
    }

    static var isRunningUITests: Bool {
        AppTestMode.isRunningUITests
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var coordinator: AppCoordinator?
    private var settingsStore: SettingsStore?
    
    private var modelContainer: ModelContainer?
    private let storeRepairService = SwiftDataStoreRepairService()

    private var currentLocale: Locale {
        settingsStore?.selectedAppLanguage.locale ?? .autoupdatingCurrent
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isPreview else { return }
        Log.bootstrap()
        guard !Self.isRunningUITests else {
            AppUITestFixture.configureApplication()
            Log.app.debug("Detected UI test environment, launching fixture surface")
            return
        }
        guard !Self.isRunningTests else {
            Log.app.debug("Detected XCTest environment, skipping app startup flow")
            return
        }
        
        do {
            try storeRepairService.prepareStoreLocation()
            modelContainer = try makeModelContainer()
        } catch {
            let initialError = error
            Log.app.error("Failed to create ModelContainer: \(describe(error: initialError))")

            do {
                let repairOutcome = try storeRepairService.repairIfNeeded(storeURL: storeRepairService.storeURL())
                guard repairOutcome.repaired else {
                    showModelContainerErrorAlert(error: initialError)
                    NSApplication.shared.terminate(nil)
                    return
                }

                Log.app.info("Retrying ModelContainer creation after repairing the SwiftData store")
                modelContainer = try makeModelContainer()
            } catch {
                Log.app.error("Failed to repair ModelContainer store: \(describe(error: error))")
                showModelContainerErrorAlert(error: initialError)
                NSApplication.shared.terminate(nil)
                return
            }
        }
        
        guard let container = modelContainer else {
            NSApplication.shared.terminate(nil)
            return
        }
        
        let context = container.mainContext
        coordinator = AppCoordinator(modelContext: context, modelContainer: container)
        settingsStore = coordinator?.settingsStore
        PindropThemeController.shared.refresh()

        updateDockVisibility()
        setupMainMenu()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        Task { @MainActor in
            await coordinator?.start()
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(NSMenuItem(title: localized("About Pindrop", locale: currentLocale), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: localized("Settings…", locale: currentLocale), action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: localized("Quit Pindrop", locale: currentLocale), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        mainMenu.addItem(appMenuItem)
        
        // Edit menu (required for Command-V paste to work in TextFields)
        let editMenu = NSMenu(title: localized("Edit", locale: currentLocale))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(NSMenuItem(title: localized("Undo", locale: currentLocale), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: localized("Redo", locale: currentLocale), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: localized("Cut", locale: currentLocale), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: localized("Copy", locale: currentLocale), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: localized("Paste", locale: currentLocale), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: localized("Select All", locale: currentLocale), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        mainMenu.addItem(editMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc private func settingsDidChange() {
        updateDockVisibility()
        setupMainMenu()
    }
    
    private func updateDockVisibility() {
        guard !Self.isPreview else { return }
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
    }
    
    @objc func openSettings(_ sender: Any?) {
        Task { @MainActor in
            coordinator?.statusBarController.showSettings()
        }
    }
    
    private func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(url: storeRepairService.storeURL())
        return try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            configurations: configuration
        )
    }

    private func describe(error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)]"
    }
    
    private func showModelContainerErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = localized("Database Error", locale: currentLocale)
        let format = localized("Failed to initialize the database: %@\n\nThe app will now quit. Please try restarting or contact support if the problem persists.", locale: currentLocale)
        alert.informativeText = String(format: format, error.localizedDescription)
        alert.alertStyle = .critical
        alert.addButton(withTitle: localized("Quit", locale: currentLocale))
        alert.runModal()
    }
}

@MainActor
final class SwiftDataStoreRepairService {
    private enum StoreSchemaVersion: String {
        case v1 = "1.0.0"
        case v2 = "1.0.1"
        case v3 = "1.0.2"
        case v4 = "1.0.3"
        case v5 = "1.0.4"
    }

    struct RepairOutcome {
        let repaired: Bool
        let backupDirectoryURL: URL?
    }

    private struct SchemaObjectDefinition {
        let name: String
        let sql: String
    }

    private struct ReferenceArtifacts {
        let metadataBlob: Data
        let modelCacheBlob: Data
        let schemaDefinitions: [SchemaObjectDefinition]
    }

    private let fileManager: FileManager
    private let applicationSupportRootURL: URL

    init(fileManager: FileManager = .default, applicationSupportRootURL: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupportRootURL = applicationSupportRootURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    func prepareStoreLocation() throws {
        let currentStoreURL = storeURL()
        let legacyStoreURL = legacyStoreURL()

        try fileManager.createDirectory(at: currentStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let currentStoreExists = fileManager.fileExists(atPath: currentStoreURL.path)
        let legacyStoreExists = fileManager.fileExists(atPath: legacyStoreURL.path)

        let currentStoreVersion = currentStoreExists ? try inferredStoreVersion(at: currentStoreURL) : nil
        let legacyStoreVersion = legacyStoreExists ? try inferredStoreVersion(at: legacyStoreURL) : nil

        if currentStoreExists {
            guard currentStoreVersion == nil, legacyStoreVersion != nil else {
                return
            }

            let backupDirectoryURL = try backupStoreArtifacts(for: currentStoreURL)
            try removeStoreArtifacts(at: currentStoreURL)
            try copyStoreArtifacts(from: legacyStoreURL, to: currentStoreURL)
            Log.app.warning(
                "Replaced unrecognized SwiftData store at \(currentStoreURL.path) using legacy store \(legacyStoreURL.path); backup: \(backupDirectoryURL.path)"
            )
            return
        }

        guard legacyStoreExists else {
            return
        }

        guard legacyStoreVersion != nil else {
            Log.app.warning(
                "Ignoring legacy SwiftData store at \(legacyStoreURL.path) because it does not match the Pindrop schema"
            )
            return
        }

        try copyStoreArtifacts(from: legacyStoreURL, to: currentStoreURL)
        Log.app.info("Migrated SwiftData store from legacy location \(legacyStoreURL.path) to \(currentStoreURL.path)")
    }

    func storeURL() -> URL {
        Self.defaultStoreURL(applicationSupportRootURL: applicationSupportRootURL)
    }

    func repairIfNeeded(storeURL: URL? = nil) throws -> RepairOutcome {
        let targetStoreURL = storeURL ?? self.storeURL()

        guard fileManager.fileExists(atPath: targetStoreURL.path) else {
            return RepairOutcome(repaired: false, backupDirectoryURL: nil)
        }

        guard let inferredVersion = try inferredStoreVersion(at: targetStoreURL) else {
            Log.app.warning("SwiftData store repair skipped because the transcription table shape could not be inferred")
            return RepairOutcome(repaired: false, backupDirectoryURL: nil)
        }

        let metadataVersion = try readMetadataVersionIdentifier(at: targetStoreURL)
        let referenceArtifacts = try makeReferenceArtifacts(for: inferredVersion)
        let missingSchemaDefinitions = try withDatabase(at: targetStoreURL) { database in
            let existingObjectNames = try fetchSchemaObjectNames(on: database)
            return referenceArtifacts.schemaDefinitions.filter { !existingObjectNames.contains($0.name) }
        }

        guard metadataVersion != inferredVersion.rawValue || !missingSchemaDefinitions.isEmpty else {
            return RepairOutcome(repaired: false, backupDirectoryURL: nil)
        }

        let backupDirectoryURL = try backupStoreArtifacts(for: targetStoreURL)

        try withDatabase(at: targetStoreURL) { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                for schemaDefinition in missingSchemaDefinitions {
                    try execute(schemaDefinition.sql, on: database)
                }
                try updateMetadata(referenceArtifacts.metadataBlob, on: database)
                try replaceModelCache(referenceArtifacts.modelCacheBlob, on: database)
                try execute("COMMIT TRANSACTION", on: database)
            } catch {
                try? execute("ROLLBACK TRANSACTION", on: database)
                throw error
            }
        }

        if missingSchemaDefinitions.isEmpty {
            Log.app.info(
                "Repaired SwiftData store metadata from \(metadataVersion ?? "unknown") to \(inferredVersion.rawValue); backup: \(backupDirectoryURL.path)"
            )
        } else {
            let recreatedNames = missingSchemaDefinitions.map(\.name).joined(separator: ", ")
            Log.app.info(
                "Repaired SwiftData store by recreating missing schema objects (\(recreatedNames)) and refreshing metadata to \(inferredVersion.rawValue); backup: \(backupDirectoryURL.path)"
            )
        }
        return RepairOutcome(repaired: true, backupDirectoryURL: backupDirectoryURL)
    }

    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return defaultStoreURL(applicationSupportRootURL: supportURL)
    }

    static func legacyStoreURL(fileManager: FileManager = .default) -> URL {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return legacyStoreURL(applicationSupportRootURL: supportURL)
    }

    private func inferredStoreVersion(at storeURL: URL) throws -> StoreSchemaVersion? {
        try withDatabase(at: storeURL) { database in
            let columns = try fetchColumnNames(table: "ZTRANSCRIPTIONRECORD", on: database)

            guard !columns.isEmpty else {
                return nil
            }

            if try tableExists(named: "ZMEDIAFOLDER", on: database) || columns.contains("ZFOLDER") {
                return .v5
            }

            if columns.contains("ZSOURCEKINDRAWVALUE") {
                return .v4
            }

            if columns.contains("ZDIARIZATIONSEGMENTSJSON") {
                return .v3
            }

            if columns.contains("ZORIGINALTEXT") || columns.contains("ZENHANCEDWITH") {
                return .v2
            }

            return .v1
        }
    }

    private func readMetadataVersionIdentifier(at storeURL: URL) throws -> String? {
        try withDatabase(at: storeURL) { database in
            guard let metadataBlob = try fetchBlob(
                sql: "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
                on: database
            ) else {
                return nil
            }

            let plist = try PropertyListSerialization.propertyList(from: metadataBlob, format: nil)
            let dictionary = plist as? [String: Any]
            let versionIdentifiers = dictionary?["NSStoreModelVersionIdentifiers"] as? [String]
            return versionIdentifiers?.first
        }
    }

    private func backupStoreArtifacts(for storeURL: URL) throws -> URL {
        let backupsRootURL = applicationSupportRootURL
            .appendingPathComponent("Pindrop", isDirectory: true)
            .appendingPathComponent("DatabaseBackups", isDirectory: true)
        let backupDirectoryURL = backupsRootURL.appendingPathComponent(Self.repairTimestampString(), isDirectory: true)

        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        for artifactURL in storeArtifactURLs(for: storeURL) where fileManager.fileExists(atPath: artifactURL.path) {
            let backupURL = backupDirectoryURL.appendingPathComponent(artifactURL.lastPathComponent)
            try fileManager.copyItem(at: artifactURL, to: backupURL)
        }

        return backupDirectoryURL
    }

    private func makeReferenceArtifacts(for version: StoreSchemaVersion) throws -> ReferenceArtifacts {
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("reference.store")
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: directoryURL)
        }

        let configuration = ModelConfiguration(url: storeURL)
        let container: ModelContainer

        switch version {
        case .v1:
            container = try ModelContainer(
                for: TranscriptionRecordSchemaV1.TranscriptionRecordV1.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
        case .v2:
            container = try ModelContainer(
                for: TranscriptionRecordSchemaV2.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
        case .v3:
            container = try ModelContainer(
                for: TranscriptionRecordSchemaV3.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
        case .v4:
            container = try ModelContainer(
                for: TranscriptionRecordSchemaV4.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
        case .v5:
            container = try ModelContainer(
                for: TranscriptionRecord.self,
                MediaFolder.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
        }

        try container.mainContext.save()

        return try withDatabase(at: storeURL) { database in
            guard let metadataBlob = try fetchBlob(
                sql: "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
                on: database
            ) else {
                throw StoreRepairError.missingMetadata
            }

            guard let modelCacheBlob = try fetchBlob(
                sql: "SELECT Z_CONTENT FROM Z_MODELCACHE LIMIT 1",
                on: database
            ) else {
                throw StoreRepairError.missingModelCache
            }

            let schemaDefinitions = try fetchSchemaDefinitions(on: database)
            return ReferenceArtifacts(
                metadataBlob: metadataBlob,
                modelCacheBlob: modelCacheBlob,
                schemaDefinitions: schemaDefinitions
            )
        }
    }

    private func storeArtifactURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
    }

    private func copyStoreArtifacts(from sourceStoreURL: URL, to destinationStoreURL: URL) throws {
        try fileManager.createDirectory(at: destinationStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        for sourceArtifactURL in storeArtifactURLs(for: sourceStoreURL) where fileManager.fileExists(atPath: sourceArtifactURL.path) {
            let suffix = String(sourceArtifactURL.path.dropFirst(sourceStoreURL.path.count))
            let destinationArtifactURL = URL(fileURLWithPath: destinationStoreURL.path + suffix)
            try fileManager.copyItem(at: sourceArtifactURL, to: destinationArtifactURL)
        }
    }

    private func removeStoreArtifacts(at storeURL: URL) throws {
        for artifactURL in storeArtifactURLs(for: storeURL) where fileManager.fileExists(atPath: artifactURL.path) {
            try fileManager.removeItem(at: artifactURL)
        }
    }

    private func legacyStoreURL() -> URL {
        Self.legacyStoreURL(applicationSupportRootURL: applicationSupportRootURL)
    }

    private static func defaultStoreURL(applicationSupportRootURL: URL) -> URL {
        applicationSupportRootURL
            .appendingPathComponent("Pindrop", isDirectory: true)
            .appendingPathComponent("default.store")
    }

    private static func legacyStoreURL(applicationSupportRootURL: URL) -> URL {
        applicationSupportRootURL.appendingPathComponent("default.store")
    }

    private func fetchColumnNames(table: String, on database: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePointer = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: namePointer))
            }
        }

        return columns
    }

    private func tableExists(named table: String, on database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(
            statement,
            1,
            (table as NSString).utf8String,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        ) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func fetchSchemaDefinitions(on database: OpaquePointer) throws -> [SchemaObjectDefinition] {
        var statement: OpaquePointer?
        let sql = """
        SELECT name, sql
        FROM sqlite_master
        WHERE type IN ('table', 'index')
          AND name NOT LIKE 'sqlite_%'
          AND sql IS NOT NULL
        ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name
        """

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        var definitions: [SchemaObjectDefinition] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 0),
                  let sqlPointer = sqlite3_column_text(statement, 1) else {
                continue
            }

            definitions.append(
                SchemaObjectDefinition(
                    name: String(cString: namePointer),
                    sql: String(cString: sqlPointer)
                )
            )
        }

        return definitions
    }

    private func fetchSchemaObjectNames(on database: OpaquePointer) throws -> Set<String> {
        let definitions = try fetchSchemaDefinitions(on: database)
        return Set(definitions.map(\.name))
    }

    private func fetchBlob(sql: String, on database: OpaquePointer) throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            if stepResult == SQLITE_DONE {
                return nil
            }

            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        guard let bytes = sqlite3_column_blob(statement, 0) else {
            return Data()
        }

        let count = Int(sqlite3_column_bytes(statement, 0))
        return Data(bytes: bytes, count: count)
    }

    private func updateMetadata(_ metadataBlob: Data, on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE Z_METADATA SET Z_PLIST = ? WHERE Z_VERSION = 1"

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        try bind(data: metadataBlob, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }
    }

    private func replaceModelCache(_ modelCacheBlob: Data, on database: OpaquePointer) throws {
        try execute("DELETE FROM Z_MODELCACHE", on: database)

        var statement: OpaquePointer?
        let sql = "INSERT INTO Z_MODELCACHE (Z_CONTENT) VALUES (?)"

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }

        defer { sqlite3_finalize(statement) }

        try bind(data: modelCacheBlob, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }
    }

    private func bind(data: Data, at index: Int32, to statement: OpaquePointer?) throws {
        let result = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(
                statement,
                index,
                rawBuffer.baseAddress,
                Int32(data.count),
                Self.sqliteTransientDestructor
            )
        }

        guard result == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: "Failed to bind SQLite blob parameter")
        }
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreRepairError.sqlite(message: lastSQLiteErrorMessage(on: database))
        }
    }

    private func withDatabase<T>(at url: URL, _ work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = lastSQLiteErrorMessage(on: database)
            sqlite3_close(database)
            throw StoreRepairError.sqlite(message: message)
        }

        defer { sqlite3_close(database) }

        guard let database else {
            throw StoreRepairError.sqlite(message: "Failed to open database")
        }

        return try work(database)
    }

    private func lastSQLiteErrorMessage(on database: OpaquePointer?) -> String {
        guard let database,
              let errorPointer = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: errorPointer)
    }

    private static func repairTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

private enum StoreRepairError: LocalizedError {
    case missingMetadata
    case missingModelCache
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return "The store repair process could not find SwiftData metadata in the database."
        case .missingModelCache:
            return "The store repair process could not find the SwiftData model cache in the database."
        case let .sqlite(message):
            return message
        }
    }
}
