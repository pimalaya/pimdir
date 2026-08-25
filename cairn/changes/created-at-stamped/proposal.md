---
cairn: change
id: created-at-stamped
status: landed
created: 2026-08-25
---

# `created_at` is stamped, not plumbed

## Why

§13 pins `retained_at` to a form and to a *writer*: "It is stamped by SQLite itself (`strftime('%Y-%m-%dT%H:%M:%fZ','now')`) in the retiring update, so every implementation writes the same shape and none plumbs a clock through to reach it."

The two `created_at` columns get neither. `queue.created_at` is bound as `:created_at` from whatever the producer's clock and formatter produced, and `store_meta.created_at` is written by code no canonical statement covers. The schema comment says "RFC 3339 timestamp" for both, and RFC 3339 permits any offset and any sub-second precision, so `2026-08-25T13:00:00+02:00`, `2026-08-25T11:00:00Z` and `2026-08-25T11:00:00.000Z` are all conformant and none of them sort together.

§13 has no `created_at` entry at all, so nothing else narrows it.

That matters most for the queue, where the column is the only human-facing account of when an action was requested. Rows are applied in `id` order, so a skewed or differently-formatted stamp corrupts no ordering; it corrupts the operator's reading of a parked queue, which is the one situation where anyone looks.

## What

- `enqueue_action` stamps the column itself, `strftime('%Y-%m-%dT%H:%M:%fZ','now')`, and drops the `:created_at` parameter. This follows `retain_item`'s precedent exactly, for the reason §13 already gives for it.
- §13 gains a `created_at` entry pinning the form for both columns, including `store_meta.created_at`, which no canonical statement covers and which an implementation therefore writes with that expression itself.

A producer's clock stops being consulted, which is also the more correct answer: a producer may be a different process from the owner, and the database's clock is one clock for the whole store.

## Scope / non-goals

- The queue's ordering is `id` and does not change. This is about the stamp being readable and comparable, not about ordering.
- `store_meta` still has **no canonical insert statement**, which is the deeper gap here: the one row that fixes `hash_algo` for the whole store is written by ad-hoc code in every implementation, and §16's vectors exist because two implementations disagreed about exactly that field. Adding one means a seventh queries/ file and a §4.4 change, so it is its own change, not this one.
