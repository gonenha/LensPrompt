# Practice Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan inline, with one independent final reviewer.

**Goal:** User-approved 6–8-second rehearsal, deterministic local coaching, explicit upload and verified video/audio model feedback.
**Architecture:** Separate temporary rehearsal state machine; pure Core rules; app AVFoundation/Vision processing actor; Gemini video adapter using the existing credential store and redirect-safe transport. No scripts/takes mutation.
**Tech Stack:** SwiftUI, AVFoundation, Vision, Core Image, CryptoKit, existing Foundation URLSession; iOS17 minimum.
**Spec:** docs/superpowers/specs/2026-10-19-practice-feedback-design.md (approved by user).

## Global Constraints
- 6–8 seconds; default auto-stop8, validate/trim final media; MP4<=8MB.
- Keys device-only Keychain; no relay or hidden provider/model switch.
- No personal media or real credentials in development tests; user initiates synthetic paid capability test and each personal clip upload in app.
- Native video/audio supported-model allowlist + account metadata + synthetic temporal/audio test;7-day bound proof tied to provider/model/key/contract.
- Local checks available without credentials. No network on screen open or capture; no billing retries.
- Direction recommendation only; capture remains portrait. Existing scripts/takes untouched.

## Review Focus
- Late recording delegate after dismissal must close/delete its own session and never attach to a new one.
- Cancellation during permission/export/network, stale key/model approval, expired proof and repeated taps.
- Rotated/short/oversized/silent/missing-track assets and bounded transformed export; local uncertainty when no/multiple faces.
- Model claim of capability is insufficient; wrong synthetic answer must fail verification; proof must not be saved on cancellation.
- Native video/audio request contract and structured response validated; provider errors/metadata never expose secrets.

## Tasks
- [x] 1. Add failing Core tests then pure FeedbackRules/FeedbackReport/VideoCapabilityProof. Pin duration, orientation, local thresholds, uncertainty, proof expiry/identity and bounded response validation. Run swift test red then green.
- [x] 2. Add App FeedbackMedia actor: isolated session folder, playable/duration/tracks validation, bounded MP4 export/time range/preferred orientation; five-frame luminance/sharpness/Vision framing + PCM amplitude/clipping/silence; synthetic8s red→blue video with1→2 audible tone pulses. Unit tests using synthetic media; no hardware/network.
- [x] 3. Add FeedbackAI: fixed Gemini endpoint/schema; only verified gemini-4-argon; GET metadata must match exact model and generateContent. Explicit synthetic request validates event sequence+audio; proof key fingerprint/contract/model bound, cache7days. Mock transport tests fail closed and assert native video payload/privacy.
- [x] 4. Add FeedbackModel state transitions and FeedbackView: consent, preparation, bounded recording, local review, explicit analysis approval, cancellation/delete/retake/results. Prompt overlay/points and existing style. Settings entry for provider/model and explicit synthetic test. Setup launches feature without interfering with existing camera/session.
- [x] 5. Run Core and signed simulator unit/UI tests; independent read-only review and fixes; signed physical build, backup/install/compare existing scripts/takes; user-side media/paid checks remain unexercised unless initiated by user. Commit/push focused PR stacked on feat/ai-script-styles and attach.

## Execution ledger
- Core RED: new duration/target/proof symbols absent; GREEN29 Core tests.
- App RED: absent media/adapter; GREEN after isolating asynchronous export cancellation, tolerating unavailable Vision context as unknown framing, and parsing JSON MIME semantically (slashes may be escaped).
- Independent final review found premature watchdog cleanup and measurements from pre-export media. Removed watchdog; retain movie ownership until matching finish delegate. Measure final exported MP4. Reviewer rechecked both fixes and model-version proof binding without remaining P1/P2 findings.
- Ruling: short feedback prompter uses fixed pacing, explicitly stated in UI — avoids a second audio-monitoring consumer in this bounded capture; regular rehearsal/recording retain existing voice-follow behavior.
- Ruling: report exported analysis dimensions as temporary-clip dimensions, rather than pretending they are full-recording settings. Compression does not change normal recording settings.
- UI first run could not reach the sample behind33 accumulated simulator test scripts. Stopped owned run, backed up simulator scripts, removed only test-created exact-title drafts and reran from two retained fixture scripts. Physical device data untouched.
- No live provider request or personal filming by the developer. Synthetic transport tests use dummy keys; native camera and real provider quality remain user-initiated checks.

- Ruling: initial local exposure measures whole-frame samples; face detection validates framing, not skin brightness. This keeps the local measurement bounded and its uncertainty explicit; complex light-on-presenter assessment remains an optional video-model task.

Verified final checks:30 Core,28 signed iOS unit,11 full UI journeys and3 bridge tests. New feedback UI journey rechecked with its own self-cleaning draft fixture. Signed device build/install/launch passed; device scripts/takes byte-identical after final update. Remote PR delivery follows the verification commit.
