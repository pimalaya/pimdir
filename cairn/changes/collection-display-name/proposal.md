---
cairn: change
id: collection-display-name
status: landed
created: 2026-09-06
---

# A collection can be named, not only addressed

## Why

`collections.name` is normative and documented as the *logical name* (`INBOX`, `Contacts`), but §14 defines no statement that writes it. The only two statements that touch the column, `ensure_collection` and `set_collection_kind`, seed it from `:collection`, so in every store built so far the name is a verbatim copy of the id.

§9.2 asks an owner filing two accounts to namespace its ids and then says a reader should filter "on a column rather than a prefix". Seeding the name from the id defeats exactly that: the prefix lands in the label too, and a reader wanting the bare name has to split on a separator that is the owner's private convention.

For mail the cost is cosmetic, an id being the mailbox name. For DAV it is not: a CardDAV or CalDAV collection is addressed by a path segment, which servers routinely make a UUID, so a frontend renders `ED99C7C8-2741-11F1-9B88-2C202A48A29D` where the server said "Work". A consumer has already paid for this: pimalaya-linux carries a private `app_collection_name` table and a resolver beside it, for want of a column the format already declares.

## What

- `set_collection_name(collection, account, name)` under queries/storage/owner/, inserting an empty kind when the row is absent and updating only `name` when it is present, so a declared kind and the account survive.
- §14 states the rule: a name is a label, never an address; nothing keys on it; an owner that namespaces its ids SHOULD record the bare name here; keeping it current across a `rename_collection` is the owner's.
- §9.2 and GUIDE.md §8 point at it, so the namespacing advice and the configuration walkthrough name the column that answers it.
- A scenario in checks/invariants.sh: the seed is the id, the setter moves the label, the id and the kind do not move, and naming an absent collection creates it undeclared.

## Scope / non-goals

- `color`, `description` and `sort_order` have the same missing-setter gap and keep it; they are presentation the format has no consumer for yet.
- No schema change: the column exists, so nothing migrates and no version moves.
- `rename_collection` still moves the id alone. The two are independent axes, and the owner is told so rather than given a statement that couples them.
