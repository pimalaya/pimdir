---
cairn: change
id: performance-audit-2026-11-05
status: draft
created: 2026-11-05
---

# Performance audit, 2026-11-05: what a write, a read and a search cost, layer by layer

## Why

The standard grew by layers (the store, then sync, then search, then the Android shape on SQLite 3.18), each correct alone, and every performance fix so far was local: a statement rewritten, a scope narrowed. io-pimdir's a-page-lands-in-few-statements (2026-11-04) is debugging the phone's 8 ms per listed message; its a-delta-loads-what-it-names (2026-10-18) is stuck on the one predicate no index answers. This audit takes the global view: which operations cost in proportion to the store rather than to what they ask or what changed, why, and which structural changes fix them on every SQLite the format runs on, 3.18 included.

It is not a differential format audit (AGENTS.md §5). It read the ledgers of io-pimdir cairn/changes/a-page-lands-in-few-statements (as it stood at 07:59 on 2026-11-05, its host and phone profiles and the list-binding fix included), a-delta-loads-what-it-names and a-search-answers-at-scale, and android cairn/changes/store-performance, store-performance-followups and fill-from-two-queues (09:07), and lists only what they do not, or what its measurements change in them.

## Method

Measured on 2026-11-05 on a desktop (one idle core, tmpfs so no fsync cost), on the canonical schemas of storage-draft-08 and search-draft-08, with SQLite 3.51.2 and with 3.18.2 built with the AOSP flags of flake.nix's `sqliteFloor` (the Android floor). The scripts are in bench/ beside this file. Desktop numbers compare variants; a phone is 3x to 10x slower (android store-performance, 2026-10-11).

