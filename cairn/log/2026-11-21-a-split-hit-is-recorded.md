---
cairn: log
change: a-split-hit-is-recorded
landed: 2026-11-21
---

# A split hit is recorded

search-draft-16, edited in place while it is untagged (the owner's ruling of 2026-11-21): an index of the earlier text has another schema text, so §2 rebuilds it, and no draft number moves.

A text term holds for a hit when any of its live placements matches it (§8.2). FTS5 matches a document, a body or a bodiless placement's summary, so a count of text terms alone could combine them in one full-text expression (`power AND california`) only where a hit names one document. The index now records the hits that do not.

Rules and their checks:

- **SEARCH §3: a `split` row per public id whose placements name two or more documents**, a document told apart by `coalesce(object, -id)`, with `placement_by_seq` to find a public id's placements (migrations/search/0001_init.sql). Guarded by checks/invariants.sh, "index: a public id is split while its placements name two documents, bodies or bodiless summaries, and recounted after each write": two placements on one body are not split, a second body or a bodiless placement beside a body is, two bodiless placements are, a repoint to the others' body and a delete take the row away, and `split_mark` and `split_seqs` seek `placement_by_seq`. It fails with `split_mark` counting above 9 (`[|||||||11]`) and without the index (`...||00`).
- **SEARCH §3 and §4: a placement holds one document.** §4 already wrote summary text while a placement had no body and dropped it when it gained one; it now states this as an invariant (MUST NOT hold both once a batch commits), which the document count leans on. No check fails for this rule alone: a body holds the headers its summary indexes, so no query tells a stale summary row from the body, and the vectors compare answers, not rows. Left open: a refresh.json field stating the `summary_text` rows a canonical index holds would pin it.
- **SEARCH §4: the recount.** After a batch's placement writes, the reconciliation of keys included, `split_forget` then `split_mark` per public id a placement was upserted or deleted for. Guarded by vectors/search/refresh.json, new case "a hit holding two bodies holds a text term through either": split-1 filed in home/INBOX (quince) and home/Archive (rhubarb), repointed to the INBOX body, back, then removed. Each step states `split`, the rows a canonical index holds (refresh.json `v` 5, a step's new `split` field, its schema and vectors/README.md), and answers `quince rhubarb` and `quince not rhubarb` at hit level. checks/vectors.py re-derives each step's `split` from the live placements' bodies (by bytes) and summaries, and requires one step stating a split public id and one stating none: a step's list emptied fails ("the split rows a canonical index holds: [] is not [1]"), the case removed fails ("a step states a public id split and another states none", and its two fixtures named by no case). io-pimdir's `every_refresh_vector_answers` fails on the case without its `split_mark`.
- **SEARCH §8.2: a count may match whole documents** for every hit whose public id `split` does not hold, and evaluates each one it holds per placement (`split_seqs`, then `match_object` and `match_summary`). The queries of the new case pin it: a count matching documents without the correction answers `quince rhubarb` with no hit and `quince not rhubarb` with one, in steps 1 and 3.

The statements: `split_forget` and `split_mark` (indexer, §4), `split_seqs` (query client, §8.2), named in §3's table and run by the invariants scenario; queries/signatures.json and vectors/manifest.json restated. `split_seqs` walks `split` by a `CROSS JOIN`, the planner otherwise scanning every placement through `placement_by_seq` on an index without statistics.

Informative: GUIDE.md §15 names the recount in refresh steps 5 and 6 and the joint count in query step 4. OVERVIEW.md names no table or statement and is unchanged.

Measured by io-pimdir on the 517k-message Enron store (its cairn/log/2026-11-21-text-counts-match-whole-documents.md): no public id is split there, every seq having one placement; `power california` counts in 13 ms against 43, `california not gas` in 17 against 47; the index grows by 6.7 MB of 1.88 GB.

checks/io-pimdir.rev moves with the io-pimdir commit that follows.
