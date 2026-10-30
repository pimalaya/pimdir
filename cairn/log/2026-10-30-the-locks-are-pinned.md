---
cairn: log
change: the-locks-are-pinned
date: 2026-10-30
---

# The lock primitive is pinned

Edit 2 of the pimdir stable-release plan. GUIDE said "`flock` or `fcntl`", and on Linux the two do not see each other, so two implementations could both own a store, or a collector delete a staged body.

- **STORAGE §8** (normative): owner.lock, objects.lock and index.lock are taken whole-file with `flock(2)` on Unix and `LockFileEx` over the whole range on Windows, `LOCK_NB` or `LOCKFILE_FAIL_IMMEDIATELY` where a rule forbids waiting; never `fcntl` or `lockf` record locks.
- **SEARCH §3** (normative): index.lock said to follow it.
- **GUIDE §2, §15** (informative): the calls by name.

No check in this repository can hold a lock primitive, the checks running SQLite and no implementation. io-pimdir already conforms (`fs4`: `flock`, `LockFileEx` over the whole range, src/client/lock.rs).