- Write (bench/write_bench.py): 20,000 new mail placements in batches of 500, each `bump_next_seq`, `insert_item`, two `placement_flag` rows, `insert_binding`, two `binding_base_flag` rows, `upsert_mail_summary` and four `item_address` rows, through prepared statements reused, WAL, `synchronous = FULL`, foreign keys and `secure_delete` on; median of three runs.
- Read and search (bench/query_bench.py, bench/marks.sql, bench/occ.sql): stores of 100,000 and 300,000 headers-only messages, a third read, two flags each; an index.db holding `placement` and `flag` as a refresh writes them; io-pimdir's compiled `is:unread` (src/client/search/compile.rs) against the store's own statements; FTS4 and FTS5 tables of 100,000 rows for the full-text costs.
- The app's own write path: the host and phone profiles io-pimdir's a-page-lands-in-few-statements recorded on 2026-11-05 (FillPageMeasure on the host SQLite 3.18, the OnePlus A5000's debug log), and Android 15's framework classes as Robolectric runs them (android-all 15, disassembled).

## The layers and what they cost

| Operation | Run by | Cost today | Should cost |
| --- | --- | --- | --- |
| A list page (list_mail_page_filtered and its siblings) | reader | 0.4 ms at 100k and 300k, 1 ms on 3.18 | the page: fine |
| A count, per day, unread per mailbox (count_mail, count_mail_by_day, count_unread, sum_mail) | reader, on every redraw of the Android list | the collection: 113 to 194 ms at 100k, 617 to 647 ms at 300k | what matches; the badge O(1) |
| A search page (io-pimdir and the Android bridge) | query client | the store, whatever is asked: 328 ms at 100k, 1,051 ms at 300k for `is:unread` | the page, or the matches of a selective term |
| A search answer's coverage | query client | the bodiless items of the scope: 51 to 62 ms at 300k headers-only | the collections |
| An agenda window (occurrences_between, occurring_between) | query client | every occurrence before the window's end: 6.5 ms where 0.75 suffice at 329k | the window |
| A delta, a round's last page | engine | the collection, loaded into memory: 22.5 s of a 28 s step at 1M, 1.3 to 1.7 s at 100k (2026-10-11 audit) | what changed and what owes a push |
| Writing a listed message | owner | 0.103 ms of SQL and 2.1 KB of pimdir.db on the desktop; on the phone 8 ms, about 3 ms since the list binding stopped flushing the statement cache | 1 ms on the phone, fewer bytes, fewer statements |
| Refreshing the index after a flag change | indexer | the summary re-read and its full-text row and flag rows rewritten | nothing for a flag |
| Reconciling the index after a purge or a collection | indexer | anti-joins over the whole index (placements_gone, objects_gone) | what was purged |

## Findings

### F1. A search reads the whole store, whatever it asks

Evidence: io-pimdir's compiled query (src/client/search/compile.rs, `Compiled::with` and `select`) opens every statement with `live`, a `DISTINCT` over every live item of every kind, tests each term's membership in a materialised set, computes each hit's sort key and kind by two correlated subqueries, sorts every hit and cuts by `LIMIT … OFFSET`. `is:unread` answers a page of 51 in 328 ms at 100k and 1,051 ms at 300k, a count in 74 and 290 ms, a page at offset 5,000 a little more. The store's keyset page answering the same rows (list_mail_page_filtered, `:seen` 0) takes 0.4 ms at both sizes and any depth.

The Android bridge forks that compiler (android rust/src/search/compile.rs, 799 lines), and its mail list asks for every hit, unpaged (android rust/src/ffi/search.rs:190, MailStore.java:725), carries them over JNI as JSON, then binds them back one `INSERT` per hit into `temp.param` for every page it reads (android rust/pimdir/queries/app/search_mail_indexed.sql).

The full-text side is not the cost: reading a term's whole match set takes 3 to 4 ms for 100,000 matches on FTS4 (3.18) and FTS5 (3.51), and 0.06 ms for 2,000 on FTS5; writing it to a temporary table keyed by rowid, 15 ms for 100,000. A per-row probe is the expensive way: 86 µs per probe on FTS4 under 3.18 (862 ms for 10,000), 6 µs on FTS5 under 3.51.

Cause: the compiler is a set algebra over the store. SEARCH §8.2 and GUIDE §15 step 4 state page forms that avoid it, neither implementation runs them, and the store-order form they describe tests each row with `match_object` or `match_summary`, the probe that costs most on the Android shape.

Fix: one planner in the I/O-free core (src/search/plan.rs, no rusqlite), shared by io-pimdir and the bridge, each rendering its shape's full-text fragment (F11):

- the scope, the collections `account:`, `collection:` and `kind:` narrow to, as the coverage already computes it;
- each text term's matches read once into a temporary set, as today, kept for the query's later pages;
- a driver: the store's order, each collection's `items_by_sort` merged as list_mail_page_filtered merges them, testing each row against the sets and the structured terms (store seeks), negation their complement; or, when the smallest positive set is small (its row count is known once read), that set, joined to the store and sorted; or `occurrence` for a dated calendar query;
- hits deduplicated by `(account, seq)` as the walk meets them, and a keyset cursor `(sort_key, seq, account)` in place of `OFFSET`;
- a count apart, and only when asked: the smallest set's size bounds it.

Spec (search draft): SEARCH §8.2 says which placement places a hit (its first in the order walked, so the greatest key descending and the least ascending, where io-pimdir takes the greatest), restates the store-order form with membership in each term's matches rather than a probe per row, and vectors walk pages to the end. `sort:relevance` keeps io-pimdir's whole-set order.

Version: none. The walk, the sets and the seeks run on 3.18, under FTS4 as under FTS5.

### F2. Every count is a full pass over its collection

Evidence: count_mail with `:seen` 0 takes 152 ms at 100k on 3.51 and 192 ms on 3.18, count_unread 158 to 194 ms, count_mail_by_day 113 ms on 3.18, all linear (617 to 647 ms at 300k). The Android mail list sizes itself by count_mail and places its day headers by count_mail_by_day on every redraw (android mail.md, "The mail list SHALL hold only the rows near the scroll position"), and redraws as each page of a sync lands.

Cause: unread is the absence of a `\Seen` row, tested by one `placement_flag` seek per item.

Fix: the store carries the system flags as bits on the item, `items.marks` (`\Seen` 1, `\Answered` 2, `\Flagged` 4, `\Draft` 8, `\Deleted` 16, by their exact bytes), and a base's on its binding, `bindings.base_marks`, `CHECK (flags_known = 1 OR marks = 0)` beside each. Two ways:

- **As the representation** (recommended): those flags are the columns, every other flag a row as now. A typical message writes its flags with `insert_item` and `insert_binding` and runs no flag statement; a flag change is one `UPDATE` of the column, stamped once by items_stamp_update. Reads join the bits and the rows into one set (§4.4's `flags` text), and the merge stays element-wise. This also removes the stamp chain at its cause, a flag row requesting its item's restamp (F4).
- **As a mirror** of the rows, kept by the `UPDATE` placement_flag_stamp_insert and placement_flag_stamp_delete already run (`SET changed = -1, marks = …`), checks/invariants.sh holding it equal to them: no model change, the counts gain as below, the writes gain nothing.

The representation is a second encoding of one set, sharper for an implementer (`\seen` is a row, `\Seen` a bit), which vectors must pin; it is recommended because F4 leaves statement count as the phone's lever and F13 makes the write the fill's ceiling. With `marks` in `items_by_sort`, or a partial `items_unread(collection, sort_key) WHERE deleted = 0 AND marks & 1 = 0`:

- count_mail `:seen` 0, in its canonical shape: 152 to 6.5 ms on 3.51, 152 to 66 ms on 3.18; 3.9 and 33 ms when its text leaves out the attachment test the chip did not bind;
- unread per mailbox on `items_unread`: 2.3 ms (3.51) and 34 ms (3.18) with two thirds unread, in proportion to the unread;
- count_mail_by_day gains nothing from the bits (it filters on no flag): 113 to 80 ms on 3.18 only when its text leaves out the unbound tests.

The Android list should also recount at most once per pass, or fold the feed into its counts, rather than recount the collection for every page that lands.

Version: partial indexes and bit operators are on 3.18 (3.8.0). A partial index serves only the very term it names, so the statements spell `marks & 1 = 0`.

Spec (storage draft): STORAGE §4.3 (`items.marks`, the mirror rule), §13, §14.1's counts and seen tests, an invariant.

### F3. A delta loads the whole collection (a-delta-loads-what-it-names)

That change's open point is what owes a push. Proposed answer, a statement rather than a stored marker:

- `list_owing_bindings(collection, source)`: the handles of this source's bindings whose placement may not be `Clean` (SYNC §3): a conflicted binding or item, a deleted item, no base, flags known on both sides and differing, an object other than the base's;
- `list_lacking_items(collection, source)`: the live items holding a body that this source does not bind, its `Created` projections;
- the engine loads the `Handles` and `Links` they name beside what the page lists.

A superset is safe, since the projection still decides each status from the rows it loads; a subset loses a push. So the predicate reads SYNC §3 conservatively, and a vector pins it on every status. It reads `bindings_by_handle` on `(collection, source)` and each item by its key: still a pass over the collection, but in SQL, allocating nothing, where today 92.8 MiB of placements, summaries and addresses cross into the engine at 425k. With F2's bits, and `bindings.base_marks` mirrored the same way, the flag test is a column comparison. A stored owed marker would make it proportional to the changes, at the risk of the silent-loss class the sync lessons record: worth it only if the statement still measures slow at 1M.

Measure the statements at 100k and 1M, on 3.18 and 3.51, before choosing.

### F4. The phone's 8 ms per message was statements prepared again; statement count is what is left (a-page-lands-in-few-statements)

Evidence, from that change on 2026-11-05: a page of 500 on the host SQLite 3.18 took 355 ms, 97% inside statements, about 27 statement runs per message; on the phone 7.9 ms per message, 86% inside statements, every statement 6 to 11 times its host time. It found the cause in `create_param`, run through `execSQL` before every list bind: run only when `clear_param` fails, the host page fell to 106 ms, and a Graph page of 500 now lands in 1.5 to 1.6 s on the phone (android fill-from-two-queues), about 3 ms a message against the 1 ms target.

Why, which that change leaves open: Android's `execSQL` flushes the statement cache after any DDL. In the Android 15 framework (`SQLiteDatabase.executeSql` in Robolectric's android-all 15), a statement `DatabaseUtils.getSqlStatementType` reads as DDL (one starting `CRE`, `DRO` or `ALT`) is followed by `SQLiteConnectionPool.clearAcquiredConnectionsPreparedStatementCache()` and `closeAvailableNonPrimaryConnectionsAndLogExceptions()`. Every statement after a `create_param` was therefore prepared again, its trigger programs recompiled with it, and the idle reader connections were closed, each reopened by the next read. The index handle runs its `CREATE_TERM_MATCH` through `compileStatement`, which flushes nothing; the app's other `execSQL` calls are savepoints, the attach and migrations.

This bench agrees once statements stay prepared (bench/write_bench.py, per new message):

| Variant | ms | Bytes |
| --- | --- | --- |
| canonical, every trigger | 0.103 | 2,101 |
| stamp triggers dropped (the bound for any stamp scheme) | 0.079 (−23%) | 2,095 |
| that change's pending stamp | 0.090 (−12%) | 2,105 |
| canonical, each statement prepared anew | 0.204 (+98%) | 2,101 |

The app's host page after the fix is 0.21 ms a message for its 27 runs, the stamp triggers 18% of it (106 against 87 ms).

What is left on the phone is statement runs, each at 6 to 11 times its host cost. Beyond that change's step 3 (the sender rule once per page, one lookup by link for unheld members), the levers are:

- no DDL through `execSQL` on any hot path, a test failing a page write whose profile names one;
- an item inserted with its flags known: the app's `SET_FLAGS_KNOWN` after `INSERT_ITEM` costs a statement and a stamp the canonical `insert_item` spares;
- lists bound inline (F9), ending the list binding's statements;
- the system flags carried as columns (F2), ending a typical message's flag and base-flag statements and its stamp requests, which leaves that change's step 2 nothing to save on a new message (one stamp from its insert either way);
- multi-row `INSERT … VALUES` for a page's fresh members (those no other op of the batch names, so the batch's order holds), up to the 999 variables: per-row triggers are cheap natively, so the step 3 objection to multi-row inserts weighs less than the calls they save.

