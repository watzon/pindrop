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
    xcodebuild -scheme {{scheme}} -configuration Release -derivedDataPath DerivedData \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
        build
    @echo "🔏 Re-signing with adhoc identity (required for macOS TCC permissions)..."
    codesign --force --deep --sign - {{app_bundle}}
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
        -testPlan Unit \
        -destination 'platform=macOS'
    @echo "✅ Tests complete"

# Run integration tests only (opt-in)
test-integration:
    @echo "🧪 Running integration tests..."
    xcodebuild test \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -testPlan Integration \
        -destination 'platform=macOS'
    @echo "✅ Integration tests complete"

# Run unit + integration suites
test-all: test test-integration
    @echo "✅ All test suites complete"

# Run tests with coverage
test-coverage:
    @echo "🧪 Running tests with coverage..."
    xcodebuild test \
        -project {{xcode_project}} \
        -scheme {{scheme}} \
        -testPlan Unit \
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

# Full local release workflow: build, sign, DMG, notarize
release-local: clean build-release sign dmg
	@echo "🎉 Release build complete!"
	@echo "📦 DMG: {{dmg_dir}}/{{app_name}}.dmg"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Test the DMG on a clean Mac"
	@echo "  2. Notarize: just notarize {{dmg_dir}}/{{app_name}}.dmg"
	@echo "  3. Staple: just staple {{dmg_dir}}/{{app_name}}.dmg"

