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

enum OnboardingProgressPresentation {
    static let dotCount = OnboardingStep.allCases.count

    static func activeIndex(for step: OnboardingStep) -> Int {
        step.rawValue
    }
}

enum OnboardingType {
    static let bigHeading = FontLoader.font(family: .newsreader, size: 40, weight: .medium)
    static let stepHeading = FontLoader.font(family: .newsreader, size: 28, weight: .medium)
    static let primaryButton = FontLoader.font(family: .inter, size: 14, weight: .semibold)
    static let ghostButton = FontLoader.font(family: .inter, size: 13, weight: .medium)
    static let stepSubtitle = FontLoader.font(family: .inter, size: 13, weight: .regular)
    static let welcomeSubtitle = FontLoader.font(family: .inter, size: 14, weight: .regular)
}

struct OnboardingPrimaryButton: View {
    let title: String
    var icon: Icon?
    let action: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let icon {
                    IconView(icon: icon, size: 13)
                        .scaleEffect(
                            x: icon.rawValue == Icon.arrowRight.rawValue && layoutDirection == .rightToLeft
                                ? -1
                                : 1
                        )
                }
            }
            .font(OnboardingType.primaryButton)
            .foregroundStyle(AppColors.contentBackground)
            .padding(.vertical, 10)
            .padding(.horizontal, 22)
            .background(AppColors.accent, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct OnboardingGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(OnboardingType.ghostButton)
            .foregroundStyle(AppColors.textSecondary)
            .keyboardFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OnboardingWindow: View {
    @ObservedObject var settings: SettingsStore
    var modelManager: ModelManager
    var transcriptionService: TranscriptionService
    let permissionManager: PermissionManager
    let onComplete: () -> Void
    let onPreferredContentSizeChange: (CGSize) -> Void
    let onStepChange: (OnboardingStep) -> Void
    
    @State private var currentStep: OnboardingStep = .welcome
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedModelName: String = "openai_whisper-base"
    @State private var direction: Int = 1
    
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

    private static let preferredContentSize = CGSize(width: 760, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if canGoBack {
                    Button(action: goBack) {
                        HStack(spacing: 4) {
                            IconView(icon: .chevronLeft, size: 14)
                                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1)
                            Text(localized("Back", locale: settings.selectedAppLocale.locale))
                        }
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            stepIndicator
                .padding(.top, 8)
        }
        .padding(24)
        .background(AppColors.windowBackground)
        .clipShape(.rect(cornerRadius: 12))
        .frame(width: 760, height: 560)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .onAppear {
            let initialStep = OnboardingStep(rawValue: settings.currentOnboardingStep) ?? .welcome
            currentStep = initialStep
            onStepChange(initialStep)
            onPreferredContentSizeChange(Self.preferredContentSize)
            Log.boot.info("OnboardingWindow appeared step=\(initialStep.title) storedStepIndex=\(settings.currentOnboardingStep)")
        }
    }
    
    // Renders through OnboardingProgressPresentation so the unit tests pin the
    // actual dot row (7 dots, download step included).
    private var stepIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0..<OnboardingProgressPresentation.dotCount, id: \.self) { index in
                stepDot(at: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: localized("Step %d of %d", locale: settings.selectedAppLocale.locale),
                locale: settings.selectedAppLocale.locale,
                OnboardingProgressPresentation.activeIndex(for: currentStep) + 1,
                OnboardingProgressPresentation.dotCount
            )
        )
    }

    @ViewBuilder
    private func stepDot(at index: Int) -> some View {
        let isActive = index == OnboardingProgressPresentation.activeIndex(for: currentStep)

        Capsule()
            .fill(isActive ? AppColors.accent : AppColors.border)
            .frame(width: isActive ? 18 : 6, height: 6)
            .appAnimation(.fast, value: currentStep)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case .welcome:
                WelcomeStepView(onContinue: { goToStep(.modelSelection) })
                    .transition(stepTransition)
                
            case .modelSelection:
                ModelSelectionStepView(
                    modelManager: modelManager,
                    selectedModelName: $selectedModelName,
                    onContinue: { startModelDownload() }
                )
                .transition(stepTransition)
                
            case .modelDownload:
                ModelDownloadStepView(
                    modelManager: modelManager,
                    transcriptionService: transcriptionService,
                    modelName: selectedModelName,
                    onComplete: { goToStep(.aiEnhancement) },
                    onCancel: { goToStep(.modelSelection, direction: -1) }
                )
                .transition(stepTransition)
                
            case .aiEnhancement:
                AIEnhancementStepView(
                    settings: settings,
                    onContinue: { goToStep(.permissions) },
                    onSkip: { goToStep(.permissions) },
                    onPreferredContentSizeChange: { size in
                        onPreferredContentSizeChange(size)
                    }
                )
                .transition(stepTransition)
                
            case .permissions:
                PermissionsStepView(
                    settings: settings,
                    permissionManager: permissionManager,
                    onContinue: { goToStep(.hotkeySetup) }
                )
                .transition(stepTransition)
                
            case .hotkeySetup:
                HotkeySetupStepView(
                    settings: settings,
                    onContinue: { goToStep(.ready) },
                    onSkip: { goToStep(.ready) }
                )
                .transition(stepTransition)
                
            case .ready:
                ReadyStepView(
                    settings: settings,
                    modelManager: modelManager,
                    selectedModelName: selectedModelName,
                    onComplete: completeOnboarding
                )
                .transition(stepTransition)
            }
        }
        .animation(reduceMotion ? nil : AppTheme.Animation.smooth, value: currentStep)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let localeForward: Edge = layoutDirection == .rightToLeft ? .leading : .trailing
        let localeBackward: Edge = layoutDirection == .rightToLeft ? .trailing : .leading
        let insertion = direction > 0 ? localeForward : localeBackward
        let removal = direction > 0 ? localeBackward : localeForward
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }
    
    private func goToStep(_ step: OnboardingStep, direction: Int = 1) {
        Log.boot.info("Onboarding goToStep -> \(step.title) direction=\(direction)")
        self.direction = direction
        withAnimation(reduceMotion ? nil : AppTheme.Animation.smooth) {
            currentStep = step
            settings.currentOnboardingStep = step.rawValue
        }
        onStepChange(step)
    }
    
    private func goBack() {
        guard let previous = previousStep else { return }
        goToStep(previous, direction: -1)
    }
    
    private func startModelDownload() {
        let cached = modelManager.isModelDownloaded(selectedModelName)
        Log.boot.info("Onboarding startModelDownload model=\(selectedModelName) alreadyOnDisk=\(cached)")
        if cached {
            goToStep(.aiEnhancement)
        } else {
            goToStep(.modelDownload)
        }
    }
    
    private func completeOnboarding() {
        Log.boot.info("Onboarding completeOnboarding selectedModel=\(selectedModelName)")
        settings.selectedModel = selectedModelName
        settings.hasCompletedOnboarding = true
        settings.currentOnboardingStep = 0
        // The permissions step presented the telemetry toggle, so fresh installs
        // never also get the standalone consent prompt.
        TelemetryConsentService.markConsentHandledDuringOnboarding(settings: settings)
        onComplete()
    }
}

#if DEBUG
struct OnboardingWindow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingWindow(
            settings: SettingsStore(),
            modelManager: PreviewModelManagerWindow(),
            transcriptionService: TranscriptionService(),
            permissionManager: PermissionManager(),
            onComplete: {},
            onPreferredContentSizeChange: { _ in },
            onStepChange: { _ in }
        )
    }
}

final class PreviewModelManagerWindow: ModelManager {
    override init() {
        // Skip async initialization to avoid launching WhisperKit in preview
    }
}
#endif
