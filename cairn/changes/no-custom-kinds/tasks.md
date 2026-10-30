---
cairn: tasks
change: no-custom-kinds
---

# Tasks

- [x] STORAGE §1, §4.3: the closed set, the empty undeclared kind, `x-` named for capabilities, roles and actions only (§13's `kind` entry landed with every-vocabulary-is-open-or-closed)
- [x] migrations/storage/0001_init.sql: `CHECK (kind IN ('', 'message/rfc822', 'text/vcard', 'text/calendar', 'application/octet-stream'))` on `collections`; the reconciliation on open repairs another kind to `''` (`repair_kinds`) and rebuilds the table (STORAGE §6); landed with every-vocabulary-is-open-or-closed
- [x] checks/invariants.sh: a fifth kind refused by `set_collection_kind`, over a declared kind too, an empty kind accepted from `ensure_collection` (failing on 8b2e8b6); landed with every-vocabulary-is-open-or-closed
- [x] Decide the open question (a source offering another media type): recorded kindless and never synced (2026-10-30)
- [x] State the decision in STORAGE §14 and SYNC §1
- [x] OVERVIEW.md §2: the kinds are the standard's, and how a new one arrives
- [x] Lands in storage-draft-05; log entry with the rationale of proposal.md

Followers, tracked in their repositories: io-pimdir (check `set_collection_kind` callers and the CLI's `collection` verbs against the `CHECK`, a source's other media type recorded kindless).
