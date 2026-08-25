---
cairn: log
change: created-at-stamped
date: 2026-08-25
---

# `created_at` is stamped by the store, not plumbed in from a producer

§13 pinned `retained_at` to a form *and* to a writer: stamped by SQLite with `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, "so every implementation writes the same shape and none plumbs a clock through to reach it". The two `created_at` columns had neither, and §13 had no entry for them at all. The schema said "RFC 3339 timestamp", which is not a shape: it admits any offset and any sub-second precision, so `2026-08-25T13:00:00+02:00`, `2026-08-25T11:00:00Z` and `2026-08-25T11:00:00.000Z` are all conformant and none of them sort together.

`enqueue_action` now stamps the column itself and no longer takes `:created_at`. §13 gained a `created_at` entry covering both columns.

Verified by running it rather than by reading it: a store created and one action enqueued produce `2026-08-25T12:23:46.576Z` in both `store_meta` and `queue`, 24 characters, UTC, identical shape.

## Why stamping rather than merely pinning the form

Pinning the form in §13 alone would have left every producer formatting its own clock correctly, which is the kind of requirement that is met four times and missed once. Stamping removes the possibility instead of documenting it, exactly as `retain_item` already did.

It is also the better clock. A producer is a different process from the owner (§8) and may be skewed differently; the database has one clock for the whole store. Nothing about ordering changes either way, since the queue is ordered by `id`, and that is worth saying plainly: this column is not load-bearing for correctness. It is the only human-facing account of when an action was requested, and the situation where anyone reads it is an operator looking at a parked queue, which is precisely when three formats in one column is worst.

## The deeper gap this did not close

`store_meta` has **no canonical insert statement**. The one row that fixes `hash_algo` for the entire store is written by ad-hoc code in every implementation, and §16's vectors exist because two implementations disagreed about exactly that field. §13 now tells whoever writes that row which expression to use for `created_at`, but the row itself is still outside queries/.

Closing it means a seventh file under queries/ and a §4.4 change, so it is its own change rather than a corner of this one. It is the most valuable remaining item in this area.

## Not landed here

io-pimdir and the Android app both bind `:created_at` today. Dropping it is a breaking signature change on the enqueue path.
