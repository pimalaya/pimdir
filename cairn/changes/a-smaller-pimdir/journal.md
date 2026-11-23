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