io-pimdir has the same flaw by another road: rusqlite's `execute`, `query_row` and `prepare` (src/client.rs:1349 `rows`, 324 call sites) never consult the statement cache (rusqlite 0.41.1's `Connection::execute` prepares each call, its src/lib.rs:629; the cache holds 16 by default). `prepare_cached`, with a capacity above the hot path's distinct statements, should give the CLI what the list-binding fix gave the app (2x on this bench, 3.3x on the app's host page).

### F5. The schema spends its bytes on repeated keys: an integer placement id

Evidence: a headers-only message costs 2,101 bytes of pimdir.db (212 MB per 100,000 messages): `item_address` and its index 814 bytes for four rows, `placement_flag` and its index 286 for two flags, `binding_base_flag` 154, the primary-key autoindexes of `items`, `bindings` and `mail_summary` 199, `bindings_by_link` 58. Each child row and index entry carries `(collection, link_id)` again, two texts of about 60 bytes. Keyed by an integer placement id (a sketch with the same indexes and triggers), the message costs 1,072 bytes and its write 0.066 ms (−36%), 0.055 ms with the pending stamp (−46%).

Fix: `items.id INTEGER PRIMARY KEY AUTOINCREMENT`, never reused and never shown (a consumer keeps `(collection, seq)`), `UNIQUE (collection, link_id)`; `placement_flag`, `bindings`, `binding_base_flag`, the six summaries, `item_address`, `mail_in_reply_to`, `task_category` and `supersessions` keyed by `item`. Beside the bytes:

