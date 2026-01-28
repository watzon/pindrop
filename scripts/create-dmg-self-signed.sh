#!/bin/bash
set -e

APP_NAME="Pindrop"
APP_BUNDLE="DerivedData/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DIST_DIR="dist"
BACKGROUND_IMG="assets/images/dmg-background.png"

# Create dist directory
mkdir -p "${DIST_DIR}"

# Check if background image exists
if [ ! -f "${BACKGROUND_IMG}" ]; then
    echo "⚠️  Warning: ${BACKGROUND_IMG} not found, creating DMG without custom background"
    create-dmg \
      --volname "${APP_NAME}" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --app-drop-link 450 185 \
      "${DIST_DIR}/${DMG_NAME}" \
      "${APP_BUNDLE}"
else
    # Create DMG with custom background
    # Background image: 800x400 pixels (standard DMG size)
    # Window size must match background image dimensions
    # Pindrop app position: left box center ~200,185
    # Applications shortcut position: right box center ~600,185
    create-dmg \
      --volname "${APP_NAME}" \
      --window-pos 200 120 \
      --window-size 800 400 \
      --background "${BACKGROUND_IMG}" \
      --icon-size 100 \
      --icon "${APP_NAME}.app" 200 185 \
      --app-drop-link 600 185 \
      "${DIST_DIR}/${DMG_NAME}" \
      "${APP_BUNDLE}"
fi

echo "✅ Self-signed DMG created: ${DIST_DIR}/${DMG_NAME}"
echo "⚠️  Users will see Gatekeeper warning - they must approve in System Settings"
