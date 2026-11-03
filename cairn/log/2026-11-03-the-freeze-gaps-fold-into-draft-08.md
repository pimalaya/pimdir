---
cairn: log
change: the-freeze-gaps-fold-into-draft-08
date: 2026-11-03
---

# The freeze gaps fold into draft-08

The open sync items the ledgers held before the pin (io-pimdir and every app on one pimdir commit), decided by the user on 2026-11-03 as recommended, folded into storage-draft-08 and sync-draft-07 with no number bump, no tag naming either yet.

Rules, and the check guarding each:

- **An edit over an unread base waits** (SYNC §5 content axis, §6 claims revisited; audit-2026-10-31 S10). A local body over a base naming a revision and no body derives no `Update`, nor the `Remove` a move's staged edit rides ahead of: the server's body at that revision was never read, and the push would lose it unkept. An upgrade at `Full` revisits it and reads that body into the base, after which the edit pushes. Guarded by vectors/sync/132 (no push) and 133 (the upgrade), and by checks/vectors.py, whose `Update` rule no longer counts a base naming no body as agreed; its "faces no body" rule exempts an edit staged before the run.
- **A capped listing proves no absence** (SYNC §4 `capped`, §5; audit-2026-10-31 :98). A source listing at most a number of members misses the same ones at every round, so a confirming round cannot help. A connector knowing of the cap sets `capped` on every page of the collection's rounds; such a round finds nothing absent, deletes only what the source states removed, and closes. This replaces the guard the ledger asked for: parking would hold every round open for ever, since the same members are missing each time. Guarded by vectors/sync/134 and checks/vectors.py (every page of a capped round says so; a capped round's absence is no drop). vectors/schema/sync.schema.json gains `capped`.
- **A bodiless copy needs its source in the target** (SYNC §7, §10; audit-2026-10-10 :27). A `Copy` or a `Move` of a placement holding no body is refused unless its binding is based and its source syncs the target (`collection_sources`): only that source holds the origin, and another source is offered the create once the body is held. Guarded by vectors/sync/135 and checks/vectors.py.
- **`Overrule` and `Settle` are batch operations** (STORAGE §14, SYNC §7, §10; the-consumers-gaps-fold-into-draft-08 :16). The write contract named neither, though SYNC §7 has the engine state both. Text only: the vectors already run both (100 to 105, 118 to 123).
- **A resolution naming both conflicts settles both** (two-silent-losses-fold-into-draft-08 :14). vectors/sync/131: the item and the binding settled in one write, nothing retained.

Proved: copies of 132, 134 and 135 broken as the rules forbid (132 pushing the `Update`, 134 dropping binding 10, 135 not failing) fail checks/vectors.py with "Update a.vcf is gated on a revision whose body was agreed or read", "binding 10 leaves only for a stated removal or a closed round's absence in scope" and "a Copy no body nor origin could deliver fails". `nix flake check path:$PWD` passes. io-pimdir failed 132 to 135 before following (its cairn/log/2026-11-03-the-crate-follows-the-freeze-gaps.md).

GUIDE.md and OVERVIEW.md follow.
