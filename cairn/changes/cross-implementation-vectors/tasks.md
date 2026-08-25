---
cairn: tasks
change: cross-implementation-vectors
---

# Tasks

## Landed in this repository

- [x] `vectors/objects.json`: body to object name for `blake3` and `sha256-128`, with the sharded blob path, the empty body, and the RFC 4648 §10 encoding vectors.
- [x] `vectors/meta.json` and `vectors/fixtures/`: 17 cases over the three kinds, including every case Annex A hedges (no `FN`; unparseable `Date`; zoned `DTSTART` on a fold and on a gap; `VTODO` with `DUE` and no `DTSTART`).
- [x] Author the expected values from the algorithm and the prose, not by running either implementation.
- [x] SPEC.md §16: a normative section naming vectors/ as part of the format.
- [x] SPEC.md §5: say what an object name *is*, which authoring the vectors showed it never had (digest width, truncation, alphabet, what the shard prefix comes off).
- [x] Annex A: pin the five conventions that were not decidable as written (the ambiguous-time offset, `meta.date`'s zone, `from`/`to`'s form, the case mapping, `recurring`'s `false`).
- [x] `vectors/README.md`: derivation, consumer rules, and what is deliberately not pinned.
- [x] Log entry.

## Left to the consumers

- [ ] **io-pimdir**: `tests/vectors.rs`, skipping when this repository is not checked out beside it, comparing parsed structures rather than JSON text.
- [ ] **Android**: vendor vectors/ into the test resources with their SHA-256 recorded, plus a CI step that re-hashes against this repository.
