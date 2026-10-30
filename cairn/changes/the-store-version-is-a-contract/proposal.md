---
cairn: change
id: the-store-version-is-a-contract
status: landed
created: 2026-10-30
---

# The store version is a contract

## Why

Edit 1 of the pimdir stable-release plan (2026-10-30), from blocker 1 of the consolidated pimdir review. STORAGE had no upgrade contract an implementation could rely on after a freeze:

- An implementation meeting a newer or corrupt store MAY rebuild it, losing un-pushed edits (STORAGE.md:170 at 8b2e8b6): an older binary may wipe a newer store.
- Reconciliation drops every table and column the canonical schema lacks. Kept after a freeze, an older owner destroys a newer owner's additions. Reproduced, not theoretical: himalaya built at io-pimdir 3b4bed8 opened a later store as owner and dropped `supersessions` and four `task_summary` columns.
- The documents disagreed: "recreated" (STORAGE.md:104, README.md:90) against "reconcile or refuse" (STORAGE.md:172).
- No canonical statement moved `store_meta.version`, which io-pimdir set by hand while §4.2 makes disagreeing stamps corrupt.
- A migration had to preserve items and bindings only, while the queue, receipts, references, capabilities, retained rows and unbound collections exist nowhere else.
- Annex A derivations carried no revision, so a changed derivation had no recorded "re-derivation owed" state.

The plan decided the frozen schema stays `user_version` 1 (draft stores are 1 too), with the accepted risk that apps released on io-pimdir 0.5 (neverest 0.3.0, himalaya 2.2.1, cardamum 0.3.0, calendula 0.2.0) open a v1 store without refusing; io-pimdir 0.5 has no reconcile, so they do not rewrite the schema.

## What

- STORAGE §4.2: version and `user_version` move together, only in a migration's transaction; this part's major is the schema version; while draft, version 1 is edited in place and an earlier draft's store is reconciled, never recreated; once released, 0001_init.sql never changes.
- STORAGE §6: the owner's open is three ordered steps: refuse a store above the implementation's version (every profile, never reconciled, migrated, rebuilt nor written); reconcile a version 1 store to 0001_init.sql alone, before any migration; run the migrations above, each setting `user_version` and `store_meta.version` (`set_store_version`). No implementation rebuilds a store it cannot read ("MAY rebuild and lose" removed). A migration preserves every row of every table. A reader or producer reads an older or unreconciled store with missing columns as `NULL` and missing tables as empty. While draft, an owner reconciles or refuses naming what is missing, never recreates nor deletes.
- STORAGE §6 and Annex A: Annex A is at revision 1; `store_meta.derivation` records the revision a store was derived under, written by `init_store_meta`; an owner at a later revision re-derives the changed columns from held bodies and records it (`set_derivation`, which never lowers it).
- migrations/storage/0001_init.sql: `store_meta.derivation INTEGER NOT NULL DEFAULT 1` (a new column folded into version 1 pre-v1, which reconciliation adds with its default); the header says the file never changes once released.
- queries/storage/owner/set_store_version.sql, set_derivation.sql (new); init_store_meta.sql binds `:derivation`; read/load_store_meta.sql answers `derivation` last.
- GUIDE §2 and §3, README Status, OVERVIEW §1 follow.

## Lands in

storage-draft-05. GUIDE, README and OVERVIEW are informative.

## Out

- io-pimdir: the canonical bump statement, reconcile only at version 1 and before migrations, refusal above its version for every profile, `store_meta.format` checked, fixtures from the v0.5.1 and v0.7.0 tags, a synthetic 0002 test. Tracked in io-pimdir's cairn.
- The draft shims elsewhere in the text ("predating §15.6", "an earlier draft" in §13 `round_band`, A.1) stay where they are: the reconciliation keeps reading them, and moving them to an upgrade annex is editorial (should-fix-before-the-freeze).
