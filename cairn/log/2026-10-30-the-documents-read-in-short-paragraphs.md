---
cairn: log
change: the-documents-read-in-short-paragraphs
date: 2026-10-30
---

# The documents read in short paragraphs

An editorial pass over OVERVIEW, STORAGE, SYNC, SEARCH and GUIDE, after the README's rewrite: no paragraph or bullet over about 450 characters, enumerations of cases, conditions and steps as lists, rationale and history cut (it belongs to this log), restatements replaced by § references. Headings, numbering, anchors, tables, code spans, statement names and links are unchanged, and every part keeps its BCP 14 keyword counts. No Status line moves.

Three wording fixes that state what the rest of the text already did:

- SYNC §3: an item conflict lasts until an `Edit` or a `Remove` settles it, as §7 and §9 say (it read "an `Edit`").
- SYNC §5: "Neither half MUST be dropped for the other" now reads "An engine MUST NOT drop either half for the other".
- STORAGE §13: the `item_reference.role` list names `parent` and `source`, as 0001_init.sql's CHECK and §14.2 do. GUIDE §15 points at §3 for the shape comparison (it read §2).

`nix flake check path:$PWD` passes.
