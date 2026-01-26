//
//  SplashScreen.swift
//  Pindrop
//
//  Splash screen shown during app initialization
//

import SwiftUI

struct SplashScreen: View {
    
    @State private var isAnimating = false
    @State private var loadingText = "Initializing..."
    
    let loadingMessages = [
        "Initializing...",
        "Loading models...",
        "Preparing audio...",
        "Almost ready..."
    ]
    
    var body: some View {
        ZStack {
            // Background
            AppColors.windowBackground
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xxl) {
                Spacer()
                
                // App icon area
                VStack(spacing: AppTheme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isAnimating ? 1.3 : 1.0)
                            .opacity(isAnimating ? 0 : 0.6)
                        
                        Circle()
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                            .opacity(isAnimating ? 0 : 0.8)
                        
                        Circle()
                            .fill(AppColors.accentBackground)
                            .frame(width: 80, height: 80)
                        
                        Image("PindropIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(AppColors.accent)
                            .scaleEffect(isAnimating ? 1.05 : 1.0)
                    }
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                    
                    // App name
                    Text("Pindrop")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    // Tagline
                    Text("Local voice-to-text")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                // Loading indicator
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(AppColors.accent)
                    
                    Text(loadingText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .contentTransition(.numericText())
                }
                .padding(.bottom, AppTheme.Spacing.huge)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 500)
        .onAppear {
            isAnimating = true
            cycleLoadingMessages()
        }
    }
    
    private func cycleLoadingMessages() {
        Task {
            for message in loadingMessages {
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation(.easeInOut(duration: 0.3)) {
                    loadingText = message
                }
            }
        }
    }
}

// MARK: - Splash Window Controller

@MainActor
final class SplashWindowController {
    
    private var window: NSWindow?
    
    func show() {
        guard window == nil else { return }
        
        let splashView = SplashScreen()
        let hostingController = NSHostingController(rootView: splashView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.setContentSize(NSSize(width: 400, height: 500))
        window.center()
        
        // Add rounded corners
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = AppTheme.Radius.xl
        window.contentView?.layer?.masksToBounds = true
        
        // Add subtle shadow
        window.hasShadow = true
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    
    func dismiss(completion: (() -> Void)? = nil) {
        guard let window = window else {
            completion?()
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
            self.window = nil
            completion?()
        })
    }
}

// MARK: - Preview

#Preview("Splash Screen") {
    SplashScreen()
        .preferredColorScheme(.light)
}

#Preview("Splash Screen - Dark") {
    SplashScreen()
        .preferredColorScheme(.dark)
}
