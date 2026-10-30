---
cairn: change
id: a-purge-cutoff-carries-milliseconds
status: landed
created: 2026-10-30
---

# A purge cutoff carries milliseconds

## Why

algorithm-audit-2026-09-04 ledger: millisecond stamps against second-precision cutoffs in `purge_retained_before`. `retained_at` is stamped `%Y-%m-%dT%H:%M:%fZ` and the statement compares text, so `2026-10-30T10:00:05Z` sorts after `2026-10-30T10:00:05.900Z` (`.` before `Z`) and a second-precision cutoff purges up to a second more than asked.

## What

STORAGE §11.2: the cutoff MUST be written as the stamps are, milliseconds and `Z` included. One sentence; no schema or statement change.

## Lands in

storage-draft-05.
