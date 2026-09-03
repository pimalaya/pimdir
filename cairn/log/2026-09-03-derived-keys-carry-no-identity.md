---
cairn: log
change: derived-keys-carry-no-identity
date: 2026-09-03
---

# A writer-derived key never dedups and never shares a `seq`

`lookup_objects` was keyed on the assigned `link_id` with no exclusion for a prefixed one. Two messages stating no `Message-ID`, with the same subject, sender and second-precision date (a monitoring system firing twice), share an `alt:` key; across two collections of one account the lookup handed the first body to the second placement, which read as hydrated and never fetched its own.

That is the wrong merge §9 says the design avoids, verified by reading the statement rather than by a live store.

A prefixed key (`alt:`, `hash:`, `dup:`) states no identity, so it is excluded from `lookup_objects` and never asked of `seq_for_link_any`: such an item draws its own `seq`. The cost is a missed dedup for a message nothing identifies, which §9 already calls harmless.

§9 also states what a mutable resource under a `hash:` key does when edited: a new key under the same handle, the old item retained, a delete and an add on every other source. It converges and it is what a resource stating no identity owes.
