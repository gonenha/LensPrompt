---
name: lensprompt-script
description: Prepare a Hebrew video script for the personal iPhone app מול העדשה and, after the user's explicit approval, send its title, scrolling text and four speaking points from this Mac through the paired device connection. Use for requests such as תכין תסריט למול העדשה or שלח את התסריט לאייפון; not for generic writing or publishing videos.
---

# Script to מול העדשה

Prepare the requested spoken script in the conversation. Include a title, the full text for scrolling, and four short natural-speaking reminders: הפתיח, הכאב, הפתרון, ההצעה. Follow the user's topic, audience, tone and length; do not invent brand facts. Ask only for information that materially affects the draft.

Save a UTF-8 JSON draft under this task's user-facing outputs directory. Use a fresh UUID for each new or revised draft, and this shape:

- `version`: integer `1`
- `id`: fresh canonical UUID string
- `title`: nonempty title
- `text`: nonempty full spoken text
- `points`: object with nonempty string keys/values `opening`, `pain`, `solution`, `offer`
- `mode`: `scrolling` (default), or `talkingPoints` if requested. Both forms remain available inside the app.

No NUL characters; total file <=1MB UTF-8. Title <=1,000 UTF-8 bytes, full text <=800,000, each point <=50,000. Use structured file writing, not shell interpolation of the user's words.

The helper beside this skill is `scripts/send_script.py`. Validate the completed file with `python3 <skill-directory>/scripts/send_script.py inspect <draft-path>` and keep its SHA-256. Show the exact title, full text and all four points to the user for review. The user requested approval before transfer: **do not send until the human explicitly approves this final draft**, e.g. ״מאשר, שלח לאייפון״. Approval of the feature itself is not approval of an unseen script. A revision needs a new UUID, a new review and approval.

After approval, use the exact unchanged file and hash:

`python3 <skill-directory>/scripts/send_script.py send <draft-path> --approved-sha256 <approved-hash> --device <paired-device-id>`

There is no default device. Ask the user to identify their paired physical iPhone and pass its identifier explicitly with `--device`; the app bundle is `personal.lensprompt.app`. List paired devices with `xcrun devicectl list devices` when needed. The iPhone must be paired to this Mac and reachable by cable or wireless development connection. Do not select a simulator because its name mentions iPhone 15. Do not change the target, reset pairing, create certificates, reinstall the app or alter phone settings as part of sending a script.

The helper stages an immutable payload and then a ready marker, never writes scripts.json or touches videos. The app imports on foreground polling or next launch; it defers import during a take. Same ID/hash retries preserve local edits and do not duplicate or recreate deleted scripts. If the user wants revised content as a new script, create and approve a new draft ID.

Read the helper's structured result:
- `acknowledged`: the app confirmed receipt of this ID/hash. Report acknowledgment. On a retry, this is historical: the user may have edited or deleted the original since receipt; do not claim it is currently present or unchanged.
- `queued`: transfer completed but app import is unconfirmed. Say it is waiting for the app to be opened or the take to finish; do not claim it is already in the library.
- `error`: preserve the approved draft and report the actual issue. For a disconnected phone, ask the user to connect it; do not silently switch devices or send destinations. After a transient connection issue, at most one retry of the same approved bytes is appropriate once connectivity is restored. Changed content must never reuse the approved ID.

This is a local Codex-to-personal-app workflow. It needs no OpenAI API key, server or third-party messaging account. Transfer is not video publication. Do not send any script or message to other people.
