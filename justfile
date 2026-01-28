# Pindrop Build System
# Requires: Xcode, create-dmg (brew install create-dmg)

# Default recipe - show available commands
default:
    @just --list

# Variables
app_name := "Pindrop"
scheme := "Pindrop"
build_dir := "DerivedData/Build/Products"
release_dir := build_dir / "Release"
app_bundle := release_dir / app_name + ".app"
dmg_dir := "dist"

# Build configuration
xcode_project := "Pindrop.xcodeproj"

# Clean all build artifacts
clean:
    @echo "🧹 Cleaning build artifacts..."
    rm -rf {{build_dir}}
    rm -rf {{dmg_dir}}
    rm -rf DerivedData
    @echo "✅ Clean complete"

# Build for development (Debug)
build:
    @echo "🔨 Building {{app_name}} (Debug)..."
    xcodebuild \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Debug \
        -derivedDataPath DerivedData \
        build
    @echo "✅ Debug build complete"

# Build for release
build-release:
    @echo "🔨 Building {{app_name}} (Release)..."
    xcodebuild \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -derivedDataPath DerivedData \
        build
    @echo "✅ Release build complete"
    @echo "📦 App bundle: DerivedData/Build/Products/Release/{{app_name}}.app"

# Self-signed build (no developer account needed)
build-self-signed:
    @echo "🔨 Building {{app_name}} (Release)..."
    xcodebuild -scheme {{scheme}} -configuration Release -derivedDataPath DerivedData build
    @echo "✅ Self-signed build complete"

# Self-signed DMG (no developer account needed)
dmg-self-signed: build-self-signed
    @echo "📦 Creating self-signed DMG..."
    @./scripts/create-dmg-self-signed.sh
    @echo "✅ Self-signed DMG created in {{dmg_dir}}/"

# Run the app in Xcode
run:
    @echo "🚀 Running {{app_name}}..."
    open -a Xcode {{xcode_project}}
    # Note: Press Cmd+R in Xcode to run

# Run tests
test:
    @echo "🧪 Running tests..."
    xcodebuild test \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -destination 'platform=macOS'
    @echo "✅ Tests complete"

# Run tests with coverage
test-coverage:
    @echo "🧪 Running tests with coverage..."
    xcodebuild test \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -destination 'platform=macOS' \
        -enableCodeCoverage YES
    @echo "✅ Tests with coverage complete"

# Type check only (no build)
typecheck:
    @echo "🔍 Type checking..."
    xcodebuild \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Debug \
        -derivedDataPath DerivedData \
        -dry-run \
        build
    @echo "✅ Type check complete"

# Create DMG for distribution
dmg: build-release
    @echo "📦 Creating DMG..."
    @./scripts/create-dmg.sh
    @echo "✅ DMG created in {{dmg_dir}}/"

# Quick DMG (assumes release build exists)
dmg-quick:
    @echo "📦 Creating DMG (skipping build)..."
    @./scripts/create-dmg.sh
    @echo "✅ DMG created in {{dmg_dir}}/"

# Archive for App Store / Notarization
archive:
    @echo "📦 Creating archive..."
    xcodebuild archive \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -archivePath {{build_dir}}/{{app_name}}.xcarchive
    @echo "✅ Archive created: {{build_dir}}/{{app_name}}.xcarchive"

# Export archive to .app
export-app: archive
    @echo "📤 Exporting app..."
    xcodebuild -exportArchive \
        -archivePath {{build_dir}}/{{app_name}}.xcarchive \
        -exportPath {{release_dir}} \
        -exportOptionsPlist scripts/ExportOptions.plist
    @echo "✅ App exported to {{release_dir}}"

# Sign the app bundle (requires Developer ID certificate)
sign:
    @echo "✍️  Signing app bundle..."
    codesign --force --deep --sign "Developer ID Application" {{app_bundle}}
    @echo "✅ App signed"

