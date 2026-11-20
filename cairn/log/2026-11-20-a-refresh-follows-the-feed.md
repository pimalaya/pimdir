---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# A refresh follows the feed

The first line of the freeze plan's section 4: vectors of a refresh driven by the change feed (STORAGE §4.5, SEARCH §4), so no implementation passes while missing a stamp. No rule moves: the stamping rules of STORAGE §4.5 and the refresh of SEARCH §4 stand as written, and what was prose alone is now a vector, in search-draft-15 and storage-draft-15.

## What moved

- vectors/search/refresh.json, format 1, with its schema vectors/schema/search-refresh.schema.json: a case is a store of store.json's shape and its steps, each a write an owner makes, the feed it leaves above the cursor read before it (`changed`: items as `(collection, link_id)`, collections, whether the purge count moved) and the queries answered after a refresh. One case of ten steps: an insert, a flag on an unchanged body, a body replaced under its link id, a bodiless item's summary changed under unchanged columns (the writer's `stamp_item`), a coverage moving, a rename, an item retained, its purge, a card retained then erased.
- SEARCH §11 states the file, its version and how an implementation runs it, a rebuilt index answering alike; §12's indexer row names it. STORAGE §16 and §17's owner row bind an owner to the feed each step leaves, which fails nowhere else.
- checks/vectors.py validates the file against its schema, re-derives each step's `changed` from §4.5's stamping rules over a model of the store, checks every query against the grammar and every hit against the items the step leaves searchable, and counts the file's fixtures among the named ones. checks/names.sh checks the version SEARCH §11 states for it; `put`, `cover` and `erase` join its listed words. checks/tags.sh gives the file, its schema and its fixtures to SEARCH. vectors/README.md describes the format; vectors/manifest.json restated.

## Guards

- checks/vectors.py: the summary step stating no item changed fails ("step 4: the items the feed lists: [] is not [('work/Archive', 'budget-1@example.net')]").
- io-pimdir tests/search.rs `every_refresh_vector_answers` runs every step through the crate's owner, its feed and its index, and an index rebuilt from a backup of the store. With the writer's `stamp_item` under an unchanged item disabled (src/client/write.rs), step 4 fails on the feed ("the items the feed lists"), and, the feed check skipped, on the refreshed index ("\"subject:final\": refreshed"); restored, it passes.

The page token across a refresh (freeze plan 5b) joins this file in a later step.
