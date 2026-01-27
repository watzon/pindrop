# Build Guide

Complete guide for building, testing, and distributing Pindrop.

## Prerequisites

### Required
- **Xcode 15+** with Command Line Tools
- **macOS 14+** (Sonoma or later)
- **just** - Command runner (`brew install just`)

### Optional (for distribution)
- **create-dmg** - DMG creation (`brew install create-dmg`)
- **Apple Developer Account** - For code signing and notarization
- **swiftlint** - Code linting (`brew install swiftlint`)
- **swiftformat** - Code formatting (`brew install swiftformat`)

Check installed tools:
```bash
just check-tools
```

## Quick Start

```bash
just build
just test
just run
```

## Build Commands

### Development

```bash
just build              # Debug build
just test               # Run test suite
just test-coverage      # Run tests with coverage
just dev                # Clean + build + test
```

### Release

```bash
just build-release      # Release build
just dmg                # Build + create DMG
just release            # Full release workflow
```

### Maintenance

```bash
just clean              # Remove build artifacts
just lint               # Lint Swift code
just format             # Format Swift code
```

## Build Workflows

### 1. Development Build

For local testing and development:

```bash
just dev
```

This runs:
1. `clean` - Remove old artifacts
2. `build` - Debug build
3. `test` - Run test suite

### 2. Release Build

For creating a distributable app:

```bash
just build-release
```

Output: `build/Release/Pindrop.app`

### 3. DMG Creation

For distribution to users:

```bash
just dmg
```

This runs:
1. `build-release` - Create release build
2. `create-dmg.sh` - Package into DMG

Output: `dist/Pindrop.dmg`

### 4. Full Release (Signed)

For App Store or notarized distribution:

```bash
just release
```

This runs:
1. `clean` - Remove old artifacts
2. `build-release` - Create release build
3. `sign` - Code sign the app
4. `dmg` - Create DMG

Then manually:
```bash
just notarize dist/Pindrop.dmg
just staple dist/Pindrop.dmg
```

## Code Signing

### Setup

1. Get your Team ID:
```bash
security find-identity -v -p codesigning
```

2. Update `scripts/ExportOptions.plist`:
```xml
<key>teamID</key>
<string>YOUR_TEAM_ID</string>
```

### Sign App Bundle

```bash
just sign
```

### Verify Signature

```bash
just verify-signature
```

## Notarization

### Setup

1. Create app-specific password at [appleid.apple.com](https://appleid.apple.com)

2. Store credentials:
```bash
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

### Notarize DMG

```bash
just notarize dist/Pindrop.dmg
```

### Staple Ticket

```bash
just staple dist/Pindrop.dmg
```

## Version Management

### Show Current Version

```bash
just version
```

### Bump Version

```bash
just bump-patch        # 1.0.0 → 1.0.1
just bump-minor        # Manual: 1.0.0 → 1.1.0
```

## Testing

### Run All Tests

```bash
just test
```

### Run with Coverage

```bash
just test-coverage
```

### Manual Testing

```bash
xcodebuild test \
  -project Pindrop.xcodeproj \
  -scheme Pindrop \
  -destination 'platform=macOS'
```

## CI/CD

### GitHub Actions Example

```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install just
        run: brew install just
      - name: Run CI workflow
        run: just ci
```

The `just ci` command runs:
1. `clean`
2. `build` (Debug)
3. `test`
4. `build-release`

## Troubleshooting

### Build Fails

```bash
just clean
just build
```

### Tests Fail

```bash
just clean
just test
```

### DMG Creation Fails

Check requirements:
```bash
brew install create-dmg
just build-release
just dmg-quick
```

### Code Signing Fails

Verify certificate:
```bash
security find-identity -v -p codesigning
```

### Notarization Fails

Check credentials:
```bash
xcrun notarytool history --keychain-profile "notarytool-password"
```

## Directory Structure

```
pindrop/
├── build/                  # Build output
│   └── Release/
│       └── Pindrop.app
├── dist/                   # Distribution files
│   └── Pindrop.dmg
├── scripts/                # Build scripts
│   ├── create-dmg.sh
│   └── ExportOptions.plist
├── justfile                # Build commands
└── Pindrop.xcodeproj       # Xcode project
```

## Advanced Usage

### Custom Build Settings

```bash
just show-settings
```

### Archive for App Store

```bash
just archive
just export-app
```

### Open in Xcode

```bash
just xcode
```

## Tips

1. **Use `just` for everything** - Consistent, documented commands
2. **Run tests before committing** - `just test`
3. **Clean before release builds** - `just clean build-release`
4. **Verify signatures** - `just verify-signature`
5. **Test DMG on clean Mac** - Before distribution

## Resources

- [just documentation](https://github.com/casey/just)
- [create-dmg documentation](https://github.com/create-dmg/create-dmg)
- [Apple Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Xcode Build Settings Reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
