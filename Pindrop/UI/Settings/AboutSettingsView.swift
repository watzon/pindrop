//
//  AboutSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale
    @State private var copiedSystemInfo = false

    var body: some View {
        SettingsPaneStack {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.accent)
                        .frame(
                            width: SettingsLayoutMetrics.aboutIconSize,
                            height: SettingsLayoutMetrics.aboutIconSize
                        )
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppColors.contentBackground)
                }

                Text("Pindrop")
                    .font(AppTypography.wordmark)
                    .foregroundStyle(AppColors.textPrimary)

                Text(versionChannelLine)
                    .font(AppTypography.monoTime)
                    .foregroundStyle(AppColors.textSecondary)

                Text(localized(SettingsAboutPresentation.taglineKey, locale: locale))
                    .font(FontLoader.font(family: .newsreader, size: 15, weight: .regular, italic: true))
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 16) {
                    linkButton(localized("GitHub", locale: locale), url: "https://github.com/watzon/pindrop")
                    Text("·").foregroundStyle(AppColors.textTertiary)
                    linkButton(localized("Website", locale: locale), url: "https://pindrop.watzon.tech")
                    Text("·").foregroundStyle(AppColors.textTertiary)
                    linkButton(localized("License — MIT", locale: locale), url: "https://github.com/watzon/pindrop/blob/main/LICENSE")
                    Text("·").foregroundStyle(AppColors.textTertiary)
                    linkButton(localized("Acknowledgements", locale: locale), url: "https://github.com/watzon/pindrop#acknowledgements")
                }
                .font(AppTypography.label)

                Text(localized("Bundled fonts (Newsreader, Inter, JetBrains Mono) are licensed under the SIL Open Font License.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Text(localized("SenseVoice-Small (FunASR) model weights are licensed by Alibaba Group under the FunASR Model Open Source License; attribution required.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardRadius, style: .continuous)
                    .fill(AppColors.contentBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardRadius, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )

            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Copy System Info", locale: locale))
                } control: {
                    Button {
                        copySystemInfo()
                    } label: {
                        SettingsMenuButton(
                            title: copiedSystemInfo
                                ? localized("Copied!", locale: locale)
                                : localized("Copy", locale: locale),
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(copiedSystemInfo)
                    .accessibilityIdentifier("settings.button.copySystemInfo")
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(
                        title: localized("Open Logs in Finder", locale: locale),
                        subtitle: localized("Attach logs from this folder when filing a GitHub issue.", locale: locale)
                    )
                } control: {
                    Button {
                        revealLogsInFinder()
                    } label: {
                        SettingsMenuButton(
                            title: localized("Open", locale: locale),
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.button.openLogs")
                }
            }

            Text(localized("Made with care for local speech.", locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var versionChannelLine: String {
        let channel = SettingsAboutPresentation.channelLabel(
            feedURLString: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            locale: locale
        )
        return SettingsAboutPresentation.versionLine(
            version: appVersion,
            build: buildNumber,
            channel: channel
        )
    }

    private func linkButton(_ title: String, url: String) -> some View {
        Button {
            if let destination = URL(string: url) {
                NSWorkspace.shared.open(destination)
            }
        } label: {
            Text(title)
                .foregroundStyle(AppColors.accent)
        }
        .buttonStyle(.plain)
    }

    private func copySystemInfo() {
        let info = """
            Pindrop: \(appVersion) (\(buildNumber))
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Chip: \(chipType)
            Model: \(activeModel)
            """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        copiedSystemInfo = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedSystemInfo = false
        }
    }

    private func revealLogsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.currentLogFileURL])
    }

    private var chipType: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }

        switch machine {
        case "arm64": return "Apple Silicon"
        case "x86_64": return "Intel"
        default: return machine ?? "Unknown"
        }
    }

    private var activeModel: String {
        settings.selectedModel.isEmpty ? "Not loaded" : settings.selectedModel
    }

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var appVersion: String {
        Self.isPreview ? "1.0.0" : Bundle.main.appShortVersionString
    }

    private var buildNumber: String {
        Self.isPreview ? "1" : Bundle.main.appBuildVersionString
    }
}

#Preview {
    AboutSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 560)
        .background(AppColors.windowBackground)
        .themeRefresh()
}
