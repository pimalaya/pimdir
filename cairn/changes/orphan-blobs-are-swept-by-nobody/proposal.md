---
cairn: change
id: orphan-blobs-are-swept-by-nobody
status: landed
created: 2026-08-25
---

# An orphan blob is swept by nobody, and the write path is built on the promise that it is

## Why

§14 step 5 unlinks garbage blobs after the commit, and explains why that order is the safe one: "a crash leaves at worst an orphan file (harmless, swept by the next batch) rather than a row pointing at a missing body". The order is right. The parenthesis is false.

Nothing in the write path can sweep an orphan blob, and the reason is structural rather than an oversight in some implementation. `list_garbage_objects` selects `FROM objects`. A blob is orphaned precisely when its row has already been deleted and committed, which is what step 3 and step 4 did before the crash. There is no row left to find it by, and no write batch ever reads the blob directory, so a later batch cannot see the file at all. Reproduced against the canonical statements: batch 1 lists `doomed`, deletes its row and commits; the process dies before the unlink; batch 2 runs the entire §14 GC sequence and lists nothing.

So the blob stays, for ever, with no signal. The store's own reads never mention it, `retained_bytes()` does not count it (it totals bodies that retained *items* hold), and no invariant is violated: this is a store that is entirely healthy by every check it has, quietly holding bytes nothing will ever reclaim.

That would be a modest disk leak on its own. What makes it worth a change is that the promise is **load-bearing** in two other places:

- §5's write bullet justifies the whole database-after-blob ordering by "the reverse leaving at worst an orphan file", where "at worst" is doing the same work the parenthesis is.
- The audit's proposal to permit the blob write **before** `BEGIN` rests on it too: content-addressed and immutable, so a crash leaves an orphan file at worst. That change is a good one, and it deserves an orphan story that is true before it is made on the strength of one that is not.

An implementation reading §14 today is told the crash window self-heals. io-pimdir's operator CLI happens to know better, since `check` diffs the blob directory against `objects` and `check --fix` unlinks the difference behind a grace period. That is the real answer, and it is an *operator* action the format never mentions.

## What

- **§14 step 5**: drop the false parenthesis. State what an orphan blob actually is: a file no row names, reclaimable only by a sweep that reads the directory, which no write batch does.
- **§5**: name the orphan sweep as the thing that reclaims them, state that it MUST diff the directory against `objects` rather than trust a refcount, and state the grace period as normative, since a sweep that unlinks a blob a concurrent batch has just written and not yet committed a row for destroys a live body. Grace beats locking here: the writer holds no lock over the window between its blob write and its commit.
- **§14 step 1**: permit the blob write before `BEGIN`, now that the orphan it can leave is honestly accounted for. Writing a blob inside the transaction holds SQLite's write lock across a file write, two `fsync`s and a rename, which serialises every other writer behind an I/O path that has nothing to do with the database.

## Scope / non-goals

- No schema change. An orphan blob is by definition a file with no row, so no column can track one.
- The sweep is not made mandatory on a write path. It is an operator action, and the format's job here is to say that it exists and that a store needs it, not to put a directory scan in front of every batch.
- Does not settle the audit's separate question of whether an object indexed with **no referrer** is legal. That is a row with no pointer, the mirror image of this and a different decision.
