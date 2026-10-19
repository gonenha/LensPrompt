# Take Review, Delete, Pause and Interruption Protection

**Goal:** Make finished recordings immediately watchable, offer visible confirmed deletion, pause/resume a single recording, and reduce call interruptions.
**Spec:** User requested all three take controls and approved the prior two-layer interruption proposal. iOS Focus is user-configured; the app must not claim to enable Focus itself.
**Architecture:** Use native AVCaptureFileOutput pause/resume on iOS 18+, acknowledge via delegate events, and freeze playback timer/text separately from text-only pause. Keep iOS 17 support with pause unavailable there. Preview uses the finalized movie only; release camera/audio before playback. Deletion operates on the explicit selected take after confirmation. Preserve scripts and other takes.

## Tasks
- [x] Add failing Core tests for pause/resume confirmation, stopping in transitions and late callbacks; implement lifecycle.
- [x] Add failing app tests for frozen timer/text, manual text pause preservation, finalized movie readiness and targeted deletion.
- [x] Wire native pause delegates through CameraModel into RecordingModel and add separate pause/continue controls.
- [x] Automatically present a large movie review after finishing; explicit replay and confirmed delete in review/result/library.
- [x] Enable best-effort no-interruption audio preference and add honest Focus setup instructions.
- [x] Run Core, iOS unit and UI regression checks, inspect screenshots, independent review, signed build and phone update if reachable.
- [x] Push a focused PR based on feat/dark-studio, which is still awaiting merge as PR #1.

## Acceptance
Capture pause keeps the same movie URL, excludes the pause from media and timer, preserves text-only pause on resume, and can finish while paused. Pending pause/resume disables repeated toggles but never disables finish. Real interrupts still finish safely. Native media pause/call behavior requires physical acceptance; practice tests are not hardware proof. A deletion must not delete scripts or other takes; errors remain visible. No automatic recording or silent phone configuration during validation.
