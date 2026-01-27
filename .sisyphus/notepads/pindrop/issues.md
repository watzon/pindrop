# Issues & Gotchas - Pindrop

(To be populated as we encounter problems)

## DMG Creation Issues (2026-01-27)

### Issue: `just dmg` Failed with Build Errors

**Problem**: Release build failed with "Unable to find module dependency: 'OrderedCollections'" error when using `SYMROOT=build` setting.

**Root Cause**: Conflicting build paths - setting both `derivedDataPath` and `SYMROOT` caused Swift Package Manager dependency resolution to fail.

**Solution**: 
1. Removed `SYMROOT={{build_dir}}` from `build-release` recipe in justfile
2. Updated `build_dir` variable to point to actual output: `DerivedData/Build/Products`
3. Updated `create-dmg.sh` to use correct app bundle path: `DerivedData/Build/Products/Release/Pindrop.app`
4. Fixed icon path in `create-dmg.sh`: Changed `AppIcon.icns` to `${APP_NAME}.icns` (actual filename is `Pindrop.icns`)

**Verification**: DMG now creates successfully with `just dmg` or `just dmg-quick`

**Files Modified**:
- `justfile`: Fixed build paths and removed conflicting SYMROOT
- `scripts/create-dmg.sh`: Updated APP_BUNDLE path and icon filename

**Result**: ✅ DMG creation now works correctly, produces 7.6MB distributable DMG

## Model Path Issues - Complete Resolution (2026-01-27)

### Issue 3: TranscriptionService Looking in Wrong Location After Path Fix

**Problem**: After fixing the model download path in ModelManager, TranscriptionService couldn't find models because it was still looking in the default WhisperKit location.

**Error**:
```
Download failed: Model file not found at /Users/watzon/Library/Application Support/Pindrop/openai_whisper-base/MelSpectrogram.mlmodelc
```

**Root Cause**: TranscriptionService's `loadModel(modelName:)` was using `WhisperKitConfig(model: modelName)` without specifying the `downloadBase` parameter, so WhisperKit looked in its default location instead of our custom path.

**Solution**: Added `downloadBase` parameter to TranscriptionService:

1. Added `modelsBaseURL` computed property (matching ModelManager):
```swift
private let fileManager = FileManager.default

private var modelsBaseURL: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Pindrop", isDirectory: true)
}
```

2. Updated WhisperKitConfig to include downloadBase:
```swift
let config = WhisperKitConfig(
    model: modelName,
    downloadBase: modelsBaseURL,  // Added this
    verbose: false,
    logLevel: .error,
    prewarm: true,
    load: true
)
```

**Result**: TranscriptionService now looks for models in the same location where ModelManager downloads them.

**Complete Path Flow**:
1. ModelManager downloads to: `~/Library/Application Support/Pindrop/` (WhisperKit adds `models/argmaxinc/whisperkit-coreml/`)
2. TranscriptionService loads from: `~/Library/Application Support/Pindrop/` (WhisperKit adds `models/argmaxinc/whisperkit-coreml/`)
3. Final path: `~/Library/Application Support/Pindrop/models/argmaxinc/whisperkit-coreml/{modelName}/`

**Files Modified**:
- ModelManager.swift: Fixed download path (removed extra `/models`)
- TranscriptionService.swift: Added downloadBase parameter to match

**Verification**: ✅ Build succeeded, paths now consistent between download and load
