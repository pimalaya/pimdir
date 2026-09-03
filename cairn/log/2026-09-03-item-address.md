---
cairn: log
change: item-address
date: 2026-09-03
---

# One generic address table, the person axis of the store

`item_address(collection, link_id, role, position, address, name)` holds every person an item names, whatever its kind: a message's `from`, `to`, `cc`, `bcc`, a card's `email`, a calendar object's `organizer` and `attendee`.

It is one table rather than a column per kind because the question it answers, everything about this address, is asked across all of them, and `item_address_by_address` answers it with a seek where a JSON summary could not answer it at all.

Annex A.6 fixes the canonical form: the addr-spec alone, display name and `mailto:` removed, lowercased whole. RFC 5321 §2.4 makes the local part case-sensitive and practice does not, and a graph that splits `Alice@` from `alice@` answers the question wrong more often than the rule it honours.

A mail at the `Meta` tier fills the table completely, an IMAP `ENVELOPE` carrying every address, which is strictly more than the first-address-only `from` and `to` the JSON held.

The search part (SEARCH.md) keys `from:`, `with:` and `person:` on this table and holds no address graph of its own.
