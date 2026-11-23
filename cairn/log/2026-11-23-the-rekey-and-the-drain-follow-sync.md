---
cairn: log
change: the-rekey-and-the-drain-follow-sync
landed: 2026-11-23
---

# The rekey and the drain follow SYNC

io-pimdir's rekey departed from SYNC.md §4 and §8 in the cases cairn/changes/a-smaller-sync reproduced (K3, R0 to R8), two of them silent losses, and its queue drain from §7 (K4). io-pimdir cairn/changes/what-the-consumers-need fixed the engine; this entry records what SYNC.md, edited in place (sync-draft-15 is untagged), now states, and the vector that fails without each rule. storage-draft-17 and search-draft-17 do not move.

## SYNC.md §8, the rekey

- An unknown listed flag set leaves the base's, holding no opinion (§3): a flag change still owed stays owed and the next sync pushes it. Vector 201 (R4, a silent loss: the base took the unknown set and the owed flag was never pushed).
- A conflict the old handle held is carried as it is when the listing states no revision. Vector 202 (R1, a silent loss: the conflict was cleared and its diverging body made collectable).
- A delivered create a member resolves to is landed as a page lands it (§6): its provisional handle dropped `Superseded`, its staged flags kept over a base of the listed flags and its staged body, `Created` reported. Vector 203 (R5).
- A member resolving to no old binding is named as a page names one: it joins a create the store offers the source, reported `Added` (vector 204, R6b), lands a pending create of the source whose key it states and whose summary it agrees with, reported `Created` (vector 205, R6a), and is minted apart, reported `Disagreed`, when the summary disagrees (vector 206). A pending create's key counts as taken only unless the member lands it: rule D10 of io-pimdir's change, where the rule counted it taken whatever the member, so the member was minted apart and the add pushed again, a second message on the server (neverest NV1).
- A conflicted tombstone is carried with its conflict, a delete settling none (§3), listed at its base revision (vector 207, R2b) or at its conflict's (vector 208, R2c): never settled, never revived, no `Remove` derived.
- A tombstone holding a local edit met by a remote edit is a `Conflict` at the fetched revision holding the listed body, as a page records it. Vector 209 (R3: it was revived as a pull and the edit kept only by an item retained apart).
- A listing holding a handle twice is read by its first entry, as a page reads it (§4). Vector 210 (R0: the first entry's flags were carried under the last entry's identity, the old item dropped `Deleted`).
- A body the listing carries is stored as a page stores it: an arrival's and a pull's become the item's body and the base's, at `Full`. Vectors 211 and 212 (R8).
- A binding with no base a member resolves to takes a base of the listed flags alone, claiming nothing reconciled, its conflict kept; one no member resolves to is re-staged under its provisional handle (rule D1, today's outcome stated). No vector can state that starting state (checks/vectors.py: a binding has a base unless provisional), so io-pimdir's tests/engine/rekey_cases.rs pins it.
- Vector 213 pins a tombstone listed at its base carried with the listed flags riding along (R2a, as SYNC already stated).

## SYNC.md §5, the events

- A rekey reports `Created` for a create it lands and `Disagreed` for a member it mints apart from a create, as a page does, besides `Added`; io-pimdir's rekey also reports `Overruled` from its write's answer, as any verb whose write keeps a body apart does.

## The drain

- The vectors have no drain verb, so K4 is checked in io-pimdir: tests/drain_copy.rs (a queued `copy` or `move` into a collection another source binds the identity in joins that item, as `store.mutate` does, where it minted a second item under a `dup:` key) and, in tests/vectors_sync.rs, every mutate vector a queue action expresses drained to the vector's rows (17 cases, none disagreeing).

## Checks

- vectors/manifest.json restated for vectors 201 to 213; vectors/README.md names each.
- checks/io-pimdir.rev names the io-pimdir commit whose suite passes them, set in the commit after this one.
- cairn/changes/a-smaller-sync/tasks.md ticks K3 and K4; cairn/changes/a-smaller-pimdir/consumers.md gains the two statements the Android store binds that io-pimdir 46d851f dropped (Android lane AN2).
