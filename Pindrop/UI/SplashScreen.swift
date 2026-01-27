//
//  SplashScreen.swift
//  Pindrop
//
//  Splash screen shown during app initialization
//

import SwiftUI

// MARK: - Splash Screen State

@MainActor
final class SplashScreenState: ObservableObject {
    @Published var loadingText: String = "Initializing..."
    @Published var progress: Double?
    @Published var isDownloading: Bool = false
    
    func setLoading(_ text: String) {
        loadingText = text
        progress = nil
        isDownloading = false
    }
    
    func setDownloading(_ text: String) {
        loadingText = text
        progress = 0.0
        isDownloading = true
    }
    
    func updateProgress(_ value: Double) {
        progress = value
    }
    
    func hideProgress() {
        progress = nil
        isDownloading = false
    }
}

// MARK: - Splash Screen View

struct SplashScreen: View {
    
    @ObservedObject var state: SplashScreenState
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // App icon area
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isAnimating ? 1.3 : 1.0)
                            .opacity(isAnimating ? 0 : 0.6)
                        
                        Circle()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                            .opacity(isAnimating ? 0 : 0.8)
                        
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .scaleEffect(isAnimating ? 1.05 : 1.0)
                    }
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                    
                    // App name
                    Text("Pindrop")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Tagline
                    Text("Local voice-to-text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Loading indicator
                VStack(spacing: 12) {
                    if state.isDownloading, let progress = state.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    
                    Text(state.loadingText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 500)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Splash Window Controller

@MainActor
final class SplashWindowController {
    
    private var window: NSWindow?
    private var hostingController: NSHostingController<SplashScreen>?
    let state: SplashScreenState
    
    init(state: SplashScreenState) {
        self.state = state
    }
    
    func show() {
        guard window == nil else { return }
        
        let splashView = SplashScreen(state: state)
        let hostingController = NSHostingController(rootView: splashView)
        self.hostingController = hostingController
        
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.setContentSize(NSSize(width: 400, height: 500))
        window.center()
        
        // Add rounded corners
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
        
        // Add subtle shadow
        window.hasShadow = true
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    
    func setLoading(_ text: String) {
        state.setLoading(text)
    }
    
    func setDownloading(_ text: String) {
        state.setDownloading(text)
    }
    
    func updateProgress(_ value: Double) {
        state.updateProgress(value)
    }
    
    func hideProgress() {
        state.hideProgress()
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
            self.hostingController = nil
            completion?()
        })
    }
}

// MARK: - Previews

#Preview("Splash Screen") {
    SplashScreen(state: SplashScreenState())
}
