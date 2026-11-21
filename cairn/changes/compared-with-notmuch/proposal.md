---
cairn: change
id: compared-with-notmuch
status: draft
created: 2026-11-21
---

# Compared with notmuch: the API, and a benchmark on 0.5 and 1 million messages

## Why

pimdir is close to its freeze (the-freeze-plan). notmuch is the reference for a local mail index that "handles millions of mails", so the owner asked on 2026-11-21 what each side lacks against the other, and where pimdir stands on the same mail at that scale.

## What

Two parts: an API comparison read from both sides' sources, and a benchmark of the same Maildir imported and queried by both. No spec or code changed; the follow-ups are in tasks.md, each waiting on an owner decision.

Versions: notmuch 0.40 (libnotmuch 5.7.0, Xapian 1.4.31, nixpkgs); pimdir search-draft-15 for the benchmark, search-draft-16 for Part 1's query lines; io-pimdir 5d6419a (v0.19.0 plus tests), release build, fat LTO.

## Part 1: the API

Sources: notmuch.h and the notmuch 0.40 man pages (man1, notmuch-search-terms(7), notmuch-sexp-queries(7), notmuch-properties(7), notmuch-hooks(5)); STORAGE.md, SYNC.md, SEARCH.md; io-pimdir's client API and `pimdir` CLI. Where a line says "verified", it was run on a probe Maildir of five crafted messages through both tools.

### Different jobs

notmuch is an index over mail files it does not own ("Not much of an email library, (just index and search)"): the files are the source of truth, tags are the only data it holds that the files cannot recreate, and fetching, sending and server sync are other tools' (mbsync, lieer, an MTA, through hooks). pimdir is a store: it owns the bodies (content-addressed, verified, deduplicated), syncs them with servers by three-way merge, and holds contacts, calendars, tasks and files beside mail. Most gaps on each side follow from that.

### What pimdir lacks against notmuch

