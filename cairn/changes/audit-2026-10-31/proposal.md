---
cairn: change
id: audit-2026-10-31
status: active
created: 2026-10-31
---

# The release audit of 2026-10-31, and its ledger

## Why

Before STORAGE freezes, six reviewers read the repository at 9606b43 blind, each from one angle (security, performance, specification quality, architecture, data integrity, conformance tooling), without cairn/ or AGENTS.md, so their view was not anchored on the ledgers. Their findings were merged, the ones that matter re-verified, and each compared with the open items of every tasks.md, the review of 2026-10-30 and the decisions pending since. A finding already on a ledger is not repeated here unless the reviewers brought new evidence.

The verdict: the model held (the queue applies a row once, the collector works under the staging lock, checkpoints land after the last chunk, the change feed seeks, a flag write is cheap; io-pimdir's vector suites pass against 9606b43), but what cannot change after storage-v1.0.0 was not settled (the version contract, blob naming and layout, the parse rules mail identity rests on, schema additions scheduled after v1), five paths lost data silently, and the checks caught 18 of 50 seeded faults.

## What

Every finding has one line in tasks.md, with its severity, the reviewers who found it and where to look, closed by the log entry, vector or check that answers it, or left open with the reason. The reviewers' scripts, synthetic stores and mutation harness stayed in the session's scratch directory and are not part of the repository.

## Decided

The user decided on 2026-10-31:

- **Drafts are exact.** While a part is draft, a program opens only a store its own draft wrote; any other is refused, never reconciled nor migrated. storage-v1.0.0 refuses every draft store and draft-based programs reinstall. Migrations exist from version 1 on. This reverses the draft reconciliation of the-store-version-is-a-contract and replaces the-draft-shims-gather-in-one-annex with a deletion.
- **D1, compatibility levels.** `store_meta` carries a read and a produce compatibility version beside `version`, from version 1: a reader opens a store whose read version it knows, a producer one whose produce version it knows, an owner only a version it knows. `bindings_by_link` lands now; the pending bit and the purge log (algorithm-audit-2026-09-04 :77, :78) stay after v1, a migration that raises neither level.
- **D2** is answered by the exact draft marker.
- **D3, one on-disk format.** The canonical schema enforces types by `CHECK (typeof(…))` rather than `STRICT` and loads on SQLite 3.18 (verified on 3.18.0: every table, trigger and index created, every write path compiled); statement text stays free per implementation; `store_meta.shape` and its refusal go. index.db keeps shapes, FTS5 and FTS4 differing on disk.
- **D4, keys.** Text composite keys stay for v1, their measured cost accepted (1.84 KB of metadata per item, 21.9 s to rename a 250k-item folder); the small child tables become `WITHOUT ROWID` and the mostly-`NULL` pointer indexes partial.
- **D5, one hash.** BLAKE3 at 32 bytes; `sha256-128` goes; a blob write never replaces an existing file.
- **D6, one shard level.** `objects/<hash[0:2]>/<hash>`.
- **D7, the store's write contract** (batch operations, drop reasons, tiers, chunk boundaries) moves from SYNC §10 into STORAGE §14, and the store records which SYNC version wrote its sync state.
- **D8, the producer's capability gate** is a SHOULD; the owner stays authoritative.
- **D9, accepted for v1:** folder-shaped placements, identity as the primary key with its prefixes, attachment stand-ins in the store, a single owner with no handover, no local annotation table. A Windows and macOS note joins STORAGE §5 and §8.

## Lands in

storage-draft-08, sync-draft-07 and search-draft-08, in batches, each with its log entry: format identity and versions, the blob store, store statements and performance, identity and derivations, sync rules, search, structure and security, then the checks.
