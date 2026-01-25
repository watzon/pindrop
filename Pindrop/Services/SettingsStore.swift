//
//  SettingsStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftUI
import Security
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    
    // MARK: - Errors
    
    enum SettingsError: Error, LocalizedError {
        case keychainError(String)
        
        var errorDescription: String? {
            switch self {
            case .keychainError(let message):
                return "Keychain error: \(message)"
            }
        }
    }
    
    // MARK: - AppStorage Properties
    
    @AppStorage("selectedModel") var selectedModel: String = "openai_whisper-base"
    @AppStorage("toggleHotkey") var toggleHotkey: String = "⌘⇧R"
    @AppStorage("toggleHotkeyCode") var toggleHotkeyCode: Int = 15
    @AppStorage("toggleHotkeyModifiers") var toggleHotkeyModifiers: Int = 0x100100
    @AppStorage("pushToTalkHotkey") var pushToTalkHotkey: String = "⌘⇧T"
    @AppStorage("pushToTalkHotkeyCode") var pushToTalkHotkeyCode: Int = 17
    @AppStorage("pushToTalkHotkeyModifiers") var pushToTalkHotkeyModifiers: Int = 0x100100
    @AppStorage("outputMode") var outputMode: String = "clipboard"
    @AppStorage("aiEnhancementEnabled") var aiEnhancementEnabled: Bool = false
    @AppStorage("floatingIndicatorEnabled") var floatingIndicatorEnabled: Bool = false
    
    // MARK: - Keychain Properties
    
    private let keychainService = "com.pindrop.settings"
    private let apiEndpointAccount = "api-endpoint"
    private let apiKeyAccount = "api-key"
    
    // MARK: - Cached Keychain Values
    
    private(set) var apiEndpoint: String?
    private(set) var apiKey: String?
    
    // MARK: - Initialization
    
    init() {
        // Load keychain values on initialization
        apiEndpoint = try? loadFromKeychain(account: apiEndpointAccount)
        apiKey = try? loadFromKeychain(account: apiKeyAccount)
    }
    
    // MARK: - Keychain Methods
    
    func saveAPIEndpoint(_ endpoint: String) throws {
        try saveToKeychain(value: endpoint, account: apiEndpointAccount)
        apiEndpoint = endpoint
    }
    
    func saveAPIKey(_ key: String) throws {
        try saveToKeychain(value: key, account: apiKeyAccount)
        apiKey = key
    }
    
    func deleteAPIEndpoint() throws {
        try deleteFromKeychain(account: apiEndpointAccount)
        apiEndpoint = nil
    }
    
    func deleteAPIKey() throws {
        try deleteFromKeychain(account: apiKeyAccount)
        apiKey = nil
    }
    
    // MARK: - Private Keychain Helpers
    
    private func saveToKeychain(value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SettingsError.keychainError("Failed to encode value")
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SettingsError.keychainError("Failed to save to keychain: \(status)")
        }
    }
    
    private func loadFromKeychain(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw SettingsError.keychainError("Failed to load from keychain: \(status)")
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SettingsError.keychainError("Failed to decode value")
        }
        
        return value
    }
    
    private func deleteFromKeychain(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SettingsError.keychainError("Failed to delete from keychain: \(status)")
        }
    }
}
