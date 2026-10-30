---
cairn: log
change: no-custom-kinds
date: 2026-10-30
---

# The set of kinds is closed

Decided on 2026-09-03 with the typed summaries and never written down; the open question settled by edit 7 of the pimdir stable-release plan. The `CHECK` on `collections.kind`, `repair_kinds` and their scenarios landed with every-vocabulary-is-open-or-closed; this entry lands the prose.

- **STORAGE §1, §4.3** (normative): a collection's kind is `message/rfc822`, `text/vcard`, `text/calendar` or `application/octet-stream`, `''` until declared; the set grows by a change to the standard, carrying its summary table, its Annex A section and its vectors, never by a writer; `x-` names capabilities, reference roles and queue actions, never a kind.
- **STORAGE §14, SYNC §1** (normative): a source offering a collection of another media type (a DAV collection of `text/x-vlist`) has it recorded kindless and never synced.
- **OVERVIEW §2** (informative) follows.

Why closed: a kind is only useful to a reader that knows it, its summary table, derivation, sort key and search extraction, so every client pays to learn a new kind whether the format reserves room or not; the-file-kind (2026-10-10) is the path working. Reserved `x_` tables, a registry, a kind trait and an export special case were rejected as complexity for nobody: an opaque kind would be the dropped `items.meta` column again, a shape nothing renders and nothing checks.

Guarded by the scenarios every-vocabulary-is-open-or-closed added to checks/invariants.sh (a fifth kind refused, over a declared kind too; the repair). io-pimdir checks its callers in its own cairn.