# Verify code signature
verify-signature:
    @echo "🔍 Verifying signature..."
    codesign --verify --deep --strict --verbose=2 {{app_bundle}}
    spctl --assess --type execute --verbose=2 {{app_bundle}}
    @echo "✅ Signature verified"

# Notarize the DMG (requires Apple Developer account)
notarize dmg_path:
    @echo "📝 Notarizing {{dmg_path}}..."
    xcrun notarytool submit {{dmg_path}} \
        --keychain-profile "notarytool-password" \
        --wait
    @echo "✅ Notarization complete"

# Staple notarization ticket to DMG
staple dmg_path:
    @echo "📎 Stapling notarization ticket..."
    xcrun stapler staple {{dmg_path}}
    @echo "✅ Stapling complete"

# Full release workflow: build, sign, DMG, notarize
release: clean build-release sign dmg
    @echo "🎉 Release build complete!"
    @echo "📦 DMG: {{dmg_dir}}/{{app_name}}.dmg"
    @echo ""
    @echo "Next steps:"
    @echo "  1. Test the DMG on a clean Mac"
    @echo "  2. Notarize: just notarize {{dmg_dir}}/{{app_name}}.dmg"
    @echo "  3. Staple: just staple {{dmg_dir}}/{{app_name}}.dmg"

# Install dependencies (if any)
deps:
    @echo "📦 Installing dependencies..."
    @echo "✅ No external dependencies to install (WhisperKit is via SPM)"

# Open project in Xcode
xcode:
    @echo "🔧 Opening Xcode..."
    open {{xcode_project}}

# Show build settings
show-settings:
    @echo "⚙️  Build settings:"
    xcodebuild -project {{xcode_project}} -scheme {{scheme}} -showBuildSettings

# Show version info
version:
    @echo "📋 Version info:"
    @agvtool what-version
    @agvtool what-marketing-version

# Bump version (patch)
bump-patch:
    @echo "⬆️  Bumping patch version..."
    @agvtool next-version -all
    @just version

# Bump version (minor) - requires manual edit
bump-minor:
    @echo "⬆️  Bumping minor version..."
    @echo "Please update MARKETING_VERSION in project settings"
    @just xcode

# Lint Swift code (requires SwiftLint)
lint:
    @echo "🔍 Linting Swift code..."
    @if command -v swiftlint >/dev/null 2>&1; then \
        swiftlint; \
    else \
        echo "⚠️  SwiftLint not installed. Run: brew install swiftlint"; \
    fi

# Format Swift code (requires SwiftFormat)
format:
    @echo "✨ Formatting Swift code..."
    @if command -v swiftformat >/dev/null 2>&1; then \
        swiftformat .; \
    else \
        echo "⚠️  SwiftFormat not installed. Run: brew install swiftformat"; \
    fi

# Check for required tools
check-tools:
    @echo "🔧 Checking required tools..."
    @command -v xcodebuild >/dev/null 2>&1 || echo "❌ xcodebuild not found"
    @command -v create-dmg >/dev/null 2>&1 || echo "⚠️  create-dmg not found (brew install create-dmg)"
    @command -v swiftlint >/dev/null 2>&1 || echo "ℹ️  swiftlint not found (optional: brew install swiftlint)"
    @command -v swiftformat >/dev/null 2>&1 || echo "ℹ️  swiftformat not found (optional: brew install swiftformat)"
    @echo "✅ Tool check complete"

# Show app info
info:
    @echo "📱 {{app_name}} Info:"
    @echo "  Project: {{xcode_project}}"
    @echo "  Scheme: {{scheme}}"
    @echo "  Build Dir: {{build_dir}}"
    @echo "  Release Dir: {{release_dir}}"
    @echo "  App Bundle: {{app_bundle}}"
    @echo "  DMG Dir: {{dmg_dir}}"

# Development workflow: clean, build, test
dev: clean build test
    @echo "✅ Development build and test complete"

# CI workflow: clean, build, test, build-release
ci: clean build test build-release
    @echo "✅ CI workflow complete"
