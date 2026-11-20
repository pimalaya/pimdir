---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# A collection's parent and presentation

A gap the generator's lane found and the lead confirmed: STORAGE §4.3 describes `collections.parent` and the presentation columns `color`, `description` and `sort_order`, and every collection listing answers them, yet no canonical statement wrote any of them (`delete_collection` alone touched `parent`, through its foreign key). io-pimdir only read them; the Android app writes `description` and `color` through a statement of its own (android/rust/pimdir/queries/app/write_collection.sql), which STORAGE allows, and never `parent` nor `sort_order`. Recommended by the lead over dropping the columns, which a freeze of 0001_init.sql makes one-way. Lands in storage-draft-15, no number moving, the schema untouched.

## What moved

- **STORAGE §14** (normative): `set_collection_parent(collection, parent)` writes a parent from what a source states; the hierarchy MUST stay a forest within an account, a parent being a collection of the same account, never the collection itself nor one under it, and the statement changes no row for a parent breaking it or one the store does not hold, which the owner reads as a refusal. `set_collection_presentation(collection, color, description, sort_order)` writes the three together on a declared collection, a reader taking the color and the description as untrusted text (§18).
- **queries/storage/owner/set_collection_parent.sql**, **set_collection_presentation.sql**: the parent guard is a recursive walk up from the parent, SQLite 3.8.3's, under the 3.18 floor; queries/signatures.json restated.
- **GUIDE §8**: a parent and a presentation beside the name and the role.

## Guards

- checks/invariants.sh, "A parent and a presentation are what a source states": the setter and the reader, a cycle, the collection itself and another account's parent refused, the row unchanged, an unknown parent refused, `NULL` at the top, stamped in the feed, a renamed parent followed and a deleted one leaving its children at the top; the presentation listed in `sort_order`, cleared, and an undeclared collection not declared by it. With the statement reduced to a bare `UPDATE`, three scenarios fail ("a collection under its own child", "under itself", "a parent of another account").
- checks/names.sh and checks/signatures.py name and sign both statements; io-pimdir wraps them (its cairn/log/2026-11-20-a-collection-parent-and-presentation.md).

## Left

- The Android app may replace its own write_collection.sql by the canonical statements, and write `parent` and `sort_order` its sources state.
- The generator's model writes no parent nor presentation yet; its lane's to take the statements.
