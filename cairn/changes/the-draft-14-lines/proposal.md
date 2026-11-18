---
cairn: change
id: the-draft-14-lines
status: in-progress
created: 2026-11-18
---

# The draft-14 lines

## Why

The lines left for the next draft before pimdir v1, gathered so they land in one bump: the owner ruling D34 on refusals (2026-11-16, cairn/changes/a-refused-push-shows-on-its-receipt/tasks.md), the format parts of the CLI family analysis of 2026-11-15 (PIM-12, PIM-14), the create a source binding nothing of refuses (seen live by neverest, 2026-11-16), and the audit-2026-11-12 lines C1, C2 and C4 marked "before".

## What changes

1. SYNC §4: `401`, `407` and `423` are no refusal, beside `408`, `409`, `412`, `425` and `429`; a quota exceeded is no refusal, a size exceeded stays one. Each is left unreported, as a transport failure is: a change held by its key would never be pushed once the credential is renewed, the lock released or space freed (D34).
2. SYNC §3, §5, §9, STORAGE §10: a deleted item a source binds projects `Tombstone` whatever conflict stands, carrying its binding's divergence; a binding's conflict names a server edit that beats the delete, so such a tombstone derives no `Remove`; an item conflict holds no delete back and is kept by the retained item (PIM-12, as io-pimdir's hub already projects).
3. SYNC §7, STORAGE §15.2 to §15.4: a `Move` into the collection its placement is in is refused, a queued `move` there parked naming it and never enqueued (PIM-14, io-pimdir's `move-in-place`).
4. The refusal of a create offered to a source binding nothing of it (unit 2, its own section once proposed).
5. C1, C2, C4 of audit-2026-11-12 (unit 3).
6. The bump to storage-, sync- and search-draft-14 (unit 4).
