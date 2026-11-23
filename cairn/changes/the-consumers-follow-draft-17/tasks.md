---
cairn: tasks
change: the-consumers-follow-draft-17
---

# Tasks

The lanes' own steps are in their plans; these are the owner's, in order.

- [ ] 1. Launch the seven lanes, each with its git grant (frame §4) and, for io-pimdir, the yes or no to 0.20.0.
- [ ] 2. Rule on io-pimdir's D1 to D13 when its lane reaches drop 2 (its defaults stand meanwhile).
- [ ] 3. Re-sign and push each io-pimdir drop (with this repository's vectors for drop 2); tell the app lanes the hash.
- [ ] 4. Once every app lane is green on drop 3's hash, cross-app check included: the signed tag v0.20.0, the Releases workflow green on all targets.
- [ ] 5. checks/io-pimdir.rev to v0.20.0's commit here, and the tags storage-draft-17, sync-draft-15 and search-draft-17 at that commit.
- [ ] 6. Each app lane swaps its pin for `io-pimdir = "0.20"` and re-runs its gate; re-sign and push the apps.
- [ ] 7. App releases in the agreed order (pimdir v1 before neverest v1; the five CLIs on one io-pimdir revision); the Android release after the owner's device checks.
- [ ] 8. A log entry here once the consumers are on 0.20, and this folder archived.
