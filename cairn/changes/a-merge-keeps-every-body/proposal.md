---
cairn: change
id: a-merge-keeps-every-body
status: landed
created: 2026-10-30
---

# A merge keeps every body it does not adopt

## Why

Edit 4 of the pimdir stable-release plan (2026-10-30), from blocker 4 of the consolidated pimdir review and the app reviews. Each gap below loses an edit without a conflict, against the 3-way merge principle (never last-writer-wins, same-instance edits conflict):

- **A queued `update` has no base.** STORAGE §15.3's payload names no expected object, so two producers (calendula and unfog editing one VTODO, or two runs of one) both pass their own check and the owner applies the second over the first, a local last-writer-wins the merge never sees.
- **The shared body is not pinned.** When the shared item holds no body (a body-less pull writes `Meta`), SYNC §9 cannot see a divergence and a local edit is dropped (io-pimdir src/hub.rs:467-494, by reading); neverest works around it with an in-memory ancestor (driver.rs:3478-3866). STORAGE §5 counts no `shared_object`, so the agreed body may be collected while a binding still reconciles against it.
- **`prefer-incoming` and `prefer-existing`** (STORAGE §13, SYNC §5, §9) discard the losing body with no record and no event. They stay (neverest's one-way modes use them, driver.rs:338-339), opt-in, but the loser must stay pinned and reported.
- **`SetFlags` replaces absolutely** (SYNC §4, :126): a server flag change between the listing and the push is overwritten. algorithm-audit-2026-09-04 ledger :79.
- **Pushes gated on `if_match` "where supported"** (SYNC §4, :125, :127) leave an unguarded window nobody is told about (a-source-states-its-write-guard).
- **An `add` whose body is unreadable** is applied by io-pimdir (unfog probe); STORAGE §15.2 calls a body unreadable an environment failure, retried, without a MUST nor a vector.

## What

- STORAGE §15.3: an optional `if_match` on the `update` payload, the body the producer replaced; the owner parks the row when the item's current body differs. SYNC §7: an `Edit` carrying it is refused.
- STORAGE §5, §6, §13, 0001_init.sql: `bindings.shared_object` is counted and references `objects(hash)`; `recompute_refcounts`, `collection_holds_objects`, `release_bases_before` follow, `repair_shared_objects` clears a swept one before reconciliation rebuilds `bindings`, which recounts after its backfills.
- SYNC §9: a body-less upsert and one leaving the item conflicted move no `shared_object`; an item holding no body has changed; a body fills an item a pull emptied; a divergence whose incoming body is not carried is recorded as `manual`; SYNC §6: the upgrade fetches that body into `items.conflict_object`. STORAGE §10: a fill leaves an item conflict standing.
- SYNC §5, §9, STORAGE §11, §13: the body a policy does not adopt is kept as a retained item and reported `Overruled`.
- SYNC §4: `SetFlags { handle, add, remove }`; vectors 02, 03, 09, 26, 27, 42 and checks/vectors.py's change key follow.
- SYNC §4: the unguarded window stated.
- STORAGE §15.2 and SYNC §7: an `add` or `update` whose body is unreadable is retried, then parked, never applied bodiless.
- GUIDE §2, §10 to §13 and OVERVIEW §6 follow.

## Decided (2026-10-30)

- The shared body is pinned by counting `bindings.shared_object` always, like `base_object`: one body per binding, the latest agreement point, which is the merge ancestor an engine reads. The earlier rationale (counting it "would pin every body a source ever agreed with") was wrong.
- The `prefer-*` loser is a retained sibling item under the minted key, not `conflict_object` (the schema `CHECK` stays), purged by the normal retention purge, reported as `Overruled`. The same holds for the local edit `PreferRemote` drops. `PreferLocal` overwrites a body the store never read, so it has nothing to keep; a source that must keep the server's body uses `Manual`.
- The payload stays at `v` 1: `if_match` is optional, its absence is the behaviour before it, and an owner predating it applies the row unguarded as before. A future field an owner must not ignore takes a new `v`, which should-fix-before-the-freeze makes skipped by an owner that does not know it.
- Not adopted as written: "a body-less upsert never clears the item's held body". With no local edit, the binding's base names the new revision and no body; keeping the old body would make that binding `Dirty` (SYNC §3 rule 4) and push the stale body over the server's unread edit. The item drops its body on a fast-forward as before, and what the orchestrator's rule protected (a local or another source's edit meeting a body-less pull) is kept by the divergence and fill rules instead.
- A divergence, and every upsert leaving the item conflicted, moves no `shared_object`: moving it there would unpin the ancestor at the moment a conflict needs it (vector 28 and 33 now keep b's at c1).

## Lands in

storage-draft-05 and sync-draft-05.
