---
cairn: log
change: spec-restructure
landed: 2026-08-16
---

# Reorder the spec, move the meta conventions to an annex

Sections had been appended as they were written rather than placed, so the order no longer told a story: integrity sat after ownership, retention and collection generation were at the end because they landed last, and the per-kind `meta` conventions sat in the middle of the normative text while being explicitly informative.

Editorial only. No requirement changed, no schema moved, and the word count is the same to within the new table of contents.

## What landed

A table of contents, an annex, and an order that runs **the artifact, then the model, then the API**:

- the artifact: layout, database, blob store, migrations, integrity;
- who may touch it: concurrency and ownership;
- the model: identity and dedup, sync, retention, collection generation, encodings;
- the API: operations and reads, action queue;
- Annex A: the per-kind `meta` and `sort_key` conventions, informative and now visibly so.

Retention moved next to the sync model because it *is* the terminal state of that model's `deleted` memory, and collection generation next to it because a rekeyed handle space is a sync fact. Integrity moved up beside the blob store and migrations, whose invariants it checks. Encodings moved down to sit against the operations that bind them.

## The renumbering

Citations written before today point at the old numbers. The mapping:

| old | new | section |
| --- | --- | --- |
| §1–§6 | unchanged | goals, terminology, layout, database, blob store, migrations |
| §7 | §8 | concurrency and ownership |
| §8 | §7 | integrity |
| §9 (§9.1–§9.3) | unchanged | identity and dedup |
| §10 | unchanged | sync model |
| §11 | §13 | encodings |
| §12, §12.1 | §14, §14.1 | operations, reading the store |
| §13 | Annex A | application meta conventions |
| §14, §14.1–§14.5 | §15, §15.1–§15.5 | action queue |
| §15 | §12 | collection generation |
| §16, §16.1–§16.2 | §11, §11.1–§11.2 | retention |

Roughly 75 citations in other repositories (io-pimdir, neverest, linux, calendula, cardamum, himalaya, android) still name the old numbers. Those in source comments and Cairn spec files can be corrected as each repository is touched; those in Cairn log entries are immutable by the convention and stay as written, which this table resolves.

## Why now

The cost of renumbering is exactly those citations, and it only grows: the freeze will make the numbers a published surface, and every month adds consumers. Draft is the last cheap moment.
