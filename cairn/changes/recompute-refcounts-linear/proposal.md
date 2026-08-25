---
cairn: change
id: recompute-refcounts-linear
status: landed
created: 2026-08-25
---

# The repair statement is what it claims to be

## Why

`recompute_refcounts` (queries/objects.sql) is the normative repair §7 offers, and §14 describes it as O(items+bindings+queue). It is O(objects × items).

Its shape is a correlated scalar subquery per object row, and the one over `items` is an `OR` chain across `object_hash` and `conflict_object`, which no single index can serve. `EXPLAIN QUERY PLAN` reports a full `SCAN i` once per object, and did the same for `SCAN q` before `queue_by_object` existed. On a store of a few hundred thousand items, the statement the format offers as its integrity repair is on the order of 10^10 row visits.

io-pimdir already carries the correct shape in its operator CLI, `refcount_drift`: a `UNION ALL` of the four pointer columns, grouped by hash and left-joined against `objects`, which plans linearly. The format's own statement should be that, and the complexity claim should stop being false.

## What

- Rewrite `recompute_refcounts` as the `UNION ALL` + `GROUP BY` form.
- Correct §7 and §14 where the complexity is stated.
- io-pimdir stops declaring it a §4.4 substitution and uses it, which is what `check --fix` needs once `manual-gc` makes repair its job.

## Scope / non-goals

- The invariant does not change: an object's refcount is the number of pointers at it, across an item's body, an item's conflict body, a binding's base and a queue row's pin.
- The incremental path (`adjust_refcount`) stays the ordinary one; this is the repair.
