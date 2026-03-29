# External Integrations

**Analysis Date:** 2026-03-29

## APIs & External Services

**AI enhancement APIs:**
- OpenAI - optional text enhancement and model listing.
  - SDK/Client: custom `URLSession` clients in `Pindrop/Services/AIEnhancementService.swift` and `Pindrop/Services/AIModelService.swift`
  - Auth: API key stored in Keychain via `Pindrop/Services/SettingsStore.swift` and `Pindrop/Services/AIEnhancementService.swift`
  - Endpoints: defaults in `Pindrop/UI/Onboarding/AIEnhancementStepView.swift` (`https://api.openai.com/v1/chat/completions`, `https://api.openai.com/v1/models`)
- Anthropic - optional text enhancement with provider-specific headers.
  - SDK/Client: custom HTTP requests in `Pindrop/Services/AIEnhancementService.swift`
  - Auth: `x-api-key` header from Keychain-backed settings
  - Endpoint: `https://api.anthropic.com/v1/messages` in `Pindrop/UI/Onboarding/AIEnhancementStepView.swift`
- OpenRouter - optional OpenAI-compatible enhancement/model routing.
  - SDK/Client: custom HTTP requests in `Pindrop/Services/AIEnhancementService.swift` and `Pindrop/Services/AIModelService.swift`
  - Auth: Keychain-backed API key when configured
  - Endpoints: `https://openrouter.ai/api/v1/chat/completions` and `https://openrouter.ai/api/v1/models` from `Pindrop/UI/Onboarding/AIEnhancementStepView.swift` and `Pindrop/Services/AIModelService.swift`
- Google Gemini - UI/config option exists, but implementation is explicitly uncertain/incomplete.
  - SDK/Client: no dedicated request path detected in `Pindrop/Services/AIEnhancementService.swift`
  - Auth: placeholder support only in `Pindrop/UI/Onboarding/AIEnhancementStepView.swift`
  - Endpoint: `https://generativelanguage.googleapis.com/v1beta` in onboarding defaults
- Custom/local OpenAI-compatible providers - optional local or custom enhancement backends.
  - SDK/Client: custom HTTP requests in `Pindrop/Services/AIEnhancementService.swift` and `Pindrop/Services/AIModelService.swift`
  - Auth: optional or required depending on provider type in `Pindrop/UI/Onboarding/AIEnhancementStepView.swift`
  - Endpoints: Ollama `http://localhost:11434/v1/chat/completions`, LM Studio `http://localhost:1234/v1/chat/completions`, plus model-listing endpoints in the same file

**Model distribution / update delivery:**
- Sparkle feed + GitHub Releases - app update delivery.
  - SDK/Client: `Sparkle` via `Pindrop/Services/UpdateService.swift`
  - Auth: Sparkle EdDSA signing configured via `Pindrop/Info.plist` and release secrets in `.github/workflows/release.yml`
  - Feed URL: `https://github.com/watzon/pindrop/releases/latest/download/appcast.xml` in `Pindrop/Info.plist`
- Whisper model downloads - handled through WhisperKit in `Pindrop/Services/Transcription/WhisperKitEngine.swift` and orchestrated by `Pindrop/Services/ModelManager.swift`.
  - SDK/Client: `WhisperKit`
  - Auth: none detected
  - Remote host: not hard-coded in this repository; download source is delegated to WhisperKit and is therefore uncertain from repo-local evidence alone.
- Parakeet / FluidAudio model downloads - handled through FluidAudio in `Pindrop/Services/Transcription/ParakeetEngine.swift` and `Pindrop/Services/ModelManager.swift`.
  - SDK/Client: `FluidAudio`
  - Auth: none detected

**Tooling-triggered web/media services:**
- Web media ingestion uses local CLI tools `yt-dlp` and `ffmpeg` when transcribing URLs in `Pindrop/Services/MediaIngestionService.swift`.
  - SDK/Client: local process execution via `Process` wrapper
  - Auth: none detected
  - Remote services: whatever source URL `yt-dlp` resolves; repository does not pin a single provider

