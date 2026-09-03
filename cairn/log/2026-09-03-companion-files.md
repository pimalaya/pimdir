---
cairn: log
change: companion-files
date: 2026-09-03
---

# The store directory admits the index

§3 said a store contains *exactly* pimdir.db, the two lock files and objects/. The search part needs index.db and index.lock beside them, and "copy the directory" is the property the format is built on, so they live in the store and not in a cache directory.

§3 now lists them, says the index is derived and droppable, and says an implementation ignores a file it does not own: the collector walks objects/ and nothing else, which it already did.
