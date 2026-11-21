---
cairn: change
id: the-write-path-before-the-freeze
status: draft
created: 2026-11-21
---

# The write path before the freeze

## Why

compared-with-notmuch measured a durable import of the Enron corpus: pimdir spends less CPU than notmuch (431 s against 547 s at 517,401 messages, 902 s against 1,097 s at 1,034,802) and still takes 2 to 3.5 times its wall time, because it waits on the disk. Without flushing (eatmydata) it imports in 380 s against notmuch's 719 s. Three costs come from the standard itself, so they can change only before the freeze, a migration otherwise:

1. **Two flushes per body.** STORAGE §5 has a writer `fsync` each body's temporary, then its shard directory, before the row naming it commits: 2 million waits on the disk for a million messages (5,482 `fsync` for 3,034 messages on the smoke test).
2. **Random-key indexes.** `items_by_object`, `bindings_by_object`, `bindings_by_shared_object` and the `objects` key are keyed by the 52-character BLAKE3 name, `items_by_link` by the Message-ID, `item_address_by_address` by the address (9.4 rows per Enron message). Each insert dirties its own leaf page in each, written to the WAL and again at the checkpoint: about 80 KB written per 3.4 KB message at 390,000 messages (70 GB through SQLite, 32 GB to the disk).
3. **Commit count.** `synchronous = FULL` (STORAGE §4.1) is right and stays; what it costs is one flush per commit, so the number of commits a page takes is the lever.

The owner closed write speed as good enough on 2026-11-13 at phone scale (3,782 messages); on 2026-11-21 the owner set the bar at notmuch's efficiency and asked for these to be prototyped and measured before any reaches the spec.

## What

Each item is prototyped in io-pimdir (cairn/changes/as-fast-as-notmuch), measured on the bench (compared-with-notmuch/bench: CPU, bytes written per message, wall on a quiet machine, the 52k, 517k and 1M tiers), and folded into STORAGE only on the owner's decision:

1. **A page of bodies flushes together.** A writer writes every temporary of a batch, flushes each (or, where the platform offers it, the filesystem once: `syncfs`), moves them onto their names, flushes each shard directory it touched once, and only then commits the row naming them. The guarantee is unchanged: no row names a body a power loss could take. STORAGE §5's Write and The directories are flushed paragraphs, GUIDE's procedure, checks/invariants.sh's crash scenarios.
2. **Objects keyed by an integer.** `objects` gains an integer key assigned at insert, so new bodies take increasing ids; `items`, `bindings` (base, shared, conflict objects) and every child reference it, the BLAKE3 name kept on `objects` alone with its unique index. The object indexes then grow at their end. Touches migrations/storage, every statement naming an object, the blob GC, the vectors that name objects by hash.
3. **Addresses interned (measured first).** `item_address` references `address(id, address)`, the text once per distinct address. Kept only if the bench shows it pays for the extra join.
4. **Fewer commits per page.** Not a spec change unless the bench finds a statement of SYNC or STORAGE forcing several transactions per page; then that statement.

Not in this change: `synchronous` (stays `FULL` or `EXTRA`), the queue's exactly-once, the blob write's no-replace move.

## Decided (owner, 2026-11-21)

- **Item 2, integer object ids: go, in the store and in the index.** `objects` (pimdir.db) and `object` (index.db) keyed by an integer, the BLAKE3 name unique on the object row alone, every reference (items, bindings, children, placement) by the integer. Evidence: the write prototype (about 60% fewer SQLite bytes a message, pimdir.db 29% smaller, prototypes-2026-11-21.md) and io-pimdir's planner tuning (a text term's placements read 6 times faster at 517k, `enron` 477 to 74 ms, through placement keyed by the hash). Measured at 517k before the fold.
- Items 1 and 3 wait on the 517k measurement; item 4 landed (io-pimdir 03f1bc0).
