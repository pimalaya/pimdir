---
cairn: change
id: the-owing-rows-are-marked
status: landed
created: 2026-11-21
---

# The owing rows are marked

## Why

A sync finding nothing still cost 0.49 s on the 517k Enron store with 3,311 folders (notmuch's no-op `new`: 0.07 s), 0.43 s of it the engine's delta loads: `list_owing_bindings` and `list_lacking_items` walked every binding and every item of each collection to answer nothing (io-pimdir cairn/log/2026-11-21-a-sync-that-finds-nothing.md). Both are canonical, so the fix is the standard's.

The owner chose on 2026-11-21 a mark over a per-source stamp of the change feed: a mark backed by a partial index makes the two reads cost what is owed in every sync, where a stamp wrongly left skips work silently, a data-loss class.

## What

storage-draft-15 is edited in place (not tagged, no migration, no number moves):

- `bindings.owes` and `items.lacks`, 0 or 1, each the value of a rule the schema writes once as a view (`binding_owes`, `item_lacks`): the predicate `list_owing_bindings` used to evaluate per binding, and "live, holding a body, and a source of the collection binds it not".
- Fifteen triggers recompute a mark from its view after every write that can move it (a binding inserted or its key, conflict or base rewritten; an item inserted or its collection, conflict, deletion, flag set or body rewritten; a flag row of either set inserted or deleted; a binding gained or lost; a source row inserted, deleted or rekeyed), flipping it only where it differs. Two more refuse a flag row rewritten in place, which no trigger of the mark or of the stamp follows.
- Two partial indexes, `bindings_owing(collection, source, handle) WHERE owes = 1` and `items_lacking(collection, link_id) WHERE lacks = 1`, which the two statements now seek. `list_lacking_items` keeps an exact answer for a source no row of `sources` names (never counted by the mark) by walking the collection under a one-row guard that is empty while the row exists.
- STORAGE.md §4.6 states the marks; §4.3 and §14 name them; SYNC.md §10 and GUIDE.md follow.

The marks are derived, never stamped: a mark equals its rule at the end of every statement whoever writes, and checks/invariants.sh holds that, and that each mark covers what the statements before it answered, after every statement of every scenario.

## Decided (owner, 2026-11-21)

Landed as built, its cost known: the import 4 to 10% more CPU and 4 to 8% more wall on the 517k tier, fifteen triggers every implementation keeps, and a fresh sync for every existing storage-draft-15 store; against a no-op sync from about 0.40 to 0.12 s.

## Alternatives weighed

- **A partial index alone, no new state.** `list_owing_bindings` compares a binding with its item (flags, body), which no index over one table can hold; the conflict, deletion and no-base terms could each be a partial index, but the flag and body terms, the ones a sync moves, cannot. `list_lacking_items` is an anti-join across tables, the same. Rejected: neither statement becomes a seek.
- **A per-source stamp of the change feed** (io-pimdir's log, second shape): cheaper to write, but a base moving without its item's stamp (a binding rewritten, a source joining) would have to move it too, and a stamp left wrongly skips a push for good. The owner's decision.
- **A mark set by the triggers and cleared by the statement recording an equal base**: fewer recomputes, but a mark cleared by a writer is a mark a writer can clear wrongly; recomputing from the rule costs a few seeks per write (measured in the log).
- **A guard refusing a binding's key rewritten**: simpler than recomputing on it, but it changes which constraint refuses `UPDATE bindings SET source = ''` (checks/floor.sh and the shapes scenario expect the CHECK); recomputing keeps the refusals as they were.
