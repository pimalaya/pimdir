---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# A refresh is the rebuild

io-pimdir's generated suite refreshes an index after each owner write and compares it with one rebuilt at the same write. Two departures were the text's own, decided by the lead toward exactness (G9, G10), and land in search-draft-15.

## What moved

- **SEARCH §4** (G9, normative): a body goes with its last placement. Once a placement dropped or repointed leaves a hash no placement names (`object_placed`, new), the indexer deletes that body's text and `object` row in the same transaction, so a refreshed index holds the bodies its placements name, as a rebuilt one does, whatever the store still pins. It said the text stayed until the store's object went (`objects_gone`), which kept a body an `update` replaced, still pinned by a base, indexed for nothing. `placements_gone` now answers each placement's `hash`, for a placement gone by the key reconciliation.
- **SEARCH §9** (G10, normative): a thread's id and its `first` and `last` are recomputed when threads join and when a member is restated, its sort key having moved or not; it said on a join alone, so a moved date left the thread named and bounded by the keys of before.
- **vectors/search/refresh.json** moves to format 2: a query answers `hits` or the `threads` of a threaded listing, and a step may state `objects`, the `object` rows a canonical index holds after it, which another shape does not compare. Two cases: a card's body replaced then the card retained (`objects` 1, then 0), and a reply whose date moves before its parent's (the thread named after it, bounded by both dates as they stand).
- checks/vectors.py re-derives `objects` from the live items' bodies and checks every thread hit; checks/names.sh reads the version SEARCH §11 states; checks/invariants.sh runs `object_placed` ("a body a placement names is placed, one its last placement moved off is not") and reads `placements_gone`'s new column; queries/signatures.json restated.

## Guards

- refresh.json's two cases fail on io-pimdir with its refresh unchanged ("object rows: refreshed"; the thread listing) and pass once it follows (io-pimdir cairn/log/2026-11-20-a-refresh-is-the-rebuild.md); the generated suite's G9 and G10 are lifted there.
