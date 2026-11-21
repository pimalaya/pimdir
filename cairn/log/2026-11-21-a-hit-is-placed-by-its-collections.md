---
cairn: log
change: a-hit-is-placed-by-its-collections
landed: 2026-11-21
---

# A hit is placed by its collections

search-draft-16, untagged, edited in place. From io-pimdir's planner (as-fast-as-notmuch phase 2, performance-audit-2026-11-05 F1), which pages by walking the query's collections in key order and so reads a hit's key among the placements it walks.

- SEARCH §8.2 states a hit's key: the greatest `sort_key` of its live placements. One item's placements hold one key where the store shares a `seq` by agreement on the date (STORAGE §9.1), so a dated order is the same whichever is read; where they differ, an implementation MAY read the key among the placements of the query's collections, or of the first `collection:` or `folder:` conjunct's when two leave none. Unpinned before: the order said `sort_key` without saying whose.
- The same bullet states that a hit needs no placement in the query's collections: `collection:a collection:b` answers the items filed in both, as notmuch answers `folder:a folder:b`. io-pimdir's first planner intersected the conjuncts and answered nothing there; review caught it.

Checks: two cases of vectors/search/queries.json, `collection:home/INBOX collection:home/Kept` and `folder:home/Kept collection:home/INBOX`, both answering item 12, filed in both; they fail on the planner without its fix (seen 2026-11-21 in a scratch copy of io-pimdir's vendored vectors). The MAY has no vector: no fixture's item holds two keys, and none can while the agreement rule stands for mail.
