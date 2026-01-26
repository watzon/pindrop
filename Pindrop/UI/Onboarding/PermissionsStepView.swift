//
//  PermissionsStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AVFoundation

struct PermissionsStepView: View {
    let permissionManager: PermissionManager
    let onContinue: () -> Void
    
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var checkingPermissions = true
    
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
            await checkPermissions()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
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
            icon: "mic.fill",
            title: "Microphone",
            description: "Required for recording your voice",
            isGranted: microphoneGranted,
            isRequired: true,
            action: requestMicrophone
        )
    }
    
    private var accessibilityCard: some View {
        PermissionCard(
            icon: "accessibility",
            title: "Accessibility",
            description: "Optional: Insert text directly into apps",
            isGranted: accessibilityGranted,
            isRequired: false,
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
            .buttonStyle(.glassProminent)
            .disabled(!microphoneGranted)
        }
        .padding(.horizontal, 40)
    }
    
    private func checkPermissions() async {
        checkingPermissions = true
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = micStatus == .authorized
        
        accessibilityGranted = AXIsProcessTrusted()
        
        checkingPermissions = false
    }
    
    private func requestMicrophone() {
        Task {
            microphoneGranted = await permissionManager.requestPermission()
        }
    }
    
    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        
        Task {
            try? await Task.sleep(for: .seconds(1))
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isRequired: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isGranted ? .green : Color.accentColor)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(isGranted ? .green.opacity(0.2) : .accentColor.opacity(0.2)), in: .circle)
            
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
