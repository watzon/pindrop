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
    
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var checkingPermissions = true
    @State private var accessibilityRequestInFlight = false
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            VStack(spacing: 16) {
                microphoneCard
                accessibilityCard
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            continueSection
        }
        .padding(.vertical, 24)
        .task {
            guard !Self.isPreview else {
                checkingPermissions = false
                return
            }
            await checkPermissions()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            IconView(icon: .shield, size: 40)
                .foregroundStyle(AppColors.accent)
                .padding(.bottom, 8)
            
            Text("Permissions")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Pindrop needs a few permissions to work.\nYour privacy is always respected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
    
    private var microphoneCard: some View {
        PermissionCard(
            icon: .mic,
            title: "Microphone",
            description: "Required for recording your voice",
            isGranted: microphoneGranted,
            isRequired: true,
            action: requestMicrophone
        )
    }
    
    private var accessibilityCard: some View {
        PermissionCard(
            icon: .accessibility,
            title: "Accessibility",
            description: "Optional: Insert text directly into apps",
            isGranted: accessibilityGranted,
            isRequired: false,
            isActionDisabled: accessibilityRequestInFlight,
            action: requestAccessibility
        )
    }
    
    private var continueSection: some View {
        VStack(spacing: 12) {
            if !microphoneGranted {
                Text("Microphone permission is required to continue")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!microphoneGranted)
        }
        .padding(.horizontal, 40)
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
    let icon: Icon
    let title: String
    let description: String
    let isGranted: Bool
    let isRequired: Bool
    var isActionDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            IconView(icon: icon, size: 24)
                .foregroundStyle(isGranted ? .green : AppColors.accent)
                .frame(width: 44, height: 44)
                .background(isGranted ? .green.opacity(0.1) : AppColors.accent.opacity(0.1))
                .background(.ultraThinMaterial, in: .circle)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    
                    if isRequired {
                        Text("Required")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(.capsule)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                IconView(icon: .circleCheck, size: 24)
                    .foregroundStyle(.green)
            } else {
                Button(isActionDisabled ? "Checking..." : "Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .disabled(isActionDisabled)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }
}
