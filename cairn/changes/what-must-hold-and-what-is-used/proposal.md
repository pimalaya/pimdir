---
cairn: change
id: what-must-hold-and-what-is-used
status: draft
created: 2026-11-22
---

# What must hold and what is used

## Why

The standard and its reference implementation grew one finding at a time, and their size was never measured against what they are for. On 2026-11-22 (pimdir b5b9382, io-pimdir 00727ba):

- the three normative parts hold 71,343 words, the schema 37 tables, 43 triggers and 53 indexes, queries/ 280 statements (217 storage, 63 search), reached after 16 drafts in under four months;
- io-pimdir holds 70,644 lines under src/ (src/sync.rs alone 6,655) and 45,875 under tests/;
- the history behind them is 215 log entries here, 226 in io-pimdir, 200 sync vector files, and 147 change folders across the two repositories.

The owner judges this too much (2026-11-22) and wants a smaller base. Before deciding between pruning in place and rebuilding a kernel, two things are missing, and both are worth having whichever is chosen:

1. **What must hold.** The rules that protect a user's data are spread over the logs, the vectors and the change titles, mixed with rules that exist only because of how the current design is built. A new base that does not carry the first kind finds them again one audit at a time; one that carries the second kind is the same design.
2. **What is used.** Nothing says which statements, triggers, columns, public items and features a consumer reaches, how often, and at what cost. generator/scenarios.md reads the consumers one way (what each does); the reverse map (what nobody does) does not exist.

This change is an inventory, not an audit: it produces no finding, asks for no change to a normative part, and bumps no draft.

## What

Two ledgers and the table that joins them, all in this folder.

### 1. The invariant ledger

Every rule the history produced is sorted into one of two kinds by one test: **would the sentence still be true and testable on a store of another schema?**

- A **primary invariant** (P) is stated in terms a user, a source or a reader's answer can show: "an item missing from a listing is deleted only when the listing could have named it", "two copies declaring one identity are both kept and never take each other's body". It names no table, column, statement, key prefix, trigger, counter or profile.
- A **mechanism rule** (M) is a consequence of the current design: "a minted key already taken is minted again", "the refcount never goes below the pointers that name the object". Each M names the P it serves. An M serving no P is an orphan: either a P is missing from the list, or the rule protects nothing and is a candidate to go.

The target is 30 to 50 primary invariants. More than 60 means the test was applied loosely, and the consolidation is run again rather than the number accepted.

The pass is top-down first, so the bottom-up reading classifies against a frame instead of producing 400 sentences:

1. **Seed list**, written by hand from OVERVIEW.md, the generator's oracle properties (no loss, convergence, recovery from a crash at any step, queue order, a refreshed index equal to a rebuilt one), the loss classes found on real servers (neverest's and the Android app's logs name them: one identity held twice, a partial listing read as complete, a conflict hiding a server edit, a report saying success over a failed run) and the merge principles (three-way against a stored base, never a silent last writer).
2. **Rows**, one per source read: every log entry of pimdir and io-pimdir, every file under vectors/sync/, every case of vectors/search/, every scenario of checks/invariants.sh, and the entries of neverest's and the Android app's logs that record a loss or a wrong answer. A row holds: the source, the rule in one sentence, P or M, the parent P (a seed, or a proposed new one), the origin, the features it touches, and its witnesses (the vectors and checks that fail without it).
3. **Origin** is one of four words, and is the column the later decisions lean on most: `wild` (seen on a real server, a real corpus or a phone), `audit` (found by reading the spec or the code, never observed), `perf` (a measurement), `design` (a choice, no defect behind it).
4. **Consolidation** into invariants.md: each P with its sentence, the loss it prevents, its door (data, one-way, patchable), how many of its rows are `wild` and how many `audit`, its witnesses, how many mechanism rules and vectors hang on it, and whether its witnesses can be replayed on another design (a vector starting from a store state written row by row cannot; one reachable by a history of remote states and queued actions can).
5. **A check**, a script in this folder: every log entry and vector of the two repositories appears in a row, every row names an existing source, every M names an existing P or is listed as an orphan, every P has a witness or says it has none. The ledger is done when the script passes and the second half of the rows, read in date order, proposed no P the owner kept.

The count of mechanism rules and vectors per P is a result of its own: it prices each invariant in the current design.

### 2. The usage ledger

Usage is read at three levels, since a suite exercises rare paths on purpose and a path hit only there is not a path a user takes:

- **reachable**: a consumer's source names it;
- **exercised**: a consumer's own suite runs it;
- **hot**: a scripted day of use runs it, with its count and its time.

What is measured, each by the most mechanical means that answers it:

