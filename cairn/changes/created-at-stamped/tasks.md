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

- [x] Drop the bound parameter; a breaking signature change on the enqueue path. Done in io-pimdir (`PimdirProducer::enqueue` takes no timestamp); Android open. Closed 2026-11-13 (audit-2026-11-12, V8): done in the Android app too, whose PimdirQueue.java binds no timestamp to the enqueue.

## Deliberately not done here

- [x] A canonical insert for `store_meta`, the one row that fixes `hash_algo` store-wide and that no statement covers. Needs a seventh queries/ file and a §4.4 change, so it is its own change. Done: queries/storage/owner/init_store_meta.sql exists and STORAGE §6 runs it in the transaction applying 0001_init.sql (settled at ledger-housekeeping-2026-10-30).