- a rename moves `items.collection` and the queue's, not every child row;
- every join from a child to its item is a rowid seek, `bindings_by_link` served by `items_by_link`;
- the index keys its per-placement rows on `items.id`, which F6 uses to drop its `placement` mirror.

Cost: every canonical statement that touches a child, checks/invariants.sh, io-pimdir's write path, the Android shape. The model vectors do not move (they state collections, link ids and seqs). It is a schema change: before storage-v1, or after it a migration rewriting every child table.

### F6. The index mirrors the store, and rewrites its mirror on every flag

Evidence: the index's `flag` table copies `placement_flag` (migrations/search/0001_init.sql still justifies it as sparing "a JSON scan of every item", which flags as rows ended), and `placement` copies `(collection, seq, link_id, object_hash)`. For every stamped live row the refresh emits `PutPlacement`, `PutMissing` or `DropMissing`, `ReplaceFlags` and, for a bodiless row, `PutSummaryText` (src/search/refresh.rs:551 to 594): a message marked read has its summary and addresses read again, its full-text row deleted and inserted, its flag rows replaced. Marking read is the most frequent write of a PIM store, and a phone holds mostly bodiless mail.

Fix:

- `flag:`, `tag:` and `is:` read the store (`placement_flag_by_flag`, or F2's bits), current where the index is one refresh behind; the index's `flag` table and `ReplaceFlags` go;
- the refresh rewrites a summary's text only when it changed, the index recording a digest of the text it wrote per placement (or the store drawing a second stamp for content, `items.revised`, if reading the summary to digest it still costs);
- with F5, `summary_text` is keyed by `items.id` and `placement` keeps only what the store does not hold (the hash indexed, `cut`).

The index is derived and rebuilt (SEARCH §2): a search draft and a rebuild, no migration.

### F7. An agenda window scans every earlier occurrence

Evidence: `start < :end AND (end > :start OR start >= :start)` seeks `occurrence_by_start` from its first row. A week over 329k occurrences (300 daily series across the three-year horizon) reads 6.5 ms on 3.51 and 8 ms on 3.18; bounded below by the longest occurrence, 0.75 and 1 ms, the same 2,100 rows.

Fix: the indexer records the longest span it wrote (`index_meta.max_span`, or a fixed bound with longer occurrences kept in a table of their own), and occurrences_between and occurring_between add `start >= :start - max_span`. SEARCH §7, the two statements, a vector with a multi-day occurrence.

### F8. Coverage is recounted with every answer

Evidence: `coverage` counts the scope's bodiless items on `items_bodiless`: 51 ms (3.51) and 62 ms (3.18) over 300,000 headers-only messages, for every page and count io-pimdir answers (src/client/search.rs:1203, `coverage`).

Fix: once per query rather than per page, and kept per collection until its stamp moves (`list_collections_changed_since`); per-collection counters only if that still costs.

### F9. Android: a list read waits for the sync's write

Evidence: every read taking a list, each mail list page and count among them, binds it through `temp.param` inside an immediate transaction on the writer's connection (PimdirDb.read: "the platform has no deferred transaction below API 35"), so it waits for the batch the sync writes: 1.5 s while a Graph page of 500 lands since the list-binding fix, 4 s before, and more often once listing runs in parallel (F13). It binds one `INSERT` per value, a search's every hit included (F1).

Fix: the app's shape binds its lists inline, `IN (?1, …, ?n)`, the text rendered per arity by the bridge and cached, chunked past 999 values; its reads then run on a reader connection under WAL, outside any write. STORAGE §4.4 already lets an implementation's own text bind its lists as it chooses.

### F10. A list parameter's affinity decides the plan, and nothing checks the floor's plans

Evidence: with `temp.param.value` declared `ANY` outside a `STRICT` table it takes NUMERIC affinity, and `x.collection = p.id` stops seeking: list_mail_page_filtered falls to a skip-scan of `items_by_sort` and a sort, 203 ms at 100k and 749 ms at 300k instead of 0.4 ms. The Android fork leaves `value` untyped, which keeps the seek (1 ms on 3.18), and names the reason (android rust/pimdir/queries/read/create_param.sql). checks/invariants.sh asserts plans on the sqlite3 on PATH alone, and checks/floor.sh compiles the writes on 3.18 but plans no read.

Fix: the plan asserts also run on the floor, with a param table 3.18 loads; STORAGE §4.4 states that a list parameter's value column carries no affinity (untyped or `BLOB`).

### F11. Two query compilers, the reference one outside the I/O-free core

io-pimdir's compiler lives under src/client/ and binds rusqlite values, so the bridge, built without `client`, forked it. F1's planner in src/search/ ends the fork: io-pimdir renders it for FTS5, the bridge for FTS4.

### F12. Lesser costs, after the above

- A hit's snippet reads and re-extracts its whole body (src/client/search.rs:1139 and android rust/src/search/find.rs, `snippet`): cut it for the rows shown alone, the extraction kept per hash for the page.
- The Android search keeps the sender and subject `LIKE` beside the index (android mail.md, "The mail search reads the index"), a pass over the collection for a rare word. What the index lacks is the store's rows above `index_meta.store_change`, few and found on `items_by_changed`: the `LIKE` need test those alone.
- placements_gone and objects_gone anti-join the whole index whenever the purge count moves, a collector run included. A bounded log of purged keys, folded as the feed is and falling back to the anti-join when a consumer's cursor is older than its floor, makes it proportional to the purges.
- FTS4 on Android keeps a copy of every text it indexes, since it cannot delete from a contentless table. A contentless table with a list of dead rowids filtered at query time drops that copy (its size unmeasured here), at the price of an erase (STORAGE §11.5) rebuilding the text table.
- SEARCH §4 asks an owner to refresh after each write batch. During a fill that doubles the writer's work and, on Android, locks the rollback-journal index against every search: refresh when a fill pauses, reporting the lag as now.

### F13. Parallel listing makes the writer the fill's ceiling (android fill-from-two-queues)

That change lists on three of Graph's four sessions at once (two of three on IMAP), each waiting for its own page's write, through one writer. At 6.4 to 6.5 s a page of 500 fetched and 1.5 to 1.6 s written, three Graph jobs keep the writer busy about 4.7 s of every 8 s; a backend listing 500 envelopes in about 2 s would leave the writer the bottleneck. For this plan:

- the write path's items (F4's levers, F2's columns, F5) set the fill's speed once listing is parallel, not just their share of each page, and move up;
- each list read binding a list waits behind more writes (F9), and each landed chunk redraws a list that recounts its collection (F2): recount at most once per pass, or fold the feed;
- the index, refreshed after every write (F12), refreshes as often as chunks land: refresh when the fill pauses.

Its open point, a session waiting for its own write, is the same throughput seen from the network: every millisecond off a page's write frees its session sooner. Its unexplained engine time on a first page (1.5 to 4.6 s for 20 messages) is worth the same profile as the writes, the engine's loads timed per statement, before anything is guessed.

## Not recommended

- A batch-wide stamp floor: a-page-lands-in-few-statements rejects it already.
- Writes through `json_each`: absent on 3.18, and the per-row triggers it was to avoid are not the cost (F4).
- Plans resting on `ANALYZE` statistics: a fresh store and the platform's SQLite have none. Every driver above is the planner's choice, made from row counts it reads, never from sqlite_stat1.
- A bundled SQLite on Android for these: every fix above runs on 3.18.

## Action plan

Ordered by what each step buys against what it costs; each lands with the check that fails without it (AGENTS.md §4). tasks.md is the ledger.

Phase 0, measure (days):

1. android: the phone's profile of a page after the list-binding fix (a-page-lands-in-few-statements' open task), which ranks what is left; and a test failing a page write that runs DDL through `execSQL` (F4).
2. io-pimdir: `prepare_cached` behind a switch, tests/search_scale.rs and a write bench at 100k and 300k, on and off.
3. pimdir: the plan asserts of checks/invariants.sh on the floor (F10).

