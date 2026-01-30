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
    @State private var selectedModel = "gpt-4o-mini"
    @State private var customModel = ""
    @State private var useCustomModel = false
    @State private var enhancementPrompt = ""
    @State private var noteEnhancementPrompt = ""
    @State private var selectedPromptType: PromptType = .transcription
    @State private var showingAPIKey = false
    @State private var showingSaveSuccess = false
    @State private var showingPromptSaveSuccess = false
    @State private var errorMessage: String?
    
    enum PromptType: String, CaseIterable, Identifiable {
        case transcription = "Transcription"
        case notes = "Notes"
        
        var id: String { rawValue }
        
        var icon: Icon {
            switch self {
            case .transcription: return .mic
            case .notes: return .stickyNote
            }
        }
        
        var description: String {
            switch self {
            case .transcription:
                return "Sent to the AI model when processing dictation for direct text insertion."
            case .notes:
                return "Used when capturing notes via hotkey. Can add markdown formatting for longer content."
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            enableToggleCard
            providerCard
            promptsCard
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
    
    // MARK: - Prompts Card
    
    private var promptsCard: some View {
        SettingsCard(title: "Enhancement Prompts", icon: "text.bubble") {
            VStack(spacing: 16) {
                promptTypeTabs
                promptContent
            }
            .opacity(settings.aiEnhancementEnabled ? 1 : 0.5)
            .disabled(!settings.aiEnhancementEnabled)
        }
    }
    
    private var promptTypeTabs: some View {
        HStack(spacing: 0) {
            ForEach(PromptType.allCases) { type in
                promptTypeTab(type)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func promptTypeTab(_ type: PromptType) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedPromptType = type
            }
        } label: {
            VStack(spacing: 3) {
                IconView(icon: type.icon, size: 14)
                Text(type.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                selectedPromptType == type
                    ? AppColors.accent.opacity(0.2)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(selectedPromptType == type ? AppColors.accent : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var promptContent: some View {
        let currentPrompt = selectedPromptType == .transcription ? $enhancementPrompt : $noteEnhancementPrompt
        let charCount = selectedPromptType == .transcription ? enhancementPrompt.count : noteEnhancementPrompt.count
        
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: currentPrompt)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 220)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            
            HStack {
                Button("Reset to Default") {
                    resetCurrentPrompt()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Text("\(charCount) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(selectedPromptType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Save Prompt") {
                    saveCurrentPrompt()
                }
                .buttonStyle(.borderedProminent)
                .disabled(charCount == 0)
                
                Spacer()
                
                if showingPromptSaveSuccess {
                    HStack(spacing: 6) {
                        IconView(icon: .check, size: 12)
                            .foregroundStyle(.green)
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }
    
    private func resetCurrentPrompt() {
        switch selectedPromptType {
        case .transcription:
            enhancementPrompt = AIEnhancementService.defaultSystemPrompt
        case .notes:
            noteEnhancementPrompt = SettingsStore.Defaults.noteEnhancementPrompt
        }
    }
    
    private func saveCurrentPrompt() {
        switch selectedPromptType {
        case .transcription:
            savePrompt()
        case .notes:
            saveNotePrompt()
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
                IconView(icon: provider.icon, size: 14)
                Text(provider.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                selectedProvider == provider
                    ? AppColors.accent.opacity(0.2)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(selectedProvider == provider ? AppColors.accent : .secondary)
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
                
                if selectedProvider == .openrouter {
                    modelPicker
                }
                
                if selectedProvider == .custom {
                    customModelField
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
            IconView(icon: .construction, size: 28)
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
                    IconView(icon: showingAPIKey ? .eyeOff : .eye, size: 16)
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
            HStack {
                Text("API Endpoint")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("Must be OpenAI-compatible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            TextField("https://your-api.com/v1", text: $customEndpoint)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var customModelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Model")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("e.g., gpt-4o", text: $customModel)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Model")
                .font(.subheadline)
                .fontWeight(.medium)
            
            if useCustomModel {
                HStack(spacing: 8) {
                    TextField("e.g., openai/gpt-4o", text: $customModel)
                        .textFieldStyle(.plain)
                    
                    Button("Use Recommended") {
                        useCustomModel = false
                        customModel = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("", selection: $selectedModel) {
                            ForEach(recommendedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        Spacer()
                    }
                    
                    Button("Enter custom model") {
                        useCustomModel = true
                        customModel = selectedModel
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private var recommendedModels: [String] {
        switch selectedProvider {
        case .openrouter:
            return [
                "anthropic/claude-sonnet-4.5",
                "openai/gpt-4o-mini",
                "google/gemini-2.5-flash",
                "deepseek/deepseek-v3.2",
                "anthropic/claude-haiku-4.5",
                "openai/gpt-4o"
            ]
        case .custom:
            return [
                "gpt-4o-mini",
                "gpt-4o",
                "claude-sonnet-4.5",
                "gemini-2.5-flash",
                "deepseek-v3.2"
            ]
        default:
            return []
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
            IconView(icon: .check, size: 14)
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
            IconView(icon: .warning, size: 14)
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
            IconView(icon: .shield, size: 12)
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
        if selectedProvider == .custom {
            if customEndpoint.isEmpty { return false }
            if customModel.isEmpty { return false }
        }
        if selectedProvider == .openrouter && useCustomModel && customModel.isEmpty { return false }
        return true
    }
    
    private func loadCredentials() {
        let loadedModel = settings.aiModel
        selectedModel = loadedModel
        
        if let endpoint = settings.apiEndpoint {
            customEndpoint = endpoint
            if endpoint.contains("openai.com") {
                selectedProvider = .openai
                useCustomModel = !recommendedModels.contains(loadedModel)
                if useCustomModel { customModel = loadedModel }
            } else if endpoint.contains("anthropic.com") {
                selectedProvider = .anthropic
            } else if endpoint.contains("googleapis.com") {
                selectedProvider = .google
            } else if endpoint.contains("openrouter.ai") {
                selectedProvider = .openrouter
                useCustomModel = !recommendedModels.contains(loadedModel)
                if useCustomModel { customModel = loadedModel }
            } else if !endpoint.isEmpty {
                selectedProvider = .custom
                customModel = loadedModel
            }
        }
        if let key = settings.apiKey {
            apiKey = key
        }
        
        enhancementPrompt = settings.aiEnhancementPrompt
        noteEnhancementPrompt = settings.noteEnhancementPrompt
    }
    
    private func savePrompt() {
        settings.aiEnhancementPrompt = enhancementPrompt
        
        showingPromptSaveSuccess = true
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            showingPromptSaveSuccess = false
        }
    }
    
    private func saveNotePrompt() {
        settings.noteEnhancementPrompt = noteEnhancementPrompt
        
        showingPromptSaveSuccess = true
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            showingPromptSaveSuccess = false
        }
    }
    
    private func saveCredentials() {
        errorMessage = nil
        showingSaveSuccess = false
        
        do {
            let endpoint = selectedProvider == .custom ? customEndpoint : selectedProvider.defaultEndpoint
            try settings.saveAPIEndpoint(endpoint)
            try settings.saveAPIKey(apiKey)
            
            if selectedProvider == .custom {
                settings.aiModel = customModel
            } else if selectedProvider == .openrouter {
                settings.aiModel = useCustomModel ? customModel : selectedModel
            } else {
                settings.aiModel = selectedModel
            }
            
            settings.aiEnhancementPrompt = enhancementPrompt
            
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
