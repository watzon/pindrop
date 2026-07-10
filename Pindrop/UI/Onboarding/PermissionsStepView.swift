//
//  PermissionsStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct PermissionsStepView: View {
    let permissionManager: PermissionManager
    let onContinue: () -> Void

    @Environment(\.locale) private var locale
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var checkingPermissions = true
    @State private var accessibilityRequestInFlight = false

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            VStack(spacing: 10) {
                microphoneCard
                accessibilityCard
            }
            .frame(width: 480)
            .padding(.top, 26)

            continueSection
        }
        .task {
            guard !Self.isPreview else {
                checkingPermissions = false
                return
            }
            await checkPermissions()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            Text(localized("Permissions", locale: locale))
                .font(OnboardingType.stepHeading)
                .tracking(-0.42)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Pindrop needs a few permissions to work.\nYour privacy is always respected.", locale: locale))
                .font(OnboardingType.stepSubtitle)
                .lineSpacing(3)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private var microphoneCard: some View {
        PermissionCard(
            icon: .mic,
            title: localized("Microphone", locale: locale),
            description: localized("Required for recording your voice", locale: locale),
            isGranted: microphoneGranted,
            isRequired: true,
            action: requestMicrophone
        )
    }

    private var accessibilityCard: some View {
        PermissionCard(
            icon: .accessibility,
            title: localized("Accessibility", locale: locale),
            description: localized("Optional: Insert text directly into apps", locale: locale),
            isGranted: accessibilityGranted,
            isRequired: false,
            isActionDisabled: accessibilityRequestInFlight,
            action: requestAccessibility
        )
    }

    private var continueSection: some View {
        VStack(spacing: 0) {
            Text(localized("Without Accessibility, Pindrop copies text to the clipboard instead.", locale: locale))
                .font(AppTypography.captionLarge)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 22)

            if !microphoneGranted {
                Text(localized("Microphone permission is required to continue", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
                    .padding(.top, 8)
            }

            OnboardingPrimaryButton(title: localized("Continue", locale: locale), icon: nil, action: onContinue)
            .disabled(!microphoneGranted)
            .opacity(microphoneGranted ? 1 : 0.5)
            .padding(.top, 18)
        }
    }

    private func checkPermissions() async {
        checkingPermissions = true

        let micStatus = permissionManager.checkPermissionStatus()
        microphoneGranted = micStatus == .authorized

        accessibilityGranted = permissionManager.checkAccessibilityPermission()

        checkingPermissions = false
    }

    private func requestMicrophone() {
        Task {
            microphoneGranted = await permissionManager.requestPermission()
        }
    }

    private func requestAccessibility() {
        guard !accessibilityRequestInFlight else { return }

        accessibilityRequestInFlight = true
        accessibilityGranted = permissionManager.requestAccessibilityPermission(showPrompt: true)

        Task {
            try? await Task.sleep(for: .seconds(1))
            permissionManager.refreshAccessibilityPermissionStatus()
            accessibilityGranted = permissionManager.checkAccessibilityPermission()
            accessibilityRequestInFlight = false
        }
    }
}

#if DEBUG
struct PermissionsStepView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsStepView(
            permissionManager: PermissionManager(),
            onContinue: {}
        )
        .frame(width: 800, height: 600)
    }
}

struct PermissionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PermissionCard(
                icon: .mic,
                title: "Microphone",
                description: "Required for recording",
                isGranted: true,
                isRequired: true,
                action: {}
            )
            
            PermissionCard(
                icon: .accessibility,
                title: "Accessibility",
                description: "Optional feature",
                isGranted: false,
                isRequired: false,
                action: {}
            )
        }
        .padding()
        .frame(width: 500)
    }
}
#endif

struct PermissionCard: View {
    @Environment(\.locale) private var locale

    let icon: Icon
    let title: String
    let description: String
    let isGranted: Bool
    let isRequired: Bool
    var isActionDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconView(icon: icon, size: 17)
                .foregroundStyle(isGranted ? AppColors.accent : AppColors.textSecondary)
                .frame(width: 38, height: 38)
                .background(isGranted ? AppColors.accentBackground : AppColors.windowBackground, in: .rect(cornerRadius: 10))
                .overlay {
                    if !isGranted {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OnboardingType.primaryButton)
                    .foregroundStyle(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.captionLarge)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 6) {
                    IconView(icon: .circleCheck, size: 15)
                    Text(localized("Granted", locale: locale))
                        .font(AppTypography.labelSemibold)
                }
                .foregroundStyle(AppColors.accent)
            } else {
                Button(isActionDisabled ? localized("Checking...", locale: locale) : localized("Grant", locale: locale) + "…") {
                    action()
                }
                .buttonStyle(.plain)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.contentBackground)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(AppColors.accent, in: .rect(cornerRadius: 8))
                .disabled(isActionDisabled)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(AppColors.contentBackground, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        }
    }
}
