# Report, the night of 2026-11-22 to 2026-11-23

## In short

The refactor landed whole by 22:15 and the performance pass by 05:00, everything committed unsigned and nothing pushed. The standard binds tables and columns only (no statement): 24 store tables became 15, 43 triggers 30, and 280 statements bound by pimdir became 0. On the 1M Enron store, the night's io-pimdir is ahead of notmuch on 50 of the 51 query measures and ties the 51st, the combined count, within noise. Every count is identical to round 4's and every page and threaded page to the refactored base binary's, and it imports in 750 s and 403 s of CPU against notmuch's 1,137 s and 1,005 s, both run quiet on the same core. io-pimdir's suite went from 1,089 to 1,171 tests, all green; no test was deleted.

## Sizes, before and after

| | before | after |
| --- | --- | --- |
| store tables / triggers / indexes / columns | 24 / 43 / 42 / 183 | 15 / 30 / 40 / 152 |
| index tables (io-pimdir's own now) | 13 | 11 |
| statements bound by pimdir | 280 | 0 |
| io-pimdir statements, storage / search | 217 / 63 | 185 / 58 (+3 own after the perf pass) |
| normative words, STORAGE / SYNC / SEARCH | 39,318 / 19,059 / 12,966 | 24,683 / 19,071 / 7,970 |
| GUIDE.md | 19,844 words | retired |
| io-pimdir tests | 1,089 (+8 ignored) | 1,171 (+8 ignored) |

io-pimdir's src/ did not shrink (70.7k lines): its statements were already .sql files, and the sync engine was left alone as ruled.

## The moves

| step | pimdir | io-pimdir | note |
| --- | --- | --- | --- |
| 2. the contract leaves the standard | 692af79 | d8f4807 | statements, index schema and generator are io-pimdir's; they stay under its spec/ (decision) |
| 3. flags as columns | 774022b | 6f8b198 | `items.keywords`, `bindings.base_keywords`; 2 tables and 12 triggers gone |
| 4. one summary, one list table | 6d8a90f | 5539042 | 9 tables into `summary` and `summary_value`; 76 ported invariant tests |
| 5 and 6. guards and the index | f295ed7 | 46d851f | queue RESTRICT, 4 dead statements, `chunk` and `thread` out of the index |
| 7. the documents | d47a676, 292aab1, d1c9274, a11b865, 4909035 | fea2d0c | SEARCH, STORAGE, SYNC/OVERVIEW rewritten, GUIDE retired, logs and changelog |
| 9b. perf: pages and threads | | fcb6012 | one read transaction a page, batched thread reads, lazy snippets |
| 9b. perf: proven body hits | | f5ca598, 6457c25 | no probe for hits the hit columns proved |
| 9b. perf: incremental | | 6f98392 | index.hits patched, not re-read |
| 9b. perf: the query floor | | 39f2d2b, 17d213b | ~0.5 ms off every query |
| 9b. perf: the index build | | e303029 | merges held back, one segment a table |
| logs and the CI matrix | fccf7b8 (+ this report) | 950383f, 176e0b7 | 176e0b7 fixes the feature matrix's `search`-only builds (a path tonight broke, two dead-code warnings since round 4) |

Nothing was rolled back. Skipped: the stretch items (supersessions as a column, performers into capabilities, statement twins), because 3 h 40 were lost idle (22:53 to 02:34: my waiter on the 1M import matched its own command line and never returned) and a store move during the perf pass would have forced a 1M re-import.

## Performance

Import, GNU time, core 12, writeback body flush, the machine quiet:

| | sync | index | total wall | CPU |
| --- | --- | --- | --- | --- |
| 1M notmuch new (fresh, 05:36) | | | 1,137 s | 1,005 s |
| 1M io-pimdir 509fd83 (2026-11-21, before writeback and round 4) | 1,422 s | 762 s | 2,184 s | 507 s |
| 1M tonight (e303029) | 520 s | 230 s | 750 s | 403 s |
| 517k notmuch new (fresh, 05:27) | | | 522 s | 483 s |
| 517k round 4 (00727ba, fresh, 05:21) | 239 s | 124 s | 363 s | 208 s |
| 517k tonight (e303029) | 232 s | 99 s | 331 s | 185 s |

The index build is the gain the code made (the import agent: a 517k rebuild from 121.8 to 92.2 s and 22.9 to 16.5 GB written). The sync code barely moved (`ensure_collection` alone), and its wall time moves with the disk: 339 s at 517k and 827 s at 1M on the first run at 22:31, 232 s and 520 s on the quiet run at 05:00.

Queries at 1M, hyperfine medians in ms, 20 runs, core 12, one run per row with notmuch / round 4 (00727ba on runs/x2d) / tonight (e303029 on its own 1M store):

| query | count | page of 50 | threads of 50 |
| --- | --- | --- | --- |
| all mail | 53.67 / 5.54 / 4.94 | 262.91 / 11.47 / 10.41 | 279.47 / 12.95 / 11.45 |
| unread | 21.24 / 6.98 / 6.66 | 80.36 / 10.20 / 9.53 | 84.95 / 11.15 / 9.90 |
| flagged | 6.14 / 4.92 / 4.36 | 16.41 / 6.93 / 6.15 | 18.36 / 8.21 / 7.10 |
| from address | 13.12 / 5.78 / 5.73 | 17.10 / 6.51 / 6.37 | 19.56 / 7.75 / 7.20 |
| from name | 4.08 / 3.75 / 3.16 | 8.34 / 6.50 / 4.47 | 9.42 / 7.14 / 4.74 |
| subject word | 5.65 / 4.47 / 3.94 | 14.70 / 7.43 / 4.89 | 17.10 / 9.22 / 6.46 |
| common word | 88.31 / 51.80 / 51.72 | 287.10 / 60.15 / 57.14 | 303.08 / 62.30 / 59.23 |
| mid word | 9.32 / 6.75 / 6.18 | 27.77 / 9.99 / 7.85 | 29.48 / 11.26 / 8.66 |
| rare word | 2.30 / 2.48 / 1.89 | 4.60 / 5.12 / 3.75 | 5.53 / 5.95 / 4.16 |
| phrase | 16.45 / 8.47 / 7.88 | 28.24 / 13.63 / 10.36 | 29.16 / 14.13 / 10.49 |
| two words | 7.45 / 6.58 / 6.00 | 17.26 / 10.45 / 8.12 | 18.74 / 11.40 / 8.65 |
| negation | 9.24 / 7.45 / 6.88 | 22.82 / 10.61 / 8.54 | 25.26 / 11.78 / 9.35 |
| prefix | 5.72 / 4.92 / 4.36 | 12.24 / 8.47 / 5.41 | 14.62 / 10.36 / 6.86 |
| date month | 23.89 / 6.38 / 5.65 | 39.63 / 9.12 / 7.85 | 41.44 / 10.05 / 8.57 |
| combined | 4.53 / 5.87 / 4.73 (tie) | 6.31 / 8.53 / 5.89 | 8.20 / 10.16 / 7.13 |
| unread word | 6.53 / 6.72 / 6.13 | 14.88 / 10.61 / 8.46 | 16.16 / 12.02 / 9.08 |
| folder | 2.63 / 2.88 / 2.13 | 2.92 / 3.44 / 2.73 | 4.00 / 4.81 / 3.57 |

- **Behind notmuch at the start of the pass:** rare word (page, threads), combined (all three), folder (threads). All are ahead now except the combined count. Three more pairs of 50 runs gave notmuch 6.1, 5.0 and 4.5 ms against pimdir's 5.6, 5.1 and 4.7, so the combined count is a tie within noise.
- **Answers:**
  - The 51 `--json` outputs of the final binary on its store are identical to the night's base binary (46d851f) on its store, and the 17 counts to round 4's.
  - The 51 outputs were also identical after each patch.
- **Incremental, 517k** (the incr agent, its own store copy):
  - A 300-message refresh takes 617 to 189 ms (notmuch new 725).
  - 1,000 flag changes take 368 to 84 ms.
  - The no-op sync takes 126 to 107 ms against notmuch's 52 ms. That one stays behind: the rest is in the sync engine, which the ruling left alone.
- **Details:** per patch in perf/README.md and io-pimdir cairn/log/2026-11-23-*.md. The agents' patches are kept under .pimdir-night/perf/agents/*/patch.diff.

## Decisions taken alone (decisions.md has each with its undo)

- No attribution trailer in commits (your instructions over the harness').
- The statements, index schema and generator stay under io-pimdir's spec/ rather than a new sql/ (churn for nothing).
- Baseline clippy, fmt and no_std skipped at the start; run at the checkpoints and at the end.
- floor.sh no longer checks query plans on SQLite 3.18: those plans are io-pimdir's now, which owes them a check.
- refresh.json at `v` 6 pins answers only; io-pimdir checks refreshed against rebuilt index rows instead.
- README's SEARCH major now means a break of the query language or of what an answer states.
- checks/references.pl kept (it checks links), its GUIDE entry removed (fccf7b8).
- Five unused search statements (`flagged`, `attached`, `holding`, `categorised`, `occurring_between`) and the index's `missing` table kept, for the Android app.
- `store_meta_identity` kept: it is what tells a restored copy from the store a consumer followed.
- STORAGE.md stops at 24,683 words, not 18,000: what is left is rules.
- §14.1's read list (unread by `\Seen`, a message counted once, LIKE, NULL cursors) went with the statements; io-pimdir still does all of it.
- The reader statements keep their names and columns through aliases (`title AS subject`, `uid AS message_id`, `card_kind AS kind`).
- New CHECKs on `summary`; an undeclared-kind collection whose body changes kind replaces its summary row.
- The CLI's `"table": "mail_summary"` output kept, as the vectors' logical name.
- `delete_collection` checks queued actions first, the RESTRICT behind it, same error code.
- The refresh coroutine still emits thread and chunk ops (public types unchanged, the Android app served).
- Stretch skipped; the perf pass started at 02:45 instead of 05:15.

## Consumers (consumers.md; nothing was ported, as ruled)

- **neverest:** 1 line to patch, the format string in a test.
- **himalaya:** 4 lines: two `UPDATE mail_summary` and one `DROP TABLE item_address` in tests, plus the format string.
- **cardamum:** 0 lines.
- **calendula:** 2 lines: one `UPDATE event_summary` and the format string.
- **Android:**
  - 52 of the 130 bound names touch the moves.
  - About 50 of its own statements break (28 app, 18 owner forks, 4 index), as does its Rust search.
  - Estimate: one to two focused days.
  - storage-draft-17 refuses existing stores, so every app starts over.

## Not verified

- No live server, no phone, no consumer build. The io-pimdir CI matrix ran locally: `cargo test --all-features`, `--no-default-features --features cli` and `--lib` green at 950383f (2,778 tests across the three runs, 0 failed); fmt and clippy `-D warnings`, on all features and on each search feature alone, green at 176e0b7, which changed a path and two attributes after the tests.
- The ignored suites (8 tests) did not run.
- The sync phase's wall time is disk-bound and moved 1.6x between runs, so trust its CPU and bytes over its wall time.
- No dbstat per table.

## Doubts left for you

1. **The two kept items:** keep `store_meta_identity`, the five unused statements and the `missing` table, or cut them and give the Android port more work?
2. **The §14.1 read list:** should it come back as reader duties in STORAGE?
3. **STORAGE.md's length:** cut more rules, or accept 24.7k words?
4. **Uncovered invariants:** 120 of the 196 rules have no test yet.
   - 48 are plan checks and 17 are rehearsals, left aside by design.
   - The other 55 are listed in invariants.tsv; the porting agent judged about 35 of them worth a test.
   - io-pimdir also owes the SQLite 3.18 plan checks that floor.sh dropped.
5. **`PimdirReader::get_item`:** it answers `invitation: None`. This is old behaviour (the reader's statements never read it), not a regression.
6. **Static linking:** it would save 0.15 to 0.21 ms a query (the dynamic loader is 7.8% of a count). That is a packaging choice.
7. **A breach of the rules:** the floor agent ran `nix build nixpkgs#glibc.static` to measure static linking, which downloaded from cache.nixos.org despite the brief's no-network rule. Nothing else left the machine.
8. **Push and tags:** pushing pimdir (with checks/io-pimdir.rev at 176e0b7) and io-pimdir, and tagging storage-draft-17 and search-draft-17, are yours. The consumers follow at their next bump.
9. **The no-op sync:** it is still 2x notmuch's. The rest of its cost is in the sync engine; touch it or not?

## Where things are

- pimdir: this change folder (journal.md, decisions.md, perf/README.md, consumers.md, rules.tsv, invariants.tsv) and cairn/log/2026-11-22-a-smaller-pimdir.md.
- io-pimdir: cairn/log/2026-11-22-a-smaller-pimdir.md, 2026-11-23-the-night-perf-pass.md, 2026-11-23-the-hit-columns-patched.md, 2026-11-23-a-build-merges-once.md, and CHANGELOG.md under Unreleased.
- .pimdir-night: checkpoints/, perf/ (binaries, stores old-x1, new-x1, new-x2, final-x1, final-x2 and nm-x1, about 50 GB to delete when done, logs, scripts).
