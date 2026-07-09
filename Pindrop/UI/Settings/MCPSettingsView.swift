//
//  MCPSettingsView.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import AppKit
import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale

    @State private var selectedClient: MCPClient = .claudeCode
    @State private var opencodeIsGlobal = true
    @State private var portText = ""
    @State private var copiedSnippet = false
    @State private var copiedToken = false
    @State private var errorMessage: String?

    private var token: String {
        settings.loadMCPToken() ?? localized("Not generated yet — enable the server", locale: locale)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    localized("Enable MCP Server", locale: locale),
                    isOn: $settings.mcpServerEnabled
                )
                .accessibilityIdentifier("settings.toggle.mcpServerEnabled")

                if settings.mcpServerEnabled {
                    LabeledContent(localized("Port", locale: locale)) {
                        TextField("46337", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .frame(width: 88)
                            .fixedSize(horizontal: true, vertical: true)
                            .onSubmit { applyPort() }
                            .onChange(of: portText) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(5))
                                if digits != newValue {
                                    portText = digits
                                }
                                applyPortIfValid()
                            }
                            .accessibilityIdentifier("settings.field.mcpPort")
                    }

                    LabeledContent(localized("Bearer Token", locale: locale)) {
                        HStack {
                            Button {
                                copyToken()
                            } label: {
                                Label(
                                    copiedToken ? localized("Copied!", locale: locale) : token,
                                    systemImage: copiedToken ? "checkmark" : "doc.on.doc"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            }
                            .accessibilityIdentifier("settings.button.copyMCPToken")

                            Button(localized("Regenerate", locale: locale)) {
                                regenerateToken()
                            }
                        }
                    }
                }
            } header: {
                Text(localized("MCP Server", locale: locale))
            } footer: {
                Text(
                    settings.mcpServerEnabled
                        ? localized("Port changes take effect the next time the server starts.", locale: locale)
                        : localized("Run a local HTTP server so AI agents can submit transcription jobs, search history, and manage speakers.", locale: locale)
                )
            }

            if settings.mcpServerEnabled {
                Section {
                    Picker(localized("Client", locale: locale), selection: $selectedClient) {
                        ForEach(MCPClient.allCases) { client in
                            Text(client.displayName)
                                .tag(client)
                        }
                    }
                    .accessibilityIdentifier("settings.picker.mcpClient")
                    .onChange(of: selectedClient) { _, _ in copiedSnippet = false }

                    if selectedClient == .opencode {
                        Picker(localized("Configuration Scope", locale: locale), selection: $opencodeIsGlobal) {
                            Text(localized("Global", locale: locale)).tag(true)
                            Text(localized("Project", locale: locale)).tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: opencodeIsGlobal) { _, _ in copiedSnippet = false }
                    }

                    Text(selectedClient.instructions(isGlobal: opencodeIsGlobal, locale: locale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledContent(localized("Configuration File", locale: locale)) {
                        Text(selectedClient.configFilePath(isGlobal: opencodeIsGlobal))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(localized("Configuration Snippet", locale: locale))
                            Spacer()
                            Button(
                                copiedSnippet
                                    ? localized("Copied!", locale: locale)
                                    : localized("Copy", locale: locale)
                            ) {
                                copySnippet()
                            }
                            .accessibilityIdentifier("settings.button.copyMCPSnippet")
                        }

                        ScrollView([.horizontal, .vertical]) {
                            Text(configSnippet)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 150, maxHeight: 240)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                    }
                } header: {
                    Text(localized("Agent Setup", locale: locale))
                } footer: {
                    Text(localized("Copy the configuration snippet into your preferred AI agent host.", locale: locale))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = "\(settings.mcpServerPort)"
        }
        .alert(
            localized("MCP Configuration Error", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK", locale: locale), role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    private var configSnippet: String {
        selectedClient.configSnippet(
            port: settings.mcpServerPort,
            token: token,
            isGlobal: opencodeIsGlobal
        )
    }

    private func applyPort() {
        guard applyPortIfValid() else {
            portText = "\(settings.mcpServerPort)"
            return
        }
    }

    @discardableResult
    private func applyPortIfValid() -> Bool {
        guard let port = Int(portText), port > 1024, port < 65535 else {
            return false
        }
        if settings.mcpServerPort != port {
            settings.mcpServerPort = port
        }
        return true
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        copiedToken = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedToken = false
        }
    }

    private func copySnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configSnippet, forType: .string)
        copiedSnippet = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedSnippet = false
        }
    }

    private func regenerateToken() {
        do {
            try settings.saveMCPToken(MCPTokenGenerator.generate())
        } catch {
            Log.ui.error("Failed to regenerate MCP token: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

enum MCPClient: String, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case cursor
    case codex
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex CLI"
        case .opencode: "OpenCode"
        }
    }

    func configFilePath(isGlobal: Bool = true) -> String {
        switch self {
        case .claudeCode: ".claude/settings.json"
        case .cursor: ".cursor/mcp.json"
        case .codex: "~/.codex/config.toml"
        case .opencode: isGlobal ? "~/.config/opencode/opencode.json" : "opencode.json"
        }
    }

    func instructions(isGlobal: Bool = true, locale: Locale) -> String {
        switch self {
        case .claudeCode:
            localized("Add this to .claude/settings.json in your project root, or ~/.claude/settings.json for user-wide access.", locale: locale)
        case .cursor:
            localized("Add this to .cursor/mcp.json in your project root, or ~/.cursor/mcp.json for all projects. Restart Cursor after saving.", locale: locale)
        case .codex:
            localized("Add this to ~/.codex/config.toml. Project-scoped configuration can live in .codex/config.toml for trusted projects.", locale: locale)
        case .opencode:
            isGlobal
                ? localized("Add this to ~/.config/opencode/opencode.json for user-wide access across all projects.", locale: locale)
                : localized("Add this to opencode.json in your project root for project-specific access.", locale: locale)
        }
    }

    func configSnippet(port: Int, token: String, isGlobal: Bool = true) -> String {
        switch self {
        case .claudeCode:
            """
            {
              "mcpServers": {
                "pindrop": {
                  "type": "http",
                  "url": "http://localhost:\(port)/mcp",
                  "headers": {
                    "Authorization": "Bearer \(token)"
                  }
                }
              }
            }
            """
        case .cursor:
            """
            {
              "mcpServers": {
                "pindrop": {
                  "url": "http://localhost:\(port)/mcp",
                  "headers": {
                    "Authorization": "Bearer \(token)"
                  }
                }
              }
            }
            """
        case .codex:
            """
            [mcp_servers.pindrop]
            url = "http://localhost:\(port)/mcp"
            http_headers = { "Authorization" = "Bearer \(token)" }
            """
        case .opencode:
            """
            {
              "$schema": "https://opencode.ai/config.json",
              "mcp": {
                "pindrop": {
                  "type": "remote",
                  "url": "http://localhost:\(port)/mcp",
                  "headers": {
                    "Authorization": "Bearer \(token)"
                  }
                }
              }
            }
            """
        }
    }
}

#Preview {
    MCPSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 600)
}
