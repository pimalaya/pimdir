---
cairn: tasks
change: mail-write-names-from-himalaya
---

# Tasks

- [ ] Review the four rows and the two exclusions with the maintainer.
- [ ] STORAGE.md Annex B: the four rows; B.1: a flag change on `$Important` and `$Junk` read under their row, else under `mail.flags.keywords`.
- [ ] B.2 and payloads/: `collection-rename` and `collection-delete` intents, their schemas and vectors; the delete's rule for the items it removes.
- [ ] checks/names.sh and checks/vectors.py pass with the new rows and payloads.
- [ ] io-pimdir: the constants, and the gate reading the two flags under their row first.
- [ ] himalaya: map `collection.rename` and `collection.delete` to `mailbox.rename` and `mailbox.delete` when its shared verbs exist.
- [ ] Log entry; status `landed`.
