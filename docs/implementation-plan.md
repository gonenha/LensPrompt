# LensPrompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build the approved Hebrew iPhone teleprompter with local scripts, constant scrolling and front-camera movie recording.
**Architecture:** A small Foundation core owns text import, validated preferences, persistence and scroll timing. SwiftUI presents the approved screens; an isolated AVFoundation capture service writes movies directly to Documents, separate from prompt overlays.
**Tech Stack:** Swift 6, SwiftUI, AVFoundation, AVKit, Photos, local Swift Package, XcodeGen (project generation only).
**Spec:** ../iphone-prompter-spec.md in the containing outputs directory.

## Global Constraints

- iPhone 15, iOS 17+, portrait front-camera 1080p/30fps; Hebrew RTL with mixed English and numerals.
- No server, account, speech recognition, editing, cloud sync, or external runtime dependencies.
- Handheld: medium font and 3-second countdown. One metre: large font and 7-second countdown.
- Fixed scroll: 50–220 WPM or 10–1800 seconds; empty scripts cannot start.
- Pausing or reaching the end of text never stops movie recording. Timer starts from capture delegate didStart, not the countdown.
- Movie files and recoverable pending takes survive relaunch. No destructive cleanup without confirmation.

## Review Focus

- Corrupt manifests or invalid UTF-8 must never overwrite existing content.
- Interrupted/pending movies must not disappear or be called successfully saved without a playable file.
- A canceled countdown or a background transition while capture is starting must not leave an unseen recorder running.
- Long mixed-direction scripts, changed typography and one-word scripts must finish scrolling at the intended reading line.
- Denied permissions, missing hardware, disk-full errors and denied photo-library access preserve rehearsal and sharing.

## Task 1: Core behavior and persistence

**Files:** Core/Package.swift; Core/Sources/PrompterCore/{Models,Library,ScrollClock}.swift; Core/Tests/PrompterCoreTests/CoreTests.swift.
**Interfaces:** Script (id/title/text/updatedAt/settings), PromptSettings.duration(wordCount:), ScriptLibrary(root: URL), ScrollClock(travel:duration:).

- [ ] Write Swift Testing cases for 150 words at 100 WPM = 90 seconds, timing clamps, multilingual whitespace count, invalid UTF-8, pause preserving recording elapsed, end clamp, speed change preserving offset, atomic script persistence, pending take recovery and corrupt manifest preservation.
- [ ] Run `swift test --package-path Core`, observe missing behavior fail, implement minimal core and rerun all tests.
- [ ] Commit core and tests after green.

## Task 2: Native interface and rehearsal

**Files:** project.yml; App/{LensPromptApp,Theme,LibraryViews,SetupView,PromptOverlay,PlaybackModel}.swift; UITests/FlowTests.swift.
**Interfaces:** consume ScriptLibrary + Script; produce PlaybackModel start/pause/reset/stop and measured PromptLayout travel using UIKit text layout.

- [ ] Write an XCUITest journey for editing a script, choosing distance preset and rehearsal pause/reset/end; run against an empty initial app to see missing controls fail.
- [ ] Implement local library UI, editor, UTF-8 fileImporter, setup, settings saved per script, rehearsal and countdown cancellation.
- [ ] Generate project, build for iPhone simulator, run the UI journey and core suite.
- [ ] Commit interface and project after green.

## Task 3: Capture and durable takes

**Files:** App/{CameraHardware,CameraModel,RecordingView,TakesView}.swift; Core model and tests as needed.
**Interfaces:** capture service sends didStart and didFinish events; UI starts scroll only on didStart. ScriptLibrary creates pending takes before capture and finalizes only after validating video playability.

- [ ] Add core/session tests for canceling before start, interruption while starting, finishing without losing elapsed state and recovery of unfinished takes. Observe RED then implement lifecycle transitions.
- [ ] Implement permission-gated capture on a background serial executor, portrait output with mic, preview, background/interruption stop, local take metadata, AVPlayer, photo add-only authorization and system share sheet.
- [ ] Build both device (unsigned) and simulator, run core and UI tests. Confirm rehearsal remains usable without camera hardware.
- [ ] Commit recording implementation after green.

## Task 4: Review and delivery

**Files:** README.md; docs/validation.md; Assets.xcassets; user-facing simulator screenshots.

- [ ] Run all tests, inspect screenshots, install/launch on an iPhone 15 simulator and verify relaunch persistence.
- [ ] Request one independent whole-project review, address important findings with regression tests and rerun affected checks.
- [ ] Document exactly what passed locally and what still needs a physical iPhone/account signing; open the Xcode project and simulator for the user.

## Execution decisions

The user authorized implementation with “תתקדם”; proceed inline without another approval round. This is a new isolated local repository, not an existing checkout: initialize on `build/iphone-prompter`; no remote or publication is required. Build intermediates stay in work/, final project and instructions in outputs/.
