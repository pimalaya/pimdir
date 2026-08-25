---
cairn: change
id: spec-algorithm-audit
status: landed
created: 2026-08-25
---

# What a first reader finds wrong in the format itself

## Why

The format and its reference implementation grew together, one change at a time, each one reviewed against the state before it and none against the whole. On 2026-08-25 the spec, the migrations, the canonical queries and io-pimdir were read cold, in full, by a reader with no history of the design and no stake in defending it. This file records what that reading found on the **format** side: the requirements SPEC.md states that are unsound, unrepresentable, or provably slower than the complexity they claim. The implementation-side findings live in io-pimdir under `store-algorithm-audit`, and the engine-side ones in io-replica under `engine-algorithm-audit`.

Nothing here is agreed. It is a triage list: each item that survives review becomes its own change with its own delta, because several of them contradict each other about which side is wrong.

## What

### The spec asks for an unsound read

**§14 `lookup_objects(links)` takes no collection.** io-pimdir implements it faithfully (`LOOKUP_OBJECTS`, `src/sql.rs:491`), selecting store-wide on `link_id` and folding the rows into a map where the last one wins. §9.2 already names the hazard in its own words, that two unrelated servers may mint the same vCard `UID`, and answers it with "merging is conservative". But this read *is* a merge, and it hands one account's body to another account's sync, which then believes the item is hydrated. The signature should carry the collection; deduplication across collections is a separate, deliberate axis that `list_object_placements` already serves, where the caller decides.

### The spec makes a legal state unrepresentable

**§13: "a binding's `base` is present iff at least one of `base_flags`, `base_object`, `base_revision` is non-`NULL`".** Presence is inferred from three nullable columns instead of being stated. A base of unknown flags, no revision and no object is a legal agreement with a source that reports none of the three, and it round-trips to *no base at all*, which the engine reads as never-agreed and re-pushes forever. Either add `base_present INTEGER NOT NULL DEFAULT 0`, or make an unknown flag set encode as the JSON text `null`, distinct from SQL `NULL`.

### The spec's canonical repair is quadratic

**`queries/objects.sql:23` `recompute_refcounts`** claims O(items+bindings+queue) and is O(objects x items). Its `OR` chain over `i.object_hash` and `i.conflict_object` defeats `items_by_object`, and no index covers `items.conflict_object` or `queue.object_hash`, so `EXPLAIN QUERY PLAN` reports a full `SCAN i` per object row and a full `SCAN q` per object row. On a 200k-item store that is on the order of 10^10 row visits. io-pimdir already carries the correct shape in `src/cli/db.rs:145`: a `UNION ALL` of the four pointer columns, grouped by hash and left-joined against `objects`, which plans linearly. The spec should adopt that statement and add the two missing indexes.

### The spec promises an id it never indexes

**§9.1 makes `seq` "the store-global public id".** `migrations/0001_init.sql:113` indexes only `UNIQUE(collection, seq)`, so resolving a bare `seq` is a full covering scan. io-pimdir works around it by looping every collection at two queries each. Add `CREATE INDEX items_by_seq_global ON items(seq)`.

### The spec's durability story has a hole and a false promise

**§5 says "write a temporary file, `fsync`, then `rename`".** The rename itself is not durable until the parent directory is fsynced, while the SQLite commit *is* durable, so a power cut can leave a committed row pointing at a body that never arrived. That is the exact asymmetry §14 step 5 exists to prevent, and it should be spelled out as a requirement rather than left to the reader.

**§14 step 5 says an orphan blob is "harmless, swept by the next batch".** No batch sweeps orphan *files*. Only the operator sweep does, behind a grace window and a TTY confirmation. Either the wording goes, or the sweep becomes part of the format.

**§5 and §14 disagree about an object with no referrer.** §14 invites a consumer to stream a body to its sharded path and index it without holding it whole, while §5 lets an implementation delete an object whose refcount reaches zero. io-pimdir does exactly that, in the same transaction that indexed it, so a consumer that streams bodies in one batch and places them in a later one loses them silently. Either the format requires an object to be referenced by the batch that indexes it, or refcount-zero collection needs the same grace concept the operator sweep already has.

### The spec offers optimisations nobody can take, and forbids none of the ones that matter

**§14 already permits skipping refcount and GC on a batch that touched no object.** io-pimdir never skips, and pays two full `objects` scans per transaction. Beyond restating the allowance, the sweep should be scoped to the hashes the batch decremented, which the write path already knows.

**§14's write algorithm reads as "load the collection, absorb, diff".** That is how io-pimdir implements it, and it makes a single flag toggle cost a full collection read and clone, measured linear at 90 ms for 20k items and 156 ms for 40k. §1 promises hundreds of thousands of items. The step should be stated as a batch-scoped load, which requires one index the schema does not have: `bindings(collection, source, handle)`, so a drop resolves to a link id instead of scanning.

**§8 says owners "SHOULD take an advisory lock".** Nothing takes one, and the drain deletes its queue row at the end of the transaction without checking it is still there, so two owners apply the same action twice. `add` and `copy` are not idempotent. Making the delete the *first* statement, with `RETURNING id` as the guard, turns exactly-once from a convention into a structural property, and is worth stating in §15 rather than leaving to the lock.

### The schema misses two cheap guards

`objects.refcount` is a plain integer with no floor, and the sweep predicate is `= 0`, so a double release drives it negative and leaks the object forever, unreported. With STRICT tables already in use, `CHECK (refcount >= 0)` is exactly the class of bug the schema is meant to catch loudly.

`collections` cascades onto `items`, `bindings`, `sources` and `queue`, so a single `DELETE FROM collections` silently orphans every object those rows pinned. Nothing in the crate does it and nothing forbids it either.

### Smaller

- **§4.3 `created_at` is "an RFC 3339 timestamp"** and io-pimdir writes epoch milliseconds, empty on clock error. The code is wrong, and the fix is `strftime` in the statement, as `RETAIN_ITEM` already does, which keeps the crate clock-free.
- **§14.1 pages retained items by `link_id`.** io-pimdir pages by `seq` and declares the substitution. `seq` is the better contract, since the caller purges and restores by `seq`; the spec should adopt it.
- **§7 permits repairing refcounts by recomputation.** The operator check reports drift and repairs nothing.
- **§14 leaves the residual "in memory, or a residual table"** without saying which is conformant. In memory means a killed first sync re-probes from scratch and two handles of one source disagree about what has been probed.
- **`objects` and `sources` should be `WITHOUT ROWID`**: small tables, TEXT primary key, no secondary index, every access a point lookup currently paying an index probe plus a rowid indirection. `items` should stay as it is.
- **`items_retained(collection, retained_at)`** leads with `collection`, while the store-wide purge filters on `retained_at` alone and degrades to a full scan of the index.

## Scope / non-goals

- This change lands no edit. It is the triage record; accepted findings each get their own change, delta and log entry.
- Findings about io-pimdir's code rather than the format belong to `store-algorithm-audit` in that repository, and are not repeated here.
- The concurrency envelope is the one question that has to be answered before several of these can be: the format says one owner, the operator CLI routinely opens a second owner handle while a sync holds one. One process with many handles is safe today; many processes are not.
