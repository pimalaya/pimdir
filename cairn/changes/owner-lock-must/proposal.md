---
cairn: change
id: owner-lock-must
status: landed
created: 2026-08-25
---

# The advisory lock becomes a MUST

## Why

§8 stated the single-owner rule and then left the only thing that could keep it optional: owners *SHOULD* take an advisory lock, "so a second owner waits or exits instead of racing". No implementation took one, and the rule was carried instead by SQLite's write lock, which serialises statements without serialising operations: two owners each read a consistent snapshot, then each act on it. §15.2's claim-first delete says as much in passing, calling the advisory lock what exactly-once "would otherwise be load-bearing for".

A rule stated as SHOULD, unimplemented by every implementation, and worked around where it mattered, is not a rule.

Two things beyond the MUST have to be said, because getting either wrong is worse than not locking:

- **Which lock.** An `O_EXCL` lock file makes a crashed owner lock the store for ever, so implementations add an escape hatch for a stale one, and the escape hatch is the race again. An advisory lock on an open file has no stale state to recover: the operating system drops it with the process.
- **Whose lock.** The rule is about processes, and an advisory lock is about open files. An implementation that opens one handle per source, or one per account — both of which this format invites — deadlocks against itself on its second handle unless the lock is taken once per process and shared.

And a producer is not an owner: its lock is a different one, shared, or the queue that exists so a frontend can append while the owner syncs stops working the moment an owner runs.

## What

§8 says MUST, names the two lock files, states fail-fast with its reason, states that the rule is per process, and gives producers a shared lock across the blob write and the enqueue that pins it. §3's layout gains the two files.

## Consequence for implementations

Both are new obligations, not clarifications. The Rust implementation (io-pimdir `single-owner-lock`) lands with this. The Android SQLite implementation takes neither lock today, and is non-conformant until it takes them.
