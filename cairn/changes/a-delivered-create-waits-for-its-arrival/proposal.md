---
cairn: change
id: a-delivered-create-waits-for-its-arrival
status: landed
created: 2026-11-11
---

# A delivered create waits for its arrival

## Why

A create the source took before any listing named it had no state of its own. SYNC §4 left an add accepted with no handle (an IMAP `APPEND` without UIDPLUS) a pending create, and a relocation accepted left its destination's create pending too. Both read as "not delivered", so:

- a `Remove` or a `Move` staged on such a create withdrew it (SYNC §7, io-pimdir mutate.rs: a tombstone with no base is dropped): nothing reached the server, and the next listing brought the message back. The Android app hit it on Gmail (android cairn/log/2026-11-11-gmail-trash-stays.md): a message deleted into the trash, then deleted for good or restored from the trash before the trash was listed, came back;
- an engine or an app had no way to tell a create waiting for its push from one waiting for its listing, so an app withdrew a move's target on delivery and lost what was staged on it (the `\Seen` an opened message carried).

## What

1. **A delivered create** (SYNC §2): a pending create its source accepted before any listing named the member, its `Add` accepted with no handle or a `Remove` relocating into it accepted. Its binding keeps the provisional handle and gains a base naming nothing (`base_present` 1, no flag set, revision nor body). No schema change: a binding under a provisional handle holding a base is the state.
2. **The write** (STORAGE §14): a new op, `DeliverPlacement { collection, handle }`, run by a new owner statement `deliver_binding`, conditional: it bases the binding only while it holds no base, so a create landed, withdrawn or delivered since is left alone. An engine writes it for an add accepted with no handle, and for an accepted relocation into the destination's collection, in the write recording the outcome (SYNC §4, §10).
3. **It waits** (SYNC §5): a delivered create derives no `Add`, `SetFlags`, `Update` nor `Remove`; no absence finds it (`list_unstamped_bindings` leaves out provisional handles, and the mass-absence count with it); no run drops it but the one landing it. A `Remove` or a `Move` staged on it tombstones it, binding and base kept (SYNC §7), held for the page that lands it. It waits whatever a round lists, and an engine reports it while it waits.
4. **It lands** (SYNC §6, STORAGE §9's table): the page naming its member lands it as a pending create lands, a tombstone keeping its status and destination, and the run pushes what it owes against the listed handle. A rekey carries it onto the member resolving to its link id and otherwise leaves it as it is (SYNC §8). No upgrade fetches a provisional handle (SYNC §6).
5. **No origin** (SYNC §3): `origin_for_link` leaves out a binding under a provisional handle, which names no member to copy from.

## Decided

- **A base naming nothing, not a new column or status.** The projection already reads a based binding; marking delivery with `base_present` alone keeps storage-draft-09 and every reader as they are, and an engine tells a delivered create by its provisional handle. A new `Status` would have every implementation's projection (the Android app derives it in Java) learn it; a new column would be a schema change.
- **Conditional, folded in order.** A relocation's outcome is written by the source collection's run, which never loaded the destination; the target may have been landed or withdrawn meanwhile (another session's run, an app withdrawing on a non-account-wide server). The op therefore checks the row it moves rather than trusting the engine's view, and an implementation applying the diff form folds it into the batch in order so an earlier upsert of the same binding never undoes it.
- **The base names no flags.** What the server gave the relocated or appended member is unknown until its listing; the landing sets the base from that listing, so the flags staged on the create (a `\Seen`) push then, as a three-way merge says they should.
- **Only a create a listing can land is delivered.** A create keyed by a key minted over a member's handle (`dup:<hint>#<handle>`, carried by a `Copy` or a `Move` of a member its own collection minted) is landed by no listing, no source stating such a key; delivered, it would wait for ever. It stays pending, as it was. Found by io-pimdir's identity property test.
- **A round proves nothing of a delivered create.** A round may have listed its first pages before the relocation, and a connector deletes rather than relocates when the target already holds the identity (§4), which the store may bind under another key; neither tells a delivered create to give up, and giving up would reopen the withdrawal this change closes and let an app take the arrival's markers over the staged ones. It waits, reported (SYNC §5), as a create waiting for its scope is. An earlier draft of this change re-pended a live one on a closing round; the review of 2026-11-11 found both faults.
- **A delivered create stays a destination** (`destination_for_link`), so an owner may record the delivery before the relocation leaves (SYNC §4): a consumer staging a delete or a restore on the target while the push is in flight then meets a delivered create, held, not a pending one it would withdraw, and a relocation that never went is pushed again rather than its tombstone turning into a delete.
- **A delete takes a member out of its collection alone** (SYNC §4). On a source where one id names a message in every collection (Gmail, JMAP), a `Remove` naming no destination (a move whose target landed first, a restore whose target another client landed) carried out as a delete for good took the message out of every mailbox. The Android app destroyed a trashed Gmail message that way (its patch account-wide-destroy, independent of this change).
- **sync-draft-09, storage-draft-09 in place** (the owner, 2026-11-12). An engine of sync-draft-08 opening a store holding a delivered create reads a based binding under a provisional handle: it pushes `Update` and `Remove` against the provisional handle and drops it as absent (vectors 136 and 139 fail on io-pimdir 5c18a02). The sync part is bumped so every engine refuses the other's sync state (SYNC §10). Storage needs no bump: no migration moves and a storage-draft-09 store is the same store; its statements changed, which only an engine of the new sync draft runs. Existing Android stores are refused and rebuilt by reinstalling, their unpushed changes lost, which the owner accepted.

## Lands in

sync-draft-09, new and untagged (its Status line, README, AGENTS.md; the tag the owner's), and storage-draft-09 as it stands, untagged. io-pimdir follows on its branch delivered-create (cairn/changes/a-delivered-create-waits-for-its-arrival there); checks/io-pimdir.rev moves once both are committed.
