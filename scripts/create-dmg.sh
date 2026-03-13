#!/bin/bash
set -e

# Pindrop DMG Creation Script
# Creates a distributable DMG with custom background and layout

# Configuration
APP_NAME="Pindrop"
APP_BUNDLE="DerivedData/Build/Products/Release/${APP_NAME}.app"
DMG_DIR="dist"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${DMG_DIR}/${DMG_NAME}"
VOLUME_NAME="${APP_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}❌ Error: App bundle not found at $APP_BUNDLE${NC}"
    echo -e "${YELLOW}💡 Run 'just build-release' first${NC}"
    exit 1
fi

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo -e "${RED}❌ Error: create-dmg not found${NC}"
    echo -e "${YELLOW}💡 Install with: brew install create-dmg${NC}"
    exit 1
fi

# Create dist directory
mkdir -p "$DMG_DIR"

# Remove old DMG if it exists
if [ -f "$DMG_PATH" ]; then
    echo -e "${YELLOW}🗑️  Removing old DMG...${NC}"
    rm "$DMG_PATH"
fi

# Get version from app bundle
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_BUNDLE}/Contents/Info.plist")

echo -e "${GREEN}📦 Creating DMG for ${APP_NAME} v${VERSION} (${BUILD})${NC}"

# Create DMG with create-dmg
# Documentation: https://github.com/create-dmg/create-dmg
create-dmg \
    --volname "${VOLUME_NAME}" \
    --volicon "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 150 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${APP_BUNDLE}"

# Check if DMG was created successfully
if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo -e "${GREEN}✅ DMG created successfully!${NC}"
    echo -e "${GREEN}📦 Location: ${DMG_PATH}${NC}"
    echo -e "${GREEN}📏 Size: ${DMG_SIZE}${NC}"
    echo -e "${GREEN}🏷️  Version: ${VERSION} (${BUILD})${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Test the DMG on a clean Mac"
    echo "  2. Notarize: just notarize '${DMG_PATH}'"
    echo "  3. Staple: just staple '${DMG_PATH}'"
else
    echo -e "${RED}❌ Error: DMG creation failed${NC}"
    exit 1
fi