## Data Storage

**Databases:**
- Local SwiftData / SQLite store only.
  - Connection: on-disk store created in `Pindrop/PindropApp.swift` through `ModelContainer`
  - Client: `SwiftData` with repair logic in `Pindrop/PindropApp.swift`
  - Stored entities: `TranscriptionRecord`, `MediaFolder`, `WordReplacement`, `VocabularyWord`, `Note`, and `PromptPreset` via `Pindrop/PindropApp.swift` and `Pindrop/Models/*.swift`

**File Storage:**
- Local filesystem under Application Support.
  - Models: `Pindrop/Services/ModelManager.swift`
  - AI model cache JSON: `Pindrop/Services/AIModelService.swift`
  - Logs: `Pindrop/Utils/Logger.swift`
  - Managed media assets: `Pindrop/Services/MediaIngestionService.swift`
  - No cloud file storage service detected

**Caching:**
- AI model list cache on disk in Application Support via `Pindrop/Services/AIModelService.swift`.
- Timestamp-based cache metadata in `@AppStorage` via `Pindrop/Services/SettingsStore.swift`.

## Authentication & Identity

**Auth Provider:**
- macOS Keychain for secrets.
  - Implementation: secure save/load/delete logic in `Pindrop/Services/SettingsStore.swift` and provider-specific secret handling in `Pindrop/Services/AIEnhancementService.swift`

## Monitoring & Observability

**Error Tracking:**
- No external error tracking service detected.

**Logs:**
- Local structured logging through `Log` categories in `Pindrop/Utils/Logger.swift`.
- Boot/update/AI logs are written locally; no remote log sink is detected.

## CI/CD & Deployment

**Hosting:**
- Application artifacts are distributed through GitHub Releases and consumed by Sparkle via `Pindrop/Info.plist`, `appcast.xml`, and `.github/workflows/release.yml`.
- A separate marketing site rebuild is triggered on Vercel through `.github/workflows/vercel-rebuild.yml`.

**CI Pipeline:**
- GitHub Actions CI in `.github/workflows/ci.yml` builds unsigned macOS artifacts and runs tests.
- GitHub Actions release workflow in `.github/workflows/release.yml` packages a DMG, signs update metadata, verifies versions, and publishes artifacts.

## Environment Configuration

**Required env vars:**
- Runtime/test flags: `PINDROP_TEST_MODE`, `PINDROP_RUN_INTEGRATION_TESTS`, and UI-test-related flags referenced by `Pindrop/AppCoordinator.swift`, `Pindrop/AppTestMode.swift`, and `Pindrop/Utils/Logger.swift`.
- Build flag: `FORCE_SHARED_FRAMEWORK_BUILD` in `scripts/build-shared-frameworks-if-needed.sh`.
- CI/release secrets: `GITHUB_TOKEN`, `SPARKLE_EDDSA_PRIVATE_KEY`, and `VERCEL_DEPLOY_HOOK_URL` in `.github/workflows/release.yml` and `.github/workflows/vercel-rebuild.yml`.
- User-configured AI credentials are required only when optional remote AI enhancement is enabled; those values are stored via `Pindrop/Services/SettingsStore.swift`, not committed env files.

**Secrets location:**
- User secrets: macOS Keychain via `Pindrop/Services/SettingsStore.swift` and `Pindrop/Services/AIEnhancementService.swift`.
- CI secrets: GitHub Actions secrets referenced in `.github/workflows/release.yml` and `.github/workflows/vercel-rebuild.yml`.

## Webhooks & Callbacks

**Incoming:**
- None detected for the shipped app.

**Outgoing:**
- Vercel deploy hook POST request in `.github/workflows/vercel-rebuild.yml`.
- GitHub API / CLI access during release automation in `.github/workflows/release.yml`.
- Sparkle client update checks against the GitHub-hosted appcast feed from `Pindrop/Services/UpdateService.swift` and `Pindrop/Info.plist`.

---

*Integration audit: 2026-03-29*
