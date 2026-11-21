# Prototypes, 2026-11-21

io-pimdir 7847427, snapshots under ~/code/pimalaya/.bench-notmuch/proto (never in a repo). Corpus: allen-p and arnold-j of Enron, 7,932 messages, 56 folders, 57 pages, 16.9 MB. Core 4, one run at a time, beside the 517k baseline import on core 12: wall times are indicative only (the baseline's own v0 ranged 6.7 to 19.7 s). Flushes counted by `strace -f -T -e trace=fsync,fdatasync,syncfs` launching pimbench; commits by a SQLite commit hook.

## Sync phase

| variant | flush calls (body / shard dir / SQLite) | time in flush calls | tx per page | write_bytes / msg | wchar / msg | CPU / msg | wall |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v0 today | 14,061 (7,932 / 5,963 / 166) | 5.4, 17.7, 13.5 s | 1, 2 past about 510 new members (65 tx, 57 pages) | 18.3 KB | 80.7 KB | 0.18 to 0.24 ms | 6.7 to 19.7 s |
| v1 each (write all, fsync each) | 14,061 | 37.2, 16.2, 13.8 s | as v0 | 18.3 KB | 80.8 KB | 0.17 to 0.23 ms | 39.1, 17.8, 15.1 s |
| v1 kick (`sync_file_range` at write, fsync each) | 14,061 | 6.5, 7.3, 6.7 s | as v0 | 18.3 KB | 80.7 KB | 0.18 to 0.22 ms | 8.3, 9.1, 8.2 s |
| v1 syncfs (one before the moves, one after) | 280 | 2.5, 1.8, 2.2 s | as v0 | 18.5 KB | 80.8 KB | 0.18 to 0.21 ms | 4.0, 3.2, 3.7 s |
| v4 one tx per page | 14,050 | 14.3, 14.4 s | 1 | 16.7 KB (-9%) | 80.1 KB | 0.17 ms | 15.7, 16.0 s |
| v3 addresses interned | as v0 | | as v0 | 17.0 KB (-7%) | 77.7 KB (-4%) | as v0 | 24.7 s (busy) |

The index phase is the same in every variant (28.8 KB written a message, 2.0 to 2.5 s CPU). Body fsyncs are 99% of the flush wait; shard directories (already flushed once per batch, src/client/blobs.rs `stage`) and SQLite about 1%.

## Item 2 (integer object ids), a scratch schema

A Python scratch schema with the real object indexes and the shared items indexes, WAL, `synchronous = FULL`, `secure_delete`, pages of 1,000 messages (one object, one item, one binding, three refcounts each), 20 pages measured after filling; on tmpfs, so wchar compares and write_bytes does not.

| rows | text key wchar / msg | integer key wchar / msg | database | CPU / 1,000 msgs |
| --- | --- | --- | --- | --- |
| 100k | 48.9 KB | 19.5 KB (-60%) | 123 against 87 MB | 69 against 40 ms |
| 1M | 59.1 KB | 24.4 KB (-59%) | 1,061 against 755 MB (-29%) | 61 against 52 ms |

One random index is left (the BLAKE3 name, unique on `objects`) against four today.

## Item 3 (interned addresses), the query side

Medians of 31 runs, v0 against v3: an exact `from:` address count about 5% slower (within noise), `from:@enron.com` 27% faster, threads within noise; pimdir.db 10% smaller (32,310 address rows, 3,094 distinct). It breaks erasure as written: an interned address outlives the erased item (io-pimdir tests/erase.rs `an_erased_mail_leaves_both_files`), so STORAGE §11.5 would need orphan addresses collected.

## Item 4, what forces a second transaction

The implementation's chunk, not the spec: io-pimdir src/sync.rs `WRITE_CHUNK = 1024`, cut mid-page; a new member is two ops (StoreObject, UpsertPlacement), so a page past about 510 new members splits. GUIDE.md already says one transaction a page. 3,925 transactions at 517k against 3,535 pages.

## Crash argument for item 1

Every temporary written; every one durable (an fsync each, or one `syncfs`) before any move; each moved by the no-replace move; each shard directory touched flushed once (`objects/` when a shard was created), or one `syncfs`; only then the rows commit. A loss before the last flush leaves orphans the collector removes (STORAGE §5); a name that survives holds durable bytes, since every flush ends before the first move. `syncfs` reports writeback errors only from Linux 5.8 and flushes every dirty page of the filesystem, whoever wrote it. The prototype held one descriptor per body until the flush (up to 1,000 a batch, near the default limit); a real version flushes by path or by `syncfs`.

## Recommendation to the owner

- **Item 1, keep in another form.** Writing all then flushing each gains nothing. The gain is early writeback (`sync_file_range`, about half the wait, steadier) or `syncfs` (50 times fewer calls). STORAGE §5 can allow either as long as every body is durable before its move; fsync each stays the portable floor (macOS, Android kernels before 5.8). Measure both at 517k on a quiet machine.
- **Item 2, keep: the largest lever on bytes written** (about 60% of SQLite's writes a message, 29% of the database). Confirm on the real schema at 517k before folding.
- **Item 3, probably drop**: under 10% fewer bytes, a random key left (`(address_id, role)`), erasure made harder. Keep only if 517k shows more than 10%.
- **Item 4, keep, no spec change**: cut only at a page's end (io-pimdir), 10% fewer commits, -9% bytes written on the small corpus.

Rerun commands: the agent's report kept in the session; the variants and their scripts are under ~/code/pimalaya/.bench-notmuch/proto (scripts/run.sh, scripts/classify.sh, v2-estimate/objkeys.py).
