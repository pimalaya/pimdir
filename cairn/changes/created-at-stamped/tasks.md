---
cairn: tasks
change: created-at-stamped
---

# Tasks

## Landed in this repository

- [x] `enqueue_action` stamps `created_at` with `strftime`, dropping the parameter.
- [x] SPEC.md §13: a `created_at` entry pinning the form for both columns.
- [x] SPEC.md §15.1: the producer's enqueue no longer carries a timestamp.
- [x] Log entry.

## Left to io-pimdir and Android

- [ ] Drop the bound parameter; a breaking signature change on the enqueue path.

## Deliberately not done here

- [ ] A canonical insert for `store_meta`, the one row that fixes `hash_algo` store-wide and that no statement covers. Needs a seventh queries/ file and a §4.4 change, so it is its own change.
