# Codex approved-script inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for inline implementation.

**Goal:** Generate and review a script in Codex, then send its approved title, full text and four speaking points directly into the personal iPhone app.

**Architecture:** Local Xcode development-device transport, no backend/account/cloud. The Codex helper validates a versioned JSON payload and its approved SHA-256, stages it into Documents/LensPrompt/Inbox, then copies a checksum ready marker. Foreground app polling consumes only ready transfers, saves a new Script atomically, and writes a receipt. A small installed Codex skill provides the draft→human approval→send workflow.

**Spec:** Approved conversation: prepare inside Codex, send only after human approval, automatically populate app with title/full text/points. Implementer transport choice: paired cable or wireless development connection to this Mac; disconnected phones require retry. Foreground app imports automatically, closed app imports on next launch. Do not send a sample to the real phone without content approval. Test with simulator fixtures instead.

## Global Constraints
- KISS, iOS17+, Hebrew RTL; existing library/voice/manual modes preserved.
- Never overwrite scripts.json from Mac. Only enqueue a new transfer and wait for app acknowledgment.
- Immutable UUID per approved draft; same UUID/hash retry is idempotent even after local edits or deletion. Changed content requires a new draft ID and approval.
- Title/full text/four point strings nonempty; no NUL; payload <=1MB UTF-8; version1; exact SHA marker.
- Preserve malformed, conflicting or failed transfers; do not overwrite a corrupt library.
- Do not import while recording/practicing. No camera/mic activation for transfer.
- Distinguish staged delivery from acknowledged app import. No claims of background iOS execution.

## Review Focus
- Interrupted upload without marker must never import.
- Replay after local edit/delete or crash between script save and receipt must not duplicate/overwrite.
- Malformed/oversized/checksum/UUID mismatch or corrupt library must not lose user content; valid sibling imports should still work.
- Send only approved exact file; source changes after approval must fail before transfer.
- Foreground arrival and next-launch import, with capture suspension; sender acknowledgment must match ID/hash.

### Task 1: Core import contract and durable receipts
- [x] RED core tests: staging barrier; idempotent import preserving edits/deletion; interrupted receipt recovery; checksum/UUID/invalid sibling rejection; corrupt library.
- [x] Add CodexTransfer.swift (explicit Package sources), optional Script.sourceTransferHash, Inbox/Receipts directories, import result and immutable receipts. Validate bytes/hash/schema, save before receipt, consume files only after receipt success.
- [x] GREEN full core suite; commit.

### Task 2: App reception and sender/skill
- [x] RED iOS model tests: incoming transfer updates library; recording suspend blocks reception until finished. Add simulator UI next-launch import coverage via prepared simulator inbox fixture if practical; use model tests and actual sender receipt for live foreground instead of test-only product hooks.
- [x] Foreground root task polls inbox; library status appears in library screen, no modal interruption. RecordingModel suspends imports through existing lifetime cleanup.
- [x] Add deterministic Python helper and tests: strict JSON schema, approved hash gate, UUID/path safety; devicectl staged copies + receipt verification, simulator transport for end-to-end testing. No remote shell, no secrets.
- [x] Add short discoverable Codex skill: draft title/text/four cues in Hebrew, save exact JSON, get explicit human approval, send exact hash, report acknowledged vs queued truthfully. Ship canonical skill in repository; install under ~/.codex/skills/lensprompt-script using skill-creator guidance.
- [x] Run all core/Python/iOS/UI checks and simulator foreground sender→receipt→library evidence.

### Task 3: Review and personal-phone update
- [x] Independent read-only review of boundaries; fix important findings with regression evidence.
- [x] Signed device build and signature check; install update, launch, verify directories/bridge readiness without sending unapproved sample content.
- [x] Document connection/approval/queued limitations. Commit, refresh source archive and install validated skill copy. No deployment/paid service.

## Delivery evidence

36 tests passed (19 core,10 iOS,4 UI,3 Python); actual simulator helper→app receipt E2E passed for closed/open/replayed transfer with one script and exact fields. Independent review's three correctness gaps resolved with deletion/dirty-state RED→GREEN and historical-ack wording. Signed build/verification, physical update/launch and empty technical-file round trip passed. Installed/validated discoverable skill at ~/.codex/skills/lensprompt-script. A real script is deliberately not sent until the human approves its final content. Requires paired Mac connection; suspended app imports on next foreground launch, not background wake.
