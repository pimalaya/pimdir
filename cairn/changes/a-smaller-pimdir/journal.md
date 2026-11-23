# Journal of the night

Appended at every checkpoint. The last entry names the step in progress; a session resuming starts there (tasks.md, "If the night is cut short").

## 2026-11-22 21:14, step 0

Commits read: pimdir b5b9382, io-pimdir 00727ba, himalaya a2726f56, neverest 99384ff, cardamum 22c0bd5, calendula 794550c, android c21fb53. Owner gave GO at 21:14 with the rulings at the top of proposal.md's decisions. Checkpoints under ~/code/pimalaya/.pimdir-night/checkpoints/.

## 2026-11-22 21:20, step 1 done, steps 2 and 3 running

Baseline: io-pimdir `cargo test --all-features --no-fail-fast` 1,089 passed, 0 failed, 8 ignored, 195 s wall; pimdir `nix flake check` passes (64 s) on a clean snapshot of 4fe9698 (a stale untracked .claude/worktrees/ in the pimdir checkout breaks the references check under `path:`, so checks run on tracked files). Sizes in .pimdir-night/baseline/sizes.txt. Clippy, fmt and no_std not run at baseline (CI keeps them green; they run at checkpoints). Checkpoint 00-baseline taken. The other session (pimalaya-c1) is not reachable: not told.

