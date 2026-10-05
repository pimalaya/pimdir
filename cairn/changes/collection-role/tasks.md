---
cairn: tasks
change: collection-role
---

# Tasks

## Landed in this repository

- [x] migrations/storage/0001_init.sql: the column, its `CHECK`, `collections_by_role`, `collections_role_moves`, the stamp trigger.
- [x] queries/storage/owner/set_collection_role.sql; `role` in list_collections and list_collections_by_account.
- [x] STORAGE.md §4.3, §6, §14; GUIDE.md §8; OVERVIEW.md.
- [x] checks/invariants.sh.
- [x] Log entry.

## Left to io-pimdir

- [ ] Re-vendor the schema and the statements; reconcile the column, the index and both triggers on open.
- [ ] `set_collection_role` on the owner, `role` on `PimdirCollection`, `NULL` on a store not reconciled yet.
- [ ] Tests: the reconcile, the setter, the move, the feed.

## Left to neverest

- [ ] Record the role each backend states at every sync, next to the name, and clear what it no longer states.
- [ ] A sync that declares every collection and fetches no item.

## Left to the readers

- [ ] himalaya: `Mailbox.role` from the column.
- [ ] calendula, cardamum: `default` on calendars and address books.
