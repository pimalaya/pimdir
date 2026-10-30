---
cairn: log
change: a-read-body-is-verified
date: 2026-10-30
---

# A body read is checked against its name

Edit 7 of the pimdir stable-release plan settled the open question (no new column); this lands the change. Before it, a read trusted the file: a body whose bytes no longer hashed to its name was parsed, shown, indexed and pushed as sound.

- **STORAGE §7** (normative): a reader, producer or owner reading a body whole SHOULD verify it against its name, a streamed read at its end; a mismatch and a missing file are one state, the item holding no body; a partial read is not verified and no verified mark is kept, so the schema does not move. An owner MUST unlink such a file under the staging lock taken exclusively, so the next write of the body writes it anew, and the next `Full` upgrade fetches it again. An engine MUST NOT push a body it has not verified in the run. The order of trust now reads: a name over bytes, bytes over a row.
- **SYNC §6** (normative): a `Full` level over a missing or failing blob is a claim the row does not hold, revisited by the upgrade. **SYNC §11**: an object stated `corrupt`.
- **GUIDE §11, §14** (informative) follow.

Guarded by vector 94 (a pending create whose body is `corrupt` pushes nothing) and checks/vectors.py, which fails any case pushing a body stated `corrupt` or without a blob; a copy of 94 pushing the Add fails it and passed the check of the morning. vectors/schema/sync.schema.json takes `corrupt`. A store-side read cannot be held by a check here, which runs no implementation; io-pimdir carries the flipped-byte test in its cairn.
