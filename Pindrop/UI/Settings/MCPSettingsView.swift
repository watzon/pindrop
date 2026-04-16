//
//  MCPSettingsView.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale

    @State private var selectedClient: MCPClient = .claudeCode
    @State private var opencodeIsGlobal: Bool = true
    @State private var portText: String = ""
    @State private var showCopiedFeedback = false
    @State private var showTokenCopiedFeedback = false

    private var token: String {
        settings.loadMCPToken() ?? "(not generated yet — enable the server)"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            serverCard
            if settings.mcpServerEnabled {
                integrationsCard
            }
        }
        .onAppear {
            portText = "\(settings.mcpServerPort)"
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        SettingsCard(
            title: localized("MCP Server", locale: locale),
            icon: "network",
            detail: localized("Run a local HTTP server so AI agents can submit transcription jobs, search history, and manage speakers — without touching the Pindrop UI.", locale: locale)
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                SettingsToggleRow(
                    title: localized("Enable MCP Server", locale: locale),
                    detail: localized("Starts a local HTTP server on the configured port.", locale: locale),
                    isOn: $settings.mcpServerEnabled
                )

                if settings.mcpServerEnabled {
                    SettingsDivider()

                    portRow
                    tokenRow
                }
            }
        }
    }

    private var portRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("Port", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(localized("Default: 46337. Changes take effect on next server restart.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            TextField("46337", text: $portText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.center)
                .onSubmit { applyPort() }
                .onChange(of: portText) { _, new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { portText = digits }
                }
        }
    }

    private var tokenRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Bearer Token", locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized("Click the token to copy it to your clipboard.", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button(localized("Regenerate", locale: locale)) {
                    regenerateToken()
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }

            Button {
                copyToken()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(showTokenCopiedFeedback ? localized("Copied!", locale: locale) : token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(showTokenCopiedFeedback ? AppColors.accent : AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: showTokenCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(showTokenCopiedFeedback ? AppColors.accent : AppColors.textTertiary)
                }
                .padding(AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .fill(AppColors.inputBackground)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Integrations Card

    private var integrationsCard: some View {
        SettingsCard(
            title: localized("Integration Instructions", locale: locale),
            icon: "doc.plaintext",
            detail: localized("Copy the configuration snippet for your preferred AI agent host.", locale: locale)
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Picker("", selection: $selectedClient) {
                    ForEach(MCPClient.allCases) { client in
                        Text(client.displayName).tag(client)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedClient) { _, _ in showCopiedFeedback = false }

                if selectedClient == .opencode {
                    Picker("", selection: $opencodeIsGlobal) {
                        Text(localized("Global", locale: locale)).tag(true)
                        Text(localized("Project", locale: locale)).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180, alignment: .leading)
                    .onChange(of: opencodeIsGlobal) { _, _ in showCopiedFeedback = false }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(selectedClient.instructions(isGlobal: opencodeIsGlobal))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    configSnippetView
                }
            }
        }
    }

    private var configSnippetView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text(selectedClient.configFilePath(isGlobal: opencodeIsGlobal))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button(showCopiedFeedback ? localized("Copied!", locale: locale) : localized("Copy snippet", locale: locale)) {
                    copySnippet()
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(configSnippet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(AppTheme.Spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(AppColors.inputBackground)
            )
        }
    }

    // MARK: - Helpers

    private var configSnippet: String {
        selectedClient.configSnippet(port: settings.mcpServerPort, token: token, isGlobal: opencodeIsGlobal)
    }

    private func applyPort() {
        guard let port = Int(portText), port > 1024, port < 65535 else {
            portText = "\(settings.mcpServerPort)"
            return
        }
        settings.mcpServerPort = port
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        showTokenCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showTokenCopiedFeedback = false
        }
    }

    private func copySnippet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configSnippet, forType: .string)
        showCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedFeedback = false
        }
    }

    private func regenerateToken() {
        let newToken = MCPTokenGenerator.generate()
        try? settings.saveMCPToken(newToken)
    }
}

// MARK: - MCP Client Definitions

enum MCPClient: String, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case cursor = "cursor"
    case codex = "codex"
    case opencode = "opencode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .cursor:     return "Cursor"
        case .codex:      return "Codex CLI"
        case .opencode:   return "OpenCode"
        }
    }

    /// `isGlobal` is only meaningful for .opencode; ignored by other cases.
    func configFilePath(isGlobal: Bool = true) -> String {
        switch self {
        case .claudeCode: return ".claude/settings.json"
        case .cursor:     return ".cursor/mcp.json"
        case .codex:      return "~/.codex/config.toml"
        case .opencode:   return isGlobal ? "~/.config/opencode/opencode.json" : "opencode.json"
        }
    }

    func instructions(isGlobal: Bool = true) -> String {
        switch self {
        case .claudeCode:
            return "Add to .claude/settings.json in your project root, or ~/.claude/settings.json for user-wide access."
        case .cursor:
            return "Add to .cursor/mcp.json in your project root, or ~/.cursor/mcp.json to apply to all projects. Restart Cursor after saving."
        case .codex:
            return "Add to ~/.codex/config.toml. Project-scoped config can live in .codex/config.toml (trusted projects only)."
        case .opencode:
            return isGlobal
                ? "Add to ~/.config/opencode/opencode.json for user-wide access across all projects."
                : "Add to opencode.json in your project root for project-specific access."
        }
    }

    func configSnippet(port: Int, token: String, isGlobal: Bool = true) -> String {
        switch self {
        case .claudeCode:
            return """
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
            // Cursor HTTP servers: url + headers, no type field required
            return """
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
            // Codex CLI uses TOML at ~/.codex/config.toml
            return """
            [mcp_servers.pindrop]
            url = "http://localhost:\(port)/mcp"
            http_headers = { "Authorization" = "Bearer \(token)" }
            """
        case .opencode:
            // OpenCode uses JSON with a top-level "mcp" key and type "remote"
            return """
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
