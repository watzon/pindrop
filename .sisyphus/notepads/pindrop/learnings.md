# Learnings - Pindrop

## Conventions

(To be populated as we discover patterns)

## Patterns

(To be populated with code patterns)

## Xcode Project Initialization (2026-01-25)

### Manual Project Creation
- Created Xcode project manually without xcodegen (not installed)
- Used proper UUID-based object IDs (24-character hex strings) for all PBX objects
- Critical: XCBuildConfiguration objects must NOT have a `group` property - this causes "unrecognized selector" errors

### Project Structure
```
Pindrop.xcodeproj/
├── project.pbxproj                    # Main project file with PBX objects
├── project.xcworkspace/
│   ├── contents.xcworkspacedata       # Workspace definition
│   └── xcshareddata/swiftpm/          # Swift Package Manager cache
└── xcshareddata/xcschemes/
    └── Pindrop.xcscheme               # Shared build scheme
```

### WhisperKit Integration
- Added as XCRemoteSwiftPackageReference in project.pbxproj
- Minimum version: 0.9.0 (upToNextMajorVersion)
- Repository: https://github.com/argmaxinc/WhisperKit.git
- Package resolution happens on first `xcodebuild -list` (can take time)

### Menu Bar App Configuration
- Set `LSUIElement = YES` in Info.plist to hide dock icon
- Configured entitlements for:
  - App Sandbox (com.apple.security.app-sandbox)
  - Microphone access (com.apple.security.device.audio-input)
  - User-selected file read/write (com.apple.security.files.user-selected.read-write)

### Build Settings
- Deployment target: macOS 14.0 (MACOSX_DEPLOYMENT_TARGET)
- Bundle identifier: com.pindrop.app
- Swift version: 5.0
- SwiftUI previews enabled (ENABLE_PREVIEWS = YES)
- Asset catalog compiler configured for AppIcon and AccentColor

### Gotchas
- LSP errors about @main and ContentView are false positives when project context isn't loaded
- xcodebuild timeout during package resolution is normal for first run
- Standard Xcode file headers (comments) are conventional and should be kept
