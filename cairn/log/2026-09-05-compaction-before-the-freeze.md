---
cairn: log
change: compaction-before-the-freeze
date: 2026-09-05
---

# What went rather than got fixed

`KeepBoth` staged a fork whose body carried the original `UID`, which a CardDAV or CalDAV server rejects on every `Add` under RFC 6352 §5.1 and RFC 4791 §4.1: a create pushed and refused on every run for ever. The policy, its vector and its key form (`rules-restored-from-the-engine`) are gone; three policies remain, and a fork that can land is a change of its own if it is wanted. The `Revert` and `Keep` delete option went with `deletes-and-the-trash`. `delete_items` and the replace-all write form starved the feed and stayed only as a warning; `list_object_hashes` served a diagnosis the collector never runs; `bump_next_change` is folded into a trigger; `list_queued_collections` into a store-wide drain.

Yesterday's `add-lands-on-the-holder` fixed a real race by asking every connector to answer an `Add` with the handle already holding the identity, which on IMAP is a header search per add and quietly puts identity dedup back on the connector's side, where STORAGE §9 says a source holding an identity twice is a fact to keep. The engine-side rule replaces it: an `Add` is not derived while the collection holds a probe of its source, the upgrade naming the probes landing or freeing it. Vector 25 pins the wait; vector 21 still pins the landing.

The idempotency key named a state, not a transition, and the vectors already carried one key for two `Update` pushes; a connector keeping keys across runs would drop a flag set restored or a body pushed again. Rather than fold the base into the key and rewrite every vector, SYNC §4 bounds the log: keys are forgotten once the checkpoint after their chunk lands, which is the replay the key exists for. A `hash:` key is not offered to another source, two servers re-serialising a UID-less card having handed it back to each other under a new key every run.

Cheap guards the schema now holds that the prose had only stated: `level`, `deleted`, `conflicted`, `base_present` and `conflict` in their domains, `json_valid` on every JSON column, a diverging body only under its flag on both tables, `retained_at` only under `deleted = 1`. `items_by_sort` is partial on live rows, so a mailbox whose server expunged most of it no longer pages through its trash.
