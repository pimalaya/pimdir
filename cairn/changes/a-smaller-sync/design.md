# A smaller sync: the target

Read on 2026-11-23 at pimdir e75e397 and io-pimdir 131f9bf, twice. The first reading took the engine whole, SYNC.md whole, the five consumers for what they name, and a profile of the no-op sync on the 517k Enron store. The second took, line by line, the code each proposed move touches, the document paragraph by paragraph, and what a differential oracle can and cannot be built from. The second corrected the first in several places; each correction is marked. moves.md holds the changes one by one.

## 1. What the readings say

### 1.1 The engine

| File | Code / inline test lines | Job |
| --- | --- | --- |
| src/sync.rs | 3,077 / 3,578 | `PimdirSync`, one source and one collection: choose the listing, take pages, name members, merge, push, commit events |
| src/client/write.rs | 2,869 / 138 | the store seam: `load`, `write`/`apply`, `read_hub`, `save_hub_diff`, `mint_other_messages`, summary rows |
| src/hub.rs | 1,088 / 1,554 | `project_with` (rows to placements), `absorb` (placements to rows), `PimdirHubItem::reconcile` (the collection policy) |
| src/mutate.rs | 1,003 / 1,528 | the seven mutations |
| src/upgrade.rs | 914 / 1,198 | `Meta`/`Full` fetch, linking, a conflict's body, `settle` |
| src/rekey.rs | 755 / 1,059 | a collection onto a new handle space, by link id |
| src/remote.rs, change.rs, placement.rs, collection.rs, coroutine.rs, load.rs, join.rs, run.rs, open.rs | 2,765 / 400 | the seam types, the FNV key, the 15 write ops, the join walk, the yield loop |

About 12,500 lines of code, 9,450 of inline tests, and 9,144 more under tests/engine (108 tests, 15 property tests). tests/vectors_sync.rs runs the 200 vectors through the real store, none pending. No compatibility shim: another draft's store is refused.

Where the first reading saw the weight, and what the second found there (file:line at 131f9bf):

1. **A status the write mostly ignores.** The write reads `Tombstone` (hub.rs:736) and `status != Conflict` (hub.rs:186); `Clean`, `Dirty` and `Created` are derived again at projection (hub.rs:551-566). *Corrected:* the engine reads those three itself on placements it has rewritten in the same run (sync.rs:2250, 2060, 1247), so not maintaining them changes which upserts a batch holds. Same rows, other batches (moves.md K2).
2. **Landing a pending create, twice.** sync.rs:1317-1460 and upgrade.rs:550-658. *Corrected:* under different rules on seven points (which key lands, delivered creates, the another-message test, offered copies, base flags, a diverging body, tombstones). One function for both is a rule change (moves.md K1).
3. **The conflict-policy table, twice in the engine** (sync `resolve_conflict`, upgrade `settle`), and the hub's `reconcile` for the collection policy, another axis. The decision is the same in both; the effects differ (moves.md T2).
4. **Rekey has its own merge.** *Corrected:* `carry` (rekey.rs:429-553) is not sync's merge with small differences: 14 of the 22 cases compared write another placement, and nine behaviours are a rekey's alone, untested (moves.md K3).
5. **The another-message rule in four places**: sync `name`/`take_pending_create`, the write's `mint_other_messages` (on purpose, SYNC §10), mutate's Add/Copy, upgrade's `agrees`. Each compares other things; none is a copy to remove tonight.
6. **The drain beside mutate.** *Corrected:* producer.rs:1925-1993 cannot use mutate's Add (a queued add may hold no body), 2052-2075 is no duplicate (it chooses a source, which mutate cannot), and 2187-2215 hands mutate another load than `store.mutate` does, with another key as a result in one case (moves.md K4).
7. **Small duplicates**: `is_mutable` (sync.rs:2888, upgrade.rs:874), `store_body`/`stored_body`, the re-staging of a body in sync and rekey. *Corrected:* rekey's `Resolved` map is not a copy of `self.items` (first item, last meta, on a repeated handle).
8. **A round's last page loads the whole collection** (sync.rs `LastPage`, write.rs:105). *Corrected:* the whole set serves ten uses, and five of them have no other answer in the wire as it is (moves.md W1). Pages before the last load twice, `Handles` then `Links`, which one wire selection cannot merge (W2).