Lanes: step 2 pimdir side (agent: statements, index schema, generator and their checks leave pimdir); invariants.sh mapped to io-pimdir tests (agent, read-only, on the checkpoint copy); step 3 flags as columns (agent, io-pimdir and pimdir's schema). Lead: io-pimdir side of step 2 (spec_drift compares migrations/storage, vectors, payloads only; build.rs and the generator README restate ownership).

## 2026-11-22 21:23, step 2 committed

pimdir 4250177 (queries/, migrations/search/, generator/, names.sh, signatures.py, waivers.txt, invariants.sh out; schema.sh, floor.sh, tags.sh, frozen.sh, implementation.sh, vectors.py, flake.nix, AGENTS.md, README.md follow; refresh.json v 6 pins answers only). io-pimdir 286c50f (spec_drift compares migrations/storage, vectors, payloads only; REVISION 4250177; the refresh test compares refreshed and rebuilt object and split rows). Gate: pimdir flake checks pass on the step-2 tree with the committed schema (the agent's scratch run); io-pimdir's full gate is run with step 3, since the step-3 agent was already editing the tree. Checkpoint 01-contract taken (it holds step 3 half done in the working tree; the commits are the step-2 state). Step 3 in progress.

## 2026-11-22 21:30, step 3 still running

Done beside it: rules.tsv (225 requirement sentences: 200 kept, 14 moved, 11 dropped) and rules-notes.md; consumers.md (consumer and Android map); invariants.tsv (564 rules, 196 uncovered). Running: step 3 (flags), STORAGE.md rewrite, SEARCH.md rewrite, the invariant port (waits on .pimdir-night/step3.done before running its tests).

## 2026-11-22 21:36, step 3 committed

pimdir 0f5e542, io-pimdir (this commit, REVISION 0f5e542). Gate: io-pimdir 1,090 passed (1,089 + the new keyword test), 0 failed once REVISION moved (spec_drift 7/7), 8 ignored; clippy clean; no_std lib 436 passed; pimdir flake 5/5. Triggers 43 to 31, tables 24 to 22. Plans of the mail page, unread page, counts and owing load unchanged. Checkpoint 02-flags taken. Note: checkpoint 01-contract holds a half-edited tree; do not restore from it. Next: step 4 (one summary, one list table).

## 2026-11-22 21:50, documents

SEARCH.md 12,966 to 7,970 words (0e5a9b8), STORAGE.md 39,318 to 24,683 (c7f424c), both draft-17, references check green on each. Step 4 running (pimdir's vectors check is red until it lands: checks/vectors.py still names the six summary tables). SYNC.md and OVERVIEW.md lane started.

## 2026-11-22 21:54, invariants ported

76 rules of the former invariants.sh ported as io-pimdir tests (tests/invariants_*.rs, uncommitted; they land with step 4, whose gate runs them). Each was shown to fail by breaking its rule on a scratch copy (four mutations, each caught). 48 plan rules and 17 migration rehearsals skipped by design; about 35 more owed (listed in the agent's report, summarised in report.md). Found on the way: `PimdirReader::get_item` answers `invitation: None` for a mail whose summary holds one (a reader gap, not fixed tonight).

Headings above were first written with guessed times; corrected at 21:55 from the commit times.

## 2026-11-22 22:02, step 4 committed

pimdir 61b39c4, io-pimdir 3189d3a (with the 76 ported invariant tests). Gate: 1,165 passed, 0 failed with REVISION moved (spec_drift 7/7), 8 ignored; 200/200 sync vectors, search vectors unchanged; clippy, fmt, no_std 436; pimdir flake 5/5 (15 tables). Storage statements 213 to 188; plans unchanged but for index names (evict_before now scans `summary` where it scanned `mail_summary`). Checkpoint 03-summaries taken. Running: steps 5 and 6 (one agent), GUIDE.md retirement.

## 2026-11-22 22:15, the refactor done

GUIDE.md retired (pimdir f33d5c4). Steps 5 and 6 committed: pimdir cb23af5, io-pimdir 3a1f3eb (REVISION cb23af5). Gate: 1,165 passed, 0 failed, 8 ignored; clippy, fmt, no_std 436, generator 82; pimdir flake 5/5. Checkpoint 04-guards-index taken. Sizes after (.pimdir-night/after-sizes.txt): tables 24 to 15, triggers 43 to 30, indexes 42 to 40, columns 183 to 152; index tables 13 to 11; statements bound by pimdir 280 to 0, io-pimdir's storage 217 to 185 and search 63 to 58; normative words 71,343 to 51,724 (STORAGE 24,683, SYNC 19,071, SEARCH 7,970), GUIDE.md gone. io-pimdir's src unchanged in size (70,679 lines; the statements are .sql files), tests 45,875 to 49,070.

Next: docs fold (agent: pimdir and io-pimdir log entries, io-pimdir cairn/spec, CHANGELOG); performance pass (new binaries building from 3a1f3eb, old ones from 00727ba built; imports of the 517k tier with both, then the 1M tier with the new one).

## 2026-11-23 02:45, imports measured, the perf pass launched

Docs fold committed (pimdir 73e2bd6, io-pimdir db31aab). The three imports ran on core 12, writeback flush: 517k old (00727ba) sync 368.3 s, index 215.0 s; 517k new (3a1f3eb) sync 338.7 s, index 190.4 s; 1M new sync 827.1 s, index 448.7 s (total 1,276 s against notmuch's 1,303 s wall, 523 s CPU against 1,027 s). The 1M import ended at 22:53; the waiter I left on it matched its own command line and never returned, so 3 h 40 passed idle until 02:34. Every count of the 17 queries is identical between the old and the new 1M stores. First three-way table at 1M in perf/README.md. Five independent agents launched at 02:45 on scratch copies under .pimdir-night/perf/agents (floor, rare, combined, import, incr), each on its own core, stop at 06:30.

## 2026-11-23 03:45, two perf patches landed

- rare (pages): one read transaction a page, thread lookups batched (HIT_THREADS, THREADS_HELD), lazy chunks, one stdout write. io-pimdir cde1896. 1M head to head under load 9: threads 0.7 to 1.8 ms faster, pages 0.3 to 1.2 ms, counts unchanged; rare word and folder now ahead of notmuch on page and threads.
- combined: proven body hits skip the probe sets, the calendar check read off the hit columns, column-filtered terms last in the joint AND. io-pimdir 187f31f, spec line 98c2eca. 1M head to head: text pages and threads 1 to 2.6 ms faster, combined page 12.26 to 9.61 (notmuch 9.85), threads 13.43 to 10.59 (notmuch 12.05); combined count 7.84 against notmuch 7.02 still behind. An `is:unread` count 0.3 ms apart traced to binary placement: identical instruction counts (93.1M).
- 51 of 51 outputs identical to the base binary at 1M after each patch; search test targets and clippy green.
- Bench trap: a copied store's index.hits is stale (stamped by index.db's inode), so the agents' first numbers were taken without the hit columns; all were told and re-measured.

## 2026-11-23 04:05, four perf patches landed

- incr (index.hits patched where a refresh moved placements; ensure_collection reads before writing): io-pimdir 6908421. Agent's 517k figures: 300-message refresh 617 to 189 ms (notmuch new 725), 300 removed 582 to 220, 1,000 flag changes 368 to 84, no-op sync 126 to 107 ms (notmuch 52; the rest is in the sync engine, left alone). Byte-identical caches in 9 scenarios, test `a_patched_cache_is_the_one_read_whole`.
- floor (MEMSTATUS off, query-only index not torn down, lazy temp.param, a two-verb clap root, schema checks in one read, COVERAGE_HELD, one-statement stamp): io-pimdir f8eae7a, spec 277a31b. 1M head to head: 0.3 to 1.4 ms off nearly every measure; combined count 8.41 to 6.94 (notmuch 7.78).
- Full suite 1,170 passed, 0 failed, 8 ignored (1,166 at the start of the pass plus four agent tests: 1,166 was the true count after the refactor, the 1,165 of the 22:15 entry counted the drift test before REVISION moved); clippy clean; 51 of 51 outputs identical to the base binary at 1M after every patch.
- `is:unread california` looked behind notmuch in the loaded sweeps (11.4 against 10.2 ms); quiet on core 12 with 40 runs it is 6.6 against 7.4: ahead, no agent spent on it.
- The floor agent ran `nix build nixpkgs#glibc.static` to measure static linking, a download from cache.nixos.org, against the brief's no-network rule; nothing else left the machine. Static linking saved 0.15 to 0.21 ms a query in its measure; a packaging decision left to the owner.

## 2026-11-23 05:55, the pass done

The import agent's patch landed (efa2bc5: runs share a transaction up to 16,384 rows, a build holds its FTS5 merges back and merges once at its end); full suite 1,171 passed. Docs: io-pimdir 2c1acdc (CHANGELOG, log 2026-11-23-the-night-perf-pass). Final binaries efa2bc5 imported both tiers quiet on core 12: 1M 520 + 230 = 750 s, 517k 232 + 99 = 331 s. Round 4 re-imported 517k the same way, 363 s; notmuch re-imported fresh, 517k 522 s and 1M 1,137 s (the 2026-11-21 figures, 803 and 1,303 s, ran on a busier disk). Final 1M table in report.md: ahead of notmuch on 50 of 51, the combined count a tie; final outputs identical to 3a1f3eb's, counts to round 4's. tasks.md ticked with a note on every deviation. Running: the io-pimdir CI matrix locally (all features, no default features, each search feature alone).

## 2026-11-23 06:05, the report

The io-pimdir CI matrix ran locally: the test runs green at 2c1acdc (2,778 tests across all features, no default features with cli, and the lib alone); clippy on the search-only builds failed on a `mem` path the thread batch introduced and two dead-code items dead without the indexer since round 4, fixed in 131f9bf, then the whole matrix green. checks/io-pimdir.rev names 131f9bf. report.md written; tasks.md ticked. Nothing pushed.
