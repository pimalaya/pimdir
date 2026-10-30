---
cairn: delta
change: the-locks-are-pinned
---

## MODIFIED Requirements

### Requirement: STORAGE §8 and SEARCH §3 The lock primitive
Every lock the standard names (owner.lock, objects.lock, index.lock) MUST be taken whole-file on the open file: `flock(2)` on Unix, `LOCK_EX` exclusive or `LOCK_SH` shared, `LOCK_NB` where a rule forbids waiting; `LockFileEx` on Windows over the whole range, `LOCKFILE_EXCLUSIVE_LOCK` for exclusive, `LOCKFILE_FAIL_IMMEDIATELY` where a rule forbids waiting. An implementation MUST NOT use `fcntl` or `lockf` record locks for them.

#### Scenario: two implementations on one store
- GIVEN an owner holding owner.lock with `flock(LOCK_EX)` on Linux
- WHEN a second implementation tries to own the store
- THEN its `flock(LOCK_EX | LOCK_NB)` fails and it reports the store as owned, where an `fcntl` lock would have succeeded
