---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator crate

The first code of the generator of cairn/changes/the-freeze-plan (section 2), after its design note and scenario catalogue (generator/README.md, generator/scenarios.md). No part of the standard moves: generator/ is tooling, binding no implementation, and no draft number changes.

- **generator/**: a Rust crate, `pimdir-generator`, unpublished, depending on no Pimalaya crate (D1), on rusqlite 0.43, blake3, serde and serde_json alone. It loads migrations/ and queries/ at run time from the directory above its manifest, holding every statement to its line in queries/signatures.json (the set of names both ways, and each statement's prepared parameters and columns), and creates a store as GUIDE §2 and §3 do through 0001_init.sql and `init_store_meta` alone: directory `0700`, files `0600`, the owner lock held, `foreign_keys`, `synchronous = FULL`, `secure_delete`, WAL. The draft a store names is the one init_store_meta.sql writes, never one the crate spells. PCG32 is its generator, pinned by algorithm. Its public types take no domain prefix, the owner's call for unpublished tooling.
- **Checks**: the flake's `generator` check builds the crate from its Cargo.lock and runs its tests: the PCG32 reference sequence of seed 42 and stream 54, every base32 case and object name of vectors/objects.json, every statement under queries/storage/ prepared against a fresh store to its signature, a statement run with parameters its signature does not name refused, the fresh store's `store_meta` (format, the draft of init_store_meta.sql, the three versions, the algorithm, incarnation 1, a 32-digit id, derivation 3, no sync version), its pragmas, modes and lock, and STORAGE.md stating the Annex A revision the crate derives under, so a revision bump fails it until the crate follows.
- **flake.nix**: the `generator` fileset and check; the development shell gains cargo, rustc, clippy and rustfmt.
