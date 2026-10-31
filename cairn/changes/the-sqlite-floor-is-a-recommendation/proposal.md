---
cairn: change
id: the-sqlite-floor-is-a-recommendation
status: landed
created: 2026-10-31
---

# The SQLite floor is a recommendation, and the schema needs no JSON

## Why

The essence of pimdir is a way to store and query PIM data (the user, 2026-10-31). The parts bind SQLite versions and extensions where they mean a model: STORAGE.md:98 (`MUST` 3.37 for `STRICT` and `DROP COLUMN`), SEARCH.md:42 (`MUST` 3.43 with FTS5 for `contentless_delete`), STORAGE.md:479 (a flag set spelled "as SQLite's `json()` writes it"), STORAGE §6 and SEARCH §2 (the shape compared by `sqlite_schema` text).

The Android app is the first implementation the floors shut out: it wants the platform's `android.database.sqlite` (3.18 on API 26, no JSON before 3.38, FTS3 and FTS4 only, no FTS5 on any release: AOSP external/sqlite dist/Android.bp) rather than a bundled copy, and accepts a store whose statements are its own (the user, 2026-10-31: a perpetual fork, tending toward the recommendations as devices age). Nothing in the model needs 3.37; the floors are what the canonical text needs.

The canonical schema also uses JSON where tables serve better, which this change removes on its own merits:

- `placements.flags` and `bindings.base_flags` (migrations/storage/0001_init.sql:198, :320): a flag predicate scans `json_each(i.flags)` (6 statements) rather than an index, and the set needs a spelling rule (STORAGE.md:479) whose violation fails silently.
- `mail_summary.in_reply_to` and `task_summary.categories` (:382, :446): arrays read by `json_each` (1 statement) and by the index.
- List parameters: 27 of the 34 `json_each` calls bind a list as one JSON text (`:collections` 13, `:links` 10, `:hashes` 2, `:ids` 1, `:handles` 1).
- Queue payloads rewritten in SQL: rename_queue_targets.sql reads and writes `$.to` and `$.supersedes.collection` with `json_extract` and `json_set`.

## What

**The floors become recommendations.**

- STORAGE §4.1: SQLite 3.37 or newer is RECOMMENDED, and the canonical text under migrations/ and queries/ is the RECOMMENDED shape. An implementation MAY run another shape of its own on any SQLite, provided it keeps the model: every table, column meaning, invariant, derivation (Annex A), statement's effect and vector outcome. `STRICT` is the canonical shape's way of enforcing types; another shape enforces them by `CHECK (typeof(...))` or by its writer.
- A store records its shape: `store_meta.shape`, `pimdir` for the canonical text, an implementation's own name otherwise. A program opens a store only in a shape it implements, and §6 reconciles toward the canonical text only a store of the canonical shape. An implementation of its own shape owes its own reconciliation.
- SEARCH §2: SQLite 3.43 with FTS5 is RECOMMENDED for the canonical index. An index of another shape (FTS4, FTS3, or no FTS) MAY answer the same language, provided every query's hit set is the vectors'. Relevance order is the shape's own: bm25 RECOMMENDED.
- Text folding happens before the tokenizer, not in it: the index stores and matches text folded by §5's rule (case and diacritics), so `unicode61 remove_diacritics 2`, FTS4's `remove_diacritics 1`, ICU or `simple` give one hit set. Today the fold is split between io-pimdir's `fold_text` and the FTS5 tokenizer's options.
- The vectors say which they pin: model vectors (objects, summaries, sync, search hit sets) bind every shape; vectors/schema and vectors/fixtures bind the canonical shape.

**The canonical schema needs no JSON.**

- `placement_flag(collection, seq, flag)` and `binding_base_flag(collection, link_id, source, flag)`, the primary key over all columns, `WITHOUT ROWID`, an index on `flag`. A known-empty set is told from an unknown one by `placements.flags_known` and `bindings.base_flags_known` (0 or 1), since no row cannot carry both. A flag write stamps the placement (§4.5) by its statement, as `set_flags` does today.
- `mail_in_reply_to(collection, seq, position, msg_id)` and `item_category(collection, seq, position, value)`: document order kept by `position`.
- List parameters: one temporary table the caller fills inside the statement's transaction, `temp.param(slot TEXT, position INTEGER, value)`, and the statements join it (`WHERE link_id IN (SELECT value FROM temp.param WHERE slot = 'links')`). This keeps the statement text fixed for any length and stays under the variable limit (999 before 3.32). Expanded placeholders were set aside: the text would vary with the count, and canonical statements are compared by text.
- The queue's targets as columns: `queue.target_collection`, the collection a `move`, `copy` or superseding `add` names, written by `enqueue_action` beside the payload, so a rename is a plain `UPDATE`. The payload stays a JSON document, opaque to SQL: an encoding of the action, never queried.
- The lossless rewrites go in the canonical text too, since nothing is lost: `iif` becomes `CASE` (add_reference.sql, the trigger at 0001_init.sql:562), and the §6 and SEARCH §2 shape reads use `sqlite_master`, which every version has. `UPDATE ... FROM` (recompute_refcounts, release_bases_before), `RETURNING`, upserts and `STRICT` stay canonical: the linear recount needs the join (recompute-refcounts-linear), and the rest is what 3.37 buys.

## Versions

storage-draft-07 and search-draft-07, sync-draft-06 (its flag deltas read the new tables), a migration from draft-06 moving every JSON array into its table. The migration is the canonical shape's own; an implementation of its own shape writes its own.

## Depends on, and what follows

io-pimdir follows the drafts (its own change), then the Android app runs its own shape on the platform SQLite (android cairn/changes/platform-sqlite).

## Settled

- Decided with the user (2026-10-31): `flags_known` and `base_flags_known` columns, not a sentinel row.
- `temp.param` is written in STORAGE §4.4 as the canonical shape's calling convention, which another shape replaces freely.
- The FTS5 tokenizer runs with `remove_diacritics 0`, the fold done before it (SEARCH §5): a rebuild of every canonical index, which is derived state.
- The child tables are keyed `(collection, link_id)` like their parents, and the category table is `task_category`.
