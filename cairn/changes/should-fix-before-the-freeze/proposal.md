---
cairn: change
id: should-fix-before-the-freeze
status: landed
created: 2026-10-30
---

# What should be fixed before STORAGE freezes

## Why

Edit 10 of the pimdir stable-release plan (2026-10-30): the should-fix list of the consolidated pimdir review, every recommendation accepted. None loses data on its own today, but each is cheaper fixed in a draft than after a release, where a schema change is a new version and a rule change a new minor. Line numbers are at 8b2e8b6.

## What

Store:

- **`delete_collection` drops queued work.** The cascade (0001_init.sql:576) deletes pending and parked queue rows, intents included. It refuses while the collection has queue rows (decided 2026-10-30: refused by a trigger, the operator cancelling first, rather than parked, a parked row of a deleted collection having nothing left to apply to); STORAGE §14, a scenario.
- **Unknown payload `v`.** STORAGE §13 (:355) and §15.3 (:481) say payloads are versioned and nothing says what an owner does with an unknown `v`: it skips the row, as an unknown kind (§15.2).
- **Derived prefixes.** A real UID or Message-ID starting `hash:`, `alt:`, `dup:`, `part:` or `file:` reads as writer-derived (0001_init.sql:522-525, §9): reserve the prefixes and escape such a hint (Annex A, §9), with summaries.json cases.
- **Unicode version.** Case folding (Annex A.2 :585, A.6 :638) names no Unicode version, and the canonical address drives seeks: pin one, or state the folding is of the version the vectors pin.
- **queries/ status.** STORAGE §4.4 (:135, SHOULD use verbatim) against OVERVIEW §11 (:145, binding): a statement's name, parameters and result columns bind, its text is reference. Canonical statements for what io-pimdir writes by hand: the invitation and task backfills (the version bump landed with the-store-version-is-a-contract).
- **Draft shims** (moved to the-draft-shims-gather-in-one-annex) ("predating §15.6" in §15.6 and Annex B, "an earlier draft" in §13 `round_band`, A.1) gathered in one upgrade annex, read only by reconciliation.
- **Rebuildable overclaim.** STORAGE §1 (:44), README Features (:31) and OVERVIEW §1 call the database derived and rebuildable; the queue, receipts, references, capabilities, unbound collections and un-pushed edits are not. A rebuild is a confirmed, reporting operation, never an automatic one (the same root as the "delete the store and let it resync" advice the apps relay).
- **Terminology** (STORAGE §2, :52-54) omits folders and files.

Sync:

- **Cross-source Message-ID.** A different message under one Message-ID from a second source is discarded (SYNC §9, :268) against "duplicates mint", and size is the only witness (SYNC §6, :224): mint it as a duplicate.
- **Events tied to commit** (SYNC §5, :208): an event is reported only for what the write committed.
- **Handle-less `Add`** (SYNC §4, :124): an `Accepted` add without a handle (IMAP without UIDPLUS) is specified.

Wording and checks:

- **RFC 8174 boilerplate** in the three parts, SHALL and RECOMMENDED declared; a keyword audit of rules carrying none (SYNC §5 :143, :155; STORAGE §11 :286, :292-299) and of untestable ones (SYNC.md:105).
- **Contradictions**: AGENTS.md points freeze criteria at STORAGE §6; GUIDE §11 (:244) against SYNC §8 (:250) on rekey criteria; GUIDE §7 (:255) against STORAGE §11 (:286) on purge.
- **Vectors**: a `v` on every vector file (vectors/sync/*, vectors/gtd/writers.json) and a JSON Schema per file, checked by checks/vectors.py.

Search:

- `occurring_between.sql` misses a zero-length occurrence at the range start, so a `DUE;VALUE=DATE` task misses `date:today` (against SEARCH §8, :124); a search vector.
- `horizon_left`: the prose against vectors/search/queries.json:30.
- `has:attachment`: the field rule stated.
- The review's other ambiguities: chunk offsets never stored (SEARCH §6, :82), `id:` and `linked:` (SEARCH §8, :116-117).

## Lands in

storage-draft-05, sync-draft-05 and search-draft-05.
