---
cairn: change
id: the-locks-are-pinned
status: landed
created: 2026-10-30
---

# The lock primitive is pinned

## Why

Edit 2 of the pimdir stable-release plan (2026-10-30), from blocker 2 of the consolidated pimdir review. GUIDE §2 said "`flock` or `fcntl`" and STORAGE §8 named no primitive. On Linux a `flock` lock and an `fcntl` record lock do not see each other, so two implementations could each hold owner.lock and both own the store, or a collector could delete a body a producer staged; and a process loses an `fcntl` lock when it closes any descriptor of the file, which a library opening the file again does without knowing. io-pimdir already takes BSD `flock(2)` through `fs4` (src/client/lock.rs), `LockFileEx` over the whole range on Windows.

## What

- STORAGE §8: every lock the standard names (owner.lock, objects.lock, index.lock) is taken whole-file with `flock(2)` on Unix (`LOCK_EX`, `LOCK_SH`, `LOCK_NB` where a rule forbids waiting) and `LockFileEx` on Windows over the whole range (`LOCKFILE_EXCLUSIVE_LOCK`, `LOCKFILE_FAIL_IMMEDIATELY` where a rule forbids waiting); never `fcntl` or `lockf` record locks.
- SEARCH §3: index.lock on the same terms, said explicitly.
- GUIDE §2 step 1 and §15: the calls by name.

## Lands in

storage-draft-05 and search-draft-05.

## Check

None in this repository can hold it: the checks run SQLite alone and no implementation. io-pimdir conforms as it stands (fs4's `flock` and `LockFileEx`); an implementation using `fcntl` is non-conformant by the text.
