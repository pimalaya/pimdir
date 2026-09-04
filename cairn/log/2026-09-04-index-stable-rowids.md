---
cairn: log
change: index-stable-rowids
date: 2026-09-04
---

# The index joins on explicit integer keys

object and placement were keyed on TEXT and composite primary keys, and the contentless FTS tables joined on their implicit rowids, which VACUUM may renumber on a table with no INTEGER PRIMARY KEY: a silent misalignment of text and row. Both tables carry an explicit `id INTEGER PRIMARY KEY` now, the FTS rows equal it, and the search statements return and join on `id`.
