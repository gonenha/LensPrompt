# Manual talking points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let the user speak naturally while seeing one manually advanced cue for opening, pain, solution and offer.

**Architecture:** An optional per-script presentation mode and four independently saved sentences reuse existing editor, capture lifecycle and take library. Manual cards never auto-advance or activate voice following. The elapsed take timer remains active. Existing scrolling text and settings survive switching modes.

**Tech Stack:** Existing Swift 6, SwiftUI, PrompterCore, AVFoundation. No new dependencies.

**Spec:** User request: four sentence cues (הפתיח, הכאב, הפתרון, ההצעה), replaced by a next button. Implementer defaults: add previous; skip empty sections, require at least one nonempty sentence; stop next at last cue without ending recording; reset to first for each new take; scrolling remains default for existing scripts.

## Global Constraints
- KISS, iOS17+, Hebrew RTL, all data local.
- No voice-follow microphone permission for manual practice; movie recording still requires microphone.
- Existing scripts decode safely; mode switches and duplicate preserve both text forms.

## Review Focus
- No automatic movement, including when saved voice follow was enabled.
- Empty/whitespace-only cards cannot start; optional missing sections skip in canonical order.
- Final Next and initial Previous remain bounded and never end recording.
- Large fonts/long sentences remain readable by scrolling the current card.
- Editing, relaunch, duplication and returning to scrolling retain user data.

### Task 1: Model and storage
- [x] Write failing core tests for card order/empty filtering, current-mode start eligibility, round-trip and legacy decoding, duplicate preservation.
- [x] Add PresentationMode, TalkingStage, TalkingPoint; optional storage on Script, computed current presentation and point accessors; core duplicate preserving all content.
- [x] Run core suite and commit focused files.

### Task 2: Editor, setup and recording UI
- [x] Add failing iOS model test: manual cue navigation bounded, never changes elapsed timer, and ignores saved voice follow.
- [x] Add editor mode picker and four labeled multiline sentence inputs; library cards show point count.
- [x] Hide speed/voice controls in manual mode. Display a single cue card with title/progress; scroll long sentence within card. Add large Next and Previous around existing finish button. Next disables on last; finish stays explicit.
- [x] Reuse recording lifecycle with text clock paused for manual cards. Practice bypasses audio permission. New takes reset cue index.
- [x] Run core + simulator unit/UI tests; inspect screenshot. Signed device build.

### Task 3: Review and install
- [x] Independent read-only code review; resolve important findings and verify regressions.
- [x] Update README, validation and progress; install update on connected phone without uninstalling or resetting data. Verify launch; no actual recording on user's behalf.
- [x] Commit and refresh source archive. Physical comfort/camera acceptance remains user check.

## Verification

26 tests passed: 15 core, 7 iOS, 4 UI. Signed build, signature verification, update installation and launch passed on the personal phone. New manual UI flow and screenshot inspected; first full suite exposed an existing fixed-scroll test's persisted voice-setting assumption, corrected by setting its mode explicitly. No production change was needed for that fixture. Independent review found no Important or Minor issues. Physical readability/long-text scroll comfort and real recording remain user acceptance checks; no hardware recording claim made.
