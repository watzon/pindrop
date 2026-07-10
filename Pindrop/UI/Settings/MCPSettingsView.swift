//
//  MCPSettingsView.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MCPSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale

    @State private var selectedClient: MCPClient = .claudeCode
    @State private var opencodeIsGlobal = true
    @State private var portText = ""
    @State private var copiedSnippet = false
    @State private var copiedToken = false
    @State private var showAgentSetup = false
    @State private var errorMessage: String?
    @AppStorage(SettingsLogLevel.userDefaultsKey) private var logLevelRaw = SettingsLogLevel.info.rawValue

    private var token: String {
        settings.loadMCPToken() ?? localized("Not generated yet — enable the server", locale: locale)
    }

    private var logLevel: SettingsLogLevel {
        get { SettingsLogLevel(rawValue: logLevelRaw) ?? .info }
        nonmutating set { logLevelRaw = newValue.rawValue }
    }

    var body: some View {
        SettingsPaneStack {
            // MCP
            SettingsGroupCard {
                SettingsRow(showSeparator: settings.mcpServerEnabled) {
                    SettingsRowLabel(title: localized("MCP Server", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.mcpServerEnabled,
                        label: localized("Enable MCP Server", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.mcpServerEnabled")
                }

                if settings.mcpServerEnabled {
                    SettingsRow(showSeparator: true) {
                        SettingsRowLabel(title: localized("Port", locale: locale))
                    } control: {
                        // Single TextField — avoid LabeledContent double-render (fcb33da/0ff6440).
                        TextField(
                            "",
                            text: $portText,
                            prompt: Text("46337")
                        )
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(AppTypography.monoTime)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .frame(width: 88)
                        .padding(.vertical, SettingsLayoutMetrics.dropdownVerticalPadding)
                        .padding(.horizontal, SettingsLayoutMetrics.dropdownHorizontalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.dropdownRadius, style: .continuous)
                                .fill(AppColors.windowBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.dropdownRadius, style: .continuous)
                                .strokeBorder(AppColors.border, lineWidth: 1)
                        )
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

                    SettingsRow(showSeparator: true) {
                        SettingsRowLabel(title: localized("Endpoint", locale: locale))
                    } control: {
                        Text(MCPEndpointPresentation.endpointURL(port: settings.mcpServerPort))
                            .font(AppTypography.monoTime)
                            .foregroundStyle(AppColors.textTertiary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }

                    SettingsRow(showSeparator: false) {
                        SettingsRowLabel(title: localized("Bearer Token", locale: locale))
                    } control: {
                        HStack(spacing: 8) {
                            Button {
                                copyToken()
                            } label: {
                                SettingsMenuButton(
                                    title: copiedToken
                                        ? localized("Copied!", locale: locale)
                                        : localized("Copy token", locale: locale),
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.button.copyMCPToken")

                            Button {
                                regenerateToken()
                            } label: {
                                SettingsMenuButton(
                                    title: localized("Regenerate", locale: locale),
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if settings.mcpServerEnabled {
                DisclosureGroup(isExpanded: $showAgentSetup) {
                    SettingsGroupCard {
                        SettingsRow(showSeparator: true) {
                            SettingsRowLabel(title: localized("Client", locale: locale))
                        } control: {
                            Menu {
                                ForEach(MCPClient.allCases) { client in
                                    Button(client.displayName) {
                                        selectedClient = client
                                        copiedSnippet = false
                                    }
                                }
                            } label: {
                                SettingsMenuButton(title: selectedClient.displayName)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .accessibilityIdentifier("settings.picker.mcpClient")
                        }

                        if selectedClient == .opencode {
                            SettingsRow(showSeparator: true) {
                                SettingsRowLabel(title: localized("Configuration Scope", locale: locale))
                            } control: {
                                HStack(spacing: 6) {
                                    FilterChip(
                                        title: localized("Global", locale: locale),
                                        isSelected: opencodeIsGlobal
                                    ) {
                                        opencodeIsGlobal = true
                                        copiedSnippet = false
                                    }
                                    FilterChip(
                                        title: localized("Project", locale: locale),
                                        isSelected: !opencodeIsGlobal
                                    ) {
                                        opencodeIsGlobal = false
                                        copiedSnippet = false
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedClient.instructions(isGlobal: opencodeIsGlobal, locale: locale))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(selectedClient.configFilePath(isGlobal: opencodeIsGlobal))
                                .font(AppTypography.monoSmall)
                                .foregroundStyle(AppColors.textTertiary)
                                .textSelection(.enabled)

                            HStack {
                                Text(localized("Configuration Snippet", locale: locale))
                                    .font(AppTypography.labelStrong)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                Button {
                                    copySnippet()
                                } label: {
                                    SettingsMenuButton(
                                        title: copiedSnippet
                                            ? localized("Copied!", locale: locale)
                                            : localized("Copy", locale: locale),
                                        showsChevron: false
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settings.button.copyMCPSnippet")
                            }

                            ScrollView([.horizontal, .vertical]) {
                                Text(configSnippet)
                                    .font(AppTypography.monoSmall)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(minHeight: 120, maxHeight: 200)
                            .background(AppColors.windowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(AppColors.border, lineWidth: 1)
                            }
                        }
                        .padding(SettingsLayoutMetrics.rowHorizontalPadding)
                        .padding(.bottom, SettingsLayoutMetrics.rowVerticalPadding)
                    }
                    .padding(.top, 8)
                } label: {
                    Text(localized("Agent Setup", locale: locale))
                        .font(AppTypography.labelStrong)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            // Diagnostics / logs
            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Log level", locale: locale))
                } control: {
                    Menu {
                        ForEach(SettingsLogLevel.allCases) { level in
                            Button(level.title(locale: locale)) {
                                logLevel = level
                            }
                        }
                    } label: {
                        SettingsMenuButton(title: logLevel.title(locale: locale))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("settings.picker.logLevel")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Diagnostics", locale: locale),
                        subtitle: localized("Logs never include transcript text", locale: locale)
                    )
                } control: {
                    EmptyView()
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Export Logs…", locale: locale))
                } control: {
                    Button {
                        exportLogs()
                    } label: {
                        SettingsMenuButton(
                            title: localized("Export Logs…", locale: locale),
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.button.exportLogs")
                }
            }
        }
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

    private func exportLogs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = localized("Export", locale: locale)
        panel.message = localized("Choose a folder to copy Pindrop log files into.", locale: locale)
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            let logs = SettingsLogExport.logFileURLs(in: Log.logsDirectoryURL)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let folder = destination.appendingPathComponent("Pindrop-Logs-\(stamp)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in logs {
                    let target = folder.appendingPathComponent(file.lastPathComponent)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: file, to: target)
                }
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                Log.ui.error("Failed to export logs: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            }
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
        .background(AppColors.windowBackground)
        .themeRefresh()
}
