---
cairn: change
id: no-custom-kinds
status: active
created: 2026-10-18
---

# The set of kinds is closed

## Why

Decided on 2026-09-03 with the typed summaries (PIMDIR_REPORT §4) and never written down: no custom kinds. typed-summaries logged that "the set of kinds is closed and named by the spec", but only as the reason `items.meta` went; STORAGE.md states the four kinds in a schema comment and in §1's "every kind the standard names", and no rule says a writer may not declare a fifth.

The rationale, for the log once this lands:

- A kind is only useful to a reader that knows it: its summary table, its Annex A derivation, its `sort_key`, its search extraction. Every client pays the cost of learning a new kind whether the format reserves room for it or not, so a new kind is a change to the standard, with its table and its vectors, and the-file-kind (2026-10-10) is that path working.
- The extension design considered on the way, reserved `x_` tables, a registry, a kind trait in io-pimdir and an export special case, was rejected as complexity for nobody: no consumer asked for it, and an opaque kind would be the `meta` column again, a shape nothing can render and nothing checks.

`x-` stays what it is today, an extension prefix for capabilities, reference roles and queue actions, none of which carries a body a reader must parse.

## What

- STORAGE §4.3 (`collections.kind`) and §13: a kind is one of `message/rfc822`, `text/vcard`, `text/calendar`, `application/octet-stream`, or empty until declared; anything else is refused at the write.
- A schema `CHECK` on `collections.kind` so a writer that disagrees fails at the write, as the summary tables already do for their shape, guarded by a scenario in checks/invariants.sh (AGENTS.md §4).
- STORAGE §1 "Generic" says the set is closed and grows by the standard alone; OVERVIEW.md says the same in its own words.

## Open questions

- An owner whose source offers a collection of another media type (a DAV collection of `text/x-vlist`, say): skip it silently, or record it as declared and kindless. The text should say which.
