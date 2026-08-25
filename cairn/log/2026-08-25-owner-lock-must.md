---
cairn: log
change: owner-lock-must
date: 2026-08-25
---

# The advisory lock became a MUST

§8 stated the single-owner rule and left its enforcement optional: owners *SHOULD* take an advisory lock. No implementation took one, and what carried the rule instead was SQLite's write lock, which serialises statements without serialising operations — two owners each read a consistent snapshot, then each act on it. §15.2's claim-first delete already said so in passing, calling the advisory lock what exactly-once "would otherwise be load-bearing for".

## What moved

- **§8 says MUST**, on `owner.lock` beside the database, held for as long as the process owns the store. The lock belongs to the open file rather than to the file's existence, so a crashed owner leaves a lock file that locks nothing. That distinction is normative, not incidental: an `O_EXCL` lock file needs an escape hatch for a stale one, and the escape hatch is the race again.
- **Fail fast**, naming the store, with its reason stated: a wait long enough to outlast a sync transaction is a stall with no signal, and the choice between retrying, backing off, queueing the intent through §15 and telling the user belongs to the calling program. The database's busy timeout is untouched; that contention is a different layer and worth waiting out.
- **The rule is about processes.** An implementation opening one handle per source, or one per account — both shapes this format invites — is one owner, and takes the lock once. Said explicitly because the obvious implementation, one lock per handle, deadlocks against itself on the second handle.
- **Producers take a shared lock** on `objects.lock`, across the blob write and the enqueue that pins it. A separate file from the owner's, deliberately: the queue exists so a frontend can append while the owner syncs, so an owner's exclusive lock must not exclude producers. What the shared lock delimits is the one window where a body is written and not yet referenced, which is the window a collector must not run inside.
- **§3's layout** gains both files, noted as empty, lazily created and stateless.
- The network-filesystem paragraph now names the advisory locks among what a share cannot be trusted with, beside SQLite's own.

## Who is conformant

io-pimdir lands this in the same breath (its `single-owner-lock`), registry and all. The Android SQLite implementation takes neither lock and is non-conformant until it does; it is the second owner the rule is about, so this is not a formality there.
