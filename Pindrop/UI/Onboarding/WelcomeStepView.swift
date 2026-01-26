//
//  WelcomeStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            appIcon
            
            VStack(spacing: 8) {
                Text("Welcome to Pindrop")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Local speech-to-text, right from your menu bar.\nFast, private, and always available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .opacity(textOpacity)
            
            VStack(spacing: 12) {
                featureRow(icon: .waveform, text: "Powered by WhisperKit")
                featureRow(icon: .shield, text: "100% local processing")
                featureRow(icon: .keyboard, text: "Global keyboard shortcuts")
            }
            .opacity(textOpacity)
            .padding(.vertical, 8)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .opacity(buttonOpacity)
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                buttonOpacity = 1.0
            }
        }
    }
    
    private var appIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
            
            IconView(icon: .waveform, size: 56)
                .foregroundStyle(.white)
        }
        .glassEffect(.regular.tint(.accentColor.opacity(0.2)))
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }
    
    private func featureRow(icon: Icon, text: String) -> some View {
        HStack(spacing: 12) {
            IconView(icon: icon, size: 16)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

#if DEBUG
struct WelcomeStepView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeStepView(onContinue: {})
            .frame(width: 800, height: 600)
    }
}
#endif