| notmuch | pimdir | Weight |
| --- | --- | --- |
| English stemming: `meeting` finds `meetings` (verified) | none, words match as folded tokens (SEARCH §5) | high: the first thing a notmuch user notices |
| regex on `from:`, `subject:`, `tag:`, `mid:`, `folder:`, `path:` (`/re/`), and in sexp queries | trailing `*` only | medium, power users and scripts |
| `thread:{query}`: every message of the threads a query matches | `thread:<id>` names one thread; `--threads` collapses hits | medium: "whole threads where Jane wrote" is one notmuch query |
| thread object: authors split matched/unmatched, matched and total counts, subject, union of tags | threaded listing: id, count, first, last, hits | medium for a thread-list UI |
| arbitrary per-message properties, multi-valued key/value | none; typed references between items, and the owner's private local/ directory | medium: notmuch keeps crypto state there and plugins use them freely |
| local-only tags of any string up to 200 bytes | tags are flags of a placement, synced to sources that carry keywords | different model, below |
| `id:`/`mid:` on the Message-ID | `mid:` since search-draft-16 (the-query-serves-every-client, 2026-11-21) | closed |
| natural dates: `last week`, `3rd August 2012`, times of day, zones, `@epoch` | `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, instants with an offset, `today`, `yesterday`, `30min`, `5h`, `3d`, `2w`, `2mo`, `1y`, ranges (search-draft-16) | low: no words, but pinned and zone-aware |
| user-chosen headers indexed (`index.header.List=List-Id`) | the fixed fields of SEARCH §6 | medium: `List-Id` filtering is common |
| `NEAR`, `ADJ` proximity, `xor` | phrases only | low |
| saved queries (`query:name`, sexp macros) | none, an app's feature | low |
| excluded tags (`search.exclude_tags`, omit, flag and all modes) | none; a deleted item is out of every answer, the trash is the store's | low |
| attachment text indexed by MIME type (`index.as_text`) | attachment names and types only | low to medium |
| index-time decryption with stashed session keys; `show --decrypt`, `--verify` | encrypted bodies recorded `encrypted`, headers indexed; decrypted indexing allowed on request (SEARCH §6), not implemented | medium for PGP users |
| a C library with Python, Ruby, Go and Emacs bindings in use | a Rust crate; another language implements the standard or reads SQLite | medium |
| `show` (MIME tree as JSON or sexp, parts, raw), `reply` templates, `address` harvesting with dedup and counts, `dump`/`restore`, `notmuch git`, hooks, config in the database | layering: MIME is mime-rs, replies mml and himalaya, addresses `item_address` across every kind, backup `store backup`, hooks and config the apps' | not owed by a store |

### What notmuch lacks against pimdir

| pimdir | notmuch |
| --- | --- |
| owns and verifies the bodies: BLAKE3 names, deduplicated across folders, a failing body quarantined and fetched again | references files it does not own; a moved or corrupted file is the user's problem |
| sync engine: three-way merge with IMAP, JMAP, DAV, Graph, Gmail; several sources per item; conflicts kept with both bodies; a push confirmed before local state moves | none; only the maildir flags D, F, P, R, S map to tags |
| contacts, calendars (recurrences expanded, agenda reads), tasks (status, priority, categories), files | mail only |
| cross-kind search: `person:`, `with:`, `linked:`, `kind:`, a card and its mail in one answer | mail only |
| accent folding: `reunion` finds `réunion` (verified) | not folded: `reunion` misses `réunion` (verified) |
| orders by title, sender and relevance (bm25) beside newest and oldest first (search-draft-16) | newest or oldest first in the CLI |
| a pinned grammar refusing a malformed query with its position, what was expected and the fields (verified on `(meeting`, `meeting and`, `foo:bar`, `subject:`) | Xapian guesses: `(meeting` answers 3, `foo:bar` answers 0 silently, `meeting and` fails as "A Xapian exception occurred" (verified) |
| coverage on every answer: bodiless, missing, unparseable and encrypted counts, index lag, whether the answer is complete | none: a message not indexed yet is silently absent |
| partial bodies: headers-only items, bodies released below a date with the headers kept, eviction, scoped sync windows | every file is indexed whole |
| retention: trash, restore, purge, erase scrubbing the index and free pages | delete the file, then `notmuch new` |
| action queue: add, move, copy, remove, set-flags, update, send, invitation replies, collection create, rename, delete, with receipts and per-source capabilities | `insert` only |
| readers on a consistent snapshot (SQLite WAL) while the owner writes | readers can fail with `OPERATION_INVALIDATED` and must reopen |
| durable transactions | atomic sections "only ensure atomicity, not durability" |
| change feed: a stamp per row, a purge counter, store id and incarnation, so a restored copy is detected | `lastmod` and a UUID that compaction resets |
| stable public ids and keyset paging that neither repeats nor skips under change | `--offset`, `--limit` |
| text chunks for snippets and embeddings | none |
| an open standard with cross-implementation vectors | one implementation |

### Same feature, different meaning

- **Tags.** notmuch: local, per message, on every file of the Message-ID, never sent anywhere. pimdir: per placement, synced as IMAP keywords and the like, so `pimdir tag` goes through the queue and reaches the server. A pimdir user wanting notmuch's local labels has nowhere to put them: no local-only flag namespace, no properties.
- **Duplicates.** notmuch: one message per Message-ID whatever the content. pimdir: one item per identity across collections, but another message reusing a Message-ID (another subject, date or sender) is minted apart and kept.
- **Threads.** Both link by In-Reply-To and References with phantom parents and no subject joining; on the probe both threaded alike (verified). notmuch's ids are opaque counters, pimdir's the link id of the earliest member.
- **Unread.** notmuch: a tag set by `new.tags` and cleared by the `S` flag. pimdir: the absence of `\Seen`, the server's own state.
- **Stemming against folding.** notmuch stems English and does not fold accents; pimdir folds case and accents and does not stem. Each misses what the other finds.

## Part 2: the benchmark

### Setup

- **Corpus.** The Enron corpus (CMU release of 2015-05-07, sha256 b3da1b3f…, 517,401 messages, 1.36 GiB, 3,311 folders), turned into Maildirs by bench/maildirify.py: flags drawn from a hash of each path (5% in new/, else `S` 75%, `R` 8%, `F` 4%), the same for both tools. The 1M tier adds a second copy whose Message-IDs are rewritten (`@thyme` to `@thyme2`), so it holds 1,034,802 distinct messages. Enron carries almost no In-Reply-To, so threads are mostly single messages, and no attachments.
- **notmuch.** `notmuch new` over the Maildir, `synchronize_flags=true`, `new.tags=unread;inbox`, no excluded tags, the index outside the mail tree.
- **pimdir.** bench/harness is a Maildir connector (`PimdirRemote`) driving io-pimdir's real sync engine: one round per folder in pages of 1,000, each member listed with its body (as a DAV connector lists), so every message is derived, keyed and stored the way a sync stores it, in one write. Then `PimdirIndex::refresh` builds index.db. Queries go through the `pimdir` CLI with `--refresh-timeout 0s`.
- **Measures.** Every run pinned to one core (`taskset -c 12`), one tool at a time, `sync` between runs, GNU time for wall, CPU and peak RSS, hyperfine medians (10 runs at 517k, 5 at 1M, 2 warm-ups) for queries, page cache warm. The machine (Ryzen AI Max+ 395, NVMe under LUKS, ext4) ran other sessions' builds meanwhile: read wall times as ±10%.

### Import

| 517,401 messages | notmuch | pimdir, durable | pimdir, fsync disabled (eatmydata) |
| --- | --- | --- | --- |
| wall | 719 s (720 msg/s) | 2,527 s (205 msg/s): sync 2,104, index 423 | 380 s (1,362 msg/s): sync 118, index 262 |
| CPU (user + sys) | 547 s | 431 s: sync 180, index 251 | 350 s |
| peak RSS | 412 MB | 127 MB sync, 29 MB index | same |
| on disk | 4.78 GB index, the Maildir kept apart (2.6 GB) | 1.05 GB pimdir.db, 1.98 GB index.db, 1.42 GB bodies | same |

| 1,034,802 messages | notmuch | pimdir, durable |
| --- | --- | --- |
| wall | 1,719 s (602 msg/s) | 3,320 s (312 msg/s): sync 2,214, index 1,106 |
| CPU (user + sys) | 1,097 s | 902 s: sync 377, index 525 |
| peak RSS | 421 MB | 137 MB sync, 30 MB index |
| on disk | 8.96 GB index | 2.11 GB pimdir.db, 3.96 GB index.db, 2.84 GB bodies |

At 51,960 messages (18 users) the same split holds: notmuch 46.6 s (43.2 s without fsync); pimdir 94.7 s durable (sync 61.2, index 33.5) and 26.6 s without fsync (sync 9.6, index 17.0).

**pimdir computes less than notmuch and waits on the disk.** Its CPU is 0.8 times notmuch's at both tiers, linear in the messages (sync 180 s then 377 s, index 251 s then 525 s), and without flushing it imports 1.9 times faster; durable, it is 3.5 times slower at 517k and 1.9 times at 1M. The waits, read in /proc while the 517k import ran (wchan `jbd2_log_wait_commit` 60% of samples, CPU 7 to 13%), come from three costs:

1. **Two flushes per body** (STORAGE §5: `fsync` the temporary, then the shard directory): 5,482 `fsync` for 3,034 messages on the smoke test.
2. **`synchronous = FULL` per commit** of the store and of the index (io-pimdir src/client.rs `DURABILITY`); the index commits every 256 rows.
3. **Write amplification.** At 390k messages the import had written 70 GB through SQLite and 32 GB to the disk, about 80 KB per message for 3.4 KB of mail. Each message lands in about 20 B-tree indexes, six on random keys: `items_by_link` (Message-ID), `items_by_object`, `bindings_by_object`, `bindings_by_shared_object` and the `objects` key (BLAKE3), and `item_address_by_address`, 9.4 rows per Enron message. Each random insert dirties its own leaf page, written once to the WAL and again at the checkpoint, with `secure_delete = ON` zeroing what is freed. Xapian buffers thousands of documents and flushes sorted posting lists.

**Durable wall times are the disk's, and this disk was shared.** The 517k sync slowed from 400 msg/s to 120 msg/s between 250k and 390k messages, which first read as the random-key indexes outgrowing the pages one commit shares; the 1M sync then took barely longer than the 517k one (2,214 s against 2,104 s), its rate swinging between 214 and 650 msg/s with no trend as its store grew past a million. Other sessions' builds loaded the disk (I/O pressure 12 to 26% during the 517k run): an fsync-bound wall time on this machine moves by 2, and only CPU time and bytes written compare across runs.

### Queries

Medians in ms through each CLI, process start included (notmuch's is about 2 ms). `count` is the count, `page` the first 50 newest first (notmuch `search --output=messages`, pimdir `search -n 50`), `threads` the first 50 threads (notmuch's default summary, pimdir `--threads`).

| query at 517k | hits nm / pd | notmuch count / page / threads | pimdir count / page / threads |
| --- | --- | --- | --- |
| all mail (`*`, `kind:mail`) | 517,401 / 517,401 | 30 / 133 / 141 | 831 / 3,045 / 13,837 |
| unread | 148,811 / 148,811 | 12 / 42 / 45 | 430 / 1,051 / 4,009 |
| flagged | 19,358 / 19,358 | 5 / 10 / 12 | 229 / 314 / 676 |
| `from:jeff.dasovich@enron.com` | 11,411 / 11,411 | 8 / 11 / 12 | 227 / 274 / 471 |
| `from:dasovich` | 11,411 / 11,413 | 4 / 6 / 7 | 246 / 292 / 491 |
| `subject:meeting` | 16,266 / 16,281 | 4 / 9 / 10 | 284 / 357 / 655 |
| `enron` | 494,218 / 497,593 | 48 / 145 / 156 | 1,533 / 3,614 / 14,143 |
| `california` | 39,792 / 39,826 | 6 / 16 / 18 | 357 / 517 / 1,220 |
| `kiwi` | 36 / 35 | 3 / 4 / 6 | 198 / 213 / 210 |
| `"natural gas"` | 17,654 / 17,655 | 11 / 17 / 18 | 292 / 371 / 721 |
| `power california` | 14,924 / 14,631 | 6 / 11 / 13 | 496 / 561 / 816 |
| `california not gas` | 28,748 / 28,776 | 7 / 14 / 16 | 558 / 677 / 1,182 |
| `deriv*` | 9,274 / 9,274 | 4 / 8 / 9 | 251 / 326 / 497 |
| `date:2001-05-01..2001-05-31` | 35,661 / 35,659 | 15 / 23 / 25 | 377 / 520 / 1,169 |
| from, year and word | 2,996 / 3,007 | 4 / 7 / 8 | 905 / 926 / 967 |
| unread and word | 11,383 / 11,392 | 5 / 9 / 11 | 429 / 485 / 689 |
| `folder:dasovich-j/inbox` | 1,387 / 1,387 | 3 / 4 / 6 | 134 / 145 / 167 |

| query at 1M | hits nm / pd | notmuch count / page / threads | pimdir count / page / threads |
| --- | --- | --- | --- |
| all mail | 1,034,802 / 1,034,802 | 56 / 268 / 282 | 1,727 / 6,510 / 28,416 |
| unread | 297,622 / 297,622 | 26 / 82 / 88 | 880 / 2,160 / 8,329 |
| flagged | 38,716 / 38,716 | 6 / 17 / 21 | 477 / 651 / 1,388 |
| `from:jeff.dasovich@enron.com` | 22,822 / 22,822 | 14 / 18 / 21 | 484 / 576 / 958 |
| `from:dasovich` | 22,822 / 22,826 | 4 / 9 / 11 | 515 / 606 / 988 |
| `subject:meeting` | 32,532 / 32,562 | 6 / 15 / 17 | 576 / 714 / 1,324 |
| `enron` | 988,436 / 995,186 | 94 / 288 / 314 | 3,291 / 7,730 / 28,740 |
| `california` | 79,584 / 79,652 | 9 / 28 / 31 | 744 / 1,065 / 2,519 |
| `kiwi` | 72 / 70 | 2 / 5 / 6 | 396 / 415 / 415 |
| `"natural gas"` | 35,308 / 35,310 | 18 / 30 / 32 | 595 / 746 / 1,395 |
| `power california` | 29,848 / 29,262 | 8 / 22 / 24 | 1,062 / 1,182 / 1,698 |
| `california not gas` | 57,496 / 57,552 | 12 / 30 / 31 | 1,213 / 1,447 / 2,487 |
| `deriv*` | 18,548 / 18,548 | 6 / 13 / 18 | 517 / 657 / 1,000 |
| `date:2001-05-01..2001-05-31` | 71,322 / 71,318 | 26 / 41 / 46 | 799 / 1,102 / 2,438 |
| from, year and word | 5,992 / 6,014 | 6 / 9 / 10 | 1,874 / 1,911 / 2,019 |
| unread and word | 22,766 / 22,784 | 7 / 15 / 18 | 916 / 1,019 / 1,429 |
| `folder:dasovich-j/inbox` | 1,387 / 1,387 | 3 / 4 / 5 | 274 / 290 / 310 |

The hit sets agree within 1%: free text reads more fields in pimdir (every field of SEARCH §6) and stems in notmuch, and a few Enron headers decode apart.

**notmuch answers 23 to 220 times faster at 517k, 24 to 300 times at 1M, and pimdir's cost follows the store, not the answer.** Doubling the store doubles every pimdir answer, the selective ones included: `kiwi` 198 ms then 396 ms, `folder:dasovich-j/inbox` (the same 1,387 messages in both) 134 ms then 274 ms, where notmuch stays at 2 to 3 ms. At 517k, `kiwi`, 35 hits, costs 198 ms. Timed inside io-pimdir on a scratch copy: 125 ms is the count statement, 69 ms the coverage.

- **Every query reads the whole store.** The compiled statement opens with `live(akey, account, seq) AS (SELECT DISTINCT … FROM store.items i JOIN store.collections c … WHERE i.deleted = 0 AND i.retained_at IS NULL)` and tests every live item against each term's set, so a one-collection query with no hit still costs 125 ms at 517k. A page then reads every hit before it sorts and cuts (`unsorted`), and a threaded page groups every hit. This is F1 of performance-audit-2026-11-05, whose planner task (src/search/plan.rs: a smallest-set or store-order driver, a keyset cursor, a count apart) is still open.
- **Coverage is read per collection on every answer.** `search_temporal` runs `list_coverage` once per collection (20 ms over 3,311), `COUNT_UNINDEXED` plans as a walk of `items_by_seq` over every item of the collections instead of a seek on `items_by_changed` (41 ms with the kinds' counts; 47 ms alone in sqlite3), and the 3,311 ids are bound again into `temp.param` (3 ms). This is F8 of the same audit, also open.

### Incremental work, at 517k

| | notmuch | pimdir |
| --- | --- | --- |
| nothing changed | 0.07 s (directory mtimes) | 3.7 s: 3,311 delta syncs, the connector reading every directory, plus 0.01 s of index |
| 1,000 new messages in a new folder | 3.6 s | 9.3 s sync + 3.3 s index |
| 1,000 flag changes (files renamed) | 5.4 s | 3.6 s sync + 0.1 s index |
| tag 11,411 messages (`+bench`, `--add bench`) | 7.5 s | 5.9 s, staged through the queue and applied |

pimdir's no-op cost is the harness connector's as much as the engine's (it lists every folder; a real connector asks the server for a delta); notmuch's comes from not looking at unchanged directories.

### What this says

- At import, pimdir is not slow at its own work: on the same mail it computes less than notmuch and, unflushed, finishes in half the time. Its durable rate (200 to 470 msg/s on this shared disk) is bound by flushes and random-key index writes. A first sync of a million messages over IMAP is bound by the server anyway; a local import, or a phone's first fill, meets these costs head-on.
- At query time, pimdir is two orders of magnitude behind on a large store because the reference query path is O(store) by construction. Nothing in SEARCH forces that: §8.2 already describes the two paged forms (store order with term probes, best matches first), and the audit's planner is the fix.
- On disk pimdir is smaller (3.0 GB of databases against 4.8 GB at 517k, 6.1 GB against 9.0 GB at 1M, plus its own copy of the bodies), and it uses a third of the memory.

## The plan

Decided with the owner on 2026-11-21: pimdir as efficient as notmuch (parity on the bench, more welcome), notmuch's well-chosen features taken and extended to every domain, the domains linked. Plain words stay exact; stemming (`~word`), regular expressions (`/re/`) and subqueries (`field:{query}`) come later as their own operators. No C library: the CLI's JSON output is the integration point. Decryption is not planned now but must come without a format break.

- pimdir cairn/changes/the-write-path-before-the-freeze: bodies flushed by page, integer object ids, interned addresses, prototyped and measured before the spec moves.
- pimdir cairn/changes/an-item-keeps-local-state: `item_property`, local labels, `label:` and `property:`.
- pimdir cairn/changes/the-query-reserves-its-later-forms: exact words stated, `~`, `/…/` and `{…}` refused now, the extraction status open.
- pimdir cairn/changes/a-query-reads-across-domains: subqueries, the thread summary, `list:`, address harvesting, recursive collections, proximity, regex, stemming.
- io-pimdir cairn/changes/as-fast-as-notmuch: the bench as a standing suite, the planner and coverage, the write path and the index refresh, the gates.
- io-pimdir cairn/changes/the-json-output-is-the-integration-point: the JSON output a contract, amending the-freeze-plan D4.
- io-pimdir cairn/changes/a-decryption-break: the refresh's shape when decryption comes, nothing owed now.
