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
            .buttonStyle(.borderedProminent)
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
                .stroke(AppColors.accent.opacity(0.2), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(logoScale == 1.0 ? 1.3 : 1.0)
                .opacity(logoScale == 1.0 ? 0 : 0.6)
            
            Circle()
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                .frame(width: 100, height: 100)
                .scaleEffect(logoScale == 1.0 ? 1.2 : 1.0)
                .opacity(logoScale == 1.0 ? 0 : 0.8)
            
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: 80, height: 80)
            
            Image("PindropIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(AppColors.accent)
        }
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: logoScale)
        .opacity(logoOpacity)
    }
    
    private func featureRow(icon: Icon, text: String) -> some View {
        HStack(spacing: 12) {
            IconView(icon: icon, size: 16)
                .foregroundStyle(AppColors.accent)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: Capsule())
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
