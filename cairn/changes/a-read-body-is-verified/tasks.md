---
cairn: tasks
change: a-read-body-is-verified
---

# Tasks

## pimdir

- [x] STORAGE §7 (and SYNC §6's claims): verify on a whole or streamed read, a mismatch reads as absent, the bad file unlinked by the owner, a push only of a verified body; the order of trust restated
- [x] checks: vector 94 (an object stated `corrupt`, a pending create pushing nothing), checks/vectors.py failing any push of a body stated `corrupt` or without a blob, the schema's `corrupt`
- [x] Decide the partial-read question: no new column, whole and streamed reads verified only (2026-10-30)
- [x] Decide the missing-against-wrong question: one state (2026-10-30)
- [x] GUIDE §11 and §14; SYNC §11 (`corrupt`); lands in storage-draft-05; log entry

Followers, tracked in io-pimdir's cairn: src/client/blobs.rs `get` verifies and answers `None` on a mismatch, `reader` verifies at the end of the stream; the upgrade treats such an item as bodiless and refetches, after unlinking the file; a push reads a verified body; a test where a flipped byte in a stored blob is never handed out and is fetched again; vector 94.
