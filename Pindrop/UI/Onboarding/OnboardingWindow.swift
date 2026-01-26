//
//  OnboardingWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case modelSelection
    case modelDownload
    case aiEnhancement
    case permissions
    case hotkeySetup
    case ready
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .modelSelection: return "Choose Model"
        case .modelDownload: return "Downloading"
        case .aiEnhancement: return "AI Enhancement"
        case .permissions: return "Permissions"
        case .hotkeySetup: return "Hotkeys"
        case .ready: return "Ready"
        }
    }
    
    var canSkip: Bool {
        switch self {
        case .aiEnhancement, .hotkeySetup: return true
        default: return false
        }
    }
}

struct OnboardingWindow: View {
    @ObservedObject var settings: SettingsStore
    var modelManager: ModelManager
    var transcriptionService: TranscriptionService
    let permissionManager: PermissionManager
    let onComplete: () -> Void
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedModelName: String = "openai_whisper-base"
    @State private var direction: Int = 1
    @Namespace private var namespace
    
    private var canGoBack: Bool {
        switch currentStep {
        case .welcome, .modelDownload:
            return false
        default:
            return true
        }
    }
    
    private var previousStep: OnboardingStep? {
        switch currentStep {
        case .welcome: return nil
        case .modelSelection: return .welcome
        case .modelDownload: return nil
        case .aiEnhancement: return .modelSelection
        case .permissions: return .aiEnhancement
        case .hotkeySetup: return .permissions
        case .ready: return .hotkeySetup
        }
    }
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 0) {
                ZStack {
                    HStack {
                        if canGoBack {
                            Button(action: goBack) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    stepIndicator
                }
                .frame(height: 44)
                .padding(.top, 8)
                
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            let savedStep = settings.currentOnboardingStep
            if let step = OnboardingStep(rawValue: savedStep) {
                currentStep = step
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .controlBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var stepIndicator: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    if step != .modelDownload {
                        stepDot(for: step)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
    
    @ViewBuilder
    private func stepDot(for step: OnboardingStep) -> some View {
        let isActive = step == currentStep || (step == .modelSelection && currentStep == .modelDownload)
        let isPast = step.rawValue < currentStep.rawValue
        
        Circle()
            .fill(isActive ? Color.accentColor : (isPast ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3)))
            .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
            .glassEffect(.regular.tint(isActive ? .accentColor.opacity(0.3) : .clear))
            .animation(.spring(duration: 0.3), value: currentStep)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case .welcome:
                WelcomeStepView(onContinue: { goToStep(.modelSelection) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                
            case .modelSelection:
                ModelSelectionStepView(
                    modelManager: modelManager,
                    selectedModelName: $selectedModelName,
                    onContinue: { startModelDownload() }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                
            case .modelDownload:
                ModelDownloadStepView(
                    modelManager: modelManager,
                    transcriptionService: transcriptionService,
                    modelName: selectedModelName,
                    onComplete: { goToStep(.aiEnhancement) },
                    onCancel: { goToStep(.modelSelection, direction: -1) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
            case .aiEnhancement:
                AIEnhancementStepView(
                    settings: settings,
                    onContinue: { goToStep(.permissions) },
                    onSkip: { goToStep(.permissions) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                
            case .permissions:
                PermissionsStepView(
                    permissionManager: permissionManager,
                    onContinue: { goToStep(.hotkeySetup) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                
            case .hotkeySetup:
                HotkeySetupStepView(
                    settings: settings,
                    onContinue: { goToStep(.ready) },
                    onSkip: { goToStep(.ready) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                
            case .ready:
                ReadyStepView(
                    settings: settings,
                    modelManager: modelManager,
                    selectedModelName: selectedModelName,
                    onComplete: completeOnboarding
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: currentStep)
    }
    
    private func goToStep(_ step: OnboardingStep, direction: Int = 1) {
        self.direction = direction
        withAnimation {
            currentStep = step
            settings.currentOnboardingStep = step.rawValue
        }
    }
    
    private func goBack() {
        guard let previous = previousStep else { return }
        goToStep(previous, direction: -1)
    }
    
    private func startModelDownload() {
        if modelManager.isModelDownloaded(selectedModelName) {
            goToStep(.aiEnhancement)
        } else {
            goToStep(.modelDownload)
        }
    }
    
    private func completeOnboarding() {
        settings.selectedModel = selectedModelName
        settings.hasCompletedOnboarding = true
        settings.currentOnboardingStep = 0
        onComplete()
    }
}
