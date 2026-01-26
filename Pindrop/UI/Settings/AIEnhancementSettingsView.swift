//
//  AIEnhancementSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct AIEnhancementSettingsView: View {
    @ObservedObject var settings: SettingsStore
    
    @State private var selectedProvider: AIProvider = .openai
    @State private var apiKey = ""
    @State private var customEndpoint = ""
    @State private var showingAPIKey = false
    @State private var showingSaveSuccess = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            enableToggleCard
            providerCard
        }
        .task {
            loadCredentials()
        }
    }
    
    // MARK: - Enable Toggle Card
    
    private var enableToggleCard: some View {
        SettingsCard(title: "Status", icon: "sparkles") {
            Toggle(isOn: $settings.aiEnhancementEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable AI Enhancement")
                        .font(.body)
                    Text("Improve transcription quality using AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
    
    // MARK: - Provider Card
    
    private var providerCard: some View {
        SettingsCard(title: "Provider", icon: "server.rack") {
            VStack(spacing: 16) {
                providerTabs
                    .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
                
                providerConfigContent
                    .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
            }
            .disabled(!settings.aiEnhancementEnabled)
        }
    }
    
    private var providerTabs: some View {
        HStack(spacing: 0) {
            ForEach(AIProvider.allCases) { provider in
                providerTab(provider)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func providerTab(_ provider: AIProvider) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedProvider = provider
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: provider.icon)
                    .font(.system(size: 14))
                Text(provider.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                selectedProvider == provider
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(selectedProvider == provider ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var providerConfigContent: some View {
        if !selectedProvider.isImplemented {
            comingSoonView
        } else {
            VStack(spacing: 16) {
                apiKeyField
                
                if selectedProvider == .custom {
                    customEndpointField
                }
                
                saveButton
                
                if showingSaveSuccess {
                    successMessage
                }
                
                if let errorMessage {
                    errorMessageView(errorMessage)
                }
                
                keychainNote
            }
        }
    }
    
    private var comingSoonView: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            
            Text("\(selectedProvider.rawValue) Coming Soon")
                .font(.headline)
            
            Text("This provider will be available in a future update.\nTry OpenAI or use a Custom endpoint.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
    
    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 8) {
                Group {
                    if showingAPIKey {
                        TextField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
                    } else {
                        SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                
                Button {
                    showingAPIKey.toggle()
                } label: {
                    Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var customEndpointField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Endpoint")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("https://your-api.com/v1", text: $customEndpoint)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var saveButton: some View {
        HStack {
            Spacer()
            
            Button("Save Credentials") {
                saveCredentials()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }
    
    private var successMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Credentials saved successfully")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func errorMessageView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var keychainNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Credentials are stored securely in Keychain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Logic
    
    private var canSave: Bool {
        guard selectedProvider.isImplemented else { return false }
        if apiKey.isEmpty { return false }
        if selectedProvider == .custom && customEndpoint.isEmpty { return false }
        return true
    }
    
    private func loadCredentials() {
        if let endpoint = settings.apiEndpoint {
            customEndpoint = endpoint
            if endpoint.contains("openai.com") {
                selectedProvider = .openai
            } else if endpoint.contains("anthropic.com") {
                selectedProvider = .anthropic
            } else if endpoint.contains("googleapis.com") {
                selectedProvider = .google
            } else if endpoint.contains("openrouter.ai") {
                selectedProvider = .openrouter
            } else if !endpoint.isEmpty {
                selectedProvider = .custom
            }
        }
        if let key = settings.apiKey {
            apiKey = key
        }
    }
    
    private func saveCredentials() {
        errorMessage = nil
        showingSaveSuccess = false
        
        do {
            let endpoint = selectedProvider == .custom ? customEndpoint : selectedProvider.defaultEndpoint
            try settings.saveAPIEndpoint(endpoint)
            try settings.saveAPIKey(apiKey)
            showingSaveSuccess = true
            
            Task {
                try? await Task.sleep(for: .seconds(3))
                showingSaveSuccess = false
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    AIEnhancementSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 500)
}
