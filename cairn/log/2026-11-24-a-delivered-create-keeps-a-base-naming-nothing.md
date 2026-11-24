---
cairn: log
change: a-delivered-create-keeps-a-base-naming-nothing
landed: 2026-11-24
---

# A delivered create keeps a base naming nothing

Found pinning, on the lead's request, the revive io-pimdir gave a tombstoned delivered create on 2026-11-24 (a copy over the source's own tombstone, vectors 216 to 219). SYNC.md §2 defines a delivered create as one bound under its provisional handle with a base naming no flag set, revision nor body, and a relocation stating its member's handle lands it only so (§4). io-pimdir gave such a base the item's body whenever a mutation wrote the placement, as it gives one to any binding of an immutable kind: a flag change staged on a delivered create, or a copy reviving a tombstoned one, left a base naming the body, and the relocation then passed the create by, its provisional handle never replaced by the one the server stated. Before the revive, a copy over a tombstoned delivered create staged a pending create under the same handle with no base, forgetting the delivery, so a second `Add` would have been pushed.

No part's text moves: SYNC.md §2, §4 and §7 and STORAGE §9's table (a tombstone holding a delivered create, revived) already state it. sync-draft-15 and storage-draft-17 keep their numbers.

## SYNC.md §2 and §7, a mutation on a delivered create

- A copy reviving a tombstoned delivered create of its source keeps it delivered, under its provisional handle with a base naming nothing. Vector 220 (io-pimdir at f7d10db gave the base the copied body; at b0000aa it left no base, a pending create again).
- A flag change staged on a delivered create sets the item's flags and leaves its base naming nothing. Vector 221 (the base took the body).

io-pimdir follows in the commit checks/io-pimdir.rev names.