1. **What each statement touches.** Every canonical statement and every statement of io-pimdir's own is prepared against the canonical schema under SQLite's authorizer, which reports each table and column read or written. This gives, with no reading by hand, the columns no statement reads and the tables each statement binds together. Python's `sqlite3.set_authorizer`, on the prelude checks/signatures.py already builds.
2. **What runs.** A scratch copy of io-pimdir (a `git archive` snapshot, never the checkout) gains rusqlite's `trace` feature and a hook, installed where a connection opens (src/client.rs, src/client/producer.rs, the index), that appends one line per statement to the file an environment variable names: the statement's name, resolved from its text through `sql::all()`, and its time. Statement events also name each trigger that fires, so the 43 triggers are counted the same way. Scratch copies of the consumers are built against it through `[patch.crates-io]`. Nothing of this lands in io-pimdir.
3. **Under which runs.** The consumers' own offline suites (himalaya, neverest, cardamum, calendula, carillon) for `exercised`. For `hot`, a scripted day per consumer with no real account: himalaya, cardamum and calendula reading, searching, flagging, moving and editing on a generated store (the generator's count profile) and on the bench store of compared-with-notmuch; neverest against maddy on loopback, as its without_uidplus test starts it (a first sync, a run with nothing to do, a delta bringing new mail, a flag and a delete, a run draining queued actions).
4. **The Android app**, a second implementation in Java (9,389 lines under org/pimalaya/pimdir): the names its sources bind (`PimdirSql.bind`) for `reachable`, its own `StoreProfile` over its host tests for `exercised`. Read only; a phone trace is the owner's to record, and the app's session is told before its tree is read at a fixed commit.
5. **The public API.** io-pimdir's public items (rustdoc's JSON, or the listing task 6 of the-freeze-plan still owes) against each consumer's sources: one row per item, one column per consumer. The names are distinctive (`Pimdir…`), so a search by name is reliable for types; methods are attributed by the coverage run below, or left as unknown.
6. **The code.** io-pimdir's functions run by the same suites and days, by LLVM's source coverage restricted to its sources, time-boxed to half a day: if the toolchain refuses it, the statement trace and the API table stand without it.

Consumers count as evidence by how current they are: himalaya, neverest, cardamum, calendula, carillon and the Android app follow io-pimdir 0.19.1; unfog and journal are pinned at 0.8 and count as intent only (read, never run); alarmd (0.8) and linux (0.2) do not count.

### 3. The feature table

The two ledgers meet in one table, features.md, which is what the later steps decide from. A row is a feature or mechanism of the standard (about 30 to 40: the blob store, the summaries of each kind, several sources per item and its two agreement points, the conflict policies, scopes and coverage, rounds, pages and heads, rekey, the upgrade tiers, retention and its four ways out, each queued action and intent, performers, capabilities, receipts, supersessions, properties, references, attachments as files, the roles and their version levels, the change feed, the owing marks, and for search the text index, chunks, occurrences, threads, card facts, the coverage axes, the hit columns and each query form).

- **Cost**: tables, columns, triggers, indexes and statements (from the authorizer map), words of the normative parts (by section), lines of io-pimdir (by module, by function where src/sync.rs, src/hub.rs and src/client.rs mix several), vectors and tests.
- **Value**: the primary invariants it carries and their origins, the consumers that reach it, exercise it and run it hot, its share of the traced time.

The table states no verdict. It makes three lists fall out for the owner: features no consumer reaches, features whose invariants are all `audit`, and features whose cost is out of proportion to either.

## Owner decisions

- **D1, the tree while this runs.** The ledgers are read at pimdir b5b9382 and io-pimdir 00727ba. Recommended: the freeze (the-freeze-plan) and the notmuch rounds pause until the feature table is read, since a v1 tag makes today's size permanent and every landed round moves what is being measured. If they continue, the ledgers are extended by the log entries landed since, never re-read whole.
- **D2, which consumers count**, as listed above.
- **D3, the traced days.** Loopback and generated stores only (recommended), or the live test accounts as well, which needs the run grant.
- **D4, the Android lane.** Read only at a fixed commit, as stated above, or left out until its session can join.
- **D5, the review.** The seed list is read by the owner before the bottom-up pass starts, and the consolidated list after it: two sittings of a page each. The `audit`-only invariants and the orphans are ruled on line by line at the second.

## Out of scope

Any change to STORAGE.md, SYNC.md, SEARCH.md, the schema, a statement, a vector, io-pimdir or a consumer. Any verdict on what is cut, kept as a module or kept in a kernel. Where the normative boundary sits, the budgets, and the kernel itself: each reads the feature table and is a change of its own.
