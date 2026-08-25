---
cairn: log
change: orphan-blobs-are-swept-by-nobody
date: 2026-08-25
---

# The orphan blob has a sweep, and the write path stops resting on a promise nothing kept

§14 step 5 unlinked garbage blobs after the commit and explained the order with a parenthesis: a crash leaves "at worst an orphan file (harmless, swept by the next batch)". The order was right and the parenthesis was false. It is gone, §5 now names the sweep that actually reclaims an orphan, and §14 step 1 may now write a blob before `BEGIN`, which is a change the true story supports and the false one only appeared to.

## The reproduction

Against the canonical statements and the canonical schema, a batch that drops the last pointer at a body:

```
batch 1 committed, having listed ["doomed"] for unlinking
CRASH before step 5: the blob file survives, its row does not
  rows in objects for 'doomed': 0

batch 2 ran the full §14 GC sequence and listed [] for unlinking
  does it name the orphan? false
```

It is not that batch 2 was unlucky. `list_garbage_objects` selects `FROM objects`, and a blob is orphaned precisely when its row is already deleted and committed, which is what steps 3 and 4 did before the crash. No write batch reads the blob directory at all, so the file is not merely unswept, it is unreachable from the write path. It stays for ever.

What made this worth its own change rather than a footnote is that nothing reports it. No invariant is violated, `PRAGMA integrity_check` passes, `recompute_refcounts` finds no drift, and `retained_bytes()` does not count it, since that totals bodies retained *items* hold. A store quietly holding bytes nothing will reclaim is a store that is healthy by every check it has.

## Where the promise was load-bearing

Two other places leaned on it, which is why correcting the parenthesis alone would not have been enough.

§5's write bullet justifies the entire blob-before-database ordering with "the reverse leaving at worst an orphan file", where "at worst" carries the same weight the parenthesis did. It now says what reclaims one.

And the audit's proposal to permit the blob write **before** `BEGIN` rests on it directly: content-addressed and immutable, so a crash leaves an orphan at worst. That is a good change and it landed here, but it landed on an orphan story that is now true. It is worth making: inside the transaction, a blob write holds SQLite's write lock across a file write, two `fsync`s and a rename, serialising every other writer behind an I/O path that touches no database page.

## The grace period is correctness, not caution

Writing the blob early widens a window that already existed. Between the blob write and the commit, the file is on disk with no row, which is byte-for-byte the state of an orphan. A sweep that unlinks it destroys a live body the committing writer is about to reference.

Locking does not close this. The writer holds no lock across the window, and staying out of the write transaction is the entire point of writing early. A grace period does close it, by making "young" mean "possibly in flight", so §5 states it as a MUST rather than as advice, with an hour as a sound default.

That is also what io-pimdir already built. `pimdir check` diffs the blob directory against `objects` and `check --fix` unlinks the difference behind a `--grace` that defaults to `1h`, with the reason written in its own help text. The operator tool had the right answer and the format had never described it; this change is the format catching up to its implementation rather than the other way round.

## What the sweep is required to do

Read the directory. It cannot be derived from the database, which by construction holds no evidence an orphan exists, and that is the sentence worth keeping: it is why this could not be a query, an index or a column, and why it is stated in §5 rather than solved in the schema.

The format stops short of putting it on the write path. It is an operator action, and the format's job is to say a store needs it, not to put a directory scan in front of every batch.

## A term that had to be disambiguated

§5's garbage-collection bullet said a store MAY "recompute refcounts from the pointer columns and sweep orphans", using "orphan" for an object row left unreferenced. With the word now precise, that read as the new sweep and meant the old one. It says "sweep the rows left unreferenced" and states which sweep it is.

## Not settled here

Whether an object indexed with **no referrer** is legal, or given a grace window, is the mirror image of this one: a row with no pointer rather than a file with no row. It stays in the audit's triage list where it belongs, as a decision rather than a correction.
