---
cairn: log
change: search-temporal-coverage
date: 2026-10-27
---

# Coverage says when the store is not known to hold every member

The bodiless count answers what a search could not read; nothing answered what the store may not hold at all. A collection synced under a scope holds every member only within its last closed round's scope, and one whose source never closed a round is known complete nowhere, so a query reaching below a floor answered an empty or short result as if it were the whole truth. io-pimdir (M1) already reports the axis; the standard did not.

- **SEARCH §8.2, temporal coverage**: over the query's date range, open on a side it does not bound, from the queried collections' sources' coverage (STORAGE §10, `list_coverage`): `full`, or `bounded` with `since` (a `covered_since` above the range's start, else `null`), `until` (a `covered_until` below its end, else `null`) and `filling` (a source never closed a round); a collection no source syncs is complete; rolled up as the highest `since`, the lowest `until`, `filling` when any is.
- **SEARCH §11 and vectors/search**: store.json collections carry optional `sources` coverage rows: work/INBOX covered from 2026-08-01, and a new, empty work/Archive whose source never closed a round. A case may state `temporal`, compared when stated. New cases: `collection:work/INBOX date:2026-07..` (work 1, bounded since 2026-08-01T00:00:00Z, until null, not filling), `collection:work/INBOX date:2026-08..2026-08` (work 1, full), `collection:work/Archive` (no hit, filling) and `account:work` (work 1, since 2026-08-01T00:00:00Z, filling). No earlier case's hits moved.
- **checks/vectors.py** checks the `sources` rows' shape (one never closed carries no bound) and re-derives every stated `temporal` from them; without the rows, the three bounded cases fail.

GUIDE §15 (the query step and §16's vectors step) follows. checks/schema.sh, names.sh, invariants.sh and vectors.py pass. draft-04 is not tagged yet, so the number stays.
