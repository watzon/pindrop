#!/bin/sh

set -eu

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SHARED_DIR="$SRCROOT/shared"
CORE_INFO_PLIST="$SHARED_DIR/core/build/XCFrameworks/release/PindropSharedCore.xcframework/Info.plist"
TRANSCRIPTION_INFO_PLIST="$SHARED_DIR/feature-transcription/build/XCFrameworks/release/PindropSharedTranscription.xcframework/Info.plist"
BUILD_STAMP="$SHARED_DIR/build/xcode-shared-frameworks.stamp"

needs_build=0

if [ ! -f "$CORE_INFO_PLIST" ] || [ ! -f "$TRANSCRIPTION_INFO_PLIST" ] || [ ! -f "$BUILD_STAMP" ]; then
    needs_build=1
fi

if [ "$needs_build" -eq 0 ]; then
    newest_shared_input=$(
        find "$SHARED_DIR" \
            \( -type d -name .gradle -o -type d -name build \) -prune \
            -o \
            \( -name '*.kts' -o -name '*.kt' -o -name '*.properties' -o -name 'gradlew' -o -name '*.swift' \) \
            -type f -print0 |
            xargs -0 stat -f '%m %N' |
            sort -nr |
            head -n 1 |
            cut -d' ' -f1
    )

    build_stamp_mtime=$(stat -f '%m' "$BUILD_STAMP")

    if [ "${newest_shared_input:-0}" -gt "$build_stamp_mtime" ]; then
        needs_build=1
    fi
fi

if [ "$needs_build" -eq 0 ]; then
    echo "Shared Kotlin frameworks are up to date; skipping Gradle."
    exit 0
fi

echo "Building shared Kotlin frameworks..."
cd "$SHARED_DIR"
"$SHARED_DIR/gradlew" --no-daemon --console=plain -p "$SHARED_DIR" \
    :core:assemblePindropSharedCoreXCFramework \
    :feature-transcription:assemblePindropSharedTranscriptionXCFramework
mkdir -p "$(dirname "$BUILD_STAMP")"
touch "$BUILD_STAMP"
