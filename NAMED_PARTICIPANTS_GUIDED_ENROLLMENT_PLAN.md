# Named Participants: Guided Enrollment and Classifier Plan

Last updated: 2026-04-15

This document captures the deferred follow-up phases for participant naming beyond the current implementation (label preservation + per-record manual renaming).

## Goals

- Improve speaker identity accuracy with guided user enrollment.
- Keep local-first privacy defaults for voice snippets and embeddings.
- Add an explicit, user-controlled path to train and refresh participant identification.

## Non-goals (for this phase)

- Full cloud identity sync.
- Cross-device profile replication.
- Automatic background retraining without user action.

## Product Direction

### Phase 2: Guided Enrollment Flow

Add a guided flow for creating participant profiles:

1. User selects `Add Participant`.
2. User enters participant name and optional metadata (role/team).
3. App prompts for multiple short voice snippets (for example, 3 to 5 clips, 5 to 10 seconds each).
4. App validates snippet quality (minimum SNR, non-silent, minimum duration).
5. App extracts embeddings per snippet and builds an aggregated profile embedding.
6. App stores enrollment artifact locally with timestamp and quality stats.

Recommended UX safeguards:

- Clear prompt copy per snippet: "Read this sentence in your normal voice."
- Retry affordance when snippet quality is low.
- Consent text for local voice profile storage.

### Phase 3: Lightweight Speaker Classifier

Use enrolled profiles to improve diarized speaker labeling:

- Input: diarization segment embeddings + participant enrollment embeddings.
- Candidate algorithm:
  - Start with cosine similarity + thresholding.
  - Add top-1 / top-2 margin checks to reduce false positives.
  - Optional confidence calibration using held-out enrollment snippets.
- Output:
  - `matched participant` when confidence >= threshold.
  - `unknown speaker` when below threshold.
  - Preserve stable fallback IDs for unknown speakers (`speaker-1`, `speaker-2`, etc.).

Training and refresh approach:

- "Train" can initially mean deriving profile centroids from enrollment embeddings.
- Later, allow a small local classifier (for example, nearest centroid with adaptive thresholds).
- Retraining triggers:
  - new snippets added,
  - participant renamed/merged,
  - user feedback corrections from transcript view.

## Data Model Candidates

Add a participant profile model (future schema version):

- `ParticipantProfile`
  - `id: UUID`
  - `displayName: String`
  - `embeddingBlob: Data` (or array-backed JSON)
  - `sampleCount: Int`
  - `qualityScore: Double`
  - `createdAt: Date`
  - `updatedAt: Date`

Add optional linkage for record-level assignments:

- `TranscriptionRecordParticipantAssignment`
  - `recordID`
  - `speakerID`
  - `participantProfileID`
  - `confidence`

## API and Service Design Notes

Potential additions:

- `SpeakerEnrollmentService`
  - capture prompts and snippets
  - validate snippet quality
  - build enrollment embeddings
- `SpeakerIdentityService`
  - match segment embeddings to participant profiles
  - expose confidence and fallback reasons
- Extend `SpeakerDiarizer` integration:
  - hydrate known speakers from profile store before diarization
  - write back assignment confidence metadata

## UX Touchpoints

- Settings > Models/Features:
  - add `Participants` section with profile management.
- Detail view:
  - keep manual rename (already available),
  - add `Link to Participant` action when profile match is uncertain.
- Onboarding nudge:
  - suggest enrollment after repeated multi-speaker transcripts.

## Validation and Metrics

Track locally (and optionally telemetry if enabled):

- match rate,
- unknown-speaker rate,
- user correction rate,
- confidence distribution,
- average enrollment sample quality.

Acceptance targets:

- reduced manual rename frequency over time,
- high precision for top-confidence matches,
- no regression in diarization fallback behavior.

## OMI-Inspired Research Spike

Reference inspiration: `~/Projects/clones/omi`.

Research checklist:

- Review OMI enrollment UX (prompt cadence, retries, quality checks).
- Review profile persistence and embedding aggregation strategy.
- Identify reusable ideas for confidence thresholds and mismatch handling.
- Capture notes in a short implementation brief before code changes.

Deliverable for spike:

- `release-notes/participant-enrollment-research.md` (or equivalent internal doc)
  - findings,
  - recommended thresholds,
  - migration risk notes,
  - proposed test matrix.

## Risks and Mitigations

- **Risk:** false identity matches.
  - **Mitigation:** conservative thresholds + unknown fallback.
- **Risk:** poor enrollment audio quality.
  - **Mitigation:** mandatory quality gate and retry loop.
- **Risk:** schema churn.
  - **Mitigation:** isolate profile store behind service protocol first.

## Suggested Implementation Order (Deferred)

1. Research spike and thresholds proposal.
2. Profile persistence model and migration.
3. Guided enrollment UI and snippet quality checks.
4. Classifier matching pipeline integration.
5. Confidence UX, correction loops, and metrics.
