# Model Path Duplication Fix - Findings

**Date:** 2026-01-27
**File Modified:** Pindrop/Services/ModelManager.swift

## Issue
Models were being stored in a nested path: `~/Library/Application Support/Pindrop/models/models/argmaxinc/whisperkit-coreml/`

## Root Cause
The `modelsBaseURL` computed property was appending `"Pindrop/models"` to the Application Support directory, but WhisperKit's download function automatically creates its own `models` subdirectory.

## Fix Applied
Changed line 257 in ModelManager.swift from:
```swift
.appendingPathComponent("Pindrop/models", isDirectory: true)
```
to:
```swift
.appendingPathComponent("Pindrop", isDirectory: true)
```

## Result
- Before: `Pindrop/models` + WhisperKit's `models` = `Pindrop/models/models/...`
- After: `Pindrop` + WhisperKit's `models` = `Pindrop/models/...` ✓

## Verification
- Build succeeded with no errors
- Models will now be stored at: `~/Library/Application Support/Pindrop/models/argmaxinc/whisperkit-coreml/`

## Note
Existing users with models in the old location will need to re-download their models, or migration logic can be added later if needed.
