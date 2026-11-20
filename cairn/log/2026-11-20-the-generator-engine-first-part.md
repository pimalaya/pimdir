---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's scripted remote and engine, first part

The first part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **The scripted remote** (generator/src/remote.rs): one source's side of a mailbox as an IMAP server with CONDSTORE and QRESYNC keeps it: UIDs as handles, a modification sequence as the checkpoint, a round answered newest first in pages, each page's members in handle byte order and the checkpoint on its first, a delta answering the members changed above a checkpoint and the UIDs expunged above it (SYNC §4); deliveries, flag changes and expunges by another client; pushes accepted, an add assigned a UID.
- **The engine model** (generator/src/engine.rs), from SYNC §3 to §6: a first round names every member at `Meta`, stamps its bindings and closes, finding absent what it did not list; a delta names, merges and drops what it states removed; the flag axis keeps what both sides carry or one added over the base and drops what the base held and a side dropped; a tombstone pushes a `Remove`, a pending create an `Add`, a flag set off what the source holds a `SetFlags`, in handle byte order, each keyed as SYNC §4 derives; an accepted push rebases, an accepted add moving its binding to the assigned handle; an upgrade fetches a body into the item and its base. The rounds a source closed are written back by replaying `open_round`, `stamp_bindings` and `close_round`.
- **Histories** (generator/src/history.rs): one mailbox through a first round of three pages, an upgrade, another client's flag change, removal, delivery and unflagging, a flag change, a delete and a message drained, a delta pulling and pushing, a flag changed on both sides, and a run with nothing left to do.
- **Checks**: every push of vectors/sync carries the key this crate derives, by the fields and by the typed pushes it models; each step's store is written and self-checked, its feed ordered; tests state from SYNC what each run lists, pushes and reports, a flag removed by the remote dropped, and the last run changing nothing. Broken by hand to see each fail: a merge keeping the union over a base, a pull leaving the base unmoved, an add's key without its origin field. A merge keeping the union passed until the history held a flag removed on one side.
