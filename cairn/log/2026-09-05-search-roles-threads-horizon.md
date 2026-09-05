---
cairn: log
change: search-roles-threads-horizon
date: 2026-09-05
---

# Role fields, threads with absent parents, a horizon that expands what it reaches

`from:jane` fell to the one `people` field and matched anyone the message named; `object_text` and `summary_text` carry one column per address role beside it. Threads linked only present messages by a single parent, so two replies to a root nobody held were two threads; every id a member names has a `message` row, the parent is the first `In-Reply-To` else the last `References` id, `message_by_parent` finds children by a seek, a re-keyed thread is written before the old row's cascade takes its members, and `thread_members` answers in one account since a `Message-ID` may recur across two.

The horizon roll bound the new horizon to a query written for the old one, compared a verbatim `UNTIL` to an RFC 3339 instant as text, never looked at `task_summary`, and never gave a single event beyond the horizon an occurrence once the horizon reached it. `items_to_reexpand` takes both horizons, compares the bound on its calendar day, unions the tasks and selects the single items the new window covers; GUIDE §15 runs it before `set_horizon`. The default span of an event with no end, the resolution order of a zoned time and the overlap of a zero-length occurrence are stated, and an unexpandable series yields nothing rather than failing the pass.

`is:retained` promised what §4 made unreachable, retained rows having no placement; it is gone, the trash being the store's. `flag` and `occurrence` cascade from `placement`, which GUIDE had claimed of `delete_placement` while the statement deleted one row. A blob missing when the indexer opens it writes no `object` row, so a dedup twin does not inherit an empty text. `coverage` is per kind for a client to narrow. WAL is recommended for index.db. SEARCH §2, §4, §6 to §9; GUIDE §15; migrations/search, queries/search.