### 1.2 The consumers

- **Only neverest and the Android app drive the engine.** himalaya, cardamum and calendula read and enqueue; they name write ops (`OpenRound`, `CloseRound`, `SetCheckpoint`, `RefusePlacement`) in test fixtures only, and calendula one `service(PimdirYield::WantsWrite)` in a test.
- **neverest** names 83 sync-side identifiers: the yield loop (src/sync/mod.rs:156-245, matching `PimdirListing::Round`/`Head` itself), the `PimdirSync`, `PimdirRekey` and `PimdirUpgrade` builders, `mutate` with `Edit { overrule: true }`, reports, events, `PimdirParked`, `PimdirWaitReason`, a `PimdirWriteOp::UpsertPlacement` it writes itself (driver/relay.rs:233), `store.load` called directly (driver/spine.rs:215, 548), and `LOAD_CHECKPOINT`/`UPSERT_CHECKPOINT` run on its own connection (storage.rs:149-180). It runs several stores in threads. It runs rekey, on `Renumbered` (driver/reconcile.rs:69-83); the Android app does not. 134 driver tests and about 270 more sync tests assert reports and rows: an external oracle.
- **The Android app** drives the coroutines in Rust (offline.rs) and serves load and write in Java: PimdirStorage.java (3,258 lines) re-implements write.rs, rust/src/offline/wire.rs mirrors all 15 write ops, the five load selections and every `PimdirLoaded` field as JSON, and merge.rs calls `PimdirHubItem::reconcile` and the hub's verdict types. Its `loadCollection` (177-267) answers `unstamped` to `lastPage` only. SyncVectorsTest runs the 200 vectors (161 bound, 39 unbound). Any change to a yield, a write op, a loaded field or round, stamp and refusal semantics costs it Rust, Java and vector-list edits.
- Every consumer pins storage-draft-15; moving to the tree already costs the storage-draft-17 port of a-smaller-pimdir.

So the seam is a contract in practice, whatever the standard says of it: tonight keeps it byte for byte.

### 1.3 The document

19,071 words: preamble 296, §1 173, §2 945, §3 663, §4 3,519, §5 5,330, §6 2,057, §7 1,699, §8 885, §9 1,243, §10 832, §11 1,225, §12 169. 110 MUST, 23 MUST NOT, 7 SHOULD, 16 MAY, about 775 sentences, and every unmarked statement binds as MUST (its preamble). Text marked informative is small: 204 words of *Note:*, about 740 in parentheses, 77 "so", "since" or "because". Most reasons are clauses inside a rule's own sentence.

One rule, many places. Seventeen families were inventoried; the heaviest:

| Family | Stated in | Owner |
| --- | --- | --- |
| A delivered create | §2, §3 (twice), §4 (four paragraphs), §5 (nine), §6 (four), §7 (three), §8, §10, §11 | §5 (waits, held, reported), §4 for what records it, §6 for landing, §7 for mutations on it |
| No body pushed over, or chosen against, a body nobody has read | §3, §5 (four), §6 (seven), §7 (four), §9 (three) | §5 for the source's axis, §9 for the item's |
| A refusal | §2, §4, §5 (five), §9, §10 (twice), §11, §12 | §5, §4 for the connector's classification |
| What a listing's absence proves | §4 (five), §5 (ten), §8 (three), §9, §10 | §5, as a table |
| Heads | §2, §4 (eight), §5 (twelve), §10, §11 | §4 for the connector, §5 for the engine |
| The conflict policies | §4, §5 (six), §6 (five), §7, §8, §9 | §5 for the source's, §9 for the collection's |
| The absence guards | §5 (five), §8 (three), §10 | §5; §8 keeps what differs for a rekey |
| Which write op a verb emits | inline in §4 to §8, again in §10 in one 235-word paragraph | the rule's own section; §10 holds the table |

