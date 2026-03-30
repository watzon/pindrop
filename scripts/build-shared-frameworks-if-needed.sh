#!/bin/sh

set -eu

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SHARED_DIR="$SRCROOT/shared"
FORCE_SHARED_FRAMEWORK_BUILD="${FORCE_SHARED_FRAMEWORK_BUILD:-0}"
CORE_INFO_PLIST="$SHARED_DIR/core/build/XCFrameworks/release/PindropSharedCore.xcframework/Info.plist"
TRANSCRIPTION_INFO_PLIST="$SHARED_DIR/feature-transcription/build/XCFrameworks/release/PindropSharedTranscription.xcframework/Info.plist"
UI_THEME_INFO_PLIST="$SHARED_DIR/ui-theme/build/XCFrameworks/release/PindropSharedUITheme.xcframework/Info.plist"
UI_SHELL_INFO_PLIST="$SHARED_DIR/ui-shell/build/XCFrameworks/release/PindropSharedNavigation.xcframework/Info.plist"
UI_SETTINGS_INFO_PLIST="$SHARED_DIR/ui-settings/build/XCFrameworks/release/PindropSharedAISettings.xcframework/Info.plist"
UI_WORKSPACE_INFO_PLIST="$SHARED_DIR/ui-workspace/build/XCFrameworks/release/PindropSharedUIWorkspace.xcframework/Info.plist"
SETTINGS_SCHEMA_INFO_PLIST="$SHARED_DIR/settings-schema/build/XCFrameworks/release/PindropSharedSchema.xcframework/Info.plist"
UI_LOCALIZATION_INFO_PLIST="$SHARED_DIR/ui-localization/build/XCFrameworks/release/PindropSharedLocalization.xcframework/Info.plist"
BUILD_STAMP="$SHARED_DIR/build/xcode-shared-frameworks.stamp"

needs_build=0

cleanup_xcframework_outputs() {
    rm -rf \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/debug/PindropSharedShell.xcframework" \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/release/PindropSharedShell.xcframework" \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/debug/PindropSharedNavigation.xcframework" \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/release/PindropSharedNavigation.xcframework" \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/debug/PindropSharedUIShell.xcframework" \
        "$SHARED_DIR/ui-shell/build/XCFrameworks/release/PindropSharedUIShell.xcframework" \
        "$SHARED_DIR/ui-settings/build/XCFrameworks/debug/PindropSharedAISettings.xcframework" \
        "$SHARED_DIR/ui-settings/build/XCFrameworks/release/PindropSharedAISettings.xcframework" \
        "$SHARED_DIR/ui-settings/build/XCFrameworks/debug/PindropSharedUISettings.xcframework" \
        "$SHARED_DIR/ui-settings/build/XCFrameworks/release/PindropSharedUISettings.xcframework"
}

if [ ! -f "$CORE_INFO_PLIST" ] || [ ! -f "$TRANSCRIPTION_INFO_PLIST" ] || [ ! -f "$UI_THEME_INFO_PLIST" ] || [ ! -f "$UI_SHELL_INFO_PLIST" ] || [ ! -f "$UI_SETTINGS_INFO_PLIST" ] || [ ! -f "$UI_WORKSPACE_INFO_PLIST" ] || [ ! -f "$SETTINGS_SCHEMA_INFO_PLIST" ] || [ ! -f "$UI_LOCALIZATION_INFO_PLIST" ] || [ ! -f "$BUILD_STAMP" ]; then
    needs_build=1
fi

if [ "$FORCE_SHARED_FRAMEWORK_BUILD" -eq 0 ] && [ "$needs_build" -eq 0 ]; then
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

if [ "$FORCE_SHARED_FRAMEWORK_BUILD" -eq 0 ] && [ "$needs_build" -eq 0 ]; then
    echo "Shared Kotlin frameworks are up to date; skipping Gradle."
    exit 0
fi

echo "Building shared Kotlin frameworks..."
cleanup_xcframework_outputs
cd "$SHARED_DIR"
"$SHARED_DIR/gradlew" --no-daemon --console=plain -p "$SHARED_DIR" \
    :core:assemblePindropSharedCoreXCFramework \
    :feature-transcription:assemblePindropSharedTranscriptionXCFramework \
    :ui-theme:assemblePindropSharedUIThemeXCFramework \
    :ui-shell:assemblePindropSharedNavigationXCFramework \
    :ui-settings:assemblePindropSharedAISettingsXCFramework \
    :ui-workspace:assemblePindropSharedUIWorkspaceXCFramework \
    :settings-schema:assemblePindropSharedSchemaXCFramework \
    :ui-localization:assemblePindropSharedLocalizationXCFramework
mkdir -p "$(dirname "$BUILD_STAMP")"
touch "$BUILD_STAMP"
