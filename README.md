# Pindrop 🎤

> The first 100% open source, truly Mac-native AI dictation app

![GitHub stars](https://img.shields.io/github/stars/watzon/pindrop?style=flat-square)
![GitHub license](https://img.shields.io/github/license/watzon/pindrop?style=flat-square)
![macOS](https://img.shields.io/badge/macOS-14.0+-blue?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square&logo=swift)

![Pindrop Screenshot](assets/images/screenshot.png)

**Pindrop** is a menu bar dictation app for macOS that turns your speech into text—completely offline, completely private. Built with pure Swift/SwiftUI, packaged with Xcode + SwiftPM, and powered by WhisperKit for optimal Apple Silicon performance.

[**Download Latest Release**](https://github.com/watzon/pindrop/releases) · [**Documentation**](#documentation) · [**Contributing**](#contributing) · [**Community**](#community)

---

## Features

### Dictation

- Pick from several local transcription engines: WhisperKit (OpenAI Whisper on Core ML, in sizes from tiny to large-v3), Parakeet, SenseVoice, or Apple's on-device speech stack. The model browser recommends options for your Mac.
- Streaming dictation shows words as you say them, powered by the Nemotron streaming engine (English only for now; Apple SpeechTranscriber is another option on macOS 26).
- Dictate in 16 languages. The interface is localized into 31 languages with RTL support.
- Offline speaker diarization with trainable speaker profiles. Single-speaker transcripts stay free of labels.
- Global hotkeys: toggle mode, push-to-talk, and a dedicated cancel shortcut.

### Working with transcripts

- Library with full-text search, inline editing, audio playback, and export to JSON, CSV, or plain text.
- Notes with pinning, tags, and interactive checklists.
- Custom dictionary for names and jargon that learns from your corrections and biases recognition toward your vocabulary.
- Optional AI enhancement cleans up transcripts using Apple Intelligence, Anthropic, OpenRouter, Ollama, or any OpenAI-compatible endpoint. Off by default, and API keys are stored in the Keychain. Prompt presets can be switched right from the menu bar.

### Fits into your setup

- Transcribe media files or web audio, with timestamps and speaker labels.
- A context engine rewrites spoken file paths into @mentions, and a built-in MCP server lets AI agents dictate, transcribe files, and query your library.
- Four floating indicator styles (Orb, Pill, Notch, Bubble), preset themes, and activity stats with streaks and trends.
- Pauses music and mutes system audio while you record so transcripts stay clean.
- Text lands in your clipboard every time, and directly at your cursor if you grant Accessibility permission.

## Built with

- [Swift](https://swift.org/) and [SwiftUI](https://developer.apple.com/swiftui/), with [SwiftData](https://developer.apple.com/documentation/swiftdata) for persistence
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax for Core ML Whisper inference
- [FluidAudio](https://github.com/FluidInference/FluidAudio) for Parakeet, SenseVoice, Nemotron streaming, and diarization
- [Sparkle](https://sparkle-project.org/) for updates

## Requirements

- macOS 14.0 (Sonoma) or later. A few features need newer releases: Apple SpeechTranscriber streaming and Apple Intelligence enhancement require macOS 26.
- Apple Silicon recommended. Intel Macs work, but transcription is slower.
- Microphone permission, required to record.
- Accessibility permission, optional. It enables direct text insertion and the context engine; clipboard output works without it.

## Installation

Releases are signed with a Developer ID and notarized by Apple, so Pindrop opens like any other Mac app.

1. Download `Pindrop.dmg` from the [releases page](https://github.com/watzon/pindrop/releases) or [pindrop.dev](https://pindrop.dev).
2. Open the DMG and drag Pindrop to Applications.
3. Launch it. Onboarding covers microphone permission, downloading a model (Tiny is about 75 MB and a good first pick), and setting your hotkey (Option+Space by default).

Pindrop runs in the menu bar only, so there is no dock icon. Look for the microphone in the top right of your screen.

## Usage

- Press the hotkey once to start recording, again to stop and transcribe. In push-to-talk mode, hold to record and release to transcribe. Both are configurable, along with the cancel shortcut, in Settings.
- Every transcript is copied to the clipboard. With Accessibility permission granted, it is also inserted at the cursor in the active app.
- Click the menu bar icon to open the main window: Home dashboard, Stats, Library, Notes, Dictionary, Models, and Settings.
- Transcripts are saved automatically. Search them in the Library, edit them in place, or export to JSON, CSV, or plain text.

## Privacy

Audio and transcripts are processed and stored on your Mac. Two optional programs live in Settings → Privacy, both off by default:

- Anonymous diagnostics via [TelemetryDeck](https://telemetrydeck.com): counts of app launches, transcription outcomes, and model download errors with bucketed timings. Never transcript text, audio, prompts, or file names.
- Training data contributions: keeps redacted before/after transcript pairs on your Mac (nothing is uploaded; there is no upload backend) to support a future on-device correction model. You can review, export, or delete every stored pair.

The full list of signals and stored fields is in [docs/TELEMETRY.md](docs/TELEMETRY.md).

## Building from source

```bash
git clone https://github.com/watzon/pindrop.git
cd pindrop
open Pindrop.xcodeproj   # then press Cmd+R
```

Or with [just](https://github.com/casey/just) (`brew install just`):

```bash
just build     # debug build
just test      # unit tests
just --list    # all recipes
```

[BUILD.md](BUILD.md) covers signing, exporting, and DMG packaging. [RELEASING.md](RELEASING.md) documents the maintainer release flow.

## Troubleshooting

- **No window or dock icon on launch**: Pindrop is a menu bar app on purpose. Look for the microphone icon in the menu bar.
- **Microphone permission denied**: enable Pindrop under System Settings → Privacy & Security → Microphone, then relaunch.
- **Text is not inserted at the cursor**: grant Accessibility under System Settings → Privacy & Security → Accessibility. Clipboard output works regardless.
- **Transcription is slow**: use a smaller Whisper model, or switch to Parakeet or SenseVoice.
- **Hotkey does nothing**: check for conflicts with other apps or macOS shortcuts, then record a new combination in Settings → Hotkeys.

## Project layout

```
Pindrop/
├── PindropApp.swift           # entry point and lifecycle
├── AppCoordinator.swift       # service wiring
├── Services/                  # audio, hotkeys, storage, settings, MCP, telemetry
├── Services/Transcription/    # engine protocol + WhisperKit, Parakeet, SenseVoice, Apple, Nemotron
├── Models/                    # SwiftData models and schema
├── UI/                        # main window, settings, onboarding, floating indicators
├── PindropTests/              # unit tests (Swift Testing)
└── PindropUITests/            # UI tests (XCTest)
```

## Running tests

```bash
just test          # unit tests
just test-ui       # UI tests
just test-all      # everything
```

## Community

- [GitHub Discussions](https://github.com/watzon/pindrop/discussions) for questions and ideas
- [GitHub Issues](https://github.com/watzon/pindrop/issues) for bugs and feature requests

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) and [OpenAI Whisper](https://github.com/openai/whisper)
- [FluidAudio](https://github.com/FluidInference/FluidAudio) by Fluid Inference
- [Sparkle](https://sparkle-project.org/)
