---
cairn: log
change: collection-display-name
date: 2026-09-06
---

# A collection can be named, not only addressed

`collections.name` has been in the schema since 0001, documented as the logical name, and no statement ever wrote it. `ensure_collection` and `set_collection_kind` both seed it from `:collection`, so every store built against this format carries a name that is a verbatim copy of the id, prefix included.

That is the opposite of what §9.2 asks for. It tells an owner to namespace its ids and record the account "so a reader filters on a column rather than a prefix"; seeding the label from the id puts the prefix in the label as well, and leaves a reader splitting on a separator only the owner knows.

`set_collection_name(collection, account, name)` is the missing half. It inserts with an undeclared kind when the row is absent, the way `ensure_collection` does, and updates only `name` when it is present, so a kind already declared and the account survive it. §14 states the rule it serves: a name is a label, never an address, nothing keys on it, and keeping it current across a `rename_collection` is the owner's, the two being independent axes rather than one statement's business.

The rule matters most where an id is not readable. A CardDAV or CalDAV collection is addressed by its path segment, which servers routinely make a UUID, so a frontend without this column renders the UUID. pimalaya-linux had already built a private `app_collection_name` table and a resolver to work around it, which is the clearest evidence the column was declared and then left unwritable.

Guarded by checks/invariants.sh: a collection declared through `set_collection_kind` is seeded with its id, the setter moves the label, the id and the kind do not move with it, and naming a collection that does not exist yet creates it with an undeclared kind. Without the statement the scenario cannot run at all.

`color`, `description` and `sort_order` keep the same gap deliberately: no consumer reads them yet, and one change per rule reads better than four.

No schema change, so nothing migrates and version 1 stands. 149 statements name, prepare and hold their invariants.