Phase 1, implementations and the index, no store schema change (weeks):

4. io-pimdir: `prepare_cached` throughout, cache capacity set (F4).
5. pimdir, then io-pimdir: `list_owing_bindings` and `list_lacking_items`, a sync vector, plan asserts; delta and last-page loads by them (F3).
6. io-pimdir: the planner in src/search/ (F1, F11); pimdir: SEARCH §8.2, page-walk vectors (a search draft).
7. android: the bridge on the planner, a page from one statement on the index handle, no unpaged hits; lists bound inline, reads off the writer (F1, F9).
8. pimdir, io-pimdir, android: the index without `flag`, summary text rewritten only when it changed, occurrences bounded, coverage once per query (F6, F7, F8), in the same search draft, one rebuild.
9. android: an item inserted with its flags known, the rest of a-page-lands-in-few-statements' step 3 (the sender rule once per page, one lookup by link for unheld members), multi-row inserts of a page's fresh members, the index refreshed when a fill pauses, ranked by phase 0's profile (F4, F12, F13).

Phase 2, the store schema, before storage-v1 (one storage draft, decided now):

10. The system flags as columns, `items.marks` and `bindings.base_marks`, as the representation (or the mirror), their indexes, the counts and seen tests on them (F2, F4).
11. The integer placement id (F5), and the index keyed on it (F6).
12. The stamps: with item 10 as the representation a new message draws one stamp from its insert, and a-page-lands-in-few-statements' step 2 has nothing left to save there; without it, take that pending stamp (18% of the app's host page).

