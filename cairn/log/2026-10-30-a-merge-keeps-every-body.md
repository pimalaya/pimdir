---
cairn: log
change: a-merge-keeps-every-body
date: 2026-10-30
---

# A merge keeps every body it does not adopt

Edit 4 of the pimdir stable-release plan. Six gaps each lost an edit without a conflict: a queued `update` had no base, the agreed body was neither pinned nor kept by a body-less pull, `prefer-*` discarded their loser, `SetFlags` replaced absolutely, the unguarded push window was unstated, and an `add` with an unreadable body could be applied.

- **STORAGE §5, §6, §7, §13, 0001_init.sql** (normative, schema): `bindings.shared_object` is counted like `base_object` and references `objects(hash)`, with `bindings_by_shared_object`; recompute_refcounts.sql counts six pointers, collection_holds_objects.sql reads it, release_bases_before.sql lets a shared body naming the released mail body go; reconciliation runs the new repair_shared_objects.sql before rebuilding `bindings` and `recompute_refcounts` again after its backfills, so every existing store is recounted once. Guarded by checks/invariants.sh ("shared: ...", "release: a shared body naming the released body ...", "reconcile: a shared body an earlier draft let the collector sweep ...").
- **SYNC §9 and §6, STORAGE §10** (normative): a body-less upsert and one leaving the item conflicted move no `shared_object`; an item holding no body has changed for a binding that agreed one; an upsert carrying no body over an item holding one disagrees; a body over an item a pull emptied, from a binding whose base names no body, fills it, an item conflict standing; a divergence whose incoming body is not carried is recorded as `manual` whatever the policy, the upgrade fetching it into `items.conflict_object`. Guarded by vectors 80 to 84; 28 and 33 now keep b's `shared_object` at c1.
- **SYNC §5, §9, STORAGE §11, §13** (normative): the body `prefer-incoming` replaced, the one `prefer-existing` refused and the local edit `PreferRemote` dropped are kept as a retained item under the key minted over the settling binding's handle, reported `Overruled` by whatever verb's write kept it. Guarded by vectors 85, 86 and 14.
- **STORAGE §15.3, SYNC §7** (normative): the `update` payload takes an optional `if_match`, parked on mismatch; an `Edit` carrying it is refused. The payload stays at `v` 1. Guarded by vector 87.
- **STORAGE §15.2, SYNC §7** (normative): an `add` or `update` whose body cannot be read is retried, then parked, never applied; `Add` fails, staging nothing. Guarded by vector 88 (`blob` false).
- **SYNC §4** (normative, connector seam): `SetFlags { handle, add, remove }`, derived against the set the source holds; the change key's `set-flags` fields are `add` then `remove`. Guarded by vectors 02, 03, 09, 26, 27, 42 and checks/vectors.py's key. Closes algorithm-audit-2026-09-04 ledger :79.
- **SYNC §4** (descriptive): the unguarded window of a source enforcing no precondition.
- **GUIDE §2, §10 to §13, OVERVIEW §6** (informative) follow.

The orchestrator's "a body-less upsert never clears the item's held body" was not adopted as written: with no local edit, keeping the old body beside a base naming the new revision and no body projects `Dirty` (SYNC §3) and pushes the stale body over the server's unread edit. The fast-forward still empties the item; the divergence and fill rules keep what the rule meant to keep.

The new scenarios were run against the statements and schema before the change and failed there ("shared: the body a binding last agreed with is counted, alone: expected [1|], got [0|c1]", "release: ... expected [h2 h3 h8 |4], got [h2 h3 h8 |3]"). `nix flake check path:$PWD` passes. io-pimdir mirrors migrations/ and queries/ byte for byte and follows in its own cairn; neverest drops its in-memory ancestor once it does.
