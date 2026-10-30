---
cairn: log
change: reads-proportional-to-what-they-ask
date: 2026-10-30
---

# Two decisions for reads proportional to what they ask

Edit 7 of the pimdir stable-release plan settled the two choices this change waited on since 2026-10-18; the statement rewrites they unblock moved to keyset-reads-seek-their-bound.

- **STORAGE §13** (normative): a flag set is a JSON array sorted by code point, each flag once, written as SQLite's `json()` writes it, with no whitespace, so one set has one spelling and a count finds `\Seen` by its bytes (`instr`) rather than through `json_each`. No `seen` column. No check here can see a writer's spelling, the checks binding literal sets; the rewritten counts of keyset-reads-seek-their-bound will rely on it, and its scenarios bind such sets.
- **STORAGE §14.1** (normative): no store-side FTS5. The store keeps `LIKE` (FTS5 stays no store requirement, §4.1) and indexed text search is SEARCH.md's index, which already answers the body.

No schema or statement changes. io-pimdir writes a flag set from a sorted set through compact `serde_json` (src/codec.rs `flags_to_json`), the same bytes as `json()` for every flag a server hands out (control characters aside, which no flag carries); Android and the other writers check theirs in their cairns.