A restatement is rarely an exact copy: most carry one clause the owner paragraph lacks (that a delivered create is never an origin, that a rekeyed handle loses its refusal, that only §10 says `OpenRound` comes first in its batch). Those clauses are where a merge loses a requirement, and the ledger has a column for them (§5).

**References pin the outline.** 345 references in pimdir (208 in vector notes, 197 of the 200 files; 78 in STORAGE.md; 33 in checks/vectors.py) and 719 in io-pimdir cite SYNC sections, §5 alone 391 times. None cites below a section: no subsection number, no anchor, no quoted sentence. Vector files may not change tonight, so §1 to §12 keep their numbers and topics, and a rule moved to its owner leaves a one-line pointer in the section that held it, or a vector's note would cite a section saying nothing of it.

**What is machine-checked.** checks/references.pl: every `§n` names a numbered heading and the Contents anchors match the heading slugs (a bare `§5` right after `STORAGE §10,` is read as STORAGE's and passes silently; it must run on a copy of the tracked files, the untracked .claude/worktrees breaking it on the working tree). checks/vectors.py reads SYNC.md only for backticked payload shapes starting `{ "v":`, of which there are none, and recomputes §4's change key by its own code. checks/tags.sh parses the Status line. Nothing checks a sentence or counts a key word. About 40 of the 102 bold paragraph lead-ins are echoed in checks/vectors.py comments and io-pimdir's cairn/spec headings: they stay verbatim.

### 1.4 The no-op sync

Profiled on 2026-11-23 on a copy of the 517k store (3,312 folders; the 107 ms of the perf pass came from another store and corpus): `pimbench sync` with nothing to do takes 86.9 ms (65.3 user, 21.2 sys) against notmuch new's 50.2 ms (23.0, 30.5), one hyperfine run on core 14. The report of a-smaller-pimdir said the rest was in the sync engine; that was wrong:

| Part | ms | Owner |
| --- | --- | --- |
| process start and exit | 1.1 | |
| folder walk (3,486 opendir, 3,465 statx) | 10.3 | pimbench's Maildir harness |
| store open, mtimes load, close | 1.7 | harness and store |
| delta check (stat of cur/ and new/, every folder unchanged) | 4.0 | harness |
| settle and mtimes rewrite | 1.0 | harness |
| `ensure_collection` per folder (`LOAD_KIND`, `lock.verify()` 2 statx) | 6.0 | store layer, called by the harness every run |
| `prepare_sync` → `collection_sources` (recursive CTE, about 4 µs a folder) | 13.4 | store layer (reader.rs, run.rs) |
| load 1, `Handles([])`: meta, checkpoint, round, refusals | 11 | store layer (write.rs) |
| load 2, `Owing([])`: meta, owing, lacking, `read_hub` of no link (7 statements), checkpoint, round, superseded twice, refusals again | 39.5 | store layer (write.rs) |
| the engine's `resume`, 4 a folder | 1.3 | src/sync.rs |

Per folder: 21 cached statements and two BEGIN and COMMIT pairs, about 9 single-row reads, no binding or item row, every statement a seek; flat with the folder's size (23.4 µs at 1 to 10 bindings, 24.5 µs at 1,001 to 11,896). Within the store's share, SQLite executing is 52%, rusqlite's statement cache 15% (it hashes and compares each statement's full text, comment header included), transaction begin and end 7%, BEGIN and COMMIT parsed through `execute_batch` 3.4%. Nothing is written: no `WantsWrite`, no WAL frame, no fsync.

notmuch new is O(directories) too (5,098 directories read, about 15 µs each), and imports only: it never asks whether anything local is owed a push. What pimbench adds is a whole engine round trip per folder after its source said nothing moved. A store-wide query of the collections owing anything for a source took 0.2 ms warm and 1 ms cold, written by hand with sqlite3.

neverest and the Android app do not call `prepare_sync` (they build `PimdirSync` themselves), and their no-op is a network round trip. The figure above is the bench's.

