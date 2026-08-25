---
cairn: change
id: retained-page-by-seq
status: landed
created: 2026-08-25
---

# The trash listing pages by the public id, and its index finally matches the read

## Why

§14.1 opens by saying its reads "are kind-agnostic and keyed by the public `seq` (§9.1), never by `link_id`", and `list_retained_page` then takes a `link_id` as its cursor. A reader listing the trash is handed an internal identifier (§13 calls `link_id` internal) and has to hand it back to get the next page.

`list_items_page` takes one too, and that one is defended: §14.1 calls it the page for a sweep that must see every item exactly once, where an arbitrary total order is exactly right. The trash listing is not a sweep. It is a listing a reader presents, beside `list_items_page_asc` and `count_retained`, and it is the only such read that leaks the internal key.

The cursor is also why the read is slow, which is the part that turns a tidiness argument into a real one. `items_retained` is `(collection, retained_at)`, so ordering by `link_id` cannot ride it. Measured on a collection of twenty thousand live items:

| retained items | first page |
| --- | --- |
| 200 | 0.10 ms |
| 5 000 | 1.44 ms |

The page costs what the *trash* costs, not what the page costs, because the plan carries `USE TEMP B-TREE FOR ORDER BY`: every retained row in the collection is sorted to return fifty.

## What

One index change, not two. Re-order `items_retained` from `(collection, retained_at)` to `(collection, seq)` and page `list_retained_page` on `seq`. Measured against the same store, and against the audit's separate suggestion of a second index:

| read | `(collection, retained_at)` | `(collection, seq)` |
| --- | --- | --- |
| `list_retained_page` (by `seq`) | 1.372 ms | **0.031 ms** |
| `count_retained` | 0.177 ms | 0.182 ms |
| `retained_bytes` | unchanged | unchanged |
| `purge_retained_before`, 500 collections | 55.8 ms | 52.4 ms |

Every retained read is served by the one index, none regresses, and the page stops growing with the trash. `purge_retained_before` moves from a skip-scan to a scan of the partial index, which holds only retained rows, so it is the same O(retained) and measures slightly faster.

`:after` becomes an exclusive lower bound on `seq`, with `0` starting from the beginning. That is a real sentinel rather than an invented one, since `seq` is handed out from `1` (`store_meta.next_seq`), and §14.1 already asks an implementation to expose the first page as "no cursor".

## Scope / non-goals

- `list_items_page` keeps its `link_id` cursor. It is the sweep read, and §14.1's justification for it stands; this change sharpens the distinction rather than erasing it.
- The audit's separate item, "reconsider the column order of `items_retained`", is answered here and needs no change of its own: the re-order this read wants is the re-order that item was asking about.
- The audit's suggestion of adding a `(retained_at)` index for `purge_retained_before` is **rejected on measurement**: it made no difference (54.88 ms against 56.45 ms at 500 collections), because the purge's cost is the per-row foreign-key check on `bindings`, not the lookup.
