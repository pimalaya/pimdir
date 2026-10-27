---
cairn: tasks
change: no-custom-kinds
---

# Tasks

- [ ] STORAGE §1, §4.3 and §13: the closed set, the empty undeclared kind, `x-` named for capabilities, roles and actions only
- [ ] migrations/storage/0001_init.sql: `CHECK (kind IN ('', 'message/rfc822', 'text/vcard', 'text/calendar', 'application/octet-stream'))` on `collections`; the reconciliation on open rebuilds the table (STORAGE §6)
- [ ] checks/invariants.sh: a fifth kind refused by `set_collection_kind` and `ensure_collection`, an empty kind accepted (fails on today's schema)
- [ ] Decide the open question (a source offering another media type) and state it in STORAGE §14
- [ ] OVERVIEW.md: the kinds are the standard's, and how a new one arrives
- [ ] io-pimdir: nothing writes another kind today; check `set_collection_kind` callers and the CLI's `collection` verbs against the check
- [ ] Bump the draft number if `draft-04` is tagged before this lands (AGENTS.md §2)
- [ ] Log entry with the rationale of proposal.md
