---
cairn: log
change: canonical-sql-comments-trimmed
date: 2026-08-25
---

# The canonical SQL keeps the rationale a reader cannot infer, and drops the rest

The comments in migrations/0001_init.sql, queries/ and the `note` fields of vectors/ had grown into a second specification. Nothing in them was wrong, and that was the problem: an argument stated twice drifts, and the copy nobody edits is the one a reader trusts. SPEC.md is the normative document, so the comments are now cross-references to it plus whatever the statement itself cannot say.

No SQL changed. Every statement and every DDL line is byte-identical, checked by stripping comments from both revisions and diffing, and every vector value is unchanged, checked by comparing the two JSON files with the `note` fields deleted.

## What was cut

- **Restatements of the code.** `-- One source's sync cursor for a collection.` over `SELECT checkpoint FROM sources WHERE collection = :collection AND source = :source` earns nothing. Statements whose SQL is their own documentation now carry no comment at all: `load_checkpoint`, `insert_item`, `get_item`, `count_items`, `list_link_placements`, `load_parked_actions`.
- **The repeated preamble.** Six files opened with the same six-line paragraph about reference statements, encodings and named parameters. It is two lines now, and §4.4 already carries the SHOULD and the MAY.
- **Restatements of SPEC.md.** The refcount floor had its whole §7 argument inline, the collector its whole §5 argument, the retained index its whole log entry. Each keeps the claim and the consequence, and the section reference carries the reasoning.

## What was kept

Measurements, because nothing else records them: the 80 seconds against 121 ms that chose `recompute_refcounts`' shape, and the hundred thousand statements `release_pins` replaces. Warnings whose violation is silent: `update_binding` not taking a `handle`, `delete_items` sparing retained rows, `claim_action` running first in its transaction. And the invariants a reader would otherwise have to reconstruct from the schema, such as why `load_items` carries a `sort_key` the sync layer never reads.

The files are a quarter shorter (804 lines to 614), and the section references make the duplication a link rather than a copy.
