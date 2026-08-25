---
cairn: log
change: retained-page-by-seq
date: 2026-08-25
---

# The trash listing pages by the public id, on an index that finally matches it

`list_retained_page` took a `link_id` as its cursor, in a section that opens by saying its reads are "keyed by the public `seq` (§9.1), never by `link_id`". It takes a `seq` now, and `items_retained` is re-ordered to `(collection, seq)` so the read rides it.

## Two problems, one cause

The interface problem is that `link_id` is internal (§13). A reader listing the trash was handed the internal key and had to hand it back for the next page, in the one read of §14.1 that did that. `list_items_page` takes one too, and that one is defended rather than accidental: §14.1 calls it the page for a sweep that must see every item exactly once, where an arbitrary total order is the point. The trash listing is not a sweep, it is a listing a reader presents.

The performance problem has the same cause. `items_retained` led with `retained_at`, so ordering by `link_id` could not ride it, and the plan carried `USE TEMP B-TREE FOR ORDER BY`: every retained row in the collection sorted to return fifty. The page cost what the trash cost, not what the page cost.

| retained items | first page, before |
| --- | --- |
| 200 | 0.10 ms |
| 5 000 | 1.44 ms |

## One index, not two

The audit listed "reconsider the column order of `items_retained`" as a separate item from seq paging. They are the same item: the order the read wants is the order the audit was asking about. Measured across every retained read, on twenty thousand live items and five thousand retained:

| read | `(collection, retained_at)` | `(collection, seq)` |
| --- | --- | --- |
| `list_retained_page` (by `seq`) | 1.372 ms | **0.031 ms** |
| `count_retained` | 0.177 ms | 0.182 ms |
| `retained_bytes` | unchanged | unchanged |
| `purge_retained_before`, 500 collections | 55.8 ms | 52.4 ms |

Every retained read is served by the one index and none regresses. `purge_retained_before` moves from a skip-scan (`ANY(collection)`) to a scan of the partial index, which is the same O(retained) because the index is partial and holds nothing else, and measures slightly faster. `count_retained` rides the collection prefix as before.

## An index that was proposed and is not being added

The audit also suggested a `(retained_at)` index for the store-wide `purge_retained_before`. Measured, and rejected: 54.88 ms against 56.45 ms at 500 collections, which is noise. The purge's cost is not the lookup, it is the per-row foreign-key check on `bindings` for every item deleted. An index added on the strength of a plan that looks better, without a measurement that is better, is a write amplification with no reader.

## The cursor

`:after` is now the exclusive lower bound on `seq`, with `0` starting from the beginning. That is a real sentinel rather than an invented one, since `seq` is handed out from `1` (`store_meta.next_seq` defaults to 1), and §14.1 already asked an implementation to expose the first page as "no cursor" rather than have a caller invent one.

## Not landed here

io-pimdir carries the index and the statement inline, and the `--after` on its retained listing changes type. That is its entry to write.
