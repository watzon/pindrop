# Build Scripts

This directory contains scripts for building and packaging Pindrop.

## Scripts

### `create-dmg.sh`

Creates a distributable DMG file for macOS.

**Requirements:**
- `create-dmg` (install via `brew install create-dmg`)
- Release build of Pindrop.app in `build/Release/`

**Usage:**
```bash
./scripts/create-dmg.sh
```

Or use the justfile:
```bash
just dmg
```

**Output:**
- DMG file in `dist/Pindrop.dmg`

### `download-icons.sh`

Downloads icon assets for the application.

**Usage:**
```bash
./scripts/download-icons.sh
```

### `ExportOptions.plist`

Configuration file for Xcode archive exports. Used when creating signed builds for distribution.

**Setup:**
1. Replace `YOUR_TEAM_ID` with your Apple Developer Team ID
2. Update signing certificate if needed

## Build Workflow

### Development Build

```bash
just build
```

### Release Build

```bash
just build-release
```

### Create DMG

```bash
just dmg
```

### Full Release (with signing)

```bash
just release
```

This will:
1. Clean build artifacts
2. Build release version
3. Sign the app bundle
4. Create DMG

### Notarization (requires Apple Developer account)

```bash
just notarize dist/Pindrop.dmg
just staple dist/Pindrop.dmg
```

## Directory Structure

```
scripts/
├── README.md              # This file
├── create-dmg.sh          # DMG creation script
├── download-icons.sh      # Icon download script
└── ExportOptions.plist    # Xcode export configuration
```

## Notes

- All scripts should be executable (`chmod +x script.sh`)
- DMG creation requires a successful release build first
- Notarization requires an Apple Developer account and proper credentials
