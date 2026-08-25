---
cairn: log
change: spec-algorithm-audit
date: 2026-08-25
---

# The format's own algorithm findings landed

A first-time reading of SPEC.md, the migration, the canonical statements and the reference implementation (`spec-algorithm-audit`) found rules that are unsound, complexity claims that are false, and reads the schema promises but never indexes. The ones that could be settled without freezing a still-draft decision landed here and in io-pimdir together; the rest stay in the change folder.

## What landed

- **A one-row write no longer costs a whole-collection read** (§14). The write step said "merge the batch into the collection and persist the result", and an implementation persisting the diff still read everything to compute it. The batch only ever produces writes for the rows it names, so the rest of the collection was read and merged to conclude nothing changed. §14 now states the batch-scoped read, with `load_items_by_link`, `load_bindings_by_link` and `link_for_handle` as the canonical statements and `bindings_by_handle` as the index that makes resolving a dropped handle a seek. Measured on io-pimdir, one flag on one message went from 3.5 ms at a thousand items and 59 ms at sixteen thousand, cleanly linear, to a flat 150 to 175 µs across the same range: §1 promises hundreds of thousands of items, and the write path did not meet it.

- **The drain claims its row before doing its work** (§15.2). `load_pending_actions` is read outside any transaction and the delete ran last, so two owners holding the same list both applied every action, and `add` and `copy` are not idempotent. `delete_action` becomes `claim_action`, a `DELETE ... RETURNING id` that runs first: exactly-once is now a property of the statement rather than a convention about who runs the drain, and it no longer rests on §8's advisory lock, which nothing implements.

- **A blob rename is made durable** (§5). The rule said temporary file, `fsync`, `rename`, which makes the bytes durable and says nothing about the name that reaches them. The database commit *is* durable, so a power loss could leave a committed row pointing at a body that never arrived: the one asymmetry §14's write order exists to prevent. The shard directory is now synced after the rename.

- **The object sweep is indexed and no longer leaks a negative count** (§5). `refcount = 0` becomes `refcount <= 0`, so a count a double release drove negative is collected rather than leaking for ever with nothing reporting it, and the new partial index `objects_garbage` matches that predicate exactly. Without it both halves of the sweep scanned the whole `objects` table, on every write transaction, including batches that touched no object at all.

- **The store-global public id has a store-global index.** §9.1 makes `seq` the id a consumer displays and accepts back without naming a collection, while the only index led with the collection, so resolving one meant scanning it whole. `items_by_seq_global` serves the read the spec already promised.

- **The other two pointers at an object are indexed**: `items_by_conflict_object` and `queue_by_object`, so a refcount recomputation can reach every reference by index rather than by scanning `items` and `queue` once per object row.

## Not landed, and why

- **`lookup_objects(links)` takes no collection** (§14), and §9.2 already names the hazard it walks into: two unrelated servers minting the same vCard `UID` hand each other's bodies across accounts. The fix is a signature change on io-replica's storage seam, which carries no collection on that yield either, so it belongs to a change that moves both.

- **§13 infers a binding's base from three nullable columns**, which makes a base of unknown flags, no revision and no object round-trip to no base at all: an agreed placement then reads as never-agreed and re-pushes for ever. A `base_present` column (or a `'null'` JSON encoding distinct from SQL `NULL`) fixes it, but whether io-replica can currently produce that shape on a linked placement is still open, and the answer decides whether this is a live bug or a latent one.

- **§5 and §14 disagree about an object with no referrer.** §14 invites a consumer to stream a body and index it without holding it whole, while §5 lets any refcount-zero object be deleted, so a consumer that streams bodies in one batch and places them in a later one loses them silently. Either the format requires an object to be referenced by the batch that indexes it, or the sweep needs the grace window the operator sweep already has. That is a decision, not a repair.

- **`recompute_refcounts` claims O(items+bindings+queue) and is O(objects × items)**: its `OR` chain defeats `items_by_object`. The two indexes above remove the worst of it, but the statement itself should become the `UNION ALL` + `GROUP BY` form io-pimdir already carries in its operator CLI. Left for the change that rewrites it, so the claim and the statement move together.

- **`objects.refcount` still has no `CHECK (refcount >= 0)`.** Worth having, and adding a constraint to an existing table is a rebuild, which the draft-shape reconciliation does not do today.

- **§8's advisory lock** is still unimplemented. The claim above removes the drain's dependence on it, but the concurrency envelope itself, one process with many handles or many processes, is still unstated, and several remaining findings need that answer first.

## Verification

- io-pimdir: 84 tests green, `cargo clippy --all-targets --all-features` clean. Its spec-fidelity suite compares the inlined DDL against `migrations/0001_init.sql` through SQLite's own pragmas and every canonical statement name against the constants, so the schema and statement changes here are checked against the implementation on both axes.
- The scaling figures above were measured with a throwaway release-mode probe against the reference store, before and after, and are not kept as a test: a timing assertion would be flaky where the query plan is the thing that actually changed.

## Addendum, same day

Three of the findings this entry left open were settled once `duplicate-link-id-freeze` had moved the implementation repos together.

- **`lookup_objects` is scoped, by account rather than by collection (§14).** The audit asked for a collection scope and that would have been wrong: across collections the answer is exactly what the read exists for, one message filed in two mailboxes being one body downloaded once. The account is the axis a link id is trustworthy on, and the one §9.2 already names. A single-account store writes no account, so the filter is a no-op there. No seam change was needed, so the reason this was blocked turned out not to hold.

- **§13 no longer infers a base's presence from three nullable columns.** `bindings.base_present` states it, the value columns remaining a witness only for rows written before the column existed. The shape that was unrepresentable, a source reporting no revision, no body and markers nobody has read, is a real agreement, and losing it had the placement read as never-agreed for ever.

- **`release_pins` joins the canonical statements**, the set-based form of `adjust_refcount` at -1, so settling many pins at once is one statement rather than one per hash.

Still open, unchanged: the concurrency envelope (§8's advisory lock is still unimplemented, though the drain no longer depends on it); the disagreement between §5 and §14 about an object indexed with no referrer; `recompute_refcounts`' false complexity claim and the `UNION ALL` rewrite that fixes it; and `CHECK (refcount >= 0)`.
