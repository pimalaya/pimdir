---
cairn: log
change: a-rename-follows-a-submits-copy
landed: 2026-11-24
---

# A rename follows a submit's copy

Found by the live test night of 2026-11-23 (.lanes/live/report.md of the workspace, neverest N4): a send queued with its copy filed in a folder, the folder renamed by an earlier run before the send was performed. The message was sent, then filing its copy, an `add` into the payload's `copy` replacing the intent (§15.5), failed "FOREIGN KEY constraint failed", the id gone, and the intent stayed unconfirmed. A send cannot be repeated, so the copy was never filed.

## STORAGE.md §14, renaming a collection

- The payload keeps the id it was enqueued with, but for a `submit`'s `copy`, the one collection a payload names that no column holds: the rename rewrites it in the same transaction on every queued `submit` naming the old id, pending or parked. Was: every payload kept its id, `target_collection` alone following.

No vector format states a store rename with a queue (sync/ runs an engine, search/refresh.json a reader), as none guarded the `target_collection` rule either: io-pimdir's tests/receipts.rs `a_submit_queued_before_a_rename_files_its_copy_in_the_renamed_collection` guards it, failing before with the night's error, beside tests/invariants_queue.rs `l558_l1722_a_rename_follows_into_pending_targets`. storage-draft-17 keeps its number (not tagged). io-pimdir follows in the commit checks/io-pimdir.rev names.
