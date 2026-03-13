# Build Scripts

This directory contains scripts for building and packaging Pindrop.

## Scripts

### `create-dmg.sh`

Creates a distributable DMG file for macOS.

**Requirements:**
- `create-dmg` (install via `brew install create-dmg`)
- Signed export of `Pindrop.app` in `DerivedData/Build/Products/Release/`

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
1. Sign into Xcode with your Apple Developer account
2. Enable automatic signing for the `Pindrop` target
3. Ensure a Developer ID Application certificate is available for export

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

### Manual GitHub Release

```bash
just release 1.9.0
```

This will:
1. Create/edit contextual release notes (`release-notes/vX.Y.Z.md`)
2. Bump version/build and commit the change (if needed)
3. Run tests
4. Build signed release DMG
5. Generate `appcast.xml`
6. Create and push tag
7. Create GitHub release using `gh` with notes + DMG + `appcast.xml`

### Notarization (requires Apple Developer account)

```bash
just notarize dist/Pindrop.dmg
just staple dist/Pindrop.dmg
```

## Directory Structure

```
scripts/
├── README.md                   # This file
├── create-dmg.sh               # Signed DMG creation script
├── create-dmg-self-signed.sh   # Fallback self-signed DMG script
├── sign-app-bundle.sh          # Manual/fallback bundle signing
├── download-icons.sh           # Icon download script
└── ExportOptions.plist         # Xcode export configuration
```

## Notes

- All scripts should be executable (`chmod +x script.sh`)
- `just dmg` expects `just export-app` semantics and packages the exported signed app
- `just dmg-self-signed` is retained only as a fallback path
- Notarization requires an Apple Developer account and proper credentials