Phase 3, only if measured necessary:

13. A stored owed marker for deltas over a million members (F3).
14. The purge log, per-collection counters for the badges, contentless FTS4 on Android (F12).

## Sequence (decided 2026-11-05)

- The baseline: storage-draft-08, sync-draft-07 and search-draft-08 are tagged as they stand, at the commit pinning io-pimdir 42a2f26, which every app runs. No improvement here folds into them.
- Every store-side change of this audit (phase 1 items 5 and its statements, the sender rule per page, phase 2) lands together in one storage-draft-09, with sync-draft-08 where SYNC moves, so the apps reinstall once. Search changes take search-draft-09, a rebuild only.
- io-pimdir's own items (phase 1 items 4, 6 without its spec part, 8's coverage, the refresh skipping unchanged work) touch no draft and land on draft-08 meanwhile, `prepare_cached` before any io-pimdir measurement.
- Before draft-09 is written, a bench of its candidate store schemas against the tagged draft-08 (bench/draft09.c), on 3.51 and the 3.18 floor, reporting per message the milliseconds, the bytes and the statement runs, decides phase 2's content.

## Decisions for the user

- Phase 2 moves the store to storage-draft-09 while the freeze is close: apps on draft-08 (pinned on 2026-11-03) reinstall over a new store (README, Status). After v1 each is a migration, F5 rewriting every child table. Recommended: take item 10 now as the representation, the mirror only if a second encoding of a flag set is judged too sharp; take item 11 now if the freeze can slip one draft, else leave it to v2.
- a-page-lands-in-few-statements' step 2 against item 10: one of the two, not both. The pending stamp reserves a second stamp value and needs a closing statement no writer may forget; the columns remove the restamp requests it batches.
- SEARCH §8.2: a hit placed by its first placement in the order walked.
- SEARCH §4: "after each write batch" relaxed to "when writes pause", within a stated lag.
- F3: a statement first, a stored marker only if 1M still measures slow.
