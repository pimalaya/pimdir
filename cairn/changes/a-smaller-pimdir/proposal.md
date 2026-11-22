---
cairn: change
id: a-smaller-pimdir
status: draft
created: 2026-11-22
---

# A smaller pimdir

## Why

The standard and its reference implementation grew one finding at a time: 71,343 normative words, 37 tables, 43 triggers and 280 named statements after 16 drafts in under four months. The owner judges it too much (2026-11-22) and wants, after one unattended night, a redrawn pimdir: shorter, as fast or faster, costing Neverest, Himalaya, Cardamum, Calendula and the Android app as few regressions as possible. The owner's rulings that day:

- the night may redesign, and works in pimdir and io-pimdir themselves, on their main line, no fork and no branch;
- the standard stops listing statements: the tables and their columns are the contract;
- the least structure that does the job, as dense and efficient as it can be;
- most of the work goes to storage and search; sync is complex by nature and is handled with care.

design.md holds the target and the readings behind it, tasks.md the night step by step. This document says what the night commits to.

## What the morning holds

| | Before | Target |
| --- | --- | --- |
| Normative words (STORAGE, SYNC, SEARCH) | 71,343 | at most 45,000 |
| Informative guide | 19,844 words | retired |
| Statements the standard binds | 280 | 0 |
| Store tables | 24 | 15 |
| Store triggers | 43 | about 29 |
| Index tables the standard binds | 13 | 0 (io-pimdir keeps 10) |
| io-pimdir's statement files | 280 | about 225 |
| Bench against notmuch, 1M messages | ahead on 14 of 17 | held through the refactor, then a performance pass: ahead of round 4 and of notmuch on every measure it can reach, the exact table reported |

Three moves carry it (design.md §3 to §5):

1. **The contract narrows.** The statements, the index schema, the generator and the checks that bound them leave the standard for io-pimdir. STORAGE.md describes rows and rules; SEARCH.md keeps the query language and what an answer states.
2. **The store merges its shapes.** Flags become two columns in place of two tables. Six summary tables become one, three list tables become one.
3. **The index drops what nothing reads** (`chunk`, `thread`, seven statements) and follows the store's new tables.

## What the night does not touch

The sync engine (src/sync.rs, src/hub.rs, src/mutate.rs, src/rekey.rs, src/upgrade.rs and the types of its seam) and the 200 sync vectors: not a line. A move that would need one stops and is listed. Also untouched: the blob store, the payload schemas, the query language, the reference counts, the public names the consumers use.

## What the morning does not hold

Said before the night rather than found after it:

- **io-pimdir stays about as large.** Its 70,644 lines are the engine (about 16,000), search (about 15,000), the operator CLI (about 8,000) and the store layer (about 12,000). Only the last shrinks tonight, by a few thousand lines at most. The standard is what gets visibly smaller.
- **A store of today is refused**, as every draft refuses another (storage-draft-17).
- **The Android app is not ported.** Its Java store layer follows the tables and columns (a rewrite of 3,500 to 5,000 lines by the reading of 2026-11-22). It keeps running on io-pimdir 0.19.1; the night leaves it the map of what moved.
- **The CLIs are not ported** (owner, at the start of the night): pimdir and io-pimdir, its `pimdir` CLI included, are the night's scope. Each consumer gets the list of what it names that moved.
- **The documents are rewritten unread.** The owner reads the ledger of dropped and moved requirements, and the three parts keep their draft status.
- **Performance is held, not promised.** The gains expected are on writes (12 triggers and two tables fewer under every flag change, one table under every summary) and on size; they are measured, and reported whatever they are.

## Owner decisions

Confirmed on 2026-11-22 at 21:14 ("GO"), with these rulings given at the start of the night, which win over the lines below where they differ:

- **Nothing blocks.** The night decides and reports: every decision a doubt asked for goes to decisions.md here (what, why, how to undo).
- **Commits unsigned** (`git -c commit.gpgsign=false`), no push.
- **Scope**: pimdir and io-pimdir, the `pimdir` CLI included. No consumer is ported.
- **Performance**: held through the refactor; then a pass by independent agents, each gain measured head to head by the lead. The bar is the old implementation and notmuch.
- **Clock** (the lead's, accepted): the refactor stops at 04:30 at the latest, the performance pass runs from about 05:15 to 08:30, the report is due at 09:00.
- **The sync engine** stays the one guarded zone: a change there is allowed only if it is minimal and the 200 sync vectors and the engine tests pass unmodified; otherwise the move is rolled back.

The decisions as written before the start:

- **D1, commits.** Commits on the main line of pimdir and io-pimdir for this night, one per green checkpoint, conventional messages, no attribution trailer, no push, no tag. Needed: io-pimdir's tests/spec_drift.rs compares its spec/ with pimdir at a commit, and an unattended redesign with no history is not recoverable. The first commit is made while the owner is still there, so a signing prompt shows then and not at 03:00. Rollback never goes through git: each checkpoint is also a plain copy of both trees under ~/code/pimalaya/.pimdir-night/.
- **D2, flags as a column** (design.md §3.1). A sorted, space-joined text in place of one row per flag. It is a list in a column, which the owner ruled out for JSON on 2026-10-30; it needs no function to read and is what every read answers today. Default: yes.
- **D3, one summary table** (§3.2, §3.3). Thirty-one columns, about twenty empty on a mail row. It is the costliest move for the Android app. Default: yes.
- **D4, triggers stay for the stamps and the marks** (§3.4). The writer-drawn alternative is measured, not built. Default: yes.
- **D5, what leaves pimdir**: queries/, the index schema, the generator (reversing D1 of the-freeze-plan, agreed 2026-11-20), checks/invariants.sh after its scenarios are mapped, GUIDE.md. Default: yes.
- **D6, the Android app left on 0.19.1**, with the map. Default: yes.
- **D7, no real account.** Loopback and generated stores only; the live suites stay ignored. Default: yes.
- **D8, the clock.** No storage move starts after 03:30, no search move after 04:30, the trees freeze at 05:00 for the consumers, the bench and the report, due at 07:00. Default: these hours.
- **D9, the bench tier.** The 1M store is rebuilt once at the end (about 40 minutes of machine time), compared with the store and binary of round 4. Default: yes, the 517k tier if the clock is short.
- **D10, the other session** (pimalaya-c1, idle): told at the start that both trees are worked in place tonight. Default: yes.

## Rules of the night

- No real account, no push, no tag, no publication, no version bump.
- Writes only in pimdir, io-pimdir, ~/code/pimalaya/.pimdir-night/ and the session's scratchpad. No consumer checkout and no file of the Android app is touched.
- Sub-agents never run a git write and print no secret; the lead alone commits.
- One measuring run at a time, on an idle core, with no build running.
- Production code of a kept behaviour is never changed to make a test pass; a test is changed only where the structure it named changed.
- A doubt on the design is decided, on the conservative side where there is one, and written to decisions.md.
- A move not green within one and a half times its budget is rolled back from its checkpoint and listed.
- journal.md here is appended at every checkpoint: the step, what passed, what was deleted, what is next. A session cut short, or one whose context was summarised, resumes from it.

## After

The log entries of both repositories, io-pimdir's cairn/spec folded, and report.md here. The next changes read it: the integer keys, the writer-drawn stamps, the Android port, and whether the-freeze-plan resumes on storage-draft-17. what-must-hold-and-what-is-used stays open for its invariant ledger, which the night does not build.
