---
cairn: tasks
change: what-must-hold-and-what-is-used
---

# Tasks

Files named below live in this folder unless a path says otherwise. Sub-agents stay read-only on git and write nothing outside their scratch area: each returns its rows as text, the lead writes the files.

## 0. Before anything runs

- [ ] D1 to D5 ruled on by the owner
- [ ] The commits read are written at the top of both ledgers (pimdir b5b9382, io-pimdir 00727ba, and each consumer's)
- [ ] The Android session told which commit is read, and that nothing is written there

## 1. The invariant ledger

- [ ] The row format fixed in rows/README.md: source, rule, kind (P or M), parent, origin (`wild`, `audit`, `perf`, `design`), features, witnesses; one TSV file per source family
- [ ] The P or M test written with ten worked examples, five of each kind, taken from existing log entries
- [ ] The feature vocabulary fixed (the 30 to 40 names of proposal.md's feature table), shared with section 3
- [ ] seed.md: the primary invariants read top-down from OVERVIEW.md, the generator's oracle, the loss classes of neverest's and the Android app's logs, and the merge principles
- [ ] Owner sitting 1: seed.md read, corrected, agreed
- [ ] rows/pimdir-log.tsv: the 215 entries of cairn/log, in date order
- [ ] rows/io-pimdir-log.tsv: the 226 entries of io-pimdir cairn/log, in date order
- [ ] rows/sync-vectors.tsv: the 200 files of vectors/sync/, each with whether its starting store is reachable by a history
- [ ] rows/search-vectors.tsv: the cases of vectors/search/
- [ ] rows/invariants-sh.tsv: the scenarios of checks/invariants.sh
- [ ] rows/wild.tsv: the entries of neverest's and the Android app's logs recording a loss or a wrong answer, and the classes the live testing campaign of 2026-11-15 found
- [ ] The open lines of every tasks.md under cairn/changes/ of both repositories read: one still open is a row with no witness
- [ ] Consolidation: proposed parents merged, each new P either kept or folded into a seed; invariants.md written
- [ ] check.py: every log entry and vector appears in a row, every source exists, every M has a parent or is an orphan, every P has a witness or says none; run through `nix-shell -p python3`
- [ ] Saturation stated: how many P the second half of the rows proposed, and how many were kept
- [ ] Owner sitting 2: invariants.md read; the `audit`-only invariants and the orphans ruled on, one line each

## 2. The usage ledger

- [ ] tools/touches.py: every statement of queries/ and of io-pimdir's `sql::OWN` and `sql::search` prepared under the authorizer; usage/touches.tsv (statement, table, column, read or write)
- [ ] usage/columns.tsv from it: each column of the 37 tables with the statements reading it and writing it; the columns nothing reads listed apart
- [ ] The scratch tree: `git archive` snapshots of io-pimdir and of each counted consumer under the session's scratch area, built off-tree, one build at a time
- [ ] The trace hook in the scratch io-pimdir: rusqlite's `trace` feature, a hook at each connection open, one line per statement (name, nanoseconds) and per trigger fired, to the file `PIMDIR_TRACE` names; a run with the variable unset proves the suites still pass unchanged
- [ ] tools/fold.py: trace files folded into counts and total time per statement and per trigger, per run
- [ ] `exercised`: the offline suites of himalaya, neverest, cardamum, calendula and carillon run against the scratch io-pimdir; one trace per consumer
- [ ] The day scripts under tools/days/, one per consumer, each a shell script whose steps are listed in its header
- [ ] `hot`, readers: himalaya, cardamum and calendula days on a generated store (count profile) and himalaya's on the bench store
- [ ] `hot`, owner: neverest's day against maddy on loopback (first sync, nothing to do, a delta, a drain)
- [ ] Android, `reachable`: the names bound by `PimdirSql.bind` under android/app/src/main, and any statement text of its own
- [ ] Android, `exercised`: `StoreProfile` over its host tests, if they run on this machine without a device; else noted as not measured
- [ ] usage/statements.tsv: one row per statement, columns reachable, exercised and hot per consumer, counts and time
- [ ] usage/triggers.tsv: the same for the 43 triggers
- [ ] usage/api.tsv: io-pimdir's public items against each consumer's sources, unfog and journal marked as intent
- [ ] Coverage of io-pimdir's functions under the same runs, half a day at most; usage/functions.tsv, or a line saying why it was dropped
- [ ] What was not covered, stated at the top of usage/README.md: the paths only a live server takes, the phone, the consumers left out

## 3. The feature table

- [ ] The maps written by hand, each a small TSV: table to feature, spec section to feature, io-pimdir module (or function, for src/sync.rs, src/hub.rs and src/client.rs) to feature
- [ ] tools/features.py: cost per feature (tables, columns, triggers, indexes, statements, words, lines, vectors, tests) from the maps, usage/touches.tsv and the rows
- [ ] The value columns joined: primary invariants and their origins, consumers by level, share of traced time
- [ ] features.md, with its three lists: reached by no consumer, carrying only `audit` invariants, cost out of proportion
- [ ] A log entry in cairn/log when the three files are read by the owner; this change then closes, and the next (the normative boundary, the budgets) opens from features.md

## Order and stop rules

Sections 1 and 2 share nothing but the feature vocabulary and run side by side once it is fixed. Section 3 waits for both.

- The seed list is agreed before any bottom-up row is written.
- More than 60 primary invariants: the consolidation is run again with the test tightened, not accepted.
- A measurement the tooling refuses for more than half a day (coverage, the Android host run) is dropped and named in usage/README.md.
- No row, trace or table proposes a change: a defect noticed on the way is one line in the tasks.md of the change that owns it, and the inventory goes on.
