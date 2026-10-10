---
cairn: log
change: file-sources
date: 2026-10-10
---

# File sources: what a folder's remote lists

The store and sync side of the Android plan's C.7: a folder synced from Nextcloud (Drive later), files as a mutable kind on the existing base and conflict.

- **Identity** (SYNC §4, Annex A.7): a file source MUST state an id its server keeps across a rename and a move, which is both the handle and the hint: Nextcloud's and ownCloud's `oc:id`, whose instance part makes it unique across servers, and Drive's file id. The href is not it: a handle must be bound once (§10), so an href handle would read a rename as a delete and an add and mint a key over the old one. The remote path is derived from the folder and the summary's name, so a server rename is a summary write on the same placement (vector 60), and a move between two synced folders is the store's ordinary move under one key.
- **No stable id, no file source**: a plain WebDAV collection, keyed by href alone, waits. Keying it on the href or the bytes would lose the base and the references on every rename or edit, the loss C.2 set out to avoid; settling it well wants a real server to measure (`DAV:resource-id`, RFC 8144, where offered).
- **Meta and Full** (SYNC §4): the listing states the name, the media type and the length, never the body (vector 55); a `Full` upgrade fetches the bytes, base and revision with them (vector 56).
- **Revision and pushes**: the ETag; a source stating none for a file pushes no content. A server edit is a pull to `Meta` (vector 57), a local edit an `Update` gated on the base ETag (vector 58), both a conflict the `Manual` policy records (vector 59), which a person settles by keeping both (an `Add` of the local body as a new file, then an `Edit`) or picking one. A server delete retains the item and its bytes (vector 61).
- **A held file's size is the body's**: vector 58 failed in io-pimdir until a listing over a held body kept the size the body gave, as A.7 says ("as for mail"); the listing still restates the name and type.
- **Left out**: local renames and moves push nothing, no change naming a file's name, and Drive's revision field is its connector's to settle. Both want a real connector before a rule.

checks/vectors.py accepts a file member's stated `link_id` and `summary` and checks the summary is `file_summary`'s; fixtures file-notes.txt and file-notes-edited.txt. draft-04 is not tagged yet, so the number stays.
