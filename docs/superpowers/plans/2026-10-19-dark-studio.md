# Dark Studio Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation.

**Goal:** Apply the user-approved dark-studio design to the Hebrew iPhone app.
**Architecture:** Shared SwiftUI colors and button styles, existing state and capture models. Library bottom navigation opens the existing takes sheet. No storage, signing or capture changes.
**Tech Stack:** SwiftUI, UIKit prompt renderer, iOS 17+.
**Spec:** User-approved six-screen graphic package; design tokens in docs/dark-studio-design.md.

## Global Constraints
- Hebrew RTL, existing accessibility identifiers, readable native Dynamic Type.
- Colors: background #171916, surface #252822, text #F2F1E8, secondary #A6ABA0, lime #D6E787, recording #EF7066.
- Controls >=48pt; manual cues remain manual. Pause affects text only; finishing ends take.
- No new dependencies, persisted schema changes, device identifiers or signing details in public source.

## Review Focus
- Long Hebrew titles and large text must wrap without hiding library navigation.
- Four long cue fields remain scrollable and editable without a keyboard trapping navigation.
- Recording controls and prompt must fit small screens at 40pt reading font.
- Disabled next/previous and finishing states remain visibly and functionally correct.
- Empty/error states and take export retain readable foreground/background contrast.

### Task 1: Theme and library/editor
- [x] Add library/takes navigation UI test; observe failure on missing library tab.
- [x] Update Theme.swift, LensPromptApp.swift and LibraryViews.swift. Preserve save/import/delete behavior.
- [x] Build and run navigation test; visually inspect simulator.

### Task 2: Preparation, recording and takes
- [x] Update SetupView.swift, RecordingView.swift, PromptOverlay.swift and TakesView.swift.
- [x] Run existing unit/UI behavior checks for both recording modes, persistence and permission fallback.
- [x] Inspect actual screenshots; review changes; record validation.

### Task 3: Delivery
- [x] Run Core/Python checks and signed physical-device build.
- [x] Commit/push feature branch and create focused PR; attach it to this chat.
- [x] If user's paired iPhone is reachable, install update without deleting app data.

## Execution notes
User explicitly requested implementation of the selected design; no additional design approval is required. Existing clean public checkout is isolated from the original personally configured local repository. Styling is verified visually and by existing behavioral checks; no tests mirror color constants.


## Execution record

Implemented inline in the existing isolated public checkout on feat/dark-studio. Core, capture and persistence schemas are unchanged. Independent reviews found no functional blocker; the import touch target was raised to 48pt. Visual testing drove full editor scrolling, accessibility choice stacking, keyboard focus management and pinned library creation controls. Final functional verification: 19 Core + 10 iOS + 6 UI + 3 Python = 38 passing tests. Final signed build and on-device update succeeded; script manifest bytes were preserved. Physical launch succeeded after the user unlocked the phone. Public source privacy scan passed. Delivery is a focused pull request, not an automatic merge to main.
