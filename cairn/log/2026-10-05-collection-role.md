---
cairn: log
change: collection-role
date: 2026-10-05
---

# A collection keeps the role its source states

A reader could not tell the inbox, the sent folder or the default calendar apart without asking the server or guessing from a name, although every owner reads that in the listing it syncs from. MOA asked its users to confirm each folder for want of it.

- **`collections.role`** (§4.3, §14). Mail roles are JMAP's `Mailbox/role` vocabulary, calendars and address books take `default`; the column's `CHECK` refuses anything else for the kind. Guarded by invariants.sh "role: a value outside the kind's vocabulary is refused" and "an undeclared kind takes none".
- **One holder per account and kind.** The partial unique index `collections_by_role`, and `collections_role_moves`, a `BEFORE UPDATE` trigger clearing the old holder, so `set_collection_role` moves a role in one statement. Guarded by "setting it on another collection moves it there", "each account holds its own" and "a direct second holder is refused by the index".
- **Feed.** `collections_stamp_update` watches `role`; a move stamps both collections. Guarded by "the move stamps both collections in the feed".
- **Reads.** `list_collections` and `list_collections_by_account` return `role` last. Guarded by "the setter records it, and the reader lists it".
- **§6.** A reconciled index or trigger is created when absent, a trigger whose body moved is recreated, and a reader meeting an unreconciled store reads the column as `NULL`. Left to io-pimdir's tests, the SQL holding no reconcile.

The rule that a role is written only from what a source states, never from a name, is the owner's and no check here guards it. Folded into 0001; draft-04 is not tagged yet, so the number stays.
