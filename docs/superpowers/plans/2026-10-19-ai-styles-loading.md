# Script Styles, Model Settings and Immediate Preparation Feedback

**Goal:** Show immediate animated preparation feedback, connect one selected language-model provider, and create three independently editable/filmable Hebrew styles without overwriting the source.
**Spec:** User approved original/dynamic/empathic/concise styles and requested a settings screen with OpenAI, Gemini and Claude. Capture coaching remains a later phase; no media upload in this change.
**Tech:** Existing native SwiftUI, Foundation URLSession, Security/Keychain only if user chooses personal API keys; no external package.

## Architecture and decisions
- Preparation gets its own main-actor observable state: idle → preparing → presenting → idle on actual presentation. Set state synchronously on tap; ignore duplicates; cancel on exit/background; never present after cancellation. Cover permission/session and first-layout delays with a branded Core Animation pulse, respect Reduce Motion. Keep real countdown independent. No artificial waiting.
- Existing preview hardware already uses an actor; the reported 7–8 seconds is not reproduced from source alone. Do not claim an exact root cause or performance gain without device timing.
- User approved personal API keys stored locally in device-only Keychain, without a relay server.
- Original Script remains intact. Generated scripts have new UUIDs, a source/root ID and a style marker; no title-based relation. Keep edits independent and let every version use existing editing, copy, rehearsal and recording flows. Takes remain bound to the specific script version; script-family display labels the style.
- One generation request returns all three styles plus four speaking points per style. Validate exactly one dynamic, empathetic and concise version; nonempty bounded texts, no partial saves, no automatic retries/extra charges, show a review before a single atomic library save.
- Regeneration produces another review; never overwrite an edited existing version implicitly. Prompt preserves facts, offer, prices and language; user reviews wording because semantic faithfulness cannot be guaranteed by schema validation.
- Settings show the selected provider, model, connection status and a deliberately initiated connection test. Credentials never enter scripts.json/UserDefaults/logs/repo/backups. Never silently switch provider or upload on screen open. API billing and text disclosure are visible at generation action.
- Network calls are bounded, cancellable, use fixed official HTTPS hosts and sanitized errors. No raw provider error/body or secret is displayed/logged. Invalid/truncated/refused output is never saved.

## Tasks
- [x] Preparation RED/GREEN tests: immediate state, deduplication, presentation acknowledgement, failure and cancellation during a delayed async operation; connect loader to Setup/Recording and verify existing mic-denial flow.
- [x] Core RED/GREEN tests: old-script decoding, independent version identity/editing, exact three-style validation and atomic family insertion/preservation.
- [x] Confirm connection method; fetch official request/model docs, implement settings/credential store and provider adapters with contract tests using fake transport and dummy credentials only.
- [x] Add generation/review/save flow, style-family navigation, editable speaking points and take/style association.
- [x] Full Core, iOS unit and relevant UI checks; independent review; device build/install and data preservation; focused stacked PR.

## Acceptance and review focus
Cancel while permissions or network are pending; close/background the screen before work completes; changing provider/model/key invalidates connection-test status; key save/delete failures visible; no plaintext key persistence or network redirects forwarding it; generation from edited originals does not reset existing drafts/takes; duplicate style output and missing speech points fail all; very long Hebrew/English text and accessible font sizes; native loading animation keeps moving while the main thread measures text; status never says a real provider was verified using fixtures alone.

## Verified outcome
27 Core tests, 24 iOS unit tests, 10 UI journeys and 3 bridge tests passed. Signed device build and deep signature verification passed. Installed without uninstall; scripts/takes byte-identical before/after. Physical launch blocked by device lock; unlock requested. No real API key or paid generation used; account connectivity and generated wording need user-side verification. Independent review findings (cancellation and points-only sources) fixed and rechecked.
