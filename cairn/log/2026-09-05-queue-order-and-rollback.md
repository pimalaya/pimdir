---
cairn: log
change: queue-order-and-rollback
date: 2026-09-05
---

# The drain keeps append order, rolls back before it parks, and a remove needs no source

§15 promised append order and drained per collection, so a `move` into a collection followed by an edit of the item there parked the edit when the target drained first. `list_pending_actions` reads the queue store-wide in `id` order on the partial `queue_pending`, and `list_queued_collections` is gone; `load_pending_actions` stays the reader's overlay. `claim_action` deleted the row inside the apply transaction, and a statement failure aborts the statement and not the transaction, so a park issued afterwards updated a row already gone and the commit lost the action with no trace: a failed apply rolls back first, then parks or bumps in a transaction of its own, and retries are bounded. A `remove` tombstones the shared item whoever binds it and succeeds on one nothing binds, where "the draining source" named nobody in an owner serving several sources and the row was skipped for ever. A `move` or `copy` into a collection with no declared kind parks rather than ensuring a ghost, and `rename_queue_targets` follows a rename into pending payloads, which no foreign key reaches. A queued `add` over a tombstone still propagating revives it, where the prose had said it does not block and the insert collided. STORAGE §14, §15; GUIDE §8, §13. Guarded by checks/invariants.sh.
