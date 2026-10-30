---
cairn: change
id: every-vocabulary-is-open-or-closed
status: landed
created: 2026-10-30
---

# Every vocabulary is open or closed

## Why

Edit 6 of the pimdir stable-release plan (2026-10-30), from blocker 6 of the consolidated pimdir review. A `CHECK` change is a table rebuild and, after the freeze, a new schema version (the-store-version-is-a-contract), so each vocabulary has to be decided closed (held by a `CHECK`, grown by a version) or open (no constraint, grown within a version, an unknown value read as this standard says) before version 1 is released.

## Decided

- `collections.kind`: closed, `''` until declared or one of the four media types. The `CHECK` is no-custom-kinds' and lands here; a collection an earlier draft declared with another media type is repaired to kindless (`repair_kinds`), the rest of no-custom-kinds (the rule for a source offering another media type, OVERVIEW) staying with it.
- `collections.conflict`: closed, as it was.
- `capabilities.support`: closed, as it was.
- `items.level`: closed as {1, 2}. The `0` earlier drafts wrote is repaired to `1` by reconciliation (`repair_levels`), and only a reader of an unreconciled store still reads one, as `1`.
- `collections.role`: open, its `CHECK` dropped. The JMAP role vocabulary follows the IANA registry, which grows; a reader reads a role it does not know, or one of another kind's vocabulary, as none. The one-holder index (`collections_by_role`) stays.
- `item_reference.role`: as is (named roles or `x-`).
- `store_meta.hash_algo`: stays `blake3` or `sha256-128`. Edit 9 of the plan (BLAKE3 only) is **dropped**: its precondition was that no existing store uses SHA-256, and the Android app creates its stores with `hash_algo` `sha256-128` (android/app/src/main/java/org/pimalaya/pimdir/PimdirHash.java:16, PimdirDb.java:143). No spec edit; whether a `CHECK` holds the pair is not decided here.

## What

- migrations/storage/0001_init.sql: `CHECK` on `collections.kind`; `collections.role` without a `CHECK`; `items.level` `CHECK (level IN (1, 2))`.
- queries/storage/owner/repair_levels.sql and repair_kinds.sql (new), run by reconciliation's repair step.
- STORAGE §4.3, §6, §13 (what closed and open mean, the list, `kind`, `level`), §14 (`role` open); SYNC §3 and §6, GUIDE §3, §9, §11: the `0` reading gone from the engine.
- vectors/sync/30: its store row at `level` 1 rather than an earlier draft's 0; checks/vectors.py checks every sync and search kind is of the set and every level of the ladder.

## Lands in

storage-draft-05 and sync-draft-05.
