//
//  PreviewMocks.swift
//  Pindrop
//

import SwiftUI
import SwiftData

// MARK: - SettingsStore Protocol

@MainActor
protocol SettingsStoreProtocol: ObservableObject {
    var selectedModel: String { get set }
    
    var toggleHotkey: String { get set }
    var toggleHotkeyCode: Int { get set }
    var toggleHotkeyModifiers: Int { get set }
    var pushToTalkHotkey: String { get set }
    var pushToTalkHotkeyCode: Int { get set }
    var pushToTalkHotkeyModifiers: Int { get set }
    var copyLastTranscriptHotkey: String { get set }
    var copyLastTranscriptHotkeyCode: Int { get set }
    var copyLastTranscriptHotkeyModifiers: Int { get set }
    
    var outputMode: String { get set }
    var addTrailingSpace: Bool { get set }
    
    var aiEnhancementEnabled: Bool { get set }
    var aiModel: String { get set }
    var aiEnhancementPrompt: String { get set }
    var apiEndpoint: String? { get }
    var apiKey: String? { get }
    
    var floatingIndicatorEnabled: Bool { get set }
    var showInDock: Bool { get set }
    
    var hasCompletedOnboarding: Bool { get set }
    var currentOnboardingStep: Int { get set }
    
    func saveAPIEndpoint(_ endpoint: String) throws
    func saveAPIKey(_ key: String) throws
    func deleteAPIEndpoint() throws
    func deleteAPIKey() throws
    func resetAllSettings()
}

extension SettingsStore: SettingsStoreProtocol {}

// MARK: - Preview Settings Store

@MainActor
final class PreviewSettingsStore: SettingsStoreProtocol {
    @Published var selectedModel = "openai_whisper-base"
    
    @Published var toggleHotkey = "⌥Space"
    @Published var toggleHotkeyCode = 49
    @Published var toggleHotkeyModifiers = 0x800
    @Published var pushToTalkHotkey = "⌘/"
    @Published var pushToTalkHotkeyCode = 44
    @Published var pushToTalkHotkeyModifiers = 0x100
    @Published var copyLastTranscriptHotkey = "⇧⌘C"
    @Published var copyLastTranscriptHotkeyCode = 8
    @Published var copyLastTranscriptHotkeyModifiers = 0x300
    
    @Published var outputMode = "clipboard"
    @Published var addTrailingSpace = true
    
    @Published var aiEnhancementEnabled = false
    @Published var aiModel = "openai/gpt-4o-mini"
    @Published var aiEnhancementPrompt = "You are a text enhancement assistant."
    @Published private(set) var apiEndpoint: String? = "https://api.openai.com/v1"
    @Published private(set) var apiKey: String? = nil
    
    @Published var floatingIndicatorEnabled = false
    @Published var showInDock = false
    
    @Published var hasCompletedOnboarding = true
    @Published var currentOnboardingStep = 0
    
    func saveAPIEndpoint(_ endpoint: String) throws { apiEndpoint = endpoint }
    func saveAPIKey(_ key: String) throws { apiKey = key }
    func deleteAPIEndpoint() throws { apiEndpoint = nil }
    func deleteAPIKey() throws { apiKey = nil }
    func resetAllSettings() {}
}

// MARK: - ModelManager Protocol

@MainActor
protocol ModelManagerProtocol: AnyObject, Observable {
    var availableModels: [ModelManager.WhisperModel] { get }
    var downloadProgress: Double { get }
    var isDownloading: Bool { get }
    var currentDownloadModel: String? { get }
    var downloadedModelNames: Set<String> { get }
    
    func refreshDownloadedModels() async
    func getDownloadedModels() async -> [ModelManager.WhisperModel]
    func isModelDownloaded(_ modelName: String) -> Bool
    func downloadModel(named modelName: String, onProgress: ((Double) -> Void)?) async throws
    func deleteModel(named modelName: String) async throws
}

extension ModelManager: ModelManagerProtocol {}

// MARK: - Preview Model Manager

@MainActor
@Observable
final class PreviewModelManager: ModelManagerProtocol {
    var availableModels: [ModelManager.WhisperModel] {
        [
            ModelManager.WhisperModel(
                name: "openai_whisper-tiny",
                displayName: "Whisper Tiny",
                sizeInMB: 75,
                description: "Fastest model",
                speedRating: 10.0,
                accuracyRating: 6.0,
                language: .multilingual
            ),
            ModelManager.WhisperModel(
                name: "openai_whisper-base",
                displayName: "Whisper Base",
                sizeInMB: 145,
                description: "Good balance",
                speedRating: 9.0,
                accuracyRating: 7.0,
                language: .multilingual
            ),
            ModelManager.WhisperModel(
                name: "openai_whisper-small",
                displayName: "Whisper Small",
                sizeInMB: 483,
                description: "Higher accuracy",
                speedRating: 7.5,
                accuracyRating: 8.0,
                language: .multilingual
            )
        ]
    }
    
    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var currentDownloadModel: String? = nil
    private(set) var downloadedModelNames: Set<String> = ["openai_whisper-base"]
    
    func refreshDownloadedModels() async {}
    
    func getDownloadedModels() async -> [ModelManager.WhisperModel] {
        availableModels.filter { downloadedModelNames.contains($0.name) }
    }
    
    func isModelDownloaded(_ modelName: String) -> Bool {
        downloadedModelNames.contains(modelName)
    }
    
    func downloadModel(named modelName: String, onProgress: ((Double) -> Void)?) async throws {
        downloadedModelNames.insert(modelName)
    }
    
    func deleteModel(named modelName: String) async throws {
        downloadedModelNames.remove(modelName)
    }
}

// MARK: - Preview SwiftData Container

enum PreviewContainer {
    @MainActor
    static func create(with records: [TranscriptionRecord] = []) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: TranscriptionRecord.self, WordReplacement.self, VocabularyWord.self,
            configurations: config
        )
        for record in records {
            container.mainContext.insert(record)
        }
        return container
    }
    
    @MainActor
    static var empty: ModelContainer { create() }
    
    @MainActor
    static var withSampleData: ModelContainer {
        create(with: [
            TranscriptionRecord(
                text: "This is a sample transcription.",
                timestamp: Date(),
                duration: 5.2,
                modelUsed: "tiny.en"
            ),
            TranscriptionRecord(
                text: "Another transcription from earlier.",
                timestamp: Date().addingTimeInterval(-3600),
                duration: 3.8,
                modelUsed: "base.en"
            )
        ])
    }
}
