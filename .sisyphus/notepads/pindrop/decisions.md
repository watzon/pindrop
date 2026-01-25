# Architectural Decisions - Pindrop

## Technology Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI for windows, AppKit for status bar
- **Database**: SwiftData (macOS 14+)
- **STT Engine**: WhisperKit (Core ML optimized)
- **Hotkeys**: Carbon Event API
- **Audio**: AVAudioEngine (16kHz mono 16-bit PCM)

## Key Decisions
- macOS 14+ only (Sonoma) - no backward compatibility
- Apple Silicon optimized
- Privacy-first: local by default, cloud optional
- Menu bar only app (LSUIElement = YES)
