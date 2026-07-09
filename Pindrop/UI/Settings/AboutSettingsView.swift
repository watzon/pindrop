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
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    appIcon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pindrop")
                            .font(.title2.weight(.semibold))

                        Text(localized("Local speech-to-text with WhisperKit", locale: locale))
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: localized("Version %@ (%@)", locale: locale),
                                appVersion,
                                buildNumber
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Text(localized("A native macOS menu bar dictation app using local speech-to-text with WhisperKit. 100% local processing by default with optional AI enhancement.", locale: locale))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(localized("Acknowledgments", locale: locale)) {
                Link(localized("WhisperKit", locale: locale), destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                Link(localized("OpenAI Whisper", locale: locale), destination: URL(string: "https://github.com/openai/whisper")!)
                Link(localized("Pindrop on GitHub", locale: locale), destination: URL(string: "https://github.com/watzon/pindrop")!)
            }

            Section {
                Link(localized("Report an Issue", locale: locale), destination: URL(string: "https://github.com/watzon/pindrop/issues")!)

                Button {
                    copySystemInfo()
                } label: {
                    Label(
                        copiedSystemInfo
                            ? localized("Copied!", locale: locale)
                            : localized("Copy System Info", locale: locale),
                        systemImage: copiedSystemInfo ? "checkmark" : "doc.on.doc"
                    )
                }
                .disabled(copiedSystemInfo)
                .accessibilityIdentifier("settings.button.copySystemInfo")

                Button(localized("Open Logs in Finder", locale: locale)) {
                    revealLogsInFinder()
                }
                .accessibilityIdentifier("settings.button.openLogs")
            } header: {
                Text(localized("Support", locale: locale))
            } footer: {
                Text(localized("Attach logs from this folder when filing a GitHub issue.", locale: locale))
            }

            Section {
                Text(localized("MIT License", locale: locale))
            } header: {
                Text(localized("License", locale: locale))
            } footer: {
                Text(localized("Streaming transcription model (Nemotron Speech Streaming) licensed by NVIDIA Corporation under the NVIDIA Open Model License.", locale: locale))
            }
        }
        .formStyle(.grouped)
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

    private var appIcon: Image {
        Self.isPreview ? Image(systemName: "mic.fill") : Image(nsImage: NSApp.applicationIconImage)
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
}
