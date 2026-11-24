---
cairn: log
change: a-copy-revives-its-sources-own-tombstone
landed: 2026-11-24
---

# A copy revives its source's own tombstone

Found draining the queue of the live test night of 2026-11-23 (.lanes/live/report.md of the workspace, §9), once a fourth copy took a key of its own: himalaya moved a message out of a folder and copied it back from INBOX, both through its pimdir queue, before any sync pushed the move. The copy was parked for good, "binding stalwart/imap/nv-copy/nv-abs-10@example.org on source stalwart/imap holds handle 4 and this write carries \1nv-abs-10@example.org: a binding pins one handle". Nothing was lost (parked, server untouched).

STORAGE §9's table already had a copy, a move and an add revive a tombstone holding the key, the source's own based one included ("a tombstone revives as below"), and STORAGE §10 has a binding pin one handle; SYNC.md §7 said "the create taking the key and reviving it", which reads as a create under the provisional handle, the very write the binding refuses. The text now says how the source's own tombstone is revived. sync-draft-15, storage-draft-17 and search-draft-17 keep their numbers (none is tagged).

## SYNC.md §7, `Copy`, `Move` and `Add` over the source's own tombstone

- A tombstone the run's source binds itself, its delete not pushed yet, is revived under the handle it is bound to, its binding and base kept: no create is staged, the row takes the body and flags copied, its delete is withdrawn and the destination it offered no longer derives, as for an `Edit`. A `Move`'s own tombstone then offers none, its `Remove` a plain delete. Vectors 216 (copy) and 217 (move): the engine staged a create under the provisional handle and the write refused the rebind.
- An `Add` revives such a tombstone the same way, and an add of another message reusing the identity is minted beside it. Vectors 218 and 219, failing the same way.

io-pimdir follows in the commit checks/io-pimdir.rev names.
