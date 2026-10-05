---
cairn: change
id: collection-role
status: landed
created: 2026-10-05
---

# A collection keeps the role its source states

## Why

A mail client needs to know which folder is the inbox, the sent folder, the drafts, the trash and the archive; a calendar or contacts client, which calendar or address book a new item goes to when none is named. Every server states it (IMAP special-use attributes, Graph's well-known folders, Gmail's system labels, Graph's `isDefaultCalendar`, Google's primary calendar, CalDAV's `schedule-default-calendar-URL`), and an owner reads it in the listing it already makes to sync. The store keeps none of it, so a reader that wants it either asks the server itself, which a reader of the store never does, or guesses from a folder name.

MOA met this: it asked users to confirm every folder role when adding a box, from a one-shot `neverest check` answer, because nothing it reads at runtime carries a role.

## What

- `collections.role`, `NULL` when the source states nothing. Mail takes the JMAP `Mailbox/role` vocabulary (RFC 8621 §2: the IANA IMAP Mailbox Name Attributes, lowercased, plus `inbox`): `inbox`, `sent`, `drafts`, `trash`, `junk`, `archive`, `all`, `flagged`, `important`. Calendars and address books take `default`. A `CHECK` refuses a value outside the kind's vocabulary.
- One holder per `(account, kind, role)`: the partial unique index `collections_by_role`, and the trigger `collections_role_moves` that takes the role from its old holder when it is set on another, so a move is one statement.
- `set_collection_role(collection, role)` under queries/storage/owner/; `list_collections` and `list_collections_by_account` return the column; a role change stamps the collection in the feed.
- STORAGE.md §14: written only from what a source states, never from a name, cleared when the source stops stating it, the first source with something to say winning. §6: reconciling an index, a trigger, and a reader meeting an unreconciled store.
- GUIDE.md §8 and OVERVIEW.md.
- checks/invariants.sh: the setter, the move, the feed, per-account holders, the index, the vocabulary, the undeclared kind.

## Scope / non-goals

- No guessing in the store: a client that recognises "Sent Items" does so on its side.
- No user choice in the store: a client's own assignment of roles is its configuration, not the server's state.
- `subscribed` and the structural IMAP attributes (`\Noselect`, `\HasChildren`) are not roles.
- Folded into 0001 while the part is draft; no version moves.