Measures and probes: .pimdir-night/perf/agents/noop (h-noop.json, h-parts.json, trace3.txt, per.tsv, the probe crate).

## 2. The boundary

| | Free tonight | Frozen tonight |
| --- | --- | --- |
| Engine internals (sync.rs, hub.rs, mutate.rs, upgrade.rs, rekey.rs, join.rs, private items) | where every yield stays the same (L0, moves.md §0) | every yield but `WantsLoad`, by its `Debug` text |
| write.rs `load`: which statements it runs | yes | what `PimdirLoaded` holds for each selection (neverest calls `load` itself) |
| `PimdirYield`, `PimdirArg`, `PimdirWriteOp`, `PimdirLoaded`, `PimdirLoadSelection`, hub `absorb`/`reconcile`, events, reports, builders, `PimdirRemote` and its types, the `sql::*` constants | additions only (T4's read) | yes |
| What a run pushes, writes, reports, enumerates, fetches, and the rows it leaves | | yes |
| SYNC.md words | yes, through the ledger | §1 to §12 numbers and topics, the bold lead-ins, every requirement |
| vectors/sync/, vectors/schema/sync.schema.json, checks/vectors.py's rules | | yes |
| Store schema | one index, only if T4's read measures over 1 ms at 1M | everything else |
| producer.rs | | yes |

## 3. The changes

moves.md, one by one. In short:

- **Land tonight (L0):** T1 small duplicates, T2 one policy verdict, T3 the no-op's fixed cost, T4 the collections a run may skip, T5 SYNC.md.
- **Measured tonight on scratch copies, never landed:** K1 one landing, K2 the status derived, K3 nine rekey behaviours reproduced, K4 the drain against `store.mutate`.
- **Listed with what each needs:** W1 to W3 (wire), C1 to C7 (rules).

## 4. The differential oracle

A crate under .pimdir-night/sync-diff (D), not committed, kept after the night.

### 4.1 The build

- `D/old`: io-pimdir 131f9bf from `git archive` (it carries spec/, which build.rs bakes), the first `name =` of its Cargo.toml changed to `io-pimdir-old`. Probed on 2026-11-23 with `cargo metadata --offline` and io-pimdir's Cargo.lock copied in: the two packages resolve, one rusqlite and one libsqlite3-sys in the graph, lib targets `io_pimdir` and `io_pimdir_old`. Compilation was not run.
- The manifest: `pimdir_old = { package = "io-pimdir-old", path = "old" }`, `pimdir_new = { package = "io-pimdir", path = "<the tree>" }`, an empty `[workspace]` excluding old, a release profile with `panic = "unwind"`, no LTO, `debug-assertions = true`.
- Neither dependency is named `io_pimdir`, so one file, side.rs, is `include!`-ed in two modules, each opening with `use pimdir_old as pimdir;` or `use pimdir_new as pimdir;`. No engine type crosses between the two sides: the server model and the scenario are plain types of the oracle's own, with a thin adapter per side.
- The build's target directory is on disk under D; the stores of the scenarios are on the tmpfs (`TMPDIR`), since a store opens WAL with `synchronous = FULL` and would fsync every commit on disk.
- Each side creates and seeds its own store: if T4 adds an index, one side's store is refused by the other's schema check.

### 4.2 What is compared

A driver steps each side through its own loads to its next yield that is not a load, then compares. One scenario gives:

- **Strict, the gate of a move.** After each resume: the `Debug` text of the yield (`WantsWrite`, `WantsEnumerate`, `WantsFetch`, `WantsPush`, `WantsLookupObject`, `WantsVerify`), and of the args each side's store answers (`Written`, `LookupObject`, `Verified`), which are not the same by construction. After each run: the report, and every row of every store table.
- **The load battery, after each run.** `store.load` on both sides for `All`, `Handles` of every handle, `Links` of every link id, `Owing([])` and `LastPage`, `Debug` compared. Skipping `WantsLoad` in the strict comparison leaves "what a selection answers" unchecked, and T3 edits `load`.
- **Relaxed, for the candidates of moves.md §3 only.** Per run: the concatenated write ops, pushes, fetches, enumerates, the report and the rows. It tells a batch cut in two from a row that moved.

Rows are read from sqlite_schema, table by table, joined to natural keys (objects by hash, items by collection and link id, bindings by collection, source and handle), `seq` and `changed` compared strictly since they are public and follow the write's insert order.

Masked, each for a reason read in the code:

| What | Where | Mask |
| --- | --- | --- |
| a band head's `since` | `PimdirHead::Band { since: round.started_at }` (sync.rs:629-631), an SQLite instant inside a compared `WantsEnumerate` | present or absent; the server model never branches on its value |
| `round.started_at`, `coverage.at` in a loaded answer | collection.rs:214, 226 | present or absent |
| row instants | sources.covered_at and round_started_at, items.retained_at, bindings.refused_at, item_reference.created_at, queue.created_at, receipts.applied_at, store_meta.created_at | present or absent |
| store_meta.store_id | `randomblob(16)` | dropped |
| row ids | objects.id, items.id | replaced by natural keys |
| temp and quarantine file names | pid, counter, nanoseconds (blobs.rs:1333-1342) | quarantine by count, objects/ by name |
| an error text carrying the store's path | | the directory replaced |

The engine holds no clock, no RNG and no `HashMap` in what it prints; the one `HashMap` of the store (write.rs:2613) orders statements only. The old-against-old run is the guard for whatever this table misses.

### 4.3 The scenarios

- **The 200 vectors.** The runner is tests/vectors_sync.rs copied (it cannot be included twice: inner attributes and one extern crate name), its first ten lines, its `pending` module and its expectations removed, the spec directory hardcoded. It uses public API only. 3.5 s for the 200 in a debug build.
- **Generated histories.** Nothing existing can be reused whole: the generator under io-pimdir spec/generator writes twelve fixed histories whose seed draws only the surface, its remote does not apply a push (its engine model predicts them), and `MemRemote` of tests/engine answers one page always and cannot disagree on a summary under one link id. So the oracle has its own server model, on plain types, that applies a `PimdirChange` itself:
  - listing: pages with a cursor, delta from a checkpoint with stated removals, delta heads and band heads, a cap, narrowed with and without `enumerated`, a rejected cursor, a dropped cursor;
  - members: revisions (mutable kinds), bodies carried inline and `Persisted`, a renumbering, two members under one hint, a hint reused by another message (another subject, date or sender), server object ids;
  - outcomes: accepted with a handle, accepted without, rejected, refused, unreported;
  - steps, 1 to 30 a scenario, over two or three sources on one collection: a sync (round of 1 to 4 pages, delta, forced round, scope widened), a server-side change, one of the seven mutations, an upgrade at each tier, a rekey, a cut (the coroutine dropped before or after its k-th `WantsWrite`, the store reopened, the verb run again);
  - shapes that are never reached unless forced, each given a share of the scenarios: 18 to 22 based members with half of them deleted then a forced round (the park threshold), more than 64 pushes in a run, two creates of one source under one hint, a tombstone holding an edit, each of the four policies with content pushes on and off.
- A seeded PCG, weights set by flags, a shrink that drops steps. A disagreement prints the seed, the step, and both sides.

### 4.4 Shown to fail

Before it gates anything, three bugs planted one at a time in a copy of the tree must each be caught, the seed and step count written to the journal:

| Plant | Line | Reached by |
| --- | --- | --- |
| a flag removal becomes a union | src/sync.rs:2242, `&base_flags` replaced by `&PimdirFlags::Unknown` | a based binding whose server drops a flag, then a sync listing it |
| the park threshold moved | src/sync.rs:289, `MASS_ABSENCE` 20 to 19 | a round's last page over exactly 19 based bindings, 10 or more absent, a member named, absences not accepted: the forced shape above |
| the minted key landed before the bare one | src/sync.rs:1326, the sort key negated | one source holding two creates for one hint, both agreeing with the member, then a page naming the hint |

### 4.5 What it does not see

- **The Android store.** Both sides run the Rust write.rs. A batch or a load sequence the Java serves differently is invisible. This is why the night lands L0 only.
- **A wrong load answered by a compensating write** when both change together; the battery compares loads, nothing compares a write alone on a foreign store.
- **The queue drain** (producer.rs is no coroutine), hostile answers (unsorted, repeated or ghost members: only tests/engine's `HostileRemote` has them, and it stays in the gate), a WAL torn inside a transaction (tests/generated/crash.rs stays in the gate), corrupt blobs and quarantine beyond the vectors' cases, non-mail kinds unless generated.
- **Sameness, not correctness.** A bug both sides share passes. Correctness is the vectors', the engine tests' and neverest's suite's.

### 4.6 Budget

About 150 minutes to build (first build 10, side.rs and the row dump 25, the vector runner 20, the server model and generator 50, old against old 10, the plants 20, old against the tree 10, slack 5). Estimated throughput 150 to 400 scenarios a second in release on 12 to 16 workers, unmeasured: 20,000 a gate in one to three minutes, 100,000 at the end in under fifteen. Measured on the first 1,000 before the budgets are trusted.

## 5. The document

### 5.1 The honest size

At most 14,000 words, from 19,071. The first plan said 12,000. The paragraph inventory puts dedup, tables, reasons and notes at 14,000 to 14,600; below that, rule-bearing sentences are compressed by a fifth, which is where meaning changes. Three levers reach lower, each the owner's (proposal.md D5):

| Lever | Words | Cost |
| --- | --- | --- |
| protocol examples of §4 and §5 moved to OVERVIEW.md | about 450 | a connector's author reads the mapping one document away |
| SYNC pointing at STORAGE §9, §10 and §14 where they state the same rule | 400 to 600 | each checked sentence by sentence; a ledger line `merged` into a STORAGE sentence |
| §11's field lists left to vectors/schema/sync.schema.json | 400 to 500 | normative text leaves the document for a schema |

Budget by section, at 14,000: preamble 250, §1 160, §2 780, §3 570, §4 2,480, §5 3,750, §6 1,500, §7 1,250, §8 700, §9 950, §10 550, §11 900, §12 160.

### 5.2 How it gets shorter

- Each family of §1.3 stated once, in the section owning it; every other section keeps a one-line pointer naming the rule and its owner, and the clause only it carried moves into the owner's sentence.
- Four tables, their shapes fixed before any rewriting:
  - **A, the source's policy by case** (§5): columns the four policies; rows the thirteen cases (remote changed with and without the body carried, both changed, a fold, an equal body, a conflict meeting a newer revision, a body read later by the upgrade, a tombstone and a remote edit, an arrival landing a create, content pushes forbidden, no body held).
  - **B, the collection's policy by case** (§9), apart from A: §9 owns that axis and 60 references cite it there.
  - **C, what a listing's absence proves** (§5): rows delta, each head, a page before the last, the last page of a whole-scope round, a band round, narrowed with and without `enumerated`, capped, interrupted, parked, rekey, capped rekey; columns stated removals, an in-scope dated member unlisted, an undated one, an out-of-scope one, a provisional create, the guard, whether it closes, what it reports.
  - **D, load and write by step** (§10): verb and step, the load, the ops in batch order, the order constraint, the section stating the rule. It replaces the 235-word paragraph and adds nothing: SYNC.md never names `UpsertPlacement` or `SetCheckpoint`, and a row for them states no rule.
- §4's nine page fields and §5's ten events as tables; §11's checks as bullets.
- Reasons kept only where a rule would read as arbitrary without one; the history they carry is in the log.

### 5.3 The ledger

rules.tsv here, one line per sentence of today's text:

- `old_id` (section, line, sentence), `old_section`, `incipit` (first eight words);
- `class`: rule, definition, pointer, reason, example, note, heading;
- `keyword`: MUST, MUST NOT, SHOULD, MAY, binds, none;
- `family`;
- `state`: kept, merged, tabled, or cut-informative (allowed for reason, example and note only);
- `new_section`, `new_anchor` (the lead-in or the table), `new_sentence` (number, or row and column), `new_incipit`;
- `stub`: the pointer left in the old section, required when the section changed;
- `nuance`: the clause of the target carrying what only this sentence said;
- `review`: ok, or a finding's id.

A script (tools/ledger.py here, run through `nix-shell -p python3`) fails when: a sentence of the base has no line; a rule or definition is cut; a target does not exist or does not begin with `new_incipit`; a key word changed level (binds is MUST); a moved rule has no stub naming its new section; a rule sentence of the new text is no line's target (something was added); a backticked identifier or a number of the old sentence is missing from its target without a `nuance`; a bold lead-in of the fixed list is gone; a section is over its budget. Then checks/references.pl on a copy of the tracked files.

### 5.4 The order

1. The lead, alone: the base frozen and split into sentences, the old columns filled, the owner map, the four table shapes, the lead-in list.
2. In parallel, self-contained: preamble, §1, §11, §12; in §4 the files, pages, fetch, outcomes and key paragraphs; in §7 `SetFlags` and `Add`.
3. The lead, alone, §5 in this order: absences and guards (table C), rounds and heads, the content axis and table A, deletes, moves and delivered creates, refusals, events.
4. In parallel once §5 is settled: the rest of §4, §6, §9 with table B. One agent owns the pair §6 "item conflict revisited" and §9 "a body not held", which state one rule from two ends.
5. In parallel after 4: the rest of §7, §8.
6. Last: §3 and §2, pruned to what the owners now say; then §10, whose table D copies final wording.
7. The ten sentences where every clause bears load, rewritten last and each reviewed alone: §4 on landing at a stated handle and on raw reads, §5 on resuming a round, on a local body over an unread base, on when both-changed is a conflict, on `PreferLocal`'s write before its push, on a refused offered create, §6 on landing rather than minting, §7 on a person's settle, §9 on when the source changed.
8. The adversarial read, by family, not by section: a fresh agent is given every old sentence of one family, the new text and the ledger, not the lead's view, and hunts for a requirement lost, weakened or changed. Each finding is fixed or answered in the ledger before the text lands.

Three wordings read as inconsistent today; they are carried unchanged and listed for the owner: §5 "no run drops it but the one landing it" against `Abandon`; §10 naming `PreferLocal` alone for the upgrade's `Overrule` where §6 says `PreferLocal` or `KeepLocal`; §7's trash advice, unmarked, which binds as written.

OVERVIEW.md follows where it paraphrases a moved sentence, vectors/README.md lines 55, 58 and 81 where they paraphrase §11, io-pimdir's cairn/spec/sync*.md for T2 and T4.

## 6. Listed for the owner, not done

moves.md §4 (W1 to W3, the wire) and §5 (C1 to C7, the rules), with what each needs. K1 to K4 bring the evidence the same night.

## 7. What gates a move

A move is done when all of these hold, then checkpointed and committed:

1. The differential oracle, strict comparison and load battery: the 200 vectors and 20,000 generated scenarios, no disagreement.
2. io-pimdir `cargo test --all-features`: no failure the base did not have; tests/engine, tests/vectors_sync.rs and the inline tests of the engine unchanged.
3. The 200 vector files unchanged (`git diff --stat` on pimdir/vectors empty) and passing.
4. neverest's suite on the scratch port, no failure its base did not have (when D4's port is green).
5. clippy `-D warnings`, `cargo fmt --check`, the no_std build (`cargo test --no-default-features --lib`).

T3 and T4 also run the no-op and the 300-message incremental at 517k against the base binary and notmuch new, head to head on one idle core.

## 8. The Android store, for later

The heaviest sync cost a change carries today is the Android app's second implementation of write.rs in Java and its JSON mirror of the wire. Serving its store from io-pimdir (the `client` feature in the release library, the Java store layer reduced to the provider bridges) would make the seam internal again: W1, W2, W3 and C7 of moves.md would then be ordinary refactorings under the oracle. A proposal of its own, in the Android repository, not tonight's.
