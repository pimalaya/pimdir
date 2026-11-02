---
cairn: tasks
change: mail-write-names-from-himalaya
---

# Tasks

- [x] Review the four rows and the two exclusions with the maintainer.
- [x] STORAGE.md Annex B: the four rows; B.1: a flag change on `$Important` and `$Junk` read under their row, else under `mail.flags.keywords`.
- [x] B.2 and payloads/: `collection-rename` and `collection-delete` intents, their schemas and vectors; the delete's rule for the items it removes.
- [x] checks/names.sh and checks/vectors.py pass with the new rows and payloads.
- [x] io-pimdir: the constants, and the gate reading the two flags under their row first. Done in io-pimdir 908db2b (its cairn/log/2026-11-02-the-mail-write-names-from-himalaya.md).
- [x] himalaya: queue `collection-rename` and `collection-delete` from `pimdir mailbox rename` and `pimdir mailbox delete` (himalaya cairn/log/2026-11-02-pimdir-mailbox-rename-delete.md); the shared `mailbox.rename` and `mailbox.delete` verbs wait for himalaya's capability-shared-api.
- [x] neverest: perform both intents on IMAP, Gmail, CalDAV and CardDAV, and declare `mail.flags.important` and `mail.flags.junk` on Gmail (neverest cairn/log/2026-11-02-a-collection-is-renamed-or-deleted-when-asked.md).
- [x] Log entry; status `landed`.
