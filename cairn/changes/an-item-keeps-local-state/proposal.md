---
cairn: change
id: an-item-keeps-local-state
status: draft
created: 2026-11-21
---

# An item keeps local state

## Why

compared-with-notmuch, Part 1: notmuch keeps two kinds of local state per message, both terms on its Xapian document: tags (`K<tag>`), local labels never sent anywhere, and properties (`XPROPERTY<key>=<value>`, lib/message-property.cc), multi-valued key/value pairs where notmuch keeps its own crypto state (`session-key=`, `index.decryption=`) and the tools built on it keep theirs. pimdir has neither: a tag is a flag of a placement (SEARCH §10), synced as a keyword, and an app needing state per item (a snooze time, a private label, later a session key) keeps a database of its own keyed by link id or `seq`, which drifts on every purge, restore and rekey the store otherwise tracks.

Flags are no place for it (owner discussion, 2026-11-21): they sync and derive pushes (SYNC §5), they are per placement where this state is per item, and a key holding a value set two ways on two sides is a conflict only last-writer-wins settles, which pimdir rules out. No portable protocol carries per-message key/values either (IMAP METADATA is per mailbox, ANNOTATE almost unimplemented, JMAP and Graph offer keywords and categories, which are flags), so the state is local by nature.

It is not a body's extension either: a vCard or iCalendar `X-` property lives in the body, syncs through DAV and stays the way a contact or an event carries synced extension data. A message's body is immutable, which is why mail needs this most.

## What

- **A table.** `item_property(seq, key, value)`, keyed by the item's public id (STORAGE §9), so the state follows the item across its placements, its retention and its restore, as notmuch's follows the Message-ID; multi-valued, the three columns its key; an index on `(key, value)` for search. Gone with the last row holding the `seq` (a purge, an erase scrubbing it as §11.5 scrubs the rest). Never read by SYNC, never in a binding, never pushed.
- **Keys.** `<namespace>/<name>`, ASCII, bounded (a length to fix); `pimdir/` reserved to the standard: `pimdir/label` for local labels now, `pimdir/session-key` reserved for a later decryption (cairn/changes/the-query-reserves-its-later-forms). An app writes under its own name (`himalaya/snooze-until`). Values bounded too (a length to fix).
- **Writes.** The owner writes them; a producer stages a new action, `set-property`, adding and removing values per key, payload schema under payloads/, applied in the queue's order like `set-flags`. A change stamps the item (`items.changed` of every row holding the `seq`), so the change feed carries it.
- **Search.** `label:<value>` (the value whole, folded as Annex A.2 folds `fn`, as `category:` reads) and `property:<key>=<value>` (byte for byte), read from the store by the `(key, value)` index, never copied into index.db. `tag:` stays the synced flags: shared label or private label is the user's explicit choice.
- **Readers.** A statement listing an item's properties, one listing the items holding a key, the overlay of pending `set-property` actions (§15.4).

## Decided (owner, 2026-11-21)

- **Bounds.** A key is at most 64 bytes of ASCII, `<namespace>/<name>`, each part of `[a-z0-9._-]`; a value at most 1024 bytes of UTF-8; at most 64 values per key and item. An action past them is refused as malformed.
- **Labels.** A label is kept as written and matched folded (`label:receipts` matches `Receipts`, as `category:` reads); adding a value whose fold equals one the item holds under the key is a no-op, so an item never holds two spellings of one label.
