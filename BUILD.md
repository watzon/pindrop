# Build Guide

Complete guide for building, testing, and distributing Pindrop.

## Prerequisites

### Required
- **Xcode 15+** with Command Line Tools
- **macOS 14+** (Sonoma or later)
- **just** - Command runner (`brew install just`)
- **JDK 21+** for the shared Kotlin Multiplatform build (`brew install openjdk@21`)
- **Active developer directory set to full Xcode** (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)

### Optional (for distribution)
- **create-dmg** - DMG creation (`brew install create-dmg`)
- **Apple Developer Account** - Required for the default signed release/export workflow and notarization
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

`just build` uses Xcode-managed signing. If you do not have a signing certificate configured, use `just build-unsigned` instead.

If the shared Kotlin build cannot find Java, make sure the Homebrew JDK is available in the same shell:

```bash
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

## Build Commands

### Development

```bash
just build              # Debug build with signing
just build-unsigned     # Debug build without signing
just test               # Run test suite
just test-coverage      # Run tests with coverage
just dev                # Clean + build + test
just build-unsigned     # Debug build without signing (CI/fallback)
```

### Release

```bash
just build-release      # Release build
just export-app         # Archive + export Developer ID-signed app
just dmg                # Export signed app + create DMG
just dmg-self-signed    # Fallback self-signed DMG (only if Apple signing is unavailable)
just appcast dist/Pindrop.dmg   # Generate appcast.xml for DMG
just release-notes 1.9.0        # Create draft release notes file
just release 1.9.0      # Manual GitHub release workflow (local)
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

For creating a local Release build with Xcode-managed signing:

```bash
just build-release
```

Output: `DerivedData/Build/Products/Release/Pindrop.app`

### 3. Export Signed App

For a public Developer ID-signed app bundle:

```bash
just export-app
```

This runs:
1. `archive` - Create an Xcode archive
2. `xcodebuild -exportArchive` - Export a Developer ID-signed app with automatic signing

Output: `DerivedData/Build/Products/Release/Pindrop.app`

### 4. DMG Creation

For distribution to users:

```bash
just dmg
```

This runs:
1. `export-app` - Export Developer ID-signed app
2. `create-dmg.sh` - Package into DMG

Output: `dist/Pindrop.dmg`

### 5. Manual GitHub Release

For maintainer releases (local machine, not CI):

```bash
just release 1.9.0
```

This runs:
1. Ensure contextual release notes exist (`release-notes/vX.Y.Z.md`)
2. Bump version/build in `project.pbxproj` (if needed)
3. Commit version bump (if needed)
4. `just test`
5. `just dmg`
6. `just appcast dist/Pindrop.dmg`
7. Create and push tag (`vX.Y.Z`)
8. Create GitHub release with notes + DMG + `appcast.xml` via `gh`

Optional notarization/stapling for signed distribution:
```bash
just notarize dist/Pindrop.dmg
just staple dist/Pindrop.dmg
```

## Code Signing

### Setup

1. Sign into Xcode with your Apple Developer account and enable automatic signing for the `Pindrop` target.

2. Verify signing identities:
```bash
security find-identity -v -p codesigning
```

`just export-app` uses `scripts/ExportOptions.plist` with `method=developer-id` and automatic signing, so it defaults to the team used for the archive.

### Sign App Bundle

```bash
just sign
```

Use this only for manual re-signing; the default release flow goes through `just export-app` / `just dmg`.

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
2. `build-unsigned` (Debug)
3. `test-unsigned`
4. `build-release-unsigned`

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
just export-app
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
├── DerivedData/            # Local build + export output
│   └── Build/Products/Release/Pindrop.app
├── dist/                   # Distribution files
│   └── Pindrop.dmg
├── scripts/                # Build scripts
│   ├── create-dmg.sh
│   ├── create-dmg-self-signed.sh
│   ├── sign-app-bundle.sh
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
