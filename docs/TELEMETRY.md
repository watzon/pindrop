# Pindrop Telemetry & Training Data

Last updated: 2026-07-14

Pindrop is a privacy-first dictation app. Everything described here is **opt-in and
off by default**. If you never touch the toggles in **Settings → Privacy**, Pindrop
sends nothing and stores no extra data.

This document is the complete, exhaustive description of both programs. If a signal
or field is not listed here, Pindrop does not collect it.

---

## 1. Anonymous telemetry (opt-in)

When you enable **Share anonymous usage data** (or accept the one-time prompt),
Pindrop sends anonymous signals to [TelemetryDeck](https://telemetrydeck.com), a
privacy-focused analytics service, so bugs can be found and fixed faster.

**Identity:** TelemetryDeck uses an anonymous, salted install identifier generated
by its SDK. Pindrop never sets a custom user ID, and nothing links signals to your
name, email, or Apple ID. Signals are batched on-device and sent when a network
connection is available.

### Every signal Pindrop can send

| Signal | Parameters | When |
|---|---|---|
| `app.launched` | `backend`, `model`, `locale` | App start |
| `app.onboardingCompleted` | `model` | A fresh install finishes onboarding **and** opts in |
| `transcription.succeeded` | `backend`, `model`, `durationBucket`, `wordCountBucket`, `enhanced`, `diarized` | A dictation is saved (may be sampled) |
| `transcription.failed` | `errorCase`, `stage`, `backend`, `model` | A dictation fails |
| `transcription.emptyResult` | `stage`, `backend` | No speech was detected |
| `model.downloadStarted` | `model` | A model download begins |
| `model.downloadFailed` | `model`, `errorCase` | A model download fails |
| `model.loadFailed` | `model`, `errorCase` | A downloaded model fails to load |
| `enhancement.failed` | `providerKind`, `errorCase` | An AI enhancement request fails |

### What the parameters contain

- `backend` / `model` / `providerKind` — Pindrop's own identifiers (e.g. `parakeet`,
  `openai_whisper-base`, `ollama`). Never file names or content.
- `errorCase` — the bare name of an internal error case (e.g.
  `TranscriptionError.modelNotLoaded`). Associated error messages, which can contain
  paths or provider responses, are **stripped before sending**.
- `durationBucket` / `wordCountBucket` — coarse ranges (e.g. `5-15s`, `11-50`), never
  exact values.
- `enhanced` / `diarized` — `true`/`false`.
- `stage` / `locale` — a pipeline stage name (`transcribe`, `recording`, …) and the
  interface locale (`en`, `pt-BR`, …).

The TelemetryDeck SDK also attaches its standard anonymous context (app version,
OS version, device type). See [TelemetryDeck's privacy docs](https://telemetrydeck.com/privacy/)
for details.

### What is never sent

- Transcript text, in any form — final, original, partial, or streaming
- Audio, in any form
- AI prompts, API keys, endpoints, or provider responses
- File names, file paths, URLs you dictate or import
- Names of apps you insert text into
- Speaker names, participant profiles, or voice embeddings
- Dictionary entries, word replacements, or vocabulary words
- Your name, email, or any account identifier

The full signal catalog lives in code at `Pindrop/Services/TelemetryEvents.swift` —
one auditable file.

---

## 2. Training-data contributions (opt-in, local-only)

Pindrop's long-term goal is a small, fully on-device model that cleans up
transcription output — no cloud AI required. Training such a model needs
before/after examples of transcripts being fixed.

When you enable **Contribute transcription fixes**, Pindrop keeps a local copy of
text pairs when:

- **AI enhancement** rewrites a transcript (raw recognizer output → enhanced text), or
- **you manually edit** a transcript in the Library (pre-edit text → your correction).

### Nothing is uploaded

Contributions are stored **only on your Mac**, inside Pindrop's local database.
There is no upload backend; the uploader in the code is a deliberate no-op
(`Pindrop/Services/ContributionUploader.swift`). Any future upload option will be a
separate, explicit opt-in — enabling collection is not consent to upload.

### What each stored pair contains

| Field | Contents |
|---|---|
| `inputText` / `targetText` | The before/after texts, **redacted** (see below) |
| `kind` | `aiEnhancement` or `manualEdit` |
| `modelUsed` / `enhancedWith` | Recognizer and (if any) AI model identifiers |
| `language` / `locale` | Your dictation language and interface locale settings |
| `appVersion` | Pindrop version at capture time |
| `createdAt` / `redactionVersion` / `uploadState` | Bookkeeping (`uploadState` stays `pending`) |

### Redaction — and its limits

Before a pair is stored, both texts pass through a redactor
(`Pindrop/Utils/TrainingTextRedactor.swift`) that removes **structured** personal
data: email addresses, URLs, file paths, long digit runs (phone/card numbers),
@handles, UUIDs, and token/secret patterns.

**Honest limitation:** the v1 redactor cannot detect free-form personal names in
dictated text ("tell Sarah I'll be late" keeps "Sarah"). This is a primary reason
contributions stay local-only. Review what's stored before exporting or sharing it.

### You stay in control

In **Settings → Privacy**:

- **Review…** — inspect every stored pair.
- **Export JSONL…** — export your pairs as a [JSON Lines](https://jsonlines.org)
  file (schema aligned with `docs/transcript-post-processing-model-research.md` §7).
  The internal record link (`sourceRecordID`) is never exported.
- **Delete all contributions…** — permanently removes every stored pair.
- Turning the toggle off stops collection immediately; existing pairs stay until
  you delete them.

---

## 3. Diagnostics logs

Independent of telemetry, Pindrop writes local log files
(`~/Library/Application Support/Pindrop/Logs/`, rotated, capped). Log messages are
redacted at write time — transcript text is never logged. **Export Logs…** in
Settings → Privacy copies them to a folder of your choice so you can attach them to
a GitHub issue. Logs never leave your machine unless you send them.
