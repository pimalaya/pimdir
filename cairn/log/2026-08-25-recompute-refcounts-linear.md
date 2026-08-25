---
cairn: log
change: recompute-refcounts-linear
date: 2026-08-25
---

# The refcount repair is now the linear statement it claimed to be

`recompute_refcounts` (queries/objects.sql) is the repair §7 offers and §14 names, and both described it as O(items+bindings+queue). It was O(objects x items). The claim is now true because the statement changed, not because the claim was softened.

## What was wrong

The statement counted with a correlated scalar subquery per object row, and the one over `items` was an `OR` chain across `object_hash` and `conflict_object`. A disjunction over two columns is served by no single index, so the planner had nothing to do but scan:

```
SCAN objects
CORRELATED SCALAR SUBQUERY 1
SCAN i
CORRELATED SCALAR SUBQUERY 2
SEARCH b USING COVERING INDEX bindings_by_object (base_object=?)
CORRELATED SCALAR SUBQUERY 3
SEARCH q USING COVERING INDEX queue_by_object (object_hash=?)
```

`SCAN i`, once per object row. The two index searches beneath it are `items_by_conflict_object` and `queue_by_object` doing their job; the `items` scan is the one the indexes could not reach, and it is the whole cost.

## What it is now

The four pointer columns are gathered into one stream with `UNION ALL`, counted once with `GROUP BY`, and left-joined against `objects`, which is the shape io-pimdir already carried in its operator CLI as `refcount_drift`. The left join is load-bearing twice over: it is what visits an object no pointer names any more and settles it to zero, and it is what lets the statement leave a row already holding its true count alone, so the repair writes only the drift it found.

```
MATERIALIZE counted
MATERIALIZE r
COMPOUND QUERY
LEFT-MOST SUBQUERY
SEARCH items USING COVERING INDEX items_by_object (object_hash>?)
UNION ALL
SEARCH items USING COVERING INDEX items_by_conflict_object (conflict_object>?)
UNION ALL
SEARCH bindings USING COVERING INDEX bindings_by_object (base_object>?)
UNION ALL
SEARCH queue USING COVERING INDEX queue_by_object (object_hash>?)
SCAN o USING COVERING INDEX sqlite_autoindex_objects_1
SEARCH r USING AUTOMATIC COVERING INDEX (hash=?) LEFT-JOIN
SCAN counted
SEARCH objects USING INDEX sqlite_autoindex_objects_1 (hash=?)
```

Every pointer column is now reached by its covering index and every table is visited once.

## Measured

Against the canonical schema on a store of one object, one item and one binding per link id, refcounts zeroed and recomputed:

| items | before | after |
| --- | --- | --- |
| 20 000 | 80.3 s | 121 ms |

The two forms settle the same counts. The gap is the `objects x items` term: at twenty thousand items it is already four hundred million row visits, and it grows with the square.

## Correctness checked

Against migrations/0001_init.sql, with the statement read out of queries/objects.sql rather than retyped: a body pinned three times by one item and one binding (its shared body, that same item's conflict body, that source's base) counts 3; a body pinned only by a pending queue action counts 1; a body nothing names, whose stored count says 7, is settled to 0 and so reaches the sweep; a body already holding its true count is not rewritten.

## Also corrected

§14 said the recompute is the reference form and `adjust_refcount` the alternative, without saying why an implementation would want the alternative once the recompute is linear. It now says it: the recompute's cost is the store's, not the batch's, and a store pays it whole to write one flag. The incremental form stays the write path's, and the recompute is what §7's repair runs.

§7 named recomputation without naming the statement that does it. It now names it, and says what "recomputation" covers: the four columns that pin an object, and the zero it writes for an object none of them names.

## Not landed here

io-pimdir still substitutes this statement (`RECOMPUTE_REFCOUNTS` in its `SUBSTITUTED` list), keeping `ADJUST_REFCOUNT` for the write path, which §4.4 permits and which stays the right choice for a write. What changes for it is the repair: `check --fix` reports refcount drift and does not fix it, and this statement is what it should run. That is io-pimdir's entry to write.
