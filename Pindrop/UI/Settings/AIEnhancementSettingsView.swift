//
//  AIEnhancementSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct AIEnhancementSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var apiEndpoint: String = ""
    @State private var apiKey: String = ""
    @State private var showingSaveSuccess = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Enhancement", isOn: $settings.aiEnhancementEnabled)
                
                Text("Improve transcription quality using AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Status")
                    .font(.headline)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Endpoint:")
                        .font(.subheadline)
                    
                    TextField("https://api.openai.com/v1", text: $apiEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.aiEnhancementEnabled)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key:")
                        .font(.subheadline)
                    
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.aiEnhancementEnabled)
                }
                
                HStack {
                    Button("Save Credentials") {
                        saveCredentials()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.aiEnhancementEnabled || apiEndpoint.isEmpty || apiKey.isEmpty)
                    
                    if showingSaveSuccess {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Text("Credentials are stored securely in Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Configuration")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .task {
            loadCredentials()
        }
    }
    
    private func loadCredentials() {
        if let endpoint = settings.apiEndpoint {
            apiEndpoint = endpoint
        }
        if let key = settings.apiKey {
            apiKey = key
        }
    }
    
    private func saveCredentials() {
        errorMessage = nil
        showingSaveSuccess = false
        
        do {
            try settings.saveAPIEndpoint(apiEndpoint)
            try settings.saveAPIKey(apiKey)
            showingSaveSuccess = true
            
            Task {
                try? await Task.sleep(for: .seconds(2))
                showingSaveSuccess = false
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    AIEnhancementSettingsView(settings: SettingsStore())
}
