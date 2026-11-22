---
cairn: log
change: a-smaller-pimdir
landed: 2026-11-22
---

# A smaller pimdir, storage-draft-17 and search-draft-17

The night of 2026-11-22 to 2026-11-23 redrew the standard as cairn/changes/a-smaller-pimdir planned it, on the main line, unsigned and unpushed (owner's GO at 21:14). Its decisions are in that folder's decisions.md, its checkpoints in journal.md. Commits: 4250177 (the contract), 0f5e542 (flags), 0e5a9b8 (SEARCH.md), c7f424c (STORAGE.md), 7abd20f (SYNC.md and OVERVIEW.md), 61b39c4 (summaries), f33d5c4 (GUIDE.md), cb23af5 (the queue's foreign key).

## What moved

- **The contract narrows to the schema.** queries/ (217 storage and 63 search statements), queries/signatures.json, migrations/search/, generator/ and the checks binding them (checks/names.sh, checks/signatures.py, checks/waivers.txt, checks/invariants.sh) left for io-pimdir, which owns them (D5, reversing D1 of the-freeze-plan). The store schema's tables and columns are the contract; STORAGE.md describes rows and the rules on them and names no statement; SEARCH.md keeps the index file's rules, the query language and what an answer states, the index's tables, statements and refresh procedure being an implementation's own. vectors/search/refresh.json moves to `v` 6 and pins answers alone (its `objects` and `split` expectations were index internals).
- **Flags are columns** (STORAGE §4.3, §13). `placement_flag` and `binding_base_flag` go, with their twelve triggers: every flag but the five system flags is `items.keywords` or `bindings.base_keywords`, sorted bytewise and joined by one space, `''` for none, beside `marks` and `base_marks`. The owner sorts; the schema holds the shape (printable ASCII, no leading, trailing or doubled space) and an unknown set holds neither bits nor keywords.
- **One summary table and one value table** (STORAGE §4.3, Annex A). `mail_summary`, `contact_summary`, `event_summary`, `task_summary`, `journal_summary` and `file_summary` become `summary`, one row per item keyed by `items.id`, `component` naming its kind and a `CHECK` holding every column another component owns `NULL`. `item_address`, `mail_in_reply_to` and `task_category` become `summary_value(item, role, position, value, name)`, one index `summary_value_by_value` serving the person and the reply axes.
- **The queue keeps its collection by a foreign key** (STORAGE §14, §15): `queue.collection` is `ON DELETE RESTRICT` in place of the `collections_keep_queued` trigger; the owner asks before the delete to refuse it typed. `store_meta_identity` stays (decisions.md, 21:32).
- **The documents.** STORAGE.md and SEARCH.md rewritten through the ledger rules.tsv (225 requirement sentences: 200 kept, 14 moved to io-pimdir's cairn/spec, 11 dropped, each with its reason, for the owner to read); SYNC.md names rows and batch operations where it named statements, no sync rule moving; OVERVIEW.md says the schema is the contract and the index layout each implementation's own; GUIDE.md retired, its pointers sent to the part holding each rule; AGENTS.md and README.md say the repository holds no statement, README's SEARCH major now meaning a breaking change to the query language or to what an answer states.

Storage moves to **storage-draft-17** (a store of draft-16 is refused as an earlier engine's) and search to **search-draft-17** (an index of draft-16 is rebuilt); **sync-draft-15** keeps its number, its Status line requiring storage-draft-17. No tag is made.

## Rules and their checks

- The schema's shape, every column typed by `CHECK`, no JSON function, no `*` read nor positional insert in a trigger or a view: checks/schema.sh, now over migrations/storage/ alone.
- The flag columns' shape and the summary's per-component `CHECK`s on the floor: checks/floor.sh, its well-formed rows rewritten onto `summary` and `summary_value` and its refused writes extended (a keyword with a leading, trailing or doubled space, a tab or a non-ASCII byte, keywords on an unknown set, a column of another component, a file's uid, a named `in-reply-to` value). It no longer checks statement plans on SQLite 3.18 (decisions.md, 21:23: owed by io-pimdir for its own statements). checks/rehearsal/populate.sql follows both moves.
- Every summary column a component holds, read off the schema's `CHECK`s, against the payload and vector formats: checks/vectors.py (`holds`, `SUMMARY_COLUMNS`).
- The sync rules: the 200 files of vectors/sync/, untouched, 200 of 200 through io-pimdir's runner mapping their logical rows onto the new tables. What a query answers: vectors/search/queries.json unchanged, refresh.json at `v` 6.
- The rest is io-pimdir's suite at its 3a1f3eb (the keyword sort, the summary rows, the RESTRICT by a raw delete, refresh equal to rebuild on object and split rows), with 76 tests ported from the retired checks/invariants.sh (tests/invariants_*.rs), each shown to fail by breaking its rule on a scratch copy. invariants.tsv maps its 564 rules: 368 already held, 196 not, of which 48 plan rules and 17 migration rehearsals skipped by design and about 35 owed. No check of checks/ refuses a collection delete under a queued row: the RESTRICT's guard is io-pimdir's tests/store_rules.rs alone.
- checks/implementation.sh copies migrations/storage/, vectors/ and payloads/ alone into io-pimdir, the statements, index schema and generator staying the crate's. checks/io-pimdir.rev still names f2c4940, from before the night, so that CI gate fails until it names io-pimdir 3a1f3eb or later.

## The figures

| | Before (b5b9382) | After (cb23af5) |
| --- | --- | --- |
| Store tables | 24 | 15 |
| Store triggers | 43 | 30 |
| Statements the standard binds | 280 | 0 |
| io-pimdir's statement files | 280 | 243 (185 storage, 58 search) |
| Index tables (io-pimdir's) | 13 | 11 |
| Normative words (STORAGE, SYNC, SEARCH) | 71,343 | 51,724 |
| STORAGE.md | 39,318 | 24,683 |
| SEARCH.md | 12,966 | 7,970 |
| SYNC.md | 19,059 | 19,071 |
| OVERVIEW.md (informative) | 6,197 | 6,176 |
| GUIDE.md (informative) | 19,844 | retired |

## What did not reach its target

- **STORAGE.md stops at 24,683 words against 18,000**, the normative total at about 51,700 against 45,000. Every `kept` line of rules.tsv is still stated, and what stands above the target is rules: Annex A's derivation rules (about 4,000 words), Annex B (about 2,000), §9's key table and §15.3's payload lines, which checks/vectors.py matches byte for byte. Cutting further would drop rules unread (decisions.md, 21:50).
- **The §14.1 read list went with the statements** (unread counted by the `\Seen` bit, a message counted once by `seq`, `LIKE` search, `NULL` cursors): statement behaviour io-pimdir keeps, not a ledger rule; if the owner wants them as reader duties they return to §14.1.
- **The index keeps what the design folded or cut for the Android app**: `missing` stays a table, and five search statements nothing in io-pimdir runs stay files (`flagged`, `attached`, `holding`, `categorised`, `occurring_between`), since the app runs them by name (decisions.md, 21:30).
- No consumer is ported: the four CLIs and the Android app keep io-pimdir 0.19.1 or their pins; consumers.md lists what each names that moved.
