---
cairn: tasks
change: orphan-blobs-are-swept-by-nobody
---

# Tasks

## Landed in this repository

- [x] §14 step 5: drop the false "swept by the next batch", state what an orphan blob is and what does reclaim one.
- [x] §5: a normative orphan sweep, diffing the directory against `objects`, with the grace period and why it is not optional.
- [x] §5: disambiguate "sweep orphans" in the garbage-collection bullet, which used the word for an unreferenced row.
- [x] §14 step 1: permit the blob write before `BEGIN`, on the now-true orphan story.
- [x] Log entry, with the reproduction.

## Left to io-pimdir

Nothing to build: `pimdir check --fix` is already this sweep, grace period included, defaulting to `1h`. What is left is to record that the format now describes it.

- [ ] Confirm `check --fix` reads as conformant with §5 as written, and log that the operator tool is the format's orphan sweep rather than a local convenience.
