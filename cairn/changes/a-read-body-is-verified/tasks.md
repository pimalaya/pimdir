---
cairn: tasks
change: a-read-body-is-verified
---

# Tasks

## pimdir

- [ ] STORAGE §5 and §7: verify on read, a mismatch reads as absent, the bad file's fate, a push only of a verified body
- [ ] checks: a scenario or vector where a blob's bytes no longer match its name
- [ ] GUIDE.md: the read procedure; bump the draft number if `draft-04` is tagged first; log entry

## io-pimdir

- [ ] src/client/blobs.rs: `get` verifies and answers `None` on a mismatch; `reader` verifies at the end of the stream
- [ ] The upgrade treats such an item as bodiless and refetches; a push reads a verified body
- [ ] Test: a flipped byte in a stored blob is never handed out and is fetched again
