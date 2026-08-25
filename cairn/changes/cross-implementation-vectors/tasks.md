---
cairn: tasks
change: cross-implementation-vectors
---

# Tasks

- [ ] `vectors/objects.json`: body to object name for `blake3` and `sha256-128`, with the RFC 4648 boundary lengths (1 to 5 bytes, so the leftover-bit padding is exercised), the empty body, and the sharded blob path.
- [ ] `vectors/meta.json` and `vectors/fixtures/`: one case per kind, plus the hedged cases (no `FN`; unparseable `Date`; zoned `DTSTART` on a fold and on a gap; `VTODO` with `DUE` and no `DTSTART`).
- [ ] Author the expected values from the algorithm and the prose, not by running either implementation.
- [ ] SPEC.md: a normative section naming vectors/ as part of the format.
- [ ] **io-pimdir**: `tests/vectors.rs`, skipping when this repository is not checked out beside it, comparing parsed structures rather than JSON text.
- [ ] **Android**: vendor vectors/ into the test resources with their SHA-256 recorded, plus a CI step that re-hashes against this repository.
- [ ] Log; land.
