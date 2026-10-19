# Script Take Groups Implementation Plan

**Goal:** Connect each script visually to its takes, rate takes from playback, share a selected batch, and give videos readable permanent take numbers.
**Spec:** The user's four requested behaviors in this chat. Existing dark studio style, native SwiftUI, iOS 17+, no new service or dependency.
**Architecture:** Optional backward-compatible Take metadata (script identity, number, rating and storage name). Migrate metadata without moving existing videos; attach historical title-only takes only when a single script matches. Persist per-group sequence high-water marks so deletion cannot reuse a number. New recordings live in UUID directories with readable movie basenames. Export existing and new movies into a batch of readable filenames, preserving originals. A grouped card with horizontal take cards replaces one-flat-row-per-take; a script-card shortcut opens its group. One system share sheet receives all selected URLs.

## Tasks
- [x] Core RED/GREEN: legacy decoding/migration, identity vs duplicate titles, numbers after deletion/restart, rating persistence and safe named multi-export.
- [x] App: pass script ID when recording, observable rating/group state, export preparation, grouped horizontal take cards and script shortcut.
- [x] Playback rating buttons plus named single/batch share using the same export path; missing-file errors must not share a partial set.
- [x] iOS/UI tests: ratings persist, same-script takes stay in one card, multi-selection produces one share sheet with two items, existing playback/delete regressions.
- [x] Review, full checks, signed build/install if device reachable, preserve existing scripts/videos and document validation; focused stacked PR.

## Decisions
Unrated is the initial state; choosing one of מעולה, טוב, גרוע replaces the previous rating. Display the current script title on its group, while a take's recording title and number remain stable for filenames. Historical duplicate titles cannot prove script identity and remain a separate title group. Old UUID movie files stay untouched; their shared copies receive readable names. Failed export preparation reports an error and never silently drops a selected item. Temporary exports are released when the share sheet closes.
