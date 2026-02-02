# Releasing Pindrop

This document describes the release process for Pindrop, including code signing and update distribution via Sparkle.

## EdDSA Signing Keys

Pindrop uses [Sparkle](https://sparkle-project.org/) for automatic updates. Updates are signed using EdDSA (Ed25519) for security.

### Key Storage

- **Public Key**: Embedded in `Pindrop/Info.plist` as `SUPublicEDKey`
- **Private Key**: Stored securely in the macOS Keychain (automatically managed by Sparkle)

**IMPORTANT**: The private key is NEVER committed to the repository. It is stored only in the macOS Keychain of the machine that generated it.

### Current Public Key

```
TCU0MwULuIK6y0ubIossVr+61PGh/wHZfFrRFc9F2Is=
```

This key is already configured in `Pindrop/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>TCU0MwULuIK6y0ubIossVr+61PGh/wHZfFrRFc9F2Is=</string>
```

### Generating New Keys (if needed)

If you need to regenerate the signing keys (e.g., if the private key is lost):

1. Download the Sparkle release:
   ```bash
   curl -L -o Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"
   tar -xf Sparkle.tar.xz
   ```

2. Run the key generator:
   ```bash
   ./bin/generate_keys
   ```

3. The tool will:
   - Generate a new EdDSA keypair
   - Store the private key in your macOS Keychain
   - Output the public key to stdout

4. Update `Pindrop/Info.plist` with the new public key:
   ```xml
   <key>SUPublicEDKey</key>
   <string>YOUR_NEW_PUBLIC_KEY_HERE</string>
   ```

5. **CRITICAL**: Users with older versions will NOT be able to update to versions signed with the new key. This should only be done for major releases or security incidents.

## Release Process

### Prerequisites

- macOS development machine with the private key in Keychain
- Xcode installed
- `just` command runner: `brew install just`

### Steps

1. **Update version numbers** in Xcode project settings

2. **Build and sign the release**:
   ```bash
   just release
   ```
   This will:
   - Clean build artifacts
   - Build the release version
   - Sign the app with your Developer ID
   - Create a DMG in `dist/Pindrop.dmg`

3. **Generate appcast** (for Sparkle updates):
   ```bash
   ./bin/generate_appcast /path/to/your/updates/
   ```

4. **Upload the release**:
   - Upload `dist/Pindrop.dmg` to GitHub Releases
   - Upload the `appcast.xml` to the repository (or your hosting)

5. **Tag the release**:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

## Security Notes

- Never share the private key
- Never commit the private key to version control
- The private key is tied to your Mac's Keychain and cannot be exported easily
- If you lose the private key, you will need to generate new keys and users will need to manually download updates

## Troubleshooting

### "Update is improperly signed" error

This means the update was signed with a different key than what's in the app's `Info.plist`. Ensure:
1. You're using the correct private key (check Keychain)
2. The public key in `Info.plist` matches the private key used for signing

### Lost private key

If you've lost the private key:
1. Generate new keys using `generate_keys`
2. Update `Info.plist` with the new public key
3. Notify users they'll need to manually download the update
4. Future updates will work normally with the new key