# Manual GitHub release workflow
# Usage: just release 1.9.0
# Runs locally: tests -> self-signed DMG -> appcast -> tag -> push tag -> gh release create
release version:
	#!/usr/bin/env bash
	set -euo pipefail
	
	VERSION="{{version}}"
	TAG="v${VERSION}"
	DMG_PATH="{{dmg_dir}}/{{app_name}}.dmg"
	APPCAST_PATH="appcast.xml"
	
	# Validate version format (X.Y.Z)
	if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "❌ Invalid version format: $VERSION"
		echo "   Expected format: X.Y.Z (e.g., 1.9.0)"
		exit 1
	fi
	
	echo "🚀 Releasing Pindrop ${TAG}"
	echo ""
	
	# Check for uncommitted changes
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "❌ You have uncommitted changes. Please commit or stash them first."
		exit 1
	fi

	# Ensure required tools are available
	for tool in just gh create-dmg; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "❌ Required tool not found: $tool"
			exit 1
		fi
	done

	# Ensure gh is authenticated
	if ! gh auth status -h github.com >/dev/null 2>&1; then
		echo "❌ GitHub CLI is not authenticated."
		echo "   Run: gh auth login"
		exit 1
	fi

	# Ensure tag does not already exist
	if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
		echo "❌ Tag already exists locally: ${TAG}"
		exit 1
	fi
	if git ls-remote --exit-code --tags origin "${TAG}" >/dev/null 2>&1; then
		echo "❌ Tag already exists on origin: ${TAG}"
		exit 1
	fi
	
	# Get current version
	CURRENT_VERSION=$(grep 'MARKETING_VERSION = ' Pindrop.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')
	CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION = ' Pindrop.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')
	NEXT_BUILD=$((CURRENT_BUILD + 1))
	echo "📋 Current version: ${CURRENT_VERSION}"
	echo "📋 Current build: ${CURRENT_BUILD}"
	echo "📋 New version: ${VERSION}"
	echo "📋 New build: ${NEXT_BUILD}"
	echo ""
	
	# Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.pbxproj
	echo "📝 Updating version and build number in Xcode project..."
	sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" Pindrop.xcodeproj/project.pbxproj
	sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEXT_BUILD};/g" Pindrop.xcodeproj/project.pbxproj
	
	# Verify the changes
	NEW_VERSION=$(grep 'MARKETING_VERSION = ' Pindrop.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')
	NEW_BUILD=$(grep 'CURRENT_PROJECT_VERSION = ' Pindrop.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')
	if [ "$NEW_VERSION" != "$VERSION" ]; then
		echo "❌ Failed to update version"
		exit 1
	fi
	if [ "$NEW_BUILD" != "$NEXT_BUILD" ]; then
		echo "❌ Failed to update build number"
		exit 1
	fi
	echo "✅ Version updated to ${VERSION} (build ${NEXT_BUILD})"
	
	# Commit the version bump
	echo "📦 Committing version bump..."
	git add Pindrop.xcodeproj/project.pbxproj
	git commit -m "chore: bump version to ${VERSION} (build ${NEXT_BUILD})"

	# Step 1: Ensure tests pass
	echo "🧪 Running test suite..."
	just test

	# Step 2: Build self-signed release DMG
	echo "📦 Building self-signed release DMG..."
	just dmg-self-signed

	# Step 3: Update appcast
	echo "📡 Generating appcast.xml..."
	just appcast "${DMG_PATH}"
	
	# Create annotated tag
	echo "🏷️  Creating tag ${TAG}..."
	git tag -a "${TAG}" -m "Release ${TAG}"
	
	# Push tag
	echo "🚀 Pushing tag to origin..."
	git push origin "${TAG}"

	# Create GitHub release and attach assets
	echo "📤 Creating GitHub release with DMG + appcast..."
	gh release create "${TAG}" "${DMG_PATH}" "${APPCAST_PATH}" \
		--title "Pindrop ${TAG}" \
		--generate-notes
	
	echo ""
	echo "✅ Release ${TAG} published!"
	echo ""
	echo "📋 Uploaded assets:"
	echo "  - ${DMG_PATH}"
	echo "  - ${APPCAST_PATH}"
	echo ""
	echo "ℹ️  Optional follow-up: push main when you're ready."

# Generate appcast.xml for Sparkle updates
# Usage: just appcast dist/Pindrop.dmg
appcast dmg_path:
	@echo "📡 Generating appcast.xml..."
	@if [ ! -f "{{dmg_path}}" ]; then \
		echo "❌ DMG not found: {{dmg_path}}"; \
		echo "   Run: just dmg"; \
		exit 1; \
	fi
	@if [ ! -d "bin" ] || [ ! -f "bin/generate_appcast" ]; then \
		echo "⚠️  Sparkle tools not found. Downloading..."; \
		curl -L -o /tmp/Sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"; \
		tar -xf /tmp/Sparkle.tar.xz -C /tmp; \
		mkdir -p bin; \
		cp /tmp/Sparkle-2.6.4/bin/generate_appcast bin/; \
		cp /tmp/Sparkle-2.6.4/bin/sign_update bin/ 2>/dev/null || true; \
		rm -rf /tmp/Sparkle.tar.xz /tmp/Sparkle-2.6.4; \
		echo "✅ Sparkle tools downloaded to bin/"; \
	fi
	@TAG_VERSION="v$$(grep 'MARKETING_VERSION = ' Pindrop.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/')"; \
	DOWNLOAD_PREFIX="https://github.com/watzon/pindrop/releases/download/$${TAG_VERSION}/"; \
	echo "🔏 Signing DMG and generating appcast for $${TAG_VERSION}..."; \
	echo "🔗 Download prefix: $${DOWNLOAD_PREFIX}"
	@mkdir -p updates
	@cp "{{dmg_path}}" updates/
	@if ./bin/generate_appcast --help 2>&1 | grep -q -- '--download-url-prefix'; then \
		./bin/generate_appcast --download-url-prefix "$${DOWNLOAD_PREFIX}" updates/; \
	else \
		echo "⚠️  generate_appcast does not support --download-url-prefix; generating without explicit URL prefix"; \
		./bin/generate_appcast updates/; \
	fi
	@rm -rf updates/
	@echo "✅ Appcast generated: appcast.xml"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Review appcast.xml"
	@echo "  2. Attach {{dmg_path}} and appcast.xml to the matching GitHub release tag"

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
