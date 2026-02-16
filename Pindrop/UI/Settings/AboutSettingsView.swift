//
//  AboutSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct AboutSettingsView: View {
   @State private var showCopyConfirmation = false

   var body: some View {
      VStack(spacing: AppTheme.Spacing.xl) {
         appInfoSection
         acknowledgmentsSection
         linksSection
      }
   }

   private var appInfoSection: some View {
      SettingsCard(title: "About Pindrop", icon: "mic.fill") {
         VStack(spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.xl) {
               appIcon
                  .resizable()
                  .scaledToFit()
                  .frame(width: 80, height: 80)
                  .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))

               VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                  Text("Pindrop")
                     .font(AppTypography.title)
                     .foregroundStyle(AppColors.textPrimary)

                  Text("Local speech-to-text with WhisperKit")
                     .font(AppTypography.body)
                     .foregroundStyle(AppColors.textSecondary)

                  Spacer()

                  Text("Version \(appVersion) (\(buildNumber))")
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textTertiary)
               }
               .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
               .background(AppColors.divider)

            Text(
               "A native macOS menu bar dictation app using local speech-to-text with WhisperKit. 100% local processing by default with optional AI enhancement."
            )
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.leading)
         }
      }
   }

   private var acknowledgmentsSection: some View {
      SettingsCard(title: "Acknowledgments", icon: "heart.fill") {
         VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Link(destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!) {
               HStack {
                  Text("WhisperKit")
                     .font(AppTypography.body)
                     .foregroundStyle(AppColors.textPrimary)
                  Spacer()
                  Image(systemName: "arrow.up.right.square")
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textTertiary)
               }
            }

            Divider()
               .background(AppColors.divider)

            Link(destination: URL(string: "https://github.com/openai/whisper")!) {
               HStack {
                  Text("OpenAI Whisper")
                     .font(AppTypography.body)
                     .foregroundStyle(AppColors.textPrimary)
                  Spacer()
                  Image(systemName: "arrow.up.right.square")
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textTertiary)
               }
            }

            Divider()
               .background(AppColors.divider)

            Link(destination: URL(string: "https://github.com/watzon/pindrop")!) {
               HStack {
                  Text("Pindrop on GitHub")
                     .font(AppTypography.body)
                     .foregroundStyle(AppColors.textPrimary)
                  Spacer()
                  Image(systemName: "arrow.up.right.square")
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textTertiary)
               }
            }
         }
      }
   }

   private var linksSection: some View {
      SettingsCard(title: "Support", icon: "questionmark.circle.fill") {
         VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Link(destination: URL(string: "https://github.com/watzon/pindrop/issues")!) {
               HStack {
                  Text("Report an Issue")
                     .font(AppTypography.body)
                     .foregroundStyle(AppColors.textPrimary)
                  Spacer()
                  Image(systemName: "arrow.up.right.square")
                     .font(AppTypography.caption)
                     .foregroundStyle(AppColors.textTertiary)
               }
            }

            Divider()
               .background(AppColors.divider)

            HStack {
               Text("Copy System Info for Bug Report")
                  .font(AppTypography.body)
                  .foregroundStyle(AppColors.textPrimary)
               Spacer()
               Button(action: copySystemInfo) {
                  Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                     .font(AppTypography.caption)
                     .foregroundStyle(showCopyConfirmation ? .green : AppColors.textTertiary)
               }
               .buttonStyle(.plain)
               .disabled(showCopyConfirmation)
            }

            Divider()
               .background(AppColors.divider)

            Text("MIT License")
               .font(AppTypography.body)
               .foregroundStyle(AppColors.textSecondary)
               .padding(.top, AppTheme.Spacing.xs)
         }
      }
   }

   // MARK: - System Info

   private func copySystemInfo() {
      let info = """
         Pindrop: \(appVersion) (\(buildNumber))
         macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
         Chip: \(chipType)
         Model: \(activeModel)
         """

      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(info, forType: .string)

      withAnimation {
         showCopyConfirmation = true
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
         withAnimation {
            showCopyConfirmation = false
         }
      }
   }

   private var chipType: String {
      var sysinfo = utsname()
      uname(&sysinfo)
      let machine = withUnsafePointer(to: &sysinfo.machine) {
         $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(validatingUTF8: $0)
         }
      }
      // Map common arch values
      switch machine {
      case "arm64":
         return "Apple Silicon"
      case "x86_64":
         return "Intel"
      default:
         return machine ?? "Unknown"
      }
   }

   private var activeModel: String {
      // Get from SettingsStore
      let modelName = SettingsStore().selectedModel
      return modelName.isEmpty ? "Not loaded" : modelName
   }

   // MARK: - Preview Detection

   private static var isPreview: Bool {
      ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
   }

   private var appIcon: Image {
      if Self.isPreview {
         return Image(systemName: "mic.fill")
      }
      return Image(nsImage: NSApp.applicationIconImage)
   }

   private var appVersion: String {
      if Self.isPreview {
         return "1.0.0"
      }
      return Bundle.main.appShortVersionString
   }

   private var buildNumber: String {
      if Self.isPreview {
         return "1"
      }
      return Bundle.main.appBuildVersionString
   }
}

#Preview {
   AboutSettingsView()
      .padding()
      .frame(width: 500)
}
