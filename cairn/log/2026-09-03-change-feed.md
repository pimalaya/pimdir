---
cairn: log
change: change-feed
date: 2026-09-03
---

# The store says what changed, not only that something did

`PRAGMA data_version` moves on any commit and says nothing about which rows. `seq` moves on insert only. Nothing moved on a flag change, a body update, a retention or a purge, so every derived structure (an index, a list a window shows, a mirror) could only rescan the store.

§4.5 adds `items.changed` and `collections.changed`, drawn from `store_meta.next_change` by triggers in the canonical DDL, so no implementation plumbs a stamp and an owner and a producer draw from one counter. An update stamps only when an observable column moved; a delete cannot stamp the row it removes and counts in `store_meta.purges` instead.

`stamp_item` covers a summary or address row moving under an unchanged item.

The feed retires load-all / replace-all as the reference write form: re-inserting a collection stamps every row on every sync, which drowns every consumer of the feed. The diff form io-pimdir already uses is the reference.

`list_items_changed_since`, `list_collections_changed_since` and `load_change_cursor` are the reads; queries/store.sql adds the `store_meta` insert an earlier entry noted was missing.

Verified with sqlite 3.53.2: the schema applies, the triggers fire on insert and on a changed column and not on a restated one, and the 130 statements prepare.
