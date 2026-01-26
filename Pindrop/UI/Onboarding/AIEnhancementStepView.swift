//
//  AIEnhancementStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case google = "Google"
    case anthropic = "Anthropic"
    case openrouter = "OpenRouter"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .google: return "g.circle"
        case .anthropic: return "a.circle"
        case .openrouter: return "arrow.triangle.branch"
        case .custom: return "server.rack"
        }
    }
    
    var defaultEndpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }
    
    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .google: return "AIza..."
        case .anthropic: return "sk-ant-..."
        case .openrouter: return "sk-or-..."
        case .custom: return "Enter API key"
        }
    }
    
    var isImplemented: Bool {
        switch self {
        case .openai, .custom: return true
        default: return false
        }
    }
}

struct AIEnhancementStepView: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    @State private var selectedProvider: AIProvider = .openai
    @State private var apiKey = ""
    @State private var customEndpoint = ""
    @State private var showingAPIKey = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            providerTabs
            
            providerConfigSection
                .frame(maxHeight: .infinity)
            
            actionButtons
        }
        .padding(.horizontal, 40)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
    
    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            
            Text("AI Enhancement")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Optionally clean up transcriptions with AI")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var providerTabs: some View {
        HStack(spacing: 0) {
            ForEach(AIProvider.allCases) { provider in
                providerTab(provider)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
    
    private func providerTab(_ provider: AIProvider) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedProvider = provider
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: provider.icon)
                    .font(.system(size: 18))
                Text(provider.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selectedProvider == provider
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .foregroundStyle(selectedProvider == provider ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var providerConfigSection: some View {
        VStack(spacing: 16) {
            if !selectedProvider.isImplemented {
                comingSoonView
            } else {
                apiKeyField
                
                if selectedProvider == .custom {
                    customEndpointField
                }
                
                Spacer()
                
                featureList
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    
    private var comingSoonView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("\(selectedProvider.rawValue) Support Coming Soon")
                .font(.headline)
            
            Text("This provider will be available in a future update.\nFor now, try OpenAI or use a Custom endpoint.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
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
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
    }
    
    private var customEndpointField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Endpoint")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("https://your-api.com/v1", text: $customEndpoint)
                .textFieldStyle(.plain)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
    }
    
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Enhancement will:")
                .font(.subheadline)
                .fontWeight(.medium)
            
            featureItem("Fix punctuation and capitalization")
            featureItem("Correct grammar mistakes")
            featureItem("Clean up filler words")
            featureItem("Format text appropriately")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(.accentColor.opacity(0.1)), in: .rect(cornerRadius: 12))
    }
    
    private func featureItem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Skip for Now", action: onSkip)
                .buttonStyle(.glass)
            
            Button(action: saveAndContinue) {
                Text("Save & Continue")
                    .font(.headline)
                    .frame(maxWidth: 180)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canContinue)
        }
    }
    
    private var canContinue: Bool {
        guard selectedProvider.isImplemented else { return false }
        if apiKey.isEmpty { return false }
        if selectedProvider == .custom && customEndpoint.isEmpty { return false }
        return true
    }
    
    private func saveAndContinue() {
        settings.aiEnhancementEnabled = true
        
        let endpoint = selectedProvider == .custom ? customEndpoint : selectedProvider.defaultEndpoint
        try? settings.saveAPIEndpoint(endpoint)
        try? settings.saveAPIKey(apiKey)
        
        onContinue()
    }
}
